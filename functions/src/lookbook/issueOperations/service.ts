/* eslint-disable require-jsdoc, max-len */
import {createHash} from "node:crypto";
import type {Firestore} from "firebase-admin/firestore";
import {FieldPath, FieldValue, Timestamp} from "firebase-admin/firestore";
import type {Storage} from "firebase-admin/storage";

import {
  extractionIssueExpiresAt,
  transitionExtractionIssueState,
  type ExtractionIssueAction,
  type ExtractionIssueStatus,
} from "../import/extractionIssueContract.js";
import type {
  GroundTruthInput,
  ListClustersInput,
  ParsedWriteRequest,
} from "./contract.js";

const CLUSTER_COLLECTION = "lookbookExtractionIssueClusters";
const AUDIT_COLLECTION = "lookbookExtractionIssueAuditLogs";
const MAX_SCAN_COUNT = 250;
const MAX_EVIDENCE_BYTES = 512 * 1024;
const MAX_PROJECTION_COUNT = 400;

type Bucket = ReturnType<Storage["bucket"]>;

export class IssueOperationsServiceError extends Error {
  constructor(
    readonly statusCode: 404 | 409 | 413 | 500,
    readonly code: string,
    message: string
  ) {
    super(message);
    this.name = "IssueOperationsServiceError";
  }
}

export type ClusterSummary = ReturnType<typeof clusterSummary>;

export async function listIssueClusters(input: {
  firestore: Firestore;
  query: ListClustersInput;
}): Promise<{clusters: ClusterSummary[]; nextCursor: string | null}> {
  const decodedCursor = decodeIssueClusterCursor(input.query.cursor);
  let query = input.firestore.collection(CLUSTER_COLLECTION)
    .orderBy("lastSeenAt", "desc")
    .orderBy(FieldPath.documentId(), "desc")
    .limit(MAX_SCAN_COUNT);
  if (decodedCursor !== null) {
    query = query.startAfter(
      Timestamp.fromMillis(decodedCursor.lastSeenAtMillis),
      decodedCursor.fingerprint
    );
  }
  const snapshot = await query.get();
  const matches = snapshot.docs.filter((document) => {
    const data = document.data();
    return input.query.statuses.includes(data.status) &&
      (input.query.stage === null || data.stage === input.query.stage) &&
      (!input.query.recurrenceOnly || numberValue(data.recurrenceCount) > 0) &&
      (input.query.seenAfter === null ||
        timestampMillis(data.lastSeenAt) >= input.query.seenAfter.getTime());
  });
  const selected = matches.slice(0, input.query.limit);
  const cursorDocument = matches.length > selected.length ?
    selected.at(-1) : snapshot.size === MAX_SCAN_COUNT ?
      snapshot.docs.at(-1) : undefined;
  return {
    clusters: selected.map((document) =>
      clusterSummary(document.id, document.data())),
    nextCursor: cursorDocument ? encodeIssueClusterCursor({
      fingerprint: cursorDocument.id,
      lastSeenAtMillis: timestampMillis(cursorDocument.data().lastSeenAt),
    }) : null,
  };
}

export async function getIssueCluster(input: {
  firestore: Firestore;
  bucket: Bucket;
  fingerprint: string;
}): Promise<{status: "found" | "missing"; cluster?: ClusterSummary; evidence?: unknown}> {
  const snapshot = await input.firestore.collection(CLUSTER_COLLECTION)
    .doc(input.fingerprint).get();
  if (!snapshot.exists) return {status: "missing"};
  const data = snapshot.data() ?? {};
  const summary = clusterSummary(snapshot.id, data);
  const evidence = await representativeEvidence(input.bucket, snapshot.id, data);
  return {status: "found", cluster: summary, evidence};
}

export async function getIssueClustersBatch(input: {
  firestore: Firestore;
  bucket: Bucket;
  fingerprints: string[];
}): Promise<Array<{
  fingerprint: string;
  status: "found" | "missing" | "evidenceExpired";
  cluster?: ClusterSummary;
  evidence?: unknown;
}>> {
  const references = input.fingerprints.map((fingerprint) =>
    input.firestore.collection(CLUSTER_COLLECTION).doc(fingerprint));
  const snapshots = await input.firestore.getAll(...references);
  return Promise.all(snapshots.map(async (snapshot, index) => {
    const fingerprint = input.fingerprints[index] as string;
    if (!snapshot.exists) return {fingerprint, status: "missing" as const};
    const data = snapshot.data() ?? {};
    const evidence = await representativeEvidence(
      input.bucket, fingerprint, data,
    );
    return {
      fingerprint,
      status: evidence === null ? "evidenceExpired" as const : "found" as const,
      cluster: clusterSummary(fingerprint, data),
      ...(evidence === null ? {} : {evidence}),
    };
  }));
}

