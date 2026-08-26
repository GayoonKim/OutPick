/* eslint-disable require-jsdoc, max-len */
import {randomUUID} from "node:crypto";
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import type {FileMetadata} from "@google-cloud/storage";
import {GoogleAuth} from "google-auth-library";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../../core/firebase.js";
import {IssueMessageEvidenceViewURLInput} from "./contracts.js";
import {messageEvidenceObjectPath, messageReviewRevisionID} from "../messageEvidence/contracts.js";

const VIEW_URL_TTL_MILLIS = 5 * 60 * 1_000;

export type EvidenceObjectDescriptor = {
  bundleID: string;
  attachmentID: string;
  bucket: string;
  path: string;
  destinationGeneration: string;
  sourceGeneration: string;
  bytes: number;
  contentType: string;
  attemptGeneration: number;
};

export interface EvidenceURLSigner {
  metadata(object: EvidenceObjectDescriptor): Promise<FileMetadata>;
  sign(object: EvidenceObjectDescriptor, issuanceID: string, expiresAt: Date): Promise<string>;
}

export type EvidenceIssuanceAudit = {
  issuanceID: string;
  actorUID: string;
  incidentID: string;
  reviewRevision: number;
  bundleID: string;
  attachmentID: string;
  generation: string;
  requestID: string;
  issuedAt: string;
  urlExpiresAt: string;
  result: "issued";
};

export interface EvidenceAuditWriter {
  write(event: EvidenceIssuanceAudit): Promise<void>;
}

function customMetadata(metadata: FileMetadata): Record<string, string> {
  const value = metadata.metadata;
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, String(item)]));
}

export function assertEvidenceStorageOwnership(
  object: EvidenceObjectDescriptor,
  metadata: FileMetadata,
): void {
  const custom = customMetadata(metadata);
  if (String(metadata.generation) !== object.destinationGeneration ||
      custom.outpickEvidenceBundleID !== object.bundleID ||
      custom.outpickEvidenceAttachmentID !== object.attachmentID ||
      custom.outpickEvidenceAttemptGeneration !== String(object.attemptGeneration) ||
      custom.outpickEvidenceSourceGeneration !== object.sourceGeneration ||
      Number(metadata.size) !== object.bytes || metadata.contentType !== object.contentType) {
    throw new HttpsError("failed-precondition", "Evidence Storage 소유권 metadata가 올바르지 않습니다.", {
      errorCode: "INVALID_EVIDENCE_STORAGE_METADATA",
    });
  }
}

function descriptor(input: {
  raw: unknown;
  bundleID: string;
  attemptGeneration: number;
  evidenceBucket: string;
}): EvidenceObjectDescriptor {
  const raw = input.raw && typeof input.raw === "object" ? input.raw as Record<string, unknown> : {};
  const attachmentID = typeof raw.attachmentID === "string" ? raw.attachmentID : "";
  const destinationGeneration = typeof raw.destinationGeneration === "string" ? raw.destinationGeneration : "";
  const sourceGeneration = typeof raw.sourceGeneration === "string" ? raw.sourceGeneration : "";
  const bytes = typeof raw.bytes === "number" ? raw.bytes : -1;
  const contentType = typeof raw.contentType === "string" ? raw.contentType : "";
  const path = typeof raw.path === "string" ? raw.path : "";
  const expectedPath = attachmentID ? messageEvidenceObjectPath({bundleID: input.bundleID, attemptGeneration: input.attemptGeneration, attachmentID}) : "";
  if (!attachmentID || raw.bucket !== input.evidenceBucket || path !== expectedPath ||
      !/^[1-9][0-9]*$/.test(destinationGeneration) || !/^[1-9][0-9]*$/.test(sourceGeneration) ||
      !Number.isSafeInteger(bytes) || bytes <= 0 || !contentType) {
    throw new HttpsError("failed-precondition", "Evidence object manifest가 올바르지 않습니다.");
  }
  return {bundleID: input.bundleID, attachmentID, bucket: input.evidenceBucket, path, destinationGeneration, sourceGeneration, bytes, contentType, attemptGeneration: input.attemptGeneration};
}

