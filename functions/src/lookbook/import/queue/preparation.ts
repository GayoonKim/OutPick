/* eslint-disable require-jsdoc */
import {Timestamp, type Firestore} from "firebase-admin/firestore";
import {QUEUE_POLICY} from "./contracts.js";
import {
  BATCH_COLLECTION, QUEUE_PATH, queueHash, queueDocumentID,
  type AdmissionTarget, type QueueBatch,
} from "./model.js";
import {projectQueueReceipt} from "./projection.js";
import {assertQueueBrandAvailable} from "./authorization.js";
import {assetRetrySource} from "./asset-retry.js";

export async function beginQueuePreparation(
  db: Firestore, batchID: string, owner: string, now = Date.now()
) {
  queueDocumentID(batchID);
  queueDocumentID(owner);
  const ref = db.doc(`${BATCH_COLLECTION}/${batchID}`);
  return db.runTransaction(async (transaction) => {
    const batch = (await transaction.get(ref)).data() as QueueBatch | undefined;
    const queue = (await transaction.get(db.doc(QUEUE_PATH))).data();
    if (!batch) throw new Error("REQUEST_NOT_FOUND");
    if (queue?.state === "recoveryRequired") return false;
    if (batch.state !== "preparing") return false;
    if (queue?.preparationSequence !== batch.sequence) return false;
    if (batch.preparationOwner) throw new Error("PREPARATION_BUSY");
    if (batch.preparationAttempts >= QUEUE_POLICY.preparationAttempts) {
      throw new Error("PREPARATION_EXHAUSTED");
    }
    transaction.update(ref, {
      preparationOwner: owner,
      preparationAttempts: batch.preparationAttempts + 1,
      stateRevision: batch.stateRevision + 1,
      updatedAt: now,
    });
    return true;
  });
}