export async function mutateIssueCluster(input: {
  firestore: Firestore;
  request: ParsedWriteRequest;
  operatorEmail: string;
}): Promise<Record<string, unknown>> {
  const {request, firestore} = input;
  const fingerprint = request.payload.fingerprint;
  const clusterRef = firestore.collection(CLUSTER_COLLECTION).doc(fingerprint);
  const requestHash = stableHash({
    environment: request.environment,
    action: request.action,
    payload: request.payload,
  });
  const auditID = stableHash({
    environment: request.environment,
    operatorEmail: input.operatorEmail,
    requestID: request.requestID,
  });
  const auditRef = firestore.collection(AUDIT_COLLECTION).doc(auditID);
  return firestore.runTransaction(async (transaction) => {
    const auditSnapshot = await transaction.get(auditRef);
    if (auditSnapshot.exists) {
      const audit = auditSnapshot.data() ?? {};
      if (audit.requestHash !== requestHash) {
        throw new IssueOperationsServiceError(
          409, "request_id_conflict", "requestID가 다른 요청에 사용됐습니다."
        );
      }
      return {...recordValue(audit.response, "audit response"), duplicate: true};
    }
    const clusterSnapshot = await transaction.get(clusterRef);
    if (!clusterSnapshot.exists) {
      throw new IssueOperationsServiceError(
        404, "cluster_not_found", "issue cluster를 찾을 수 없습니다."
      );
    }
    const cluster = clusterSnapshot.data() ?? {};
    const beforeStatus = issueStatus(cluster.status);
    const beforeStateVersion = nonNegativeInteger(cluster.stateVersion, 1);
    let next;
    try {
      next = transitionExtractionIssueState({
        status: beforeStatus,
        stateVersion: beforeStateVersion,
        expectedStateVersion: request.payload.expectedStateVersion,
        action: request.action as ExtractionIssueAction,
      });
    } catch (error) {
      throw new IssueOperationsServiceError(
        409, "state_conflict", error instanceof Error ? error.message : String(error)
      );
    }
    const now = FieldValue.serverTimestamp();
    const expiresAt = extractionIssueExpiresAt(next.status);
    const patch: Record<string, unknown> = {
      status: next.status,
      stateVersion: next.stateVersion,
      updatedAt: now,
      ...(expiresAt === null ? {expiresAt: FieldValue.delete()} :
        {expiresAt: Timestamp.fromDate(expiresAt)}),
      ...mutationFields(request, input.operatorEmail, now),
    };
    const jobCollection = cluster.stage === "seasonDiscovery" ?
      "seasonDiscoveryJobs" : cluster.stage === "seasonImageImport" ?
        "importJobs" : null;
    if (jobCollection === null) {
      throw new IssueOperationsServiceError(
        500, "invalid_cluster", "cluster stage가 올바르지 않습니다."
      );
    }
    const jobSnapshot = await transaction.get(
      firestore.collectionGroup(jobCollection)
        .where("extractionIssueFingerprint", "==", fingerprint)
        .limit(MAX_PROJECTION_COUNT + 1)
    );
    if (jobSnapshot.size > MAX_PROJECTION_COUNT) {
      throw new IssueOperationsServiceError(
        409,
        "projection_limit_exceeded",
        "상태 projection 대상 상한을 초과했습니다."
      );
    }
    transaction.update(clusterRef, patch);
    jobSnapshot.docs.forEach((document) => transaction.set(document.ref, {
      extractionIssueStatus: next.status,
      extractionIssueWontFixReason: request.action === "markWontFix" ?
        request.payload.wontFixReason : null,
      updatedAt: now,
    }, {merge: true}));
    const response = {
      fingerprint,
      status: next.status,
      stateVersion: next.stateVersion,
      duplicate: false,
    };
    transaction.create(auditRef, {
      auditID,
      environment: request.environment,
      operatorEmail: input.operatorEmail,
      action: request.action,
      fingerprint,
      requestID: request.requestID,
      requestHash,
      beforeStatus,
      beforeStateVersion,
      afterStatus: next.status,
      afterStateVersion: next.stateVersion,
      response,
      createdAt: now,
      expiresAt: Timestamp.fromMillis(Date.now() + 60 * 24 * 60 * 60 * 1000),
    });
    return response;
  });
}