export async function issueMessageEvidenceViewURLService(input: {
  actorUID: string;
  request: IssueMessageEvidenceViewURLInput;
  evidenceBucket: string;
  projectID: string;
  now?: Date;
  firestore?: Firestore;
  signer?: EvidenceURLSigner;
  auditWriter?: EvidenceAuditWriter;
}): Promise<{url: string; issuanceID: string; expiresAt: string}> {
  const now = input.now ?? new Date();
  const firestore = input.firestore ?? db;
  const incidentRef = firestore.collection("moderationMessageIncidents").doc(input.request.incidentID);
  const incident = await incidentRef.get();
  if (!incident.exists || incident.get("reviewRevision") !== input.request.reviewRevision) {
    throw new HttpsError("failed-precondition", "현재 review revision의 Evidence만 열람할 수 있습니다.", {errorCode: "STALE_REVIEW_REVISION"});
  }
  if (incident.get("acceptanceState") !== "reviewable" || incident.get("evidenceState") !== "available") {
    throw new HttpsError("failed-precondition", "열람 가능한 Evidence 상태가 아닙니다.");
  }
  const revision = await incidentRef.collection("revisions")
    .doc(messageReviewRevisionID(input.request.reviewRevision)).get();
  const bundleID = revision.get("evidenceBundleID");
  if (!revision.exists || typeof bundleID !== "string") {
    throw new HttpsError("failed-precondition", "현재 revision의 Evidence bundle이 아닙니다.");
  }
  const bundle = await firestore.collection("moderationMessageEvidence").doc(bundleID).get();
  if (!bundle.exists || bundle.get("reviewRevision") !== input.request.reviewRevision ||
      bundle.get("state") !== "available" || bundle.get("acceptanceState") !== "reviewable") {
    throw new HttpsError("failed-precondition", "열람 가능한 Evidence bundle이 아닙니다.");
  }
  const deleteAfter = bundle.get("deleteAfter");
  if (deleteAfter instanceof Timestamp && deleteAfter.toMillis() <= now.getTime()) {
    throw new HttpsError("failed-precondition", "Evidence 보존 기한이 종료됐습니다.");
  }
  const attemptGeneration = bundle.get("attemptGeneration");
  if (typeof attemptGeneration !== "number" || !Number.isSafeInteger(attemptGeneration) || attemptGeneration < 0) {
    throw new HttpsError("failed-precondition", "Evidence generation이 올바르지 않습니다.");
  }
  const manifest = bundle.get("evidenceObjects");
  if (!Array.isArray(manifest)) throw new HttpsError("failed-precondition", "Evidence manifest가 없습니다.");
  const raw = manifest.find((item) => item && typeof item === "object" &&
    (item as Record<string, unknown>).attachmentID === input.request.evidenceObjectID &&
    (item as Record<string, unknown>).destinationGeneration === input.request.objectGeneration);
  if (!raw) throw new HttpsError("not-found", "Evidence object를 찾을 수 없습니다.");
  const object = descriptor({raw, bundleID, attemptGeneration, evidenceBucket: input.evidenceBucket});
  const signer = input.signer ?? firebaseEvidenceURLSigner();
  const metadata = await signer.metadata(object);
  assertEvidenceStorageOwnership(object, metadata);
  const issuanceID = randomUUID();
  const expiresAt = new Date(now.getTime() + VIEW_URL_TTL_MILLIS);
  const url = await signer.sign(object, issuanceID, expiresAt);
  const writer = input.auditWriter ?? cloudLoggingEvidenceAuditWriter(input.projectID);
  await writer.write({
    issuanceID,
    actorUID: input.actorUID,
    incidentID: input.request.incidentID,
    reviewRevision: input.request.reviewRevision,
    bundleID,
    attachmentID: object.attachmentID,
    generation: object.destinationGeneration,
    requestID: input.request.clientRequestID,
    issuedAt: now.toISOString(),
    urlExpiresAt: expiresAt.toISOString(),
    result: "issued",
  });
  return {url, issuanceID, expiresAt: expiresAt.toISOString()};
}

export function firebaseEvidenceURLSigner(): EvidenceURLSigner {
  const storage = getStorage();
  return {
    metadata: async (object) => (await storage.bucket(object.bucket)
      .file(object.path, {generation: object.destinationGeneration}).getMetadata())[0],
    sign: async (object, issuanceID, expiresAt) => (await storage.bucket(object.bucket)
      .file(object.path, {generation: object.destinationGeneration}).getSignedUrl({
        version: "v4",
        action: "read",
        expires: expiresAt,
        queryParams: {"x-goog-custom-audit-issuance-id": issuanceID},
      }))[0],
  };
}

export function cloudLoggingEvidenceAuditWriter(projectID: string): EvidenceAuditWriter {
  const auth = new GoogleAuth({scopes: ["https://www.googleapis.com/auth/logging.write"]});
  return {
    write: async (event) => {
      await auth.request({
        url: "https://logging.googleapis.com/v2/entries:write",
        method: "POST",
        data: {
          logName: `projects/${projectID}/logs/moderation-evidence-audit`,
          resource: {type: "global", labels: {project_id: projectID}},
          entries: [{severity: "NOTICE", jsonPayload: {eventType: "EVIDENCE_VIEW_URL_ISSUED", ...event}}],
          partialSuccess: false,
        },
      });
    },
  };
}
