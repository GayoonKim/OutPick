/* eslint-disable require-jsdoc, max-len */
import {randomUUID} from "node:crypto";
import {
  Timestamp,
  type Firestore,
  type QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import {messageIncidentID} from "../../moderation/messageEvidence/contracts.js";
import {
  CHAT_MEDIA_EXPIRY_CONTRACT_VERSION,
  CHAT_MEDIA_EXPIRY_JOBS,
  CHAT_MEDIA_EXPIRY_LEASE_MILLIS,
  CHAT_MEDIA_EXPIRY_MAX_CONCURRENCY,
  CHAT_MEDIA_EXPIRY_MAX_JOBS_PER_RUN,
  CHAT_MEDIA_EXPIRY_QUERY_LIMIT,
  CHAT_MEDIA_EXPIRY_RETRY_ATTEMPTS,
  CHAT_MEDIA_EXPIRY_START_BUDGET_MILLIS,
  ChatMediaExpiryObject,
  nextChatMediaExpiryAttemptAt,
} from "./retentionContracts.js";

const DUE_STATUSES = ["scheduled", "retryPending"];
const EVIDENCE_FINAL_STATES = new Set(["available", "failed"]);

export type ChatMediaRetentionStorage = {
  deleteExactGeneration: (object: ChatMediaExpiryObject) => Promise<void>;
};

export type ChatMediaExpiryProcessResult = "deleted" | "deferred" | "held" | "skipped";

type ClaimedJob = {
  jobID: string;
  leaseToken: string;
  roomID: string;
  messageID: string;
  mediaExpiresAt: Timestamp;
  objects: ChatMediaExpiryObject[];
};

type Clock = () => Date;

function validID(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 &&
    value.length <= 512 && !value.includes("/");
}

function storageErrorCode(error: unknown): string {
  if (!error || typeof error !== "object") return "storage_delete_failed";
  const value = (error as {code?: unknown}).code;
  const code = typeof value === "string" ? Number(value) : value;
  if (code === 412) return "storage_generation_mismatch";
  if (code === 403 || code === 401) return "storage_permission_denied";
  if (code === 404) return "storage_object_state_changed";
  if (code === 408 || code === 429 || (typeof code === "number" && code >= 500)) {
    return "storage_temporarily_unavailable";
  }
  return "storage_delete_failed";
}

function validateObjects(
  value: unknown,
  roomID: string,
  messageID: string,
  readyBucket: string,
): ChatMediaExpiryObject[] | null {
  if (!Array.isArray(value) || value.length < 1 || value.length > 60) return null;
  const objects: ChatMediaExpiryObject[] = [];
  const identities = new Set<string>();
  for (const raw of value) {
    const entry = raw && typeof raw === "object" ? raw as Record<string, unknown> : {};
    const role = entry.role === "original" || entry.role === "thumbnail" ? entry.role : null;
    const object = {
      bucket: typeof entry.bucket === "string" ? entry.bucket : "",
      path: typeof entry.path === "string" ? entry.path : "",
      generation: typeof entry.generation === "string" ? entry.generation : "",
      role,
    };
    const prefix = `rooms/${roomID}/messages/${messageID}/attachments/`;
    const suffix = role === "original" ? "/display" : role === "thumbnail" ? "/thumbnail" : "";
    const attachmentID = object.path.startsWith(prefix) && object.path.endsWith(suffix) ?
      object.path.slice(prefix.length, -suffix.length) : "";
    if (!role || object.bucket !== readyBucket || !validID(attachmentID) ||
        object.path !== `${prefix}${attachmentID}${suffix}` ||
        !/^[1-9][0-9]*$/.test(object.generation)) return null;
    const identity = `${object.bucket}\0${object.path}\0${object.generation}`;
    if (identities.has(identity)) return null;
    identities.add(identity);
    objects.push({...object, role});
  }
  return objects;
}

function evidenceIsPending(guard: FirebaseFirestore.DocumentData | undefined): boolean {
  return guard?.guardWinner === "reportFirst" &&
    !EVIDENCE_FINAL_STATES.has(String(guard.evidenceState ?? ""));
}

async function claimJob(input: {
  firestore: Firestore;
  jobID: string;
  readyBucket: string;
  now: Date;
}): Promise<{result: "claimed"; job: ClaimedJob} | {result: "held" | "skipped"}> {
  const reference = input.firestore.collection(CHAT_MEDIA_EXPIRY_JOBS).doc(input.jobID);
  const nowTimestamp = Timestamp.fromDate(input.now);
  return input.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return {result: "skipped"};
    const data = snapshot.data();
    if (!data || ![...DUE_STATUSES, "processing"].includes(String(data.status))) {
      return {result: "skipped"};
    }
    if (data.status === "processing") {
      const lease = data.leaseExpiresAt;
      if (!(lease instanceof Timestamp) || lease.toMillis() > input.now.getTime()) {
        return {result: "skipped"};
      }
    } else {
      const nextAttemptAt = data.nextAttemptAt;
      if (!(nextAttemptAt instanceof Timestamp) || nextAttemptAt.toMillis() > input.now.getTime()) {
        return {result: "skipped"};
      }
    }
    const roomID = data.roomID;
    const messageID = data.messageID;
    const mediaExpiresAt = data.mediaExpiresAt;
    const sentAt = data.sentAt;
    const objects = validID(roomID) && validID(messageID) &&
      mediaExpiresAt instanceof Timestamp && sentAt instanceof Timestamp &&
      mediaExpiresAt.toMillis() - sentAt.toMillis() === 7 * 24 * 60 * 60 * 1000 ?
      validateObjects(data.objects, roomID, messageID, input.readyBucket) : null;
    if (data.schemaVersion !== CHAT_MEDIA_EXPIRY_CONTRACT_VERSION || !objects ||
        !(mediaExpiresAt instanceof Timestamp)) {
      transaction.set(reference, {
        status: "retryPending",
        attemptsInRun: 0,
        nextAttemptAt: nextChatMediaExpiryAttemptAt(input.now),
        leaseToken: null,
        leaseExpiresAt: null,
        lastErrorCode: "invalid_expiry_job",
        updatedAt: nowTimestamp,
      }, {merge: true});
      return {result: "skipped"};
    }
    if (mediaExpiresAt.toMillis() > input.now.getTime()) {
      transaction.set(reference, {
        status: "scheduled",
        attemptsInRun: 0,
        nextAttemptAt: mediaExpiresAt,
        leaseToken: null,
        leaseExpiresAt: null,
        lastErrorCode: null,
        updatedAt: nowTimestamp,
      }, {merge: true});
      return {result: "skipped"};
    }

    const guardRef = input.firestore.collection("moderationMessageGuards")
      .doc(messageIncidentID(roomID, messageID));
    const guard = await transaction.get(guardRef);
    if (evidenceIsPending(guard.data())) {
      transaction.update(reference, {
        status: "awaitingEvidence",
        attemptsInRun: 0,
        nextAttemptAt: null,
        leaseToken: null,
        leaseExpiresAt: null,
        lastErrorCode: null,
        updatedAt: nowTimestamp,
      });
      return {result: "held"};
    }

    const leaseToken = randomUUID();
    transaction.update(reference, {
      status: "processing",
      attemptsInRun: 0,
      nextAttemptAt: Timestamp.fromMillis(input.now.getTime() + CHAT_MEDIA_EXPIRY_LEASE_MILLIS),
      leaseToken,
      leaseExpiresAt: Timestamp.fromMillis(input.now.getTime() + CHAT_MEDIA_EXPIRY_LEASE_MILLIS),
      lastErrorCode: null,
      updatedAt: nowTimestamp,
    });
    return {
      result: "claimed",
      job: {jobID: input.jobID, leaseToken, roomID, messageID, mediaExpiresAt, objects},
    };
  });
}