function mutationFields(
  request: ParsedWriteRequest,
  operatorEmail: string,
  now: FieldValue
): Record<string, unknown> {
  if (request.action === "startProcessing") {
    return {processingStartedAt: now, processingStartedBy: operatorEmail};
  }
  if (request.action === "markNeedsGroundTruth") {
    return {groundTruthRequestedAt: now, groundTruthRequestedBy: operatorEmail};
  }
  if (request.action === "recordGroundTruthAndResume") {
    return {
      groundTruth: groundTruthDTO(request.payload.groundTruth as GroundTruthInput),
      groundTruthRecordedAt: now,
      groundTruthRecordedBy: operatorEmail,
    };
  }
  if (request.action === "reopen") {
    return {
      reopenedAt: now,
      reopenedBy: operatorEmail,
      reopenReason: request.payload.reason,
    };
  }
  return {
    wontFixReason: request.payload.wontFixReason,
    wontFixNote: request.payload.note,
    wontFixAt: now,
    wontFixBy: operatorEmail,
  };
}

function groundTruthDTO(value: GroundTruthInput): Record<string, unknown> {
  return {
    expectedCandidateCount: value.expectedCandidateCount,
    candidateKeys: value.candidateKeys,
    sourceClassification: value.sourceClassification,
    note: value.note,
  };
}

function clusterSummary(fingerprint: string, data: Record<string, unknown>) {
  return {
    fingerprint,
    stage: token(data.stage),
    adapterScope: token(data.adapterScope),
    adapterKey: token(data.adapterKey),
    platform: token(data.platform),
    parserStrategy: token(data.parserStrategy),
    failureReasons: stringArray(data.failureReasons, 20),
    qualityReasons: stringArray(data.qualityReasons, 20),
    templateSignature: token(data.templateSignature),
    extractorMajorVersion: token(data.extractorMajorVersion),
    status: token(data.status),
    stateVersion: numberValue(data.stateVersion),
    occurrenceCount: numberValue(data.occurrenceCount),
    recurrenceCount: numberValue(data.recurrenceCount),
    blockedRuntimeVersion: token(data.blockedRuntimeVersion),
    fixedRuntimeVersion: token(data.fixedRuntimeVersion),
    representativeEvidenceStatus: token(data.representativeEvidenceStatus),
    firstSeenAt: timestampISO(data.firstSeenAt),
    lastSeenAt: timestampISO(data.lastSeenAt),
    updatedAt: timestampISO(data.updatedAt),
  };
}

async function representativeEvidence(
  bucket: Bucket,
  fingerprint: string,
  cluster: Record<string, unknown>
): Promise<unknown | null> {
  if (cluster.representativeEvidenceStatus !== "ready") return null;
  const evidenceID = cluster.representativeEvidenceID;
  const path = cluster.representativeEvidenceStoragePath;
  const expectedPath = typeof evidenceID === "string" ?
    `lookbook-extraction-cluster-evidence/${fingerprint}/${evidenceID}.json` : "";
  if (!/^[a-f0-9]{40}$/.test(String(evidenceID)) || path !== expectedPath) {
    return null;
  }
  try {
    const [contents] = await bucket.file(expectedPath).download();
    if (contents.byteLength > MAX_EVIDENCE_BYTES) {
      throw new IssueOperationsServiceError(
        413, "evidence_too_large", "대표 evidence 크기 제한을 초과했습니다."
      );
    }
    const payload = recordValue(JSON.parse(contents.toString("utf8")), "evidence");
    const evidence = recordValue(payload.evidence, "evidence payload");
    return evidenceDTO(evidence);
  } catch (error) {
    if (error instanceof IssueOperationsServiceError) throw error;
    return null;
  }
}

function evidenceDTO(value: Record<string, unknown>): Record<string, unknown> {
  return {
    schemaVersion: numberValue(value.schemaVersion),
    status: token(value.status),
    stage: token(value.stage),
    source: sourceDTO(value.source),
    strategy: token(value.strategy),
    failureReasons: stringArray(value.failureReasons, 20),
    qualityReasons: stringArray(value.qualityReasons, 20),
    templateSignature: token(value.templateSignature),
    candidateEvidence: objectArray(value.candidateEvidence, 120).map((item) => ({
      candidateKey: token(item.candidateKey),
      strategy: token(item.strategy),
      sourceKind: token(item.sourceKind),
      source: sourceDTO(item.source),
    })),
    expectedCountEvidence: objectArray(value.expectedCountEvidence, 20)
      .map((item) => ({
        kind: token(item.kind),
        value: numberValue(item.value),
        confidence: finiteNumber(item.confidence),
        sourceFingerprint: token(item.sourceFingerprint),
      })),
    programmaticGalleryEvidence:
      value.programmaticGalleryEvidence === null ? null :
        programmaticGalleryDTO(value.programmaticGalleryEvidence),
    structureTokens: stringArray(value.structureTokens, 40),
    elements: objectArray(value.elements, 120).map((item) => ({
      tag: token(item.tag),
      id: nullableToken(item.id),
      classes: stringArray(item.classes, 20),
      text: nullableToken(item.text),
      sources: objectArray(item.sources, 20).map((source) => ({
        attribute: token(source.attribute),
        source: sourceDTO(source.source),
      })),
    })),
    versions: versionsDTO(value.versions),
  };
}