export async function prepareQueueItem(
  db: Firestore, batchID: string, ordinal: number, owner: string,
  now = Date.now()
) {
  queueDocumentID(batchID);
  if (!Number.isInteger(ordinal) || ordinal < 0) {
    throw new Error("INVALID_CONTRACT");
  }
  const ref = db.doc(`${BATCH_COLLECTION}/${batchID}`);
  return db.runTransaction(async (transaction) => {
    const batch = (await transaction.get(ref)).data() as QueueBatch | undefined;
    if (!batch || batch.state !== "preparing" ||
        batch.preparationOwner !== owner) throw new Error("PREPARATION_OWNER");
    const supported = ["importSeasons", "discoverSeasons", "assetRetry",
      "reviewApproval", "manualRetry", "repair"];
    if (!supported.includes(batch.kind)) {
      throw new Error("PREPARATION_KIND_NOT_CONNECTED");
    }
    const item = batch.items[ordinal];
    if (!item) throw new Error("INVALID_CONTRACT");
    if (item.admissionStatus !== "pending") return item;
    const target = (await transaction.get(ref.collection("inputs")
      .doc(String(ordinal)))).data() as AdmissionTarget | undefined;
    if (!target) throw new Error("QUEUE_CORRUPT");
    if (["reviewApproval", "manualRetry", "repair"].includes(batch.kind) &&
        !target.continuation && !target.existingJobID) {
      throw new Error("PREPARATION_KIND_NOT_CONNECTED");
    }
    if (batch.kind === "assetRetry" &&
        !target.assetRetry && !target.existingJobID) {
      throw new Error("INVALID_CONTRACT");
    }
    await assertQueueBrandAvailable(db, transaction, batch.brandID);
    const brandRef = db.doc(`brands/${batch.brandID}`);
    // 접수 때 고정한 중복 대상이 없어져도 새 작업으로 바꾸지 않는다.
    // 기존 job의 상태·실행권·이력은 현재 담당 실행이 계속 소유한다.
    if (target.existingJobID !== undefined) {
      const existingID = queueDocumentID(target.existingJobID);
      const existing = await transaction.get(
        brandRef.collection(target.collection).doc(existingID));
      if (!existing.exists) throw new Error("QUEUE_REFERENCE_NOT_FOUND");
      const execution = target.existingExecutionID ??
        existing.data()?.queueExecutionID;
      const updatedItem = {
        ...item, admissionStatus: "duplicate" as const,
        processingStatus: String(existing.data()?.status ?? "queued"),
        jobID: existingID,
        executionID: typeof execution === "string" ? execution : null,
        errorCode: null,
      };
      const items = batch.items.slice();
      items[ordinal] = updatedItem;
      transaction.update(ref, {
        items, stateRevision: batch.stateRevision + 1, updatedAt: now,
      });
      return updatedItem;
    }
    const claimRef = brandRef.collection("queueSourceClaims")
      .doc(queueHash([target.collection, target.claimKey]));
    const claim = (await transaction.get(claimRef)).data();
    const existing = claim ? await transaction.get(
      brandRef.collection(target.collection).doc(claim.jobID)
    ) : null;
    if (claim && !existing?.exists) throw new Error("QUEUE_CLAIM_UNRESOLVED");
    const claimedExecution = claim && existing &&
      typeof claim.executionID === "string" ?
      (await transaction.get(existing.ref.collection("executions")
        .doc(claim.executionID))).data() : undefined;
    const claimedContinuation = claim?.continuationPending && existing &&
      typeof claim.executionID === "string" &&
      typeof claim.batchID === "string" ?
      (await transaction.get(existing.ref.collection("executions")
        .doc(claim.executionID).collection("continuations")
        .doc(claim.batchID))).data() : undefined;
    const pendingExecution = claimedContinuation?.status === "queued" ||
      claimedExecution &&
      ["queued", "active", "draining", "retryWaiting", "recoveryRequired"]
        .includes(claimedExecution.status);
    if (target.continuation) {
      const continuation = target.continuation;
      const jobRef = brandRef.collection(target.collection)
        .doc(continuation.jobID);
      const source = (await transaction.get(jobRef)).data();
      if (!source) throw new Error("QUEUE_REFERENCE_NOT_FOUND");
      const requestedExecutionID = continuation.executionID ??
        queueHash([batchID, item.itemID, "execution"]);
      const executionRef = jobRef.collection("executions")
        .doc(requestedExecutionID);
      const previousExecution = (await transaction.get(executionRef)).data();
      if (!pendingExecution) {
        const actual = Object.fromEntries(Object.keys(continuation.expected)
          .map((key) => [key, source[key] ?? null]));
        if (queueHash(actual) !== queueHash(continuation.expected)) {
          throw new Error("CONTINUATION_SOURCE_CHANGED");
        }
      }
      const duplicate = Boolean(pendingExecution);
      const executionID = duplicate ? claim!.executionID : requestedExecutionID;
      const updatedItem = {
        ...item, admissionStatus: duplicate ? "duplicate" as const :
          "created" as const,
        processingStatus: duplicate ? String(claimedContinuation?.status ??
          claimedExecution?.status ?? source.status ?? "queued") : "queued",
        jobID: duplicate ? claim!.jobID : continuation.jobID,
        executionID, errorCode: null,
      };
      if (!duplicate) {
        // 승인 continuation은 기존 execution 이력/시도 횟수를 그대로 둔다.
        // 실제 실행권과 root 반영은 Q2의 자기 차례 활성화에서 수행한다.
        const attemptLimit = target.collection === "seasonDiscoveryJobs" ?
          QUEUE_POLICY.discoveryAttempts : QUEUE_POLICY.importAttempts;
        if (previousExecution && continuation.mode !== "reviewApproval") {
          throw new Error("QUEUE_EXECUTION_CONFLICT");
        }
        if (!previousExecution) {
          transaction.create(executionRef, {
            batchID, itemID: item.itemID, status: "queued",
            attemptCount: continuation.mode === "reviewApproval" ?
              Number(source.attemptCount ?? 0) : 0,
            attemptLimit, mode: continuation.mode, createdAt: now,
          });
        }
        transaction.create(executionRef.collection("continuations")
          .doc(batchID), {batchID, input: continuation.input,
          mode: continuation.mode, expected: continuation.expected,
          status: "queued", createdAt: now});
        transaction.set(claimRef, {
          jobID: continuation.jobID, executionID, batchID,
          continuationPending: true, updatedAt: now,
        });
      }
      const items = batch.items.slice();
      items[ordinal] = updatedItem;
      transaction.update(ref, {
        items, stateRevision: batch.stateRevision + 1, updatedAt: now,
      });
      return updatedItem;
    }
    if (target.assetRetry) {
      const retry = target.assetRetry;
      const sourceRef = brandRef.collection("importJobs").doc(retry.jobID);
      const source = (await transaction.get(sourceRef)).data();
      if (!source) throw new Error("QUEUE_REFERENCE_NOT_FOUND");
      const duplicate = Boolean(pendingExecution);
      if (!duplicate && assetRetrySource(source).sourceDigest !==
          retry.sourceDigest) throw new Error("ASSET_RETRY_SOURCE_CHANGED");
      const executionID = duplicate ? claim!.executionID :
        queueHash([batchID, item.itemID, "execution"]);
      const jobID = duplicate ? claim!.jobID :
        queueHash([batchID, item.itemID, "assetRetry"]);
      const updatedItem = {
        ...item, admissionStatus: duplicate ? "duplicate" as const :
          "created" as const,
        processingStatus: duplicate ? String(claimedExecution?.status ??
          source.status ?? "queued") : "queued",
        jobID,
        executionID, errorCode: null,
      };
      if (!duplicate) {
        const jobRef = brandRef.collection("importJobs").doc(jobID);
        transaction.create(jobRef, {
          jobType: "retrySeasonAssets",
          brandID: batch.brandID,
          sourceURL: retry.sourceURL,
          sourceImportJobID: retry.jobID,
          targetSeasonID: retry.targetSeasonID,
          createdPostIDs: retry.createdPostIDs,
          status: "queued",
          phase: "dispatching",
          dispatchGeneration: 0,
          resumeFrom: "materializing",
          queueContractVersion: 1,
          queueBatchID: batchID,
          queueExecutionID: executionID,
          dispatchMode: "batchQueue",
          createdAt: Timestamp.fromMillis(now),
          updatedAt: Timestamp.fromMillis(now),
        });
        transaction.create(jobRef.collection("executions").doc(executionID), {
          batchID, itemID: item.itemID, status: "queued", attemptCount: 0,
          attemptLimit: QUEUE_POLICY.importAttempts,
          mode: "assetFailureRetry", input: retry, createdAt: now,
        });
        transaction.set(claimRef, {
          jobID, executionID, batchID, updatedAt: now,
        });
      }
      const items = batch.items.slice();
      items[ordinal] = updatedItem;
      transaction.update(ref, {
        items, stateRevision: batch.stateRevision + 1, updatedAt: now,
      });
      return updatedItem;
    }
    const status = existing?.data()?.status;
    const blocking = target.collection === "importJobs" ?
      ["queued", "processing", "awaitingReview", "succeeded", "partialFailed"] :
      ["queued", "dispatching", "running"];
    const duplicate = claim && (pendingExecution || blocking.includes(status));
    const jobID = duplicate ? String(claim.jobID) :
      queueHash([batchID, item.itemID, "job"]);
    const executionID = duplicate ?
      (typeof claim.executionID === "string" ? claim.executionID : null) :
      queueHash([batchID, item.itemID, "execution"]);
    const updatedItem = {
      ...item, admissionStatus: duplicate ? "duplicate" as const :
        "created" as const,
      processingStatus: duplicate ? String(claimedExecution?.status ??
        existing?.data()?.status ?? "queued") : "queued",
      jobID, executionID, errorCode: null,
    };
    if (!duplicate) {
      const jobRef = brandRef.collection(target.collection).doc(jobID);
      transaction.create(jobRef, {
        ...target.jobData,
        brandID: batch.brandID, requestedBy: batch.requestedBy,
        queueContractVersion: 1, queueBatchID: batchID,
        queueExecutionID: executionID, status: "queued",
        dispatchMode: "batchQueue", phase: "dispatching",
        attemptCount: 0,
        createdAt: Timestamp.fromMillis(now),
        updatedAt: Timestamp.fromMillis(now),
      });
      transaction.create(jobRef.collection("executions").doc(executionID!), {
        batchID, itemID: item.itemID, status: "queued", attemptCount: 0,
        attemptLimit: target.collection === "seasonDiscoveryJobs" ?
          QUEUE_POLICY.discoveryAttempts : QUEUE_POLICY.importAttempts,
        createdAt: now,
      });
      transaction.set(claimRef, {jobID, executionID, batchID, updatedAt: now});
    }
    const items = batch.items.slice();
    items[ordinal] = updatedItem;
    transaction.update(ref, {
      items, stateRevision: batch.stateRevision + 1, updatedAt: now,
    });
    return updatedItem;
  });
}

