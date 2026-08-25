/* eslint-disable require-jsdoc, max-len */
import {createHash, randomUUID} from "node:crypto";
import {FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {
  MESSAGE_EVIDENCE_COMPLETED_JOB_TTL_MILLIS,
  MESSAGE_EVIDENCE_CONTRACT_VERSION,
  MESSAGE_EVIDENCE_COPY_LEASE_MILLIS,
  MESSAGE_EVIDENCE_MAX_COPY_ATTEMPTS,
  messageEvidenceObjectPath,
  messageEvidenceRetryDelayMillis,
} from "./contracts.js";
import {
  acceptMessageEvidenceBundleService,
  MessageEvidenceSourceObject,
} from "./service.js";

const COPY_JOBS = "moderationEvidenceCopyJobs";
const BUNDLES = "moderationMessageEvidence";
const PREPARATIONS = "moderationMessageReportPreparations";
const REQUESTS = "moderationMessageReportRequests";
const GUARDS = "moderationMessageGuards";
const PUBLIC_CLEANUP_JOBS = "chatMessageCleanupJobs";
const DRAIN_LIMIT = 30;
const DUE_JOB_LIMIT = 10;
const MEBIBYTE = 1024 * 1024;
const MAX_IMAGE_OBJECT_BYTES = 15 * MEBIBYTE;
const MAX_IMAGE_BUNDLE_BYTES = 150 * MEBIBYTE;
const MAX_VIDEO_OBJECT_BYTES = 350 * MEBIBYTE;

export type MessageEvidenceObject = {
  attachmentID: string;
  bucket: string;
  path: string;
  destinationGeneration: string;
  sourceGeneration: string;
  bytes: number;
  contentType: string;
  crc32c: string | null;
};

export type MessageEvidenceStorage = {
  copy: (input: {
    source: MessageEvidenceSourceObject;
    destinationBucket: string;
    destinationPath: string;
    bundleID: string;
    attemptGeneration: number;
  }) => Promise<MessageEvidenceObject>;
  deleteAttemptObject: (input: {
    destinationBucket: string;
    destinationPath: string;
    bundleID: string;
    attachmentID: string;
    attemptGeneration: number;
  }) => Promise<void>;
  deleteEvidenceObject: (input: {
    object: MessageEvidenceObject;
    bundleID: string;
    attemptGeneration: number;
  }) => Promise<void>;
};

type ClaimedCopyJob = {
  jobID: string;
  bundleID: string;
  roomID: string;
  messageID: string;
  messageType: "image" | "video";
  attemptGeneration: number;
  attempt: number;
  phase: "copying" | "acceptanceDrain" | "cleaningPartial" | "failureDrain";
  leaseToken: string;
  sourceObjects: MessageEvidenceSourceObject[];
};

function nonNegativeInteger(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : fallback;
}

function validID(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && !value.includes("/");
}

function publicCleanupJobID(roomID: string, messageID: string): string {
  return createHash("sha256").update(`${roomID}:${messageID}`).digest("hex");
}

function errorCode(error: unknown): string {
  if (error instanceof MessageEvidenceCopyError) return error.code;
  return "EVIDENCE_COPY_FAILED";
}

export class MessageEvidenceCopyError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
    this.name = "MessageEvidenceCopyError";
  }
}

