/* eslint-disable require-jsdoc, max-len */
import {createHash} from "node:crypto";
import type {Firestore, Transaction} from "firebase-admin/firestore";
import {QUEUE_POLICY} from "./contracts.js";

type Document = Record<string, unknown>;

export async function readFailureRecord(db: Firestore, tx: Transaction,
  batch: Document, item: Document, execution: Document) {
  if (!["importSeasons", "manualRetry", "reviewApproval"].includes(String(batch.kind)) ||
      typeof item.jobID !== "string" ||
      typeof item.executionID !== "string") return null;
  const jobRef = db.doc(`brands/${String(batch.brandID)}/importJobs/${item.jobID}`);
  const job = (await tx.get(jobRef)).data();
  if (job?.jobType !== "importSeasonFromURL" || typeof job.sourceURL !== "string") return null;
  const failureID = createHash("sha256")
    .update(JSON.stringify(["importJobs", job.sourceURL])).digest("hex");
  const ref = db.doc(`brands/${String(batch.brandID)}/seasonImportFailures/${failureID}`);
  const [snapshot, claimSnapshot] = await Promise.all([
    tx.get(ref), tx.get(db.doc(`brands/${String(batch.brandID)}/queueSourceClaims/${failureID}`)),
  ]);
  const claim = claimSnapshot.data();
  if (claim?.jobID !== item.jobID || claim?.executionID !== item.executionID) {
    throw new Error("QUEUE_FAILURE_SOURCE_CLAIM_LOST");
  }
  return {ref, data: snapshot.data(), jobRef, job, failureID,
    dismissed: execution.dismissedFailureID === failureID};
}

export function writeFailureRecord(tx: Transaction,
  target: Awaited<ReturnType<typeof readFailureRecord>>, batch: Document,
  item: Document, outcome: string, attemptCount: number, attemptLimit: number,
  now: number, errorCode?: string) {
  if (!target || target.dismissed) return;
  const prior = target.data;
  if (outcome === "succeeded") {
    if (prior) tx.delete(target.ref);
    return;
  }
  const failed = ["failed", "partialFailed"].includes(outcome);
  // 실패 목록이 없는 정상 최초 처리에서는 진행용 문서를 추가하지 않는다.
  if (!failed && !prior) return;
  const state = failed ? "failed" : outcome === "awaitingReview" ?
    "awaitingReview" : "retrying";
  tx.set(target.ref, {
    sourceURL: target.job.sourceURL,
    sourceCandidateID: target.job.sourceCandidateID ?? null,
    displayTitle: typeof target.job.seasonTitle === "string" ? target.job.seasonTitle :
      typeof target.job.sourceTitle === "string" ? target.job.sourceTitle : "",
    state, version: Number(prior?.version ?? 0) + 1,
    latestRequestID: batch.requestID,
    latestBatchID: batch.batchID,
    latestJobID: item.jobID, latestExecutionID: item.executionID,
    attemptCount, attemptLimit,
    failureStage: failed ? String(target.job.lastFailureStage ?? target.job.phase ?? "unknown") : prior?.failureStage ?? null,
    errorCode: failed ? (errorCode ?? (typeof target.job.errorCode === "string" ?
      target.job.errorCode.slice(0, 128) : "SEASON_IMPORT_FAILED")) : prior?.errorCode ?? null,
    errorMessage: failed ? "시즌 등록을 완료하지 못했습니다." : prior?.errorMessage ?? null,
    failedAt: failed ? now : prior?.failedAt ?? null,
    updatedAt: now, expiresAt: failed ? now + QUEUE_POLICY.resolvedFailureRetentionMs : null,
    originalRequestID: prior?.originalRequestID ?? batch.requestID,
  });
  if (failed && target.job.queueExecutionID === item.executionID) {
    tx.update(target.jobRef, {status: outcome, phase: "completed",
      queueActiveRunID: null, leaseOwner: null, leaseExpiresAt: null,
      updatedAt: new Date(now)});
  }
}
