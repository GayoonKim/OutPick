/* eslint-disable require-jsdoc, max-len */
import {createHash} from "node:crypto";
import type {Firestore} from "firebase-admin/firestore";
import {FieldPath, FieldValue, Timestamp} from "firebase-admin/firestore";

import {
  compareExtractionRuntimeVersions,
  type ExtractionIssueStage,
} from "../import/extractionIssueContract.js";
import type {GroundTruthInput} from "./contract.js";
import type {VerifyFixRequest} from "./releaseContract.js";
import type {
  CloudRunServiceState,
  ReleaseExternalVerifier,
  RuntimeContractDTO,
  SmokeResultDTO,
} from "./releaseExternal.js";
import {IssueOperationsServiceError} from "./service.js";

const CLUSTERS = "lookbookExtractionIssueClusters";
const AUDITS = "lookbookExtractionIssueAuditLogs";
const RUNS = "lookbookExtractionFixVerificationRuns";
const RELEASES = "lookbookExtractionFixReleases";
const RUNTIME = "lookbookExtractionRuntime";
const PAGE_SIZE = 200;

export async function verifyExtractionFix(input: {
  firestore: Firestore;
  request: VerifyFixRequest;
  operatorEmail: string;
  external: ReleaseExternalVerifier;
  now?: Date;
}): Promise<Record<string, unknown>> {
  const now = input.now ?? new Date();
  const {payload} = input.request;
  const requestHash = stableHash({
    environment: input.request.environment,
    action: input.request.action,
    payload,
  });
  const auditID = stableHash({operatorEmail: input.operatorEmail, requestID: input.request.requestID});
  const existingAudit = await input.firestore.collection(AUDITS).doc(auditID).get();
  if (existingAudit.exists) {
    if (existingAudit.data()?.requestHash !== requestHash) {
      throw serviceError("request_id_conflict", "requestID가 다른 검증 요청에 사용됐습니다.");
    }
    return {...(existingAudit.data()?.response ?? {}), duplicate: true};
  }
  const clusterRef = input.firestore.collection(CLUSTERS).doc(payload.fingerprint);
  const snapshot = await clusterRef.get();
  if (!snapshot.exists) throw notFound();
  const cluster = snapshot.data() ?? {};
  assertClusterReady(cluster, payload);

  const service = await input.external.cloudRunService();
  assertTraffic(service, payload);
  const runtime = await input.external.runtimeContract(service.uri);
  assertRuntime(runtime, payload, input.request.environment);
  const source = await sourceJob(input.firestore, cluster, payload.stage);
  const smoke = await input.external.extractionSmoke(service.uri, {
    fingerprint: payload.fingerprint,
    stage: payload.stage,
    sourceURL: source.sourceURL,
    sourceJobPath: source.jobPath,
  });
  assertSmoke(
    smoke, cluster, payload, source.jobPath, input.request.environment,
  );

  const runID = stableHash({requestID: input.request.requestID, fingerprint: payload.fingerprint});
  const releaseID = stableHash({fingerprint: payload.fingerprint, runtime: payload.targetRuntimeVersion});
  const response = await input.firestore.runTransaction(async (transaction) => {
    const auditRef = input.firestore.collection(AUDITS).doc(auditID);
    const audit = await transaction.get(auditRef);
    if (audit.exists) {
      if (audit.data()?.requestHash !== requestHash) {
        throw serviceError("request_id_conflict", "requestID가 다른 검증 요청에 사용됐습니다.");
      }
      return {...(audit.data()?.response ?? {}), duplicate: true};
    }
    const current = await transaction.get(clusterRef);
    if (!current.exists) throw notFound();
    const data = current.data() ?? {};
    assertClusterReady(data, payload);
    const serverNow = FieldValue.serverTimestamp();
    const nextVersion = payload.expectedStateVersion + 1;
    transaction.update(clusterRef, {
      status: "fixed",
      stateVersion: nextVersion,
      fixedRuntimeVersion: payload.targetRuntimeVersion,
      fixedWorkerRevision: payload.workerRevision,
      fixedWorkerSourceRevision: payload.workerSourceRevision,
      fixedAt: serverNow,
      updatedAt: serverNow,
      expiresAt: FieldValue.delete(),
    });
    transaction.set(input.firestore.collection(RUNTIME).doc("current"), {
      workerService: "lookbook-import-worker",
      workerRevision: payload.workerRevision,
      workerTrafficPercent: 100,
      workerSourceRevision: payload.workerSourceRevision,
      seasonDiscoveryContractRevision: runtime.seasonDiscoveryContractRevision,
      seasonDiscoveryExtractorVersion: runtime.seasonDiscoveryExtractorVersion,
      imageExtractorVersion: runtime.imageExtractorVersion,
      adapterVersions: runtime.adapterVersions,
      verifiedAt: serverNow,
      verifiedBy: input.operatorEmail,
      verificationRunID: runID,
    });
    transaction.create(input.firestore.collection(RUNS).doc(runID), {
      runID,
      fingerprint: payload.fingerprint,
      stage: payload.stage,
      sourceJobPathHash: smoke.sourceJobPathHash,
      candidateCount: smoke.candidateCount,
      candidateKeys: smoke.candidateKeys,
      failureReasons: smoke.failureReasons,
      qualityReasons: smoke.qualityReasons,
      workerRevision: payload.workerRevision,
      workerSourceRevision: payload.workerSourceRevision,
      runtimeVersion: payload.targetRuntimeVersion,
      status: "passed",
      createdAt: serverNow,
      expiresAt: Timestamp.fromMillis(now.getTime() + 24 * 60 * 60 * 1000),
    });
    transaction.set(input.firestore.collection(RELEASES).doc(releaseID), {
      releaseID,
      fingerprint: payload.fingerprint,
      stage: payload.stage,
      runtimeVersion: payload.targetRuntimeVersion,
      workerRevision: payload.workerRevision,
      verificationRunID: runID,
      status: "projecting",
      cursor: null,
      projectedCount: 0,
      createdAt: serverNow,
      updatedAt: serverNow,
      expiresAt: Timestamp.fromMillis(now.getTime() + 60 * 24 * 60 * 60 * 1000),
    }, {merge: false});
    const result = {
      fingerprint: payload.fingerprint,
      status: "fixed",
      stateVersion: nextVersion,
      runtimeVersion: payload.targetRuntimeVersion,
      verificationRunID: runID,
      releaseID,
      duplicate: false,
    };
    transaction.create(auditRef, {
      auditID,
      environment: input.request.environment,
      operatorEmail: input.operatorEmail,
      action: "verifyFix",
      fingerprint: payload.fingerprint,
      requestID: input.request.requestID,
      requestHash,
      beforeStatus: data.status,
      beforeStateVersion: data.stateVersion,
      afterStatus: "fixed",
      afterStateVersion: nextVersion,
      response: result,
      createdAt: serverNow,
      expiresAt: Timestamp.fromMillis(now.getTime() + 60 * 24 * 60 * 60 * 1000),
    });
    return result;
  });
  await projectReleasePage(input.firestore, releaseID);
  return response;
}