export function validateMessageEvidenceSources(input: {
  roomID: string;
  messageID: string;
  messageType: unknown;
  readyBucket: string;
  sources: unknown;
}): MessageEvidenceSourceObject[] {
  if (!validID(input.roomID) || !validID(input.messageID) || !input.readyBucket) {
    throw new MessageEvidenceCopyError("INVALID_EVIDENCE_SOURCE", "evidence source context is invalid");
  }
  const messageType = input.messageType === "image" || input.messageType === "video" ? input.messageType : null;
  if (messageType === null || !Array.isArray(input.sources)) {
    throw new MessageEvidenceCopyError("INVALID_EVIDENCE_SOURCE", "evidence source kind is invalid");
  }
  if ((messageType === "image" && (input.sources.length < 1 || input.sources.length > 30)) ||
      (messageType === "video" && input.sources.length !== 1)) {
    throw new MessageEvidenceCopyError("INVALID_EVIDENCE_SOURCE", "evidence source count is invalid");
  }
  const allowedTypes = messageType === "image" ?
    new Set(["image/jpeg", "image/png", "image/gif"]) : new Set(["video/mp4"]);
  const sources = input.sources.map((raw) => {
    const value = raw && typeof raw === "object" ? raw as Record<string, unknown> : {};
    const source: MessageEvidenceSourceObject = {
      attachmentID: typeof value.attachmentID === "string" ? value.attachmentID : "",
      bucket: typeof value.bucket === "string" ? value.bucket : "",
      path: typeof value.path === "string" ? value.path : "",
      generation: typeof value.generation === "string" ? value.generation : "",
      bytes: typeof value.bytes === "number" ? value.bytes : -1,
      contentType: typeof value.contentType === "string" ? value.contentType : "",
    };
    const expectedPath = `rooms/${input.roomID}/messages/${input.messageID}/attachments/${source.attachmentID}/display`;
    if (!validID(source.attachmentID) || source.bucket !== input.readyBucket ||
        source.path !== expectedPath || !/^[1-9][0-9]*$/.test(source.generation) ||
        !Number.isSafeInteger(source.bytes) || source.bytes <= 0 ||
        !allowedTypes.has(source.contentType)) {
      throw new MessageEvidenceCopyError("INVALID_EVIDENCE_SOURCE", "evidence source descriptor is invalid");
    }
    return source;
  });
  if (new Set(sources.map((source) => source.attachmentID)).size !== sources.length) {
    throw new MessageEvidenceCopyError("INVALID_EVIDENCE_SOURCE", "evidence attachment IDs must be unique");
  }
  const totalBytes = sources.reduce((sum, source) => sum + source.bytes, 0);
  if ((messageType === "image" &&
      (sources.some((source) => source.bytes > MAX_IMAGE_OBJECT_BYTES) || totalBytes > MAX_IMAGE_BUNDLE_BYTES)) ||
      (messageType === "video" && sources[0].bytes > MAX_VIDEO_OBJECT_BYTES)) {
    throw new MessageEvidenceCopyError("INVALID_EVIDENCE_SOURCE", "evidence source bytes exceed the message limit");
  }
  return sources;
}

async function claimCopyJob(
  jobID: string,
  firestore: Firestore,
  now: Date,
): Promise<ClaimedCopyJob | null> {
  const jobRef = firestore.collection(COPY_JOBS).doc(jobID);
  const nowTimestamp = Timestamp.fromDate(now);
  return firestore.runTransaction(async (transaction) => {
    const job = await transaction.get(jobRef);
    if (!job.exists) return null;
    const status = job.get("status");
    if (status === "succeeded" || status === "failed") return null;
    const nextAttemptAt = job.get("nextAttemptAt");
    const leaseExpiresAt = job.get("leaseExpiresAt");
    if (status === "processing" && leaseExpiresAt instanceof Timestamp && leaseExpiresAt.toMillis() > now.getTime()) return null;
    if (nextAttemptAt instanceof Timestamp && nextAttemptAt.toMillis() > now.getTime()) return null;
    const storedPhase = job.get("phase");
    const normalizedPhase = storedPhase === "acceptanceDrain" || storedPhase === "cleaningPartial" || storedPhase === "failureDrain" ? storedPhase : "copying";
    const previousAttempt = nonNegativeInteger(job.get("attempt"));
    // 마지막 copy lease를 획득한 worker가 종료됐다면 새 copy 시도를 만들지 않고
    // 같은 generation의 partial object를 제거한 뒤 실패 상태로 수렴시킨다.
    const phase = normalizedPhase === "copying" && status === "processing" &&
      previousAttempt >= MESSAGE_EVIDENCE_MAX_COPY_ATTEMPTS ? "cleaningPartial" : normalizedPhase;
    const attempt = phase === "copying" ? previousAttempt + 1 : previousAttempt;
    if (phase === "copying" && attempt > MESSAGE_EVIDENCE_MAX_COPY_ATTEMPTS) return null;
    const bundleID = job.get("bundleID");
    const roomID = job.get("roomID");
    const messageID = job.get("messageID");
    const attemptGeneration = nonNegativeInteger(job.get("attemptGeneration"));
    if (!validID(bundleID) || !validID(roomID) || !validID(messageID)) {
      throw new MessageEvidenceCopyError("INVALID_EVIDENCE_JOB", "evidence copy job identity is invalid");
    }
    const rawSources = job.get("sourceObjects");
    const sources = Array.isArray(rawSources) ? rawSources as MessageEvidenceSourceObject[] : [];
    const bundleRef = firestore.collection(BUNDLES).doc(bundleID);
    const bundle = await transaction.get(bundleRef);
    if (!bundle.exists || nonNegativeInteger(bundle.get("attemptGeneration")) !== attemptGeneration ||
        (phase === "copying" && !["copyPending", "copying"].includes(bundle.get("state")))) {
      throw new MessageEvidenceCopyError("STALE_EVIDENCE_GENERATION", "evidence bundle generation is stale");
    }
    const leaseToken = randomUUID();
    transaction.update(jobRef, {
      status: "processing",
      phase,
      attempt,
      leaseToken,
      leaseExpiresAt: Timestamp.fromMillis(now.getTime() + MESSAGE_EVIDENCE_COPY_LEASE_MILLIS),
      nextAttemptAt: Timestamp.fromMillis(now.getTime() + MESSAGE_EVIDENCE_COPY_LEASE_MILLIS),
      updatedAt: nowTimestamp,
    });
    if (phase === "copying") {
      transaction.set(bundleRef, {state: "copying", updatedAt: nowTimestamp}, {merge: true});
    }
    return {jobID, bundleID, roomID, messageID, messageType: job.get("messageType"), attemptGeneration, attempt, phase, leaseToken, sourceObjects: sources};
  });
}

