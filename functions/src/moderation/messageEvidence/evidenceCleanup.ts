/* eslint-disable require-jsdoc, max-len */
import {randomUUID} from "node:crypto";
import {FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {
  MESSAGE_EVIDENCE_COMPLETED_JOB_TTL_MILLIS,
  MESSAGE_EVIDENCE_COPY_LEASE_MILLIS,
  messageEvidenceObjectPath,
  messageIncidentID,
  messageReviewRevisionID,
} from "./contracts.js";
import {
  MessageEvidenceCopyError,
  MessageEvidenceObject,
  MessageEvidenceStorage,
} from "./evidenceCopy.js";

const CLEANUP_JOBS = "moderationEvidenceCleanupJobs";
const BUNDLES = "moderationMessageEvidence";
const INCIDENTS = "moderationMessageIncidents";
const MAX_CLEANUP_ATTEMPTS = 20;
const DUE_JOB_LIMIT = 10;

type ClaimedCleanupJob = {
  jobID: string;
  bundleID: string;
  attemptGeneration: number;
  attempt: number;
  leaseToken: string;
  roomID: string | null;
  messageID: string | null;
  reviewRevision: number;
  objects: unknown;
  attachmentIDs: unknown;
  bundleExists: boolean;
};

function nonNegativeInteger(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : fallback;
}

function validID(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && !value.includes("/");
}

function retryDelayMillis(attempt: number): number {
  return Math.min(6 * 60 * 60 * 1000, Math.max(60_000, 2 ** Math.min(attempt, 8) * 30_000));
}

function evidenceObjects(input: {
  value: unknown;
  bundleID: string;
  attemptGeneration: number;
  evidenceBucket: string;
  attachmentIDs: unknown;
}): MessageEvidenceObject[] {
  const value = input.value;
  if (!Array.isArray(value)) throw new MessageEvidenceCopyError("INVALID_EVIDENCE_BUNDLE", "evidence object manifest is invalid");
  const attachmentIDs = Array.isArray(input.attachmentIDs) ? input.attachmentIDs : null;
  if (attachmentIDs === null || attachmentIDs.length > 30 ||
      attachmentIDs.some((attachmentID) => !validID(attachmentID)) ||
      new Set(attachmentIDs).size !== attachmentIDs.length) {
    throw new MessageEvidenceCopyError("INVALID_EVIDENCE_BUNDLE", "evidence attachment manifest is invalid");
  }
  const objects = value.map((raw) => {
    const item = raw && typeof raw === "object" ? raw as Record<string, unknown> : {};
    const object: MessageEvidenceObject = {
      attachmentID: typeof item.attachmentID === "string" ? item.attachmentID : "",
      bucket: typeof item.bucket === "string" ? item.bucket : "",
      path: typeof item.path === "string" ? item.path : "",
      destinationGeneration: typeof item.destinationGeneration === "string" ? item.destinationGeneration : "",
      sourceGeneration: typeof item.sourceGeneration === "string" ? item.sourceGeneration : "",
      bytes: typeof item.bytes === "number" ? item.bytes : -1,
      contentType: typeof item.contentType === "string" ? item.contentType : "",
      crc32c: typeof item.crc32c === "string" ? item.crc32c : null,
    };
    const expectedPath = validID(object.attachmentID) ? messageEvidenceObjectPath({bundleID: input.bundleID, attemptGeneration: input.attemptGeneration, attachmentID: object.attachmentID}) : "";
    if (!validID(object.attachmentID) || object.bucket !== input.evidenceBucket || object.path !== expectedPath ||
        !/^[1-9][0-9]*$/.test(object.destinationGeneration) ||
        !/^[1-9][0-9]*$/.test(object.sourceGeneration) ||
        !Number.isSafeInteger(object.bytes) || object.bytes <= 0 || !object.contentType) {
      throw new MessageEvidenceCopyError("INVALID_EVIDENCE_BUNDLE", "evidence object descriptor is invalid");
    }
    return object;
  });
  if (objects.length !== attachmentIDs.length ||
      new Set(objects.map((object) => object.attachmentID)).size !== objects.length ||
      objects.some((object) => !attachmentIDs.includes(object.attachmentID))) {
    throw new MessageEvidenceCopyError("INVALID_EVIDENCE_BUNDLE", "evidence object manifest is incomplete");
  }
  return objects;
}

async function claimCleanupJob(jobID: string, firestore: Firestore, now: Date): Promise<ClaimedCleanupJob | null> {
  const jobRef = firestore.collection(CLEANUP_JOBS).doc(jobID);
  return firestore.runTransaction(async (transaction) => {
    const job = await transaction.get(jobRef);
    if (!job.exists || job.get("status") === "succeeded" || job.get("status") === "failed" || job.get("status") === "awaitingEvidence") return null;
    const leaseExpiresAt = job.get("leaseExpiresAt");
    const nextAttemptAt = job.get("nextAttemptAt");
    if (job.get("status") === "processing" && leaseExpiresAt instanceof Timestamp && leaseExpiresAt.toMillis() > now.getTime()) return null;
    if (nextAttemptAt instanceof Timestamp && nextAttemptAt.toMillis() > now.getTime()) return null;
    const bundleID = job.get("bundleID");
    if (!validID(bundleID)) throw new MessageEvidenceCopyError("INVALID_CLEANUP_JOB", "evidence cleanup bundle ID is invalid");
    const bundleRef = firestore.collection(BUNDLES).doc(bundleID);
    const bundle = await transaction.get(bundleRef);
    const previousAttempt = nonNegativeInteger(job.get("attempt"));
    // 마지막 cleanup lease를 획득한 worker가 종료된 경우 lease 만료 뒤 같은
    // 시도 번호로 idempotent delete를 재개해 영구 processing 상태를 방지한다.
    const attempt = job.get("status") === "processing" && previousAttempt >= MAX_CLEANUP_ATTEMPTS ?
      previousAttempt : previousAttempt + 1;
    if (attempt > MAX_CLEANUP_ATTEMPTS) return null;
    const leaseToken = randomUUID();
    const nowTimestamp = Timestamp.fromDate(now);
    transaction.set(jobRef, {
      status: "processing",
      phase: "deleting",
      attempt,
      leaseToken,
      leaseExpiresAt: Timestamp.fromMillis(now.getTime() + MESSAGE_EVIDENCE_COPY_LEASE_MILLIS),
      nextAttemptAt: Timestamp.fromMillis(now.getTime() + MESSAGE_EVIDENCE_COPY_LEASE_MILLIS),
      updatedAt: nowTimestamp,
    }, {merge: true});
    if (bundle.exists) {
      if (!["cleanupPending", "deleting"].includes(bundle.get("state"))) {
        throw new MessageEvidenceCopyError("INVALID_EVIDENCE_BUNDLE", "evidence bundle is not ready for cleanup");
      }
      transaction.set(bundleRef, {state: "deleting", updatedAt: nowTimestamp}, {merge: true});
    }
    return {
      jobID,
      bundleID,
      attemptGeneration: bundle.exists ? nonNegativeInteger(bundle.get("attemptGeneration")) : nonNegativeInteger(job.get("attemptGeneration")),
      attempt,
      leaseToken,
      roomID: bundle.exists && validID(bundle.get("roomID")) ? bundle.get("roomID") : null,
      messageID: bundle.exists && validID(bundle.get("messageID")) ? bundle.get("messageID") : null,
      reviewRevision: bundle.exists ? nonNegativeInteger(bundle.get("reviewRevision")) : nonNegativeInteger(job.get("reviewRevision")),
      objects: bundle.exists ? bundle.get("evidenceObjects") ?? [] : [],
      attachmentIDs: bundle.exists ? bundle.get("attachmentIDs") ?? null : [],
      bundleExists: bundle.exists,
    };
  });
}

async function markCleanupSucceeded(job: ClaimedCleanupJob, firestore: Firestore, now: Date): Promise<void> {
  const jobRef = firestore.collection(CLEANUP_JOBS).doc(job.jobID);
  const bundleRef = firestore.collection(BUNDLES).doc(job.bundleID);
  await firestore.runTransaction(async (transaction) => {
    const incidentRef = job.roomID && job.messageID ?
      firestore.collection(INCIDENTS).doc(messageIncidentID(job.roomID, job.messageID)) : null;
    const revisionRef = incidentRef ? incidentRef.collection("revisions").doc(messageReviewRevisionID(job.reviewRevision)) : null;
    const [cleanupJob, bundle, incident, revision] = await Promise.all([
      transaction.get(jobRef),
      transaction.get(bundleRef),
      incidentRef ? transaction.get(incidentRef) : Promise.resolve(null),
      revisionRef ? transaction.get(revisionRef) : Promise.resolve(null),
    ]);
    if (!cleanupJob.exists || cleanupJob.get("leaseToken") !== job.leaseToken) {
      throw new MessageEvidenceCopyError("STALE_CLEANUP_LEASE", "evidence cleanup lease is stale");
    }
    const nowTimestamp = Timestamp.fromDate(now);
    if (bundle.exists) transaction.delete(bundleRef);
    if (incidentRef && revisionRef && incident?.exists && revision?.exists) {
      transaction.set(revisionRef, {evidenceState: "deleted", evidenceBundleID: null, evidenceDeletedAt: nowTimestamp, updatedAt: nowTimestamp}, {merge: true});
      if (nonNegativeInteger(incident.get("reviewRevision")) === job.reviewRevision) {
        transaction.set(incidentRef, {evidenceState: "deleted", updatedAt: nowTimestamp}, {merge: true});
      }
    }
    transaction.set(jobRef, {
      status: "succeeded",
      phase: "completed",
      leaseToken: null,
      leaseExpiresAt: null,
      nextAttemptAt: nowTimestamp,
      lastErrorCode: null,
      attemptGeneration: FieldValue.delete(),
      reviewRevision: FieldValue.delete(),
      evidenceObjects: FieldValue.delete(),
      updatedAt: nowTimestamp,
      expiresAt: Timestamp.fromMillis(now.getTime() + MESSAGE_EVIDENCE_COMPLETED_JOB_TTL_MILLIS),
    }, {merge: true});
  });
}

async function markCleanupRetry(job: ClaimedCleanupJob, firestore: Firestore, now: Date): Promise<void> {
  const terminal = job.attempt >= MAX_CLEANUP_ATTEMPTS;
  const jobRef = firestore.collection(CLEANUP_JOBS).doc(job.jobID);
  const bundleRef = firestore.collection(BUNDLES).doc(job.bundleID);
  await firestore.runTransaction(async (transaction) => {
    const [snapshot, bundle] = await Promise.all([transaction.get(jobRef), transaction.get(bundleRef)]);
    if (!snapshot.exists || snapshot.get("leaseToken") !== job.leaseToken) return;
    transaction.set(jobRef, {status: terminal ? "failed" : "retryPending", phase: terminal ? "completed" : "deleting", leaseToken: null, leaseExpiresAt: null, nextAttemptAt: terminal ? null : Timestamp.fromMillis(now.getTime() + retryDelayMillis(job.attempt)), lastErrorCode: "EVIDENCE_CLEANUP_FAILED", updatedAt: Timestamp.fromDate(now)}, {merge: true});
    if (bundle.exists) transaction.set(bundleRef, {state: "cleanupPending", updatedAt: Timestamp.fromDate(now)}, {merge: true});
  });
}

export async function processMessageEvidenceCleanupJob(input: {
  jobID: string;
  firestore: Firestore;
  storage: MessageEvidenceStorage;
  evidenceBucket: string;
  now?: Date;
}): Promise<boolean> {
  const now = input.now ?? new Date();
  const job = await claimCleanupJob(input.jobID, input.firestore, now);
  if (!job) return false;
  try {
    const objects = evidenceObjects({value: job.objects, bundleID: job.bundleID, attemptGeneration: job.attemptGeneration, evidenceBucket: input.evidenceBucket, attachmentIDs: job.attachmentIDs});
    for (const object of objects) {
      await input.storage.deleteEvidenceObject({object, bundleID: job.bundleID, attemptGeneration: job.attemptGeneration});
    }
    await markCleanupSucceeded(job, input.firestore, now);
    return true;
  } catch (error) {
    console.error("[message-evidence-cleanup] cleanup failed", {jobID: job.jobID, attempt: job.attempt, code: error instanceof MessageEvidenceCopyError ? error.code : "EVIDENCE_CLEANUP_FAILED"});
    await markCleanupRetry(job, input.firestore, now);
    return false;
  }
}

export async function dueMessageEvidenceCleanupJobIDs(firestore: Firestore, now = new Date()): Promise<string[]> {
  const snapshot = await firestore.collection(CLEANUP_JOBS)
    .where("status", "in", ["pending", "retryPending", "processing"])
    .where("nextAttemptAt", "<=", Timestamp.fromDate(now))
    .orderBy("nextAttemptAt", "asc")
    .limit(DUE_JOB_LIMIT)
    .get();
  return snapshot.docs.map((document) => document.id);
}