function sourceDTO(value: unknown): Record<string, unknown> {
  const record = safeRecord(value);
  return {
    origin: token(record.origin),
    path: token(record.path),
    queryKeys: stringArray(record.queryKeys, 40),
    fingerprint: token(record.fingerprint),
  };
}

function versionsDTO(value: unknown): Record<string, unknown> {
  const record = safeRecord(value);
  return {
    extractorVersion: token(record.extractorVersion),
    platformAdapterKey: nullableToken(record.platformAdapterKey),
    platformAdapterVersion: nullableToken(record.platformAdapterVersion),
    domainAdapterKey: nullableToken(record.domainAdapterKey),
    domainAdapterVersion: nullableToken(record.domainAdapterVersion),
  };
}

function programmaticGalleryDTO(value: unknown): Record<string, unknown> | null {
  const record = safeRecord(value);
  return typeof record.detected === "boolean" ? {
    detected: record.detected,
    signals: stringArray(record.signals, 10),
  } : null;
}

export function encodeIssueClusterCursor(value: {
  fingerprint: string;
  lastSeenAtMillis: number;
}): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

export function decodeIssueClusterCursor(value: string | null): {
  fingerprint: string;
  lastSeenAtMillis: number;
} | null {
  if (value === null) return null;
  try {
    const parsed = recordValue(
      JSON.parse(Buffer.from(value, "base64url").toString("utf8")),
      "cursor"
    );
    if (typeof parsed.fingerprint !== "string" ||
        !/^[a-f0-9]{40}$/.test(parsed.fingerprint) ||
        !Number.isSafeInteger(parsed.lastSeenAtMillis) ||
        Number(parsed.lastSeenAtMillis) < 0) {
      throw new Error("invalid cursor");
    }
    return {
      fingerprint: parsed.fingerprint,
      lastSeenAtMillis: Number(parsed.lastSeenAtMillis),
    };
  } catch {
    throw new IssueOperationsServiceError(
      409, "invalid_cursor", "cursor가 올바르지 않습니다."
    );
  }
}

function stableHash(value: unknown): string {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function issueStatus(value: unknown): ExtractionIssueStatus {
  const statuses: ExtractionIssueStatus[] = [
    "open", "inProgress", "needsGroundTruth", "fixed", "verified", "wontFix",
  ];
  if (!statuses.includes(value as ExtractionIssueStatus)) {
    throw new IssueOperationsServiceError(
      500, "invalid_cluster", "cluster status가 올바르지 않습니다."
    );
  }
  return value as ExtractionIssueStatus;
}

function recordValue(value: unknown, name: string): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new IssueOperationsServiceError(500, "invalid_data", `${name}가 올바르지 않습니다.`);
  }
  return value as Record<string, unknown>;
}

function safeRecord(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> : {};
}

function objectArray(value: unknown, limit: number): Record<string, unknown>[] {
  return Array.isArray(value) ? value.slice(0, limit).map(safeRecord) : [];
}

function stringArray(value: unknown, limit: number): string[] {
  return Array.isArray(value) ? value.filter((item): item is string =>
    typeof item === "string").slice(0, limit) : [];
}

function token(value: unknown): string | null {
  return typeof value === "string" && value.length <= 500 ? value : null;
}

function nullableToken(value: unknown): string | null {
  return value === null ? null : token(value);
}

function numberValue(value: unknown): number {
  return Number.isSafeInteger(value) && Number(value) >= 0 ? Number(value) : 0;
}

function nonNegativeInteger(value: unknown, fallback: number): number {
  return Number.isSafeInteger(value) && Number(value) >= 0 ?
    Number(value) : fallback;
}

function finiteNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function timestampMillis(value: unknown): number {
  return value instanceof Timestamp ? value.toMillis() : 0;
}

function timestampISO(value: unknown): string | null {
  return value instanceof Timestamp ? value.toDate().toISOString() : null;
}