async function markBundleAvailable(
  job: ClaimedCopyJob,
  objects: MessageEvidenceObject[],
  firestore: Firestore,
  now: Date,
): Promise<void> {
  const jobRef = firestore.collection(COPY_JOBS).doc(job.jobID);
  const bundleRef = firestore.collection(BUNDLES).doc(job.bundleID);
  const cleanupRef = firestore.collection(PUBLIC_CLEANUP_JOBS).doc(publicCleanupJobID(job.roomID, job.messageID));
  const nowTimestamp = Timestamp.fromDate(now);
  await firestore.runTransaction(async (transaction) => {
    const [jobSnapshot, bundle, cleanup] = await Promise.all([
      transaction.get(jobRef), transaction.get(bundleRef), transaction.get(cleanupRef),
    ]);
    if (jobSnapshot.get("leaseToken") !== job.leaseToken ||
        nonNegativeInteger(jobSnapshot.get("attemptGeneration")) !== job.attemptGeneration ||
        nonNegativeInteger(bundle.get("attemptGeneration")) !== job.attemptGeneration) {
      throw new MessageEvidenceCopyError("STALE_EVIDENCE_GENERATION", "evidence copy completion is stale");
    }
    transaction.set(bundleRef, {
      state: "available",
      evidenceObjects: objects,
      objectPaths: objects.map((object) => object.path),
      sourceObjects: FieldValue.delete(),
      updatedAt: nowTimestamp,
    }, {merge: true});
    transaction.set(firestore.collection(GUARDS).doc(jobSnapshot.get("incidentID")), {
      evidenceState: "available",
      updatedAt: nowTimestamp,
    }, {merge: true});
    if (cleanup.exists && cleanup.get("status") === "awaitingEvidence") {
      transaction.set(cleanupRef, {status: "pending", nextAttemptAt: nowTimestamp, updatedAt: nowTimestamp}, {merge: true});
    }
    transaction.update(jobRef, {
      phase: "acceptanceDrain",
      evidenceObjects: objects,
      sourceObjects: FieldValue.delete(),
      updatedAt: nowTimestamp,
    });
  });
}

async function markCopySucceeded(job: ClaimedCopyJob, firestore: Firestore, now: Date): Promise<void> {
  const reference = firestore.collection(COPY_JOBS).doc(job.jobID);
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists || snapshot.get("leaseToken") !== job.leaseToken ||
        nonNegativeInteger(snapshot.get("attemptGeneration")) !== job.attemptGeneration) {
      throw new MessageEvidenceCopyError("STALE_EVIDENCE_GENERATION", "evidence copy success is stale");
    }
    transaction.set(reference, {
      status: "succeeded",
      phase: "completed",
      leaseToken: null,
      leaseExpiresAt: null,
      nextAttemptAt: Timestamp.fromDate(now),
      lastErrorCode: null,
      roomID: FieldValue.delete(),
      messageID: FieldValue.delete(),
      incidentID: FieldValue.delete(),
      reviewRevision: FieldValue.delete(),
      messageType: FieldValue.delete(),
      evidenceObjects: FieldValue.delete(),
      updatedAt: Timestamp.fromDate(now),
      expiresAt: Timestamp.fromMillis(now.getTime() + MESSAGE_EVIDENCE_COMPLETED_JOB_TTL_MILLIS),
    }, {merge: true});
  });
}

