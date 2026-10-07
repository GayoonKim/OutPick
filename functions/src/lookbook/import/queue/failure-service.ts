/* eslint-disable require-jsdoc, max-len */
import {FieldPath, type Firestore, type Transaction} from "firebase-admin/firestore";
import {parseQueueRequestEnvelope, newQueueAdmissionTimeError, QUEUE_POLICY} from "./contracts.js";
import {admitQueueRequest} from "./admission.js";
import {queueAuthorization} from "./authorization.js";
import {queueBatchID, queueDocumentID, queueHash} from "./model.js";

export function seasonImportFailureID(sourceURL: string): string {
  if (!/^https?:\/\//.test(sourceURL) || sourceURL.length > 2048) throw new Error("INVALID_CONTRACT");
  return queueHash(["importJobs", sourceURL]);
}

function exactKeys(input: Record<string, unknown>, keys: string[]) {
  if (Object.keys(input).some((key) => !keys.includes(key))) throw new Error("INVALID_CONTRACT");
}

function failureInput(input: Record<string, unknown>) {
  exactKeys(input, ["queueContractVersion", "requestID", "requestCreatedAt",
    "brandID", "failureID", "expectedVersion", "expectedExecutionID"]);
  const envelope = parseQueueRequestEnvelope(input);
  const brandID = queueDocumentID(input.brandID);
  if (typeof input.failureID !== "string" || !/^[a-f0-9]{64}$/.test(input.failureID) ||
      !Number.isSafeInteger(input.expectedVersion) || Number(input.expectedVersion) < 1) {
    throw new Error("INVALID_CONTRACT");
  }
  return {...envelope, brandID, failureID: input.failureID,
    expectedVersion: Number(input.expectedVersion),
    expectedExecutionID: queueDocumentID(input.expectedExecutionID)};
}

async function readFailedTarget(db: Firestore, tx: Transaction,
  brandID: string, failureID: string, expectedVersion: number,
  expectedExecutionID: string, now: number) {
  const ref = db.doc(`brands/${brandID}/seasonImportFailures/${failureID}`);
  const failure = (await tx.get(ref)).data();
  if (!failure) throw new Error("REQUEST_NOT_FOUND");
  if (failure.state !== "failed" || failure.version !== expectedVersion ||
      failure.latestExecutionID !== expectedExecutionID ||
      !Number.isSafeInteger(failure.expiresAt) || failure.expiresAt <= now ||
      typeof failure.sourceURL !== "string" || seasonImportFailureID(failure.sourceURL) !== failureID) {
    throw new Error("SNAPSHOT_STALE");
  }
  const jobID = queueDocumentID(failure.latestJobID);
  const executionID = queueDocumentID(failure.latestExecutionID);
  const batchID = queueDocumentID(failure.latestBatchID);
  const jobRef = db.doc(`brands/${brandID}/importJobs/${jobID}`);
  const [jobSnap, executionSnap, batchSnap, claimSnap] = await Promise.all([
    tx.get(jobRef), tx.get(jobRef.collection("executions").doc(executionID)),
    tx.get(db.doc(`lookbookImportBatches/${batchID}`)),
    tx.get(db.doc(`brands/${brandID}/queueSourceClaims/${failureID}`)),
  ]);
  const job = jobSnap.data();
  const execution = executionSnap.data();
  const claim = claimSnap.data();
  if (!job || job.jobType !== "importSeasonFromURL" || job.sourceURL !== failure.sourceURL ||
      job.queueExecutionID !== executionID || !["failed", "partialFailed"].includes(String(job.status)) ||
      !execution || !["failed", "partialFailed"].includes(String(execution.status)) ||
      execution.activeRunID != null || execution.activeAttemptID != null ||
      batchSnap.data()?.state !== "released" ||
      claim && (claim.jobID !== jobID || claim.executionID !== executionID)) {
    throw new Error("SNAPSHOT_STALE");
  }
  if (claim?.continuationPending && typeof claim.batchID === "string") {
    const continuation = (await tx.get(jobRef.collection("executions").doc(executionID)
      .collection("continuations").doc(claim.batchID))).data();
    if (continuation && ["queued", "active", "retryWaiting", "recoveryRequired"].includes(String(continuation.status))) {
      throw new Error("SNAPSHOT_STALE");
    }
  }
  return {ref, failure, job, jobID, executionID};
}

export async function admitSeasonImportFailureRetry(db: Firestore, uid: string,
  data: Record<string, unknown>, now = Date.now()) {
  const input = failureInput(data);
  const payload = {failureID: input.failureID, expectedVersion: input.expectedVersion,
    expectedExecutionID: input.expectedExecutionID};
  let frozen: Awaited<ReturnType<typeof readFailedTarget>> | undefined;
  return admitQueueRequest(db, uid, {...input, kind: "manualRetry", payload}, {
    authorize: queueAuthorization(db),
    freezeTargets: async (tx) => {
      frozen = await readFailedTarget(db, tx, input.brandID, input.failureID,
        input.expectedVersion, input.expectedExecutionID, now);
      return [{targetID: input.failureID, claimKey: frozen.failure.sourceURL,
        collection: "importJobs", jobData: {}, continuation: {
          jobID: frozen.jobID, mode: "manualRetry", executionID: null,
          expected: {status: frozen.job.status, queueExecutionID: frozen.executionID},
          input: {resumeFrom: "parsing", failureRetry: true,
            failureID: input.failureID, failureVersion: input.expectedVersion + 1,
            reviewGeneration: Number(frozen.job.reviewGeneration ?? 0) + 1},
        }}];
    },
    commit: (tx, batch) => {
      if (!frozen) throw new Error("QUEUE_CORRUPT");
      const batchID = queueBatchID(uid, input.requestID);
      const executionID = queueHash([batchID, batch.items[0].itemID, "execution"]);
      tx.update(frozen.ref, {state: "retryQueued", version: input.expectedVersion + 1,
        latestRequestID: input.requestID, latestBatchID: batchID,
        latestJobID: frozen.jobID, latestExecutionID: executionID,
        attemptCount: 0, attemptLimit: QUEUE_POLICY.importAttempts,
        updatedAt: now, expiresAt: null});
    },
  }, now);
}

export async function dismissSeasonImportFailure(db: Firestore, uid: string,
  data: Record<string, unknown>, now = Date.now()) {
  const input = failureInput(data);
  const digest = queueHash(input);
  const receiptRef = db.doc(`brands/${input.brandID}/seasonImportFailureActions/${queueBatchID(uid, input.requestID)}`);
  return db.runTransaction(async (tx) => {
    await queueAuthorization(db)(tx, uid, input.brandID);
    const receipt = (await tx.get(receiptRef)).data();
    if (receipt) {
      if (receipt.requestedBy !== uid || receipt.payloadDigest !== digest) throw new Error("REQUEST_ID_CONFLICT");
      return {requestID: input.requestID, failureID: input.failureID, removed: true};
    }
    const timeError = newQueueAdmissionTimeError(input.requestCreatedAt, now);
    if (timeError) throw new Error(timeError);
    const target = await readFailedTarget(db, tx, input.brandID, input.failureID,
      input.expectedVersion, input.expectedExecutionID, now);
    tx.delete(target.ref);
    // 늦은 같은 실행의 실패 보고가 제거한 목록을 다시 만들지 못하게 한다.
    tx.update(db.doc(`brands/${input.brandID}/importJobs/${target.jobID}`)
      .collection("executions").doc(target.executionID), {
      dismissedFailureID: input.failureID, failureDismissedAt: now,
    });
    tx.create(receiptRef, {requestedBy: uid, requestID: input.requestID,
      failureID: input.failureID, payloadDigest: digest, createdAt: now,
      expiresAt: now + QUEUE_POLICY.receiptRetentionMs});
    return {requestID: input.requestID, failureID: input.failureID, removed: true};
  });
}

export async function listSeasonImportFailures(db: Firestore, uid: string,
  data: Record<string, unknown>, now = Date.now()) {
  exactKeys(data, ["brandID", "cursor"]);
  const brandID = queueDocumentID(data.brandID);
  let cursor: {updatedAt: number; failureID: string} | null = null;
  if (data.cursor != null) {
    if (typeof data.cursor !== "object" || Array.isArray(data.cursor)) throw new Error("INVALID_CONTRACT");
    const raw = data.cursor as Record<string, unknown>;
    exactKeys(raw, ["updatedAt", "failureID"]);
    if (!Number.isSafeInteger(raw.updatedAt) || Number(raw.updatedAt) < 0 ||
        typeof raw.failureID !== "string" || !/^[a-f0-9]{64}$/.test(raw.failureID)) throw new Error("INVALID_CONTRACT");
    cursor = {updatedAt: Number(raw.updatedAt), failureID: raw.failureID};
  }
  return db.runTransaction(async (tx) => {
    await queueAuthorization(db)(tx, uid, brandID);
    let query = db.collection(`brands/${brandID}/seasonImportFailures`)
      .orderBy("updatedAt", "desc").orderBy(FieldPath.documentId(), "desc");
    if (cursor) query = query.startAfter(cursor.updatedAt, cursor.failureID);
    const page = await tx.get(query.limit(100));
    const items = page.docs.filter((doc) => {
      const value = doc.data();
      return value.state !== "failed" || Number.isSafeInteger(value.expiresAt) && value.expiresAt > now;
    }).map((doc) => {
      const value = doc.data();
      const fields = ["sourceURL", "sourceCandidateID", "displayTitle", "state", "version",
        "latestRequestID", "latestBatchID", "latestJobID", "latestExecutionID",
        "attemptCount", "attemptLimit", "failureStage", "errorCode", "errorMessage", "failedAt", "updatedAt"];
      return {failureID: doc.id, ...Object.fromEntries(fields.map((key) => [key, value[key] ?? null]))};
    });
    const last = page.docs.at(-1);
    return {brandID, items, nextCursor: page.size === 100 && last ?
      {updatedAt: last.data().updatedAt, failureID: last.id} : null};
  });
}