async function finishJob(input: {
  firestore: Firestore;
  job: ClaimedJob;
  remainingObjects: ChatMediaExpiryObject[];
  attemptsInRun: number;
  errorCode: string | null;
  now: Date;
}): Promise<boolean> {
  const reference = input.firestore.collection(CHAT_MEDIA_EXPIRY_JOBS).doc(input.job.jobID);
  return input.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists || snapshot.get("leaseToken") !== input.job.leaseToken) return false;
    if (input.remainingObjects.length === 0) {
      transaction.delete(reference);
      return true;
    }
    transaction.update(reference, {
      objects: input.remainingObjects,
      status: "retryPending",
      attemptsInRun: input.attemptsInRun,
      nextAttemptAt: nextChatMediaExpiryAttemptAt(input.now),
      leaseToken: null,
      leaseExpiresAt: null,
      lastErrorCode: input.errorCode,
      updatedAt: Timestamp.fromDate(input.now),
    });
    return true;
  });
}

export async function processChatMediaExpiryJob(input: {
  firestore: Firestore;
  storage: ChatMediaRetentionStorage;
  readyBucket: string;
  jobID: string;
  now?: Date;
  clock?: Clock;
  startDeadlineMillis?: number;
}): Promise<ChatMediaExpiryProcessResult> {
  const clock = input.clock ?? (() => input.now ?? new Date());
  if (input.startDeadlineMillis !== undefined &&
      clock().getTime() >= input.startDeadlineMillis) return "skipped";
  const claim = await claimJob({
    firestore: input.firestore,
    jobID: input.jobID,
    readyBucket: input.readyBucket,
    now: clock(),
  });
  if (claim.result !== "claimed") return claim.result;

  let remainingObjects = claim.job.objects;
  let attemptsInRun = 0;
  let lastErrorCode: string | null = null;
  let budgetExhausted = false;
  for (let attempt = 1; attempt <= CHAT_MEDIA_EXPIRY_RETRY_ATTEMPTS &&
      remainingObjects.length > 0; attempt++) {
    const beforeAttempt = clock();
    if (input.startDeadlineMillis !== undefined &&
        beforeAttempt.getTime() >= input.startDeadlineMillis) {
      budgetExhausted = true;
      break;
    }
    let attemptedAtLeastOneObject = false;
    const failedObjects: ChatMediaExpiryObject[] = [];
    for (const object of remainingObjects) {
      if (input.startDeadlineMillis !== undefined &&
          clock().getTime() >= input.startDeadlineMillis) {
        budgetExhausted = true;
        failedObjects.push(object, ...remainingObjects.slice(remainingObjects.indexOf(object) + 1));
        break;
      }
      attemptedAtLeastOneObject = true;
      try {
        await input.storage.deleteExactGeneration(object);
      } catch (error) {
        failedObjects.push(object);
        lastErrorCode = storageErrorCode(error);
      }
    }
    if (attemptedAtLeastOneObject) attemptsInRun = attempt;
    remainingObjects = failedObjects;
    if (budgetExhausted) break;
  }

  const persisted = await finishJob({
    firestore: input.firestore,
    job: claim.job,
    remainingObjects,
    attemptsInRun,
    errorCode: budgetExhausted && !lastErrorCode ? "execution_budget_exhausted" : lastErrorCode,
    now: clock(),
  });
  if (!persisted) return "skipped";
  return remainingObjects.length === 0 ? "deleted" : "deferred";
}