async function scheduleCopyRetry(job: ClaimedCopyJob, firestore: Firestore, now: Date, code: string): Promise<void> {
  const nextAttemptAt = Timestamp.fromMillis(now.getTime() + messageEvidenceRetryDelayMillis(job.attempt));
  const jobRef = firestore.collection(COPY_JOBS).doc(job.jobID);
  const bundleRef = firestore.collection(BUNDLES).doc(job.bundleID);
  await firestore.runTransaction(async (transaction) => {
    const [jobSnapshot, bundle] = await Promise.all([transaction.get(jobRef), transaction.get(bundleRef)]);
    if (!jobSnapshot.exists || jobSnapshot.get("leaseToken") !== job.leaseToken ||
        nonNegativeInteger(jobSnapshot.get("attemptGeneration")) !== job.attemptGeneration ||
        !bundle.exists || nonNegativeInteger(bundle.get("attemptGeneration")) !== job.attemptGeneration) return;
    transaction.set(jobRef, {status: "retryPending", phase: "copying", leaseToken: null, leaseExpiresAt: null, nextAttemptAt, lastErrorCode: code, updatedAt: Timestamp.fromDate(now)}, {merge: true});
    transaction.set(bundleRef, {state: "copyPending", updatedAt: Timestamp.fromDate(now)}, {merge: true});
  });
}

async function scheduleFinalizationRetry(job: ClaimedCopyJob, phase: "acceptanceDrain" | "cleaningPartial" | "failureDrain", firestore: Firestore, now: Date, code: string | null): Promise<void> {
  const reference = firestore.collection(COPY_JOBS).doc(job.jobID);
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists || snapshot.get("leaseToken") !== job.leaseToken ||
        nonNegativeInteger(snapshot.get("attemptGeneration")) !== job.attemptGeneration) return;
    transaction.set(reference, {status: "retryPending", phase, finalizationAttempt: FieldValue.increment(1), leaseToken: null, leaseExpiresAt: null, nextAttemptAt: Timestamp.fromMillis(now.getTime() + 60_000), lastErrorCode: code, updatedAt: Timestamp.fromDate(now)}, {merge: true});
  });
}

async function beginPartialCleanup(job: ClaimedCopyJob, firestore: Firestore, now: Date): Promise<boolean> {
  const reference = firestore.collection(COPY_JOBS).doc(job.jobID);
  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists || snapshot.get("leaseToken") !== job.leaseToken ||
        nonNegativeInteger(snapshot.get("attemptGeneration")) !== job.attemptGeneration) return false;
    transaction.set(reference, {phase: "cleaningPartial", updatedAt: Timestamp.fromDate(now)}, {merge: true});
    return true;
  });
}

async function deletePartialObjects(job: ClaimedCopyJob, storage: MessageEvidenceStorage, destinationBucket: string): Promise<void> {
  for (const source of job.sourceObjects) {
    await storage.deleteAttemptObject({
      destinationBucket,
      destinationPath: messageEvidenceObjectPath({bundleID: job.bundleID, attemptGeneration: job.attemptGeneration, attachmentID: source.attachmentID}),
      bundleID: job.bundleID,
      attachmentID: source.attachmentID,
      attemptGeneration: job.attemptGeneration,
    });
  }
}