export function validateReleaseCandidate(input: {
  environment: VerifyFixRequest["environment"];
  cluster: Record<string, unknown>;
  payload: VerifyFixRequest["payload"];
  service: CloudRunServiceState;
  runtime: RuntimeContractDTO;
  smoke: SmokeResultDTO;
  jobPath: string;
}): void {
  assertClusterReady(input.cluster, input.payload);
  assertTraffic(input.service, input.payload);
  assertRuntime(input.runtime, input.payload, input.environment);
  assertSmoke(
    input.smoke, input.cluster, input.payload, input.jobPath,
    input.environment,
  );
}

export async function reconcileFixReleaseProjections(firestore: Firestore): Promise<number> {
  const snapshot = await firestore.collection(RELEASES)
    .where("status", "==", "projecting").limit(20).get();
  for (const document of snapshot.docs) await projectReleasePage(firestore, document.id);
  return snapshot.size;
}

export async function projectReleasePage(firestore: Firestore, releaseID: string): Promise<void> {
  const releaseRef = firestore.collection(RELEASES).doc(releaseID);
  await firestore.runTransaction(async (transaction) => {
    const releaseSnapshot = await transaction.get(releaseRef);
    if (!releaseSnapshot.exists || releaseSnapshot.data()?.status !== "projecting") return;
    const release = releaseSnapshot.data() ?? {};
    const collection = release.stage === "seasonDiscovery" ? "seasonDiscoveryJobs" : "importJobs";
    let query = firestore.collectionGroup(collection)
      .where("extractionIssueFingerprint", "==", release.fingerprint)
      .orderBy(FieldPath.documentId()).limit(PAGE_SIZE);
    if (typeof release.cursor === "string") query = query.startAfter(release.cursor);
    const jobs = await transaction.get(query);
    let projected = 0;
    jobs.docs.forEach((job) => {
      if (releaseJobProjectionEligible(job.data(), String(release.runtimeVersion))) {
        transaction.set(job.ref, {
          extractionIssueStatus: "fixed",
          extractionIssueWontFixReason: null,
          retryAvailableRuntimeVersion: release.runtimeVersion,
          retryAvailableAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        projected += 1;
      }
    });
    const done = jobs.size < PAGE_SIZE;
    transaction.set(releaseRef, {
      status: done ? "completed" : "projecting",
      cursor: done ? null : jobs.docs.at(-1)?.ref.path,
      projectedCount: Number(release.projectedCount ?? 0) + projected,
      updatedAt: FieldValue.serverTimestamp(),
      ...(done ? {completedAt: FieldValue.serverTimestamp()} : {}),
    }, {merge: true});
  });
}

export function releaseJobProjectionEligible(data: Record<string, unknown>, runtime: string): boolean {
  if (data.extractionIssueStatus === "fixed" || data.resolvedByJobID || data.resolvedByGeneration) return false;
  if (typeof data.blockedRuntimeVersion !== "string") return false;
  return compareExtractionRuntimeVersions(data.blockedRuntimeVersion, runtime) === -1;
}

function assertClusterReady(cluster: Record<string, unknown>, payload: VerifyFixRequest["payload"]): void {
  if (cluster.stage !== payload.stage || cluster.status !== "inProgress" ||
      cluster.stateVersion !== payload.expectedStateVersion) {
    throw serviceError("state_conflict", "cluster 상태·stage·stateVersion이 검증 요청과 다릅니다.");
  }
  if (typeof cluster.blockedRuntimeVersion !== "string" ||
      compareExtractionRuntimeVersions(cluster.blockedRuntimeVersion, payload.targetRuntimeVersion) !== -1) {
    throw serviceError("runtime_not_newer", "수정 runtime이 차단 runtime보다 높지 않습니다.");
  }
}

function assertTraffic(
  service: CloudRunServiceState,
  payload: VerifyFixRequest["payload"],
): void {
  if (service.reconciling || !service.ready || service.traffic.length !== 1 ||
      service.traffic[0]?.revision !== payload.workerRevision ||
      service.traffic[0]?.percent !== 100) {
    throw serviceError("traffic_not_ready", "대상 Worker revision의 traffic이 100%가 아닙니다.");
  }
}

function assertRuntime(
  runtime: RuntimeContractDTO,
  payload: VerifyFixRequest["payload"],
  environment: VerifyFixRequest["environment"],
): void {
  const actual = payload.stage === "seasonDiscovery" ?
    `contract:${runtime.seasonDiscoveryContractRevision}` :
    `extractor:${runtime.imageExtractorVersion}`;
  const expectedProjectID = environment === "development" ?
    "outpick-test" : "outpick-664ae";
  if (runtime.schemaVersion !== 1 || runtime.projectID !== expectedProjectID ||
      runtime.workerRevision !== payload.workerRevision ||
      runtime.workerSourceRevision !== payload.workerSourceRevision || actual !== payload.targetRuntimeVersion) {
    throw serviceError("runtime_mismatch", "실행 중인 Worker runtime이 검증 대상과 다릅니다.");
  }
}

function assertSmoke(
  smoke: SmokeResultDTO, cluster: Record<string, unknown>,
  payload: VerifyFixRequest["payload"], jobPath: string,
  environment: VerifyFixRequest["environment"],
): void {
  assertRuntime(smoke.runtime, payload, environment);
  if (smoke.fingerprint !== payload.fingerprint || smoke.stage !== payload.stage ||
      smoke.sourceJobPathHash !== stableHashRaw(jobPath).slice(0, 40) || smoke.logicIssueDetected) {
    throw serviceError("smoke_failed", "실제 입력 smoke에서 문제가 해결됐음을 확인하지 못했습니다.");
  }
  const groundTruth = groundTruthValue(cluster.groundTruth);
  if (requiresGroundTruth(cluster, payload.stage) && groundTruth === null) {
    throw serviceError("ground_truth_required", "완전성 검증에 ground truth가 필요합니다.");
  }
  if (groundTruth !== null) {
    if (groundTruth.sourceClassification === "unknown" || groundTruth.sourceClassification === "nonGallery") {
      throw serviceError("ground_truth_invalid", "수정 성공을 판단할 수 없는 source classification입니다.");
    }
    if (groundTruth.expectedCandidateCount !== null && smoke.candidateCount !== groundTruth.expectedCandidateCount) {
      throw serviceError("smoke_count_mismatch", "smoke 후보 수가 ground truth와 다릅니다.");
    }
    if (groundTruth.candidateKeys.length > 0 &&
        !sameSet(groundTruth.candidateKeys, smoke.candidateKeys)) {
      throw serviceError("smoke_candidates_mismatch", "smoke 후보가 ground truth와 다릅니다.");
    }
  }
}

function requiresGroundTruth(cluster: Record<string, unknown>, stage: ExtractionIssueStage): boolean {
  if (stage === "seasonDiscovery") return true;
  const failure = strings(cluster.failureReasons);
  const quality = strings(cluster.qualityReasons);
  return !failure.includes("parse_failed") || quality.some((reason) => [
    "expected_count_mismatch", "large_rendered_delta_without_expected_evidence", "raw_candidate_drop",
  ].includes(reason));
}

async function sourceJob(firestore: Firestore, cluster: Record<string, unknown>, stage: ExtractionIssueStage): Promise<{jobPath: string; sourceURL: string}> {
  const path = cluster.representativeJobPath;
  const pattern = stage === "seasonDiscovery" ?
    /^brands\/[A-Za-z0-9_-]+\/seasonDiscoveryJobs\/[A-Za-z0-9_-]+$/ :
    /^brands\/[A-Za-z0-9_-]+\/importJobs\/[A-Za-z0-9_-]+$/;
  if (typeof path !== "string" || !pattern.test(path)) {
    throw serviceError("source_job_missing", "대표 source job 경로가 없습니다.");
  }
  const snapshot = await firestore.doc(path).get();
  const data = snapshot.data() ?? {};
  const sourceURL = stage === "seasonDiscovery" ? data.sourceArchiveURL ?? data.archiveURL : data.sourceURL;
  if (!snapshot.exists || typeof sourceURL !== "string" || !/^https:\/\//.test(sourceURL)) {
    throw serviceError("source_job_missing", "대표 source job URL을 확인할 수 없습니다.");
  }
  return {jobPath: path, sourceURL};
}

function groundTruthValue(value: unknown): GroundTruthInput | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  const data = value as Record<string, unknown>;
  return {
    expectedCandidateCount: Number.isSafeInteger(data.expectedCandidateCount) ? Number(data.expectedCandidateCount) : null,
    candidateKeys: strings(data.candidateKeys).filter((item) => /^[a-f0-9]{24}$/.test(item)),
    sourceClassification: ["completeGallery", "partialGallery", "nonGallery", "unknown"].includes(String(data.sourceClassification)) ? data.sourceClassification as GroundTruthInput["sourceClassification"] : "unknown",
    note: null,
  };
}

function strings(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function sameSet(lhs: string[], rhs: string[]): boolean {
  return lhs.length === rhs.length && [...lhs].sort().every((item, index) => item === [...rhs].sort()[index]);
}

function stableHash(value: unknown): string {
  return stableHashRaw(JSON.stringify(value));
}

function stableHashRaw(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function serviceError(code: string, message: string): IssueOperationsServiceError {
  return new IssueOperationsServiceError(409, code, message);
}

function notFound(): IssueOperationsServiceError {
  return new IssueOperationsServiceError(404, "cluster_not_found", "issue cluster를 찾을 수 없습니다.");
}