type DueCursor = QueryDocumentSnapshot | null;

async function dueBatch(input: {
  firestore: Firestore;
  now: Date;
  scheduledCursor: DueCursor;
  leaseCursor: DueCursor;
}): Promise<{
  candidates: Array<{snapshot: QueryDocumentSnapshot; dueAtMillis: number; stream: "scheduled" | "lease"}>;
}> {
  const nowTimestamp = Timestamp.fromDate(input.now);
  let scheduledQuery = input.firestore.collection(CHAT_MEDIA_EXPIRY_JOBS)
    .where("status", "in", DUE_STATUSES)
    .where("nextAttemptAt", "<=", nowTimestamp)
    .orderBy("nextAttemptAt", "asc")
    .limit(CHAT_MEDIA_EXPIRY_QUERY_LIMIT);
  let leaseQuery = input.firestore.collection(CHAT_MEDIA_EXPIRY_JOBS)
    .where("status", "==", "processing")
    .where("leaseExpiresAt", "<=", nowTimestamp)
    .orderBy("leaseExpiresAt", "asc")
    .limit(CHAT_MEDIA_EXPIRY_QUERY_LIMIT);
  if (input.scheduledCursor) scheduledQuery = scheduledQuery.startAfter(input.scheduledCursor);
  if (input.leaseCursor) leaseQuery = leaseQuery.startAfter(input.leaseCursor);
  const [scheduled, leases] = await Promise.all([scheduledQuery.get(), leaseQuery.get()]);
  const candidates = [
    ...scheduled.docs.map((snapshot) => ({
      snapshot,
      dueAtMillis: (snapshot.get("nextAttemptAt") as Timestamp).toMillis(),
      stream: "scheduled" as const,
    })),
    ...leases.docs.map((snapshot) => ({
      snapshot,
      dueAtMillis: (snapshot.get("leaseExpiresAt") as Timestamp).toMillis(),
      stream: "lease" as const,
    })),
  ].sort((left, right) => left.dueAtMillis - right.dueAtMillis ||
    left.snapshot.id.localeCompare(right.snapshot.id));
  return {candidates};
}