async function failPreparationBatch(job: ClaimedCopyJob, firestore: Firestore, now: Date): Promise<boolean> {
  const nowTimestamp = Timestamp.fromDate(now);
  return firestore.runTransaction(async (transaction) => {
    const jobRef = firestore.collection(COPY_JOBS).doc(job.jobID);
    const bundleRef = firestore.collection(BUNDLES).doc(job.bundleID);
    const preparations = await transaction.get(
      firestore.collection(PREPARATIONS)
        .where("bundleID", "==", job.bundleID)
        .where("status", "==", "processing")
        .orderBy("requestedAt", "asc")
        .limit(DRAIN_LIMIT + 1),
    );
    const selected = preparations.docs.slice(0, DRAIN_LIMIT);
    const requestRefs = selected.map((preparation) => firestore.collection(REQUESTS).doc(String(preparation.get("initialRequestID"))));
    const [jobSnapshot, bundle, cleanup, ...requests] = await Promise.all([
      transaction.get(jobRef),
      transaction.get(bundleRef),
      transaction.get(firestore.collection(PUBLIC_CLEANUP_JOBS).doc(publicCleanupJobID(job.roomID, job.messageID))),
      ...requestRefs.map((reference) => transaction.get(reference)),
    ]);
    if (!jobSnapshot.exists || jobSnapshot.get("leaseToken") !== job.leaseToken ||
        nonNegativeInteger(jobSnapshot.get("attemptGeneration")) !== job.attemptGeneration) {
      throw new MessageEvidenceCopyError("STALE_EVIDENCE_GENERATION", "evidence failure drain is stale");
    }
    selected.forEach((preparation, index) => {
      if (nonNegativeInteger(preparation.get("attemptGeneration")) !== job.attemptGeneration) {
        throw new MessageEvidenceCopyError("STALE_EVIDENCE_GENERATION", "evidence preparation generation is stale");
      }
      transaction.set(preparation.ref, {status: "failed", failedAt: nowTimestamp, lastErrorCode: "EVIDENCE_COPY_FAILED", updatedAt: nowTimestamp}, {merge: true});
      if (requests[index]?.exists) transaction.set(requestRefs[index], {status: "failed", lastErrorCode: "EVIDENCE_COPY_FAILED", updatedAt: nowTimestamp}, {merge: true});
    });
    const hasMore = preparations.size > selected.length;
    if (hasMore) {
      transaction.set(jobRef, {phase: "failureDrain", updatedAt: nowTimestamp}, {merge: true});
      return true;
    }
    if (!bundle.exists || nonNegativeInteger(bundle.get("attemptGeneration")) !== job.attemptGeneration) {
      throw new MessageEvidenceCopyError("STALE_EVIDENCE_GENERATION", "failed evidence bundle generation is stale");
    }
    transaction.set(bundleRef, {
      state: "failed",
      acceptanceState: "notReady",
      pendingPreparationCount: 0,
      textSnapshot: FieldValue.delete(),
      replyContextSnapshot: FieldValue.delete(),
      sharedContentSnapshot: FieldValue.delete(),
      attachmentIDs: [],
      sourceObjects: FieldValue.delete(),
      evidenceObjects: [],
      objectPaths: [],
      totalDisplayBytes: 0,
      updatedAt: nowTimestamp,
    }, {merge: true});
    transaction.set(firestore.collection(GUARDS).doc(jobSnapshot.get("incidentID")), {evidenceState: "failed", updatedAt: nowTimestamp}, {merge: true});
    const cleanupRef = firestore.collection(PUBLIC_CLEANUP_JOBS).doc(publicCleanupJobID(job.roomID, job.messageID));
    if (cleanup.exists && cleanup.get("status") === "awaitingEvidence") {
      transaction.set(cleanupRef, {status: "pending", nextAttemptAt: nowTimestamp, updatedAt: nowTimestamp}, {merge: true});
    }
    transaction.set(jobRef, {
      status: "failed",
      phase: "completed",
      roomID: FieldValue.delete(),
      messageID: FieldValue.delete(),
      incidentID: FieldValue.delete(),
      reviewRevision: FieldValue.delete(),
      messageType: FieldValue.delete(),
      sourceObjects: FieldValue.delete(),
      evidenceObjects: FieldValue.delete(),
      leaseToken: null,
      leaseExpiresAt: null,
      nextAttemptAt: null,
      lastErrorCode: "EVIDENCE_COPY_FAILED",
      updatedAt: nowTimestamp,
      expiresAt: Timestamp.fromMillis(now.getTime() + MESSAGE_EVIDENCE_COMPLETED_JOB_TTL_MILLIS),
    }, {merge: true});
    return false;
  });
}

async function drainAccepted(job: ClaimedCopyJob, firestore: Firestore, now: Date): Promise<boolean> {
  const result = await acceptMessageEvidenceBundleService(job.bundleID, job.attemptGeneration, now, firestore);
  if (result.remainingPreparationCount > 0) return false;
  await markCopySucceeded(job, firestore, now);
  return true;
}

async function drainFailed(job: ClaimedCopyJob, firestore: Firestore, now: Date): Promise<boolean> {
  return !await failPreparationBatch(job, firestore, now);
}

