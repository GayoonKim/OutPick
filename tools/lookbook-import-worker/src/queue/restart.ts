/* eslint-disable require-jsdoc, max-len */
import type {Firestore} from "firebase-admin/firestore";
import {QUEUE_POLICY} from "./contracts.js";
import {readOwnedBatch, type BatchOwnership} from "./coordinator.js";

type MetadataReader = (path: string) => Promise<{generation: string; size: number} | null>;

// 종료한 시도의 부분 데이터만 정리하고 다음 시도는 추출부터 시작한다.
export async function prepareSeasonRestart(input: {
  firestore: Firestore; ownership: BatchOwnership; ordinal: number;
  jobID: string; executionID: string; readMetadata?: MetadataReader; now?: number;
  forNextAttempt?: boolean;
}) {
  const {firestore: db, ownership, ordinal, jobID, executionID} = input;
  const now = input.now ?? Date.now();
  const startedAt = Date.now();
  const jobRef = db.doc(`brands/${String((await db.doc(`lookbookImportBatches/${ownership.batchID}`).get()).data()?.brandID)}/importJobs/${jobID}`);
  const executionRef = jobRef.collection("executions").doc(executionID);
  const root = (await jobRef.get()).data();
  if (!root || root.jobType !== "importSeasonFromURL" || root.status === "succeeded") {
    throw new Error("QUEUE_RESTART_SOURCE_UNSUPPORTED");
  }
  const seasonID = typeof root.targetSeasonID === "string" ? root.targetSeasonID : null;
  if (seasonID && seasonID !== `import_${jobID}`) throw new Error("QUEUE_RESTART_FOREIGN_SEASON");
  const seasonRef = seasonID ? jobRef.parent.parent!.collection("seasons").doc(seasonID) : null;
  const writes = seasonRef ? await db.collectionGroup("writes")
    .where("targetSeasonPath", "==", seasonRef.path)
    .where("status", "in", ["uploading", "published", "failed"])
    .limit(241).get() : null;
  // 다음 실행에 숨어 대량 삭제하지 않고 상한 밖 상태는 확인을 요청한다.
  if (writes && writes.size > 240) throw new Error("QUEUE_RESTART_CLEANUP_LIMIT");
  const metadata = new Map<string, Record<string, unknown>>();
  const terminatedRuns = new Map<string, {path: string; verifiedAt: number}>();
  for (const document of writes?.docs ?? []) {
    if (Date.now() - startedAt > QUEUE_POLICY.cleanupAdmissionMs) throw new Error("QUEUE_RESTART_CLEANUP_LIMIT");
    const value = document.data();
    if (!document.ref.path.startsWith(`${jobRef.path}/executions/`)) {
      throw new Error("QUEUE_RESTART_UNCONFIRMED_WRITE");
    }
    if (value.status === "uploading") {
      if (typeof value.batchID !== "string" || typeof value.runID !== "string" ||
          value.runID !== `${value.batchID}-${value.epoch}` || value.runID === ownership.runID) {
        throw new Error("QUEUE_RESTART_UNCONFIRMED_WRITE");
      }
      const path = `lookbookImportBatches/${value.batchID}/runs/${value.runID}`;
      const run = (await db.doc(path).get()).data();
      if (!run?.terminationEvidence || typeof run.terminationVerifiedAt !== "number" ||
          run.settlement !== "restartFromParsing") throw new Error("QUEUE_RESTART_UNCONFIRMED_WRITE");
      terminatedRuns.set(document.ref.path, {path, verifiedAt: run.terminationVerifiedAt});
    }
    const objects = {...(value.objects as Record<string, unknown> | undefined)};
    for (const variant of ["thumb", "detail"] as const) {
      const path = value[variant === "thumb" ? "thumbPath" : "detailPath"];
      if (typeof path !== "string" || !seasonRef || !path.startsWith(`${seasonRef.path}/`) ||
          !path.includes(`/imports/${String(value.executionID)}/${String(value.epoch)}/`)) {
        throw new Error("QUEUE_RESTART_OBJECT_PATH_INVALID");
      }
      if (objects[variant]) continue;
      if (!input.readMetadata) throw new Error("QUEUE_RESTART_METADATA_REQUIRED");
      const object = await input.readMetadata(path);
      if (object && (!/^\d+$/.test(object.generation) ||
          !Number.isSafeInteger(object.size) || object.size < 0)) {
        throw new Error("QUEUE_RESTART_METADATA_INVALID");
      }
      if (object) objects[variant] = object;
    }
    metadata.set(document.ref.path, objects);
  }
  await db.runTransaction(async (tx) => {
    const batch = await readOwnedBatch(db, tx, ownership);
    const item = (batch.items as Array<Record<string, unknown>>)[ordinal];
    const [jobSnapshot, executionSnapshot, continuationSnapshot, seasonSnapshot] = await Promise.all([
      tx.get(jobRef), tx.get(executionRef),
      tx.get(executionRef.collection("continuations").doc(ownership.batchID)),
      seasonRef ? tx.get(seasonRef) : Promise.resolve(null),
    ]);
    const job = jobSnapshot.data();
    const execution = executionSnapshot.data();
    if (!item || item.jobID !== jobID || item.executionID !== executionID ||
        !["active", "retryWaiting"].includes(String(item.processingStatus)) ||
        !job || job.targetSeasonID !== root.targetSeasonID ||
        job.queueExecutionID !== executionID || job.queueActiveRunID != null && job.queueActiveRunID !== ownership.runID ||
        job.status === "succeeded" || !execution ||
        execution.activeRunID != null && execution.activeRunID !== ownership.runID) {
      throw new Error("QUEUE_RESTART_SOURCE_CHANGED");
    }
    const season = seasonSnapshot?.data();
    if (season && (season.sourceImportJobID !== jobID || season.deletionStatus ||
        Number(season.likeCount ?? 0) > 0)) throw new Error("QUEUE_RESTART_FOREIGN_SEASON");
    const posts = seasonRef ? await tx.get(seasonRef.collection("posts").limit(241)) : null;
    const failures = seasonRef ? await tx.get(seasonRef.collection("assetFailures").limit(241)) : null;
    if (posts && posts.size > 240 || failures && failures.size > 240) throw new Error("QUEUE_RESTART_CLEANUP_LIMIT");
    for (const failure of failures?.docs ?? []) {
      if (failure.data().sourceImportJobID !== jobID) throw new Error("QUEUE_RESTART_TARGET_CHANGED");
    }
    for (const post of posts?.docs ?? []) {
      const value = post.data();
      if (value.sourceImportJobID !== jobID ||
          Object.values(value.metrics ?? {}).some((count) => Number(count) > 0)) {
        throw new Error("QUEUE_RESTART_TARGET_CHANGED");
      }
    }
    const snapshots = await Promise.all((writes?.docs ?? []).map((doc) => tx.get(doc.ref)));
    const proofs = await Promise.all([...terminatedRuns.values()].map((run) => tx.get(db.doc(run.path))));
    for (const proof of proofs) {
      if (!proof.data()?.terminationEvidence || proof.data()?.settlement !== "restartFromParsing") {
        throw new Error("QUEUE_RESTART_UNCONFIRMED_WRITE");
      }
    }
    for (const snapshot of snapshots) {
      const value = snapshot.data();
      if (!value || value.status === "uploading" && !terminatedRuns.has(snapshot.ref.path) ||
          !["uploading", "published", "failed"].includes(String(value.status))) {
        throw new Error("QUEUE_RESTART_SOURCE_CHANGED");
      }
      const prior = writes?.docs.find((doc) => doc.ref.path === snapshot.ref.path)?.data();
      if (value.thumbPath !== prior?.thumbPath || value.detailPath !== prior?.detailPath ||
          value.executionID !== prior?.executionID || value.epoch !== prior?.epoch ||
          value.runID !== prior?.runID) throw new Error("QUEUE_RESTART_SOURCE_CHANGED");
    }
    if ((posts?.size ?? 0) + (failures?.size ?? 0) + snapshots.length + 4 > QUEUE_POLICY.cleanupMaxOperations) {
      throw new Error("QUEUE_RESTART_CLEANUP_LIMIT");
    }
    for (const snapshot of snapshots) {
      tx.update(snapshot.ref, {
        status: "unpublished", objects: metadata.get(snapshot.ref.path),
        cleanupState: "pending", cleanupAfter: now + QUEUE_POLICY.unreferencedFileRetentionMs,
        cleanupBlocker: "season_restart", updatedAt: now,
      });
    }
    for (const post of posts?.docs ?? []) tx.delete(post.ref);
    for (const failure of failures?.docs ?? []) tx.delete(failure.ref);
    if (seasonSnapshot?.exists && seasonRef) tx.delete(seasonRef);
    tx.update(jobRef, {
      status: "queued", phase: "dispatching", resumeFrom: "parsing",
      lastFailureStage: job.phase ?? null,
      parseStatus: "pending", imageCandidates: [], contentStatus: "pending",
      targetSeasonID: null, createdPostIDs: [], createdPostCount: 0,
      assetSyncStatus: "pending", assetCompletedCount: 0, assetFailedCount: 0,
      approvedCandidateKeys: [], reviewCandidateKeys: [], reviewSnapshotHash: null,
      reviewStatus: "reanalyzing", reviewGeneration: Number(job.reviewGeneration ?? 0) + 1,
      leaseOwner: null, leaseExpiresAt: null,
      dispatchGeneration: Number(job.dispatchGeneration ?? 0) + 1,
      updatedAt: new Date(now),
    });
    tx.update(executionRef, {restartFromParsing: input.forNextAttempt === true,
      restartPreparedAttempt: Number(execution.attemptCount) + (input.forNextAttempt ? 1 : 0),
      restartPreparedAt: now, lastRestartSource: {seasonID,
        phase: job.phase ?? null, postCount: posts?.size ?? 0,
        assetCompletedCount: job.assetCompletedCount ?? 0,
        assetFailedCount: job.assetFailedCount ?? 0,
      }});
    if (continuationSnapshot.exists) tx.update(continuationSnapshot.ref, {restartPreparedAt: now});
  });
}