export async function drainDueChatMediaExpiryJobs(input: {
  firestore: Firestore;
  storage: ChatMediaRetentionStorage;
  readyBucket: string;
  clock?: Clock;
  startDeadlineMillis?: number;
  processJob?: typeof processChatMediaExpiryJob;
}): Promise<{candidateCount: number; resultCounts: Record<ChatMediaExpiryProcessResult, number>}> {
  const clock = input.clock ?? (() => new Date());
  const deadline = input.startDeadlineMillis ??
    clock().getTime() + CHAT_MEDIA_EXPIRY_START_BUDGET_MILLIS;
  const processJob = input.processJob ?? processChatMediaExpiryJob;
  let scheduledCursor: DueCursor = null;
  let leaseCursor: DueCursor = null;
  let candidateCount = 0;
  const resultCounts: Record<ChatMediaExpiryProcessResult, number> = {
    deleted: 0,
    deferred: 0,
    held: 0,
    skipped: 0,
  };

  while (candidateCount < CHAT_MEDIA_EXPIRY_MAX_JOBS_PER_RUN &&
      clock().getTime() < deadline) {
    const {candidates} = await dueBatch({
      firestore: input.firestore,
      now: clock(),
      scheduledCursor,
      leaseCursor,
    });
    const remainingCapacity = CHAT_MEDIA_EXPIRY_MAX_JOBS_PER_RUN - candidateCount;
    const batch = candidates.slice(0, Math.min(CHAT_MEDIA_EXPIRY_QUERY_LIMIT, remainingCapacity));
    if (batch.length === 0) break;
    const lastScheduled = batch.filter((item) => item.stream === "scheduled").at(-1);
    const lastLease = batch.filter((item) => item.stream === "lease").at(-1);
    if (lastScheduled) scheduledCursor = lastScheduled.snapshot;
    if (lastLease) leaseCursor = lastLease.snapshot;
    candidateCount += batch.length;

    for (let offset = 0; offset < batch.length; offset += CHAT_MEDIA_EXPIRY_MAX_CONCURRENCY) {
      if (clock().getTime() >= deadline) break;
      const work = batch.slice(offset, offset + CHAT_MEDIA_EXPIRY_MAX_CONCURRENCY);
      const results = await Promise.all(work.map(async ({snapshot}) => processJob({
        firestore: input.firestore,
        storage: input.storage,
        readyBucket: input.readyBucket,
        jobID: snapshot.id,
        clock,
        startDeadlineMillis: deadline,
      })));
      for (const result of results) resultCounts[result] += 1;
    }
  }
  return {candidateCount, resultCounts};
}

export const chatMediaRetentionInternals = {
  DUE_STATUSES,
  EVIDENCE_FINAL_STATES,
  evidenceIsPending,
  storageErrorCode,
  validateObjects,
};