export async function processMessageEvidenceCopyJob(input: {
  jobID: string;
  firestore: Firestore;
  storage: MessageEvidenceStorage;
  readyBucket: string;
  evidenceBucket: string;
  now?: Date;
}): Promise<boolean> {
  const now = input.now ?? new Date();
  const job = await claimCopyJob(input.jobID, input.firestore, now);
  if (!job) return false;
  try {
    if (job.phase === "acceptanceDrain") {
      const completed = await drainAccepted(job, input.firestore, now);
      if (!completed) await scheduleFinalizationRetry(job, "acceptanceDrain", input.firestore, now, null);
      return completed;
    }
    if (job.phase === "cleaningPartial") {
      await deletePartialObjects(job, input.storage, input.evidenceBucket);
      const completed = await drainFailed(job, input.firestore, now);
      if (!completed) await scheduleFinalizationRetry(job, "failureDrain", input.firestore, now, null);
      return completed;
    }
    if (job.phase === "failureDrain") {
      const completed = await drainFailed(job, input.firestore, now);
      if (!completed) await scheduleFinalizationRetry(job, "failureDrain", input.firestore, now, null);
      return completed;
    }
    const validatedSources = validateMessageEvidenceSources({
      roomID: job.roomID,
      messageID: job.messageID,
      messageType: job.messageType,
      readyBucket: input.readyBucket,
      sources: job.sourceObjects,
    });
    const validatedJob = {...job, sourceObjects: validatedSources};
    const objects: MessageEvidenceObject[] = [];
    for (const source of validatedSources) {
      objects.push(await input.storage.copy({
        source,
        destinationBucket: input.evidenceBucket,
        destinationPath: messageEvidenceObjectPath({bundleID: job.bundleID, attemptGeneration: job.attemptGeneration, attachmentID: source.attachmentID}),
        bundleID: job.bundleID,
        attemptGeneration: job.attemptGeneration,
      }));
    }
    await markBundleAvailable(validatedJob, objects, input.firestore, now);
    try {
      const completed = await drainAccepted({...validatedJob, phase: "acceptanceDrain"}, input.firestore, now);
      if (!completed) await scheduleFinalizationRetry(job, "acceptanceDrain", input.firestore, now, null);
      return completed;
    } catch (error) {
      await scheduleFinalizationRetry(job, "acceptanceDrain", input.firestore, now, errorCode(error));
      return false;
    }
  } catch (error) {
    const code = errorCode(error);
    if (job.phase === "acceptanceDrain") {
      await scheduleFinalizationRetry(job, "acceptanceDrain", input.firestore, now, code);
      return false;
    }
    if (job.phase === "cleaningPartial" || job.phase === "failureDrain") {
      await scheduleFinalizationRetry(job, job.phase, input.firestore, now, code);
      return false;
    }
    const currentJob = await input.firestore.collection(COPY_JOBS).doc(job.jobID).get();
    if (currentJob.get("phase") === "acceptanceDrain") {
      await scheduleFinalizationRetry(job, "acceptanceDrain", input.firestore, now, code);
      return false;
    }
    if (job.attempt < MESSAGE_EVIDENCE_MAX_COPY_ATTEMPTS) {
      await scheduleCopyRetry(job, input.firestore, now, code);
      return false;
    }
    if (code === "INVALID_EVIDENCE_SOURCE") {
      const completed = await drainFailed({...job, phase: "failureDrain", sourceObjects: []}, input.firestore, now);
      if (!completed) await scheduleFinalizationRetry(job, "failureDrain", input.firestore, now, null);
      return false;
    }
    try {
      if (!await beginPartialCleanup(job, input.firestore, now)) return false;
      await deletePartialObjects(job, input.storage, input.evidenceBucket);
      const completed = await drainFailed({...job, phase: "failureDrain"}, input.firestore, now);
      if (!completed) await scheduleFinalizationRetry(job, "failureDrain", input.firestore, now, null);
    } catch (cleanupError) {
      await scheduleFinalizationRetry(job, "cleaningPartial", input.firestore, now, errorCode(cleanupError));
    }
    return false;
  }
}

export async function dueMessageEvidenceCopyJobIDs(firestore: Firestore, now = new Date()): Promise<string[]> {
  const snapshot = await firestore.collection(COPY_JOBS)
    .where("status", "in", ["pending", "retryPending", "processing"])
    .where("nextAttemptAt", "<=", Timestamp.fromDate(now))
    .orderBy("nextAttemptAt", "asc")
    .limit(DUE_JOB_LIMIT)
    .get();
  return snapshot.docs.map((document) => document.id);
}

export const messageEvidenceCopyInternals = {
  DRAIN_LIMIT,
  DUE_JOB_LIMIT,
  MESSAGE_EVIDENCE_CONTRACT_VERSION,
};