// 호출자가 시작한 모든 item promise의 종료를 확인한 뒤에만 호출한다.
// batch를 함께 쓰므로 늦은 이전 transaction은 owner 변경 뒤 commit할 수 없다.
export async function finishQueuePreparation(
  db: Firestore, batchID: string, owner: string, now = Date.now()
) {
  queueDocumentID(batchID);
  const ref = db.doc(`${BATCH_COLLECTION}/${batchID}`);
  const queueRef = db.doc(QUEUE_PATH);
  return db.runTransaction(async (transaction) => {
    const batch = (await transaction.get(ref)).data() as QueueBatch | undefined;
    const queue = (await transaction.get(queueRef)).data();
    if (!batch || batch.state !== "preparing" ||
        batch.preparationOwner !== owner ||
        queue?.preparationSequence !== batch.sequence) {
      throw new Error("PREPARATION_OWNER");
    }
    const exhausted =
      batch.preparationAttempts >= QUEUE_POLICY.preparationAttempts;
    const items = batch.items.map((item) =>
      exhausted && item.admissionStatus === "pending" ? {
        ...item, admissionStatus: "failed" as const,
        errorCode: "PREPARATION_EXHAUSTED",
      } : item);
    const pending = items.some((item) => item.admissionStatus === "pending");
    const hasCreated = items.some((item) => item.admissionStatus === "created");
    const hasPreparationFailure = items.some((item) =>
      item.admissionStatus === "failed");
    const updated: QueueBatch = {
      ...batch, items, preparationOwner: null,
      state: pending ? "preparing" : hasCreated ? "queued" : "released",
      dispatchState: pending || !hasCreated ? "none" : "pending",
      ...(!pending && !hasCreated ? {releasedAt: now,
        detailCleanupAfter: now + (hasPreparationFailure ?
          QUEUE_POLICY.resolvedFailureRetentionMs :
          QUEUE_POLICY.successDetailRetentionMs),
        receiptExpiresAt: now + QUEUE_POLICY.receiptRetentionMs,
        retentionNextAt: now + (hasPreparationFailure ?
          QUEUE_POLICY.resolvedFailureRetentionMs :
          QUEUE_POLICY.successDetailRetentionMs)} : {}),
      stateRevision: batch.stateRevision + 1, updatedAt: now,
    };
    transaction.set(ref, updated);
    if (!pending) {
      transaction.update(queueRef, {
        preparationSequence: batch.sequence + 1,
      });
    }
    return projectQueueReceipt(batchID, updated);
  });
}
