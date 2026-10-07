/* eslint-disable require-jsdoc, max-len */
import {FieldValue, type Firestore, type Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {optionalString} from "../../../core/callable.js";
import {parseQueueRequestEnvelope} from "./contracts.js";
import {admitQueueRequest} from "./admission.js";
import {queueAuthorization} from "./authorization.js";
import {queueDocumentID, queueHash, type AdmissionTarget} from "./model.js";
import {approvedCandidateKeys, nextGeneration, requiredReviewDecision} from "../reviewContract.js";
import {isExtractionFixRetryEligible} from "../extractionIssueContract.js";
import {repairRequestDisposition, seasonRepairPlan} from "../repairContract.js";

type Mode = "reviewApproval" | "manualRetry" | "repairAnalyze" | "repairApply";
function stale(): never {
  throw new HttpsError("failed-precondition", "실행할 대상의 상태 또는 snapshot이 최신이 아닙니다.");
}
function integer(value: unknown): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) {
    throw new Error("INVALID_CONTRACT");
  }
  return Number(value);
}
function text(value: unknown, max: number): string {
  if (typeof value !== "string" || !value.trim() || value.length > max) {
    throw new Error("INVALID_CONTRACT");
  }
  return value.trim();
}

export async function admitImportFollowup(
  db: Firestore, uid: string, data: Record<string, unknown>, mode: Mode
) {
  const envelope = parseQueueRequestEnvelope(data);
  const brandID = queueDocumentID(data.brandID);
  const jobID = queueDocumentID(mode === "repairAnalyze" ? data.sourceImportJobID : data.jobID);
  const payload: Record<string, unknown> = {jobID, mode};
  if (mode === "reviewApproval") {
    payload.reviewGeneration = integer(data.reviewGeneration);
    payload.reviewSnapshotHash = text(data.reviewSnapshotHash, 128);
    payload.decision = requiredReviewDecision(data.decision);
    if (payload.decision === "insufficientImages") throw new Error("INVALID_CONTRACT");
    const excluded = data.excludedCandidateKeys ?? [];
    if (!Array.isArray(excluded) || excluded.length > 240) throw new Error("INVALID_CONTRACT");
    payload.excludedCandidateKeys = [...new Set(excluded.map(queueDocumentID))];
    payload.expectedCandidateCount = data.expectedCandidateCount == null ? null : integer(data.expectedCandidateCount);
    payload.note = optionalString(data, "note", 500);
  } else if (mode === "repairAnalyze") {
    payload.seasonID = queueDocumentID(data.seasonID);
  } else if (mode === "repairApply") {
    payload.repairGeneration = integer(data.repairGeneration);
    payload.repairSnapshotHash = text(data.repairSnapshotHash, 128);
  }
  const jobRef = db.doc(`brands/${brandID}/importJobs/${jobID}`);
  let commit: (transaction: Transaction) => void = () => undefined;
  return admitQueueRequest(db, uid, {...envelope, brandID,
    kind: mode.startsWith("repair") ? "repair" : mode as "reviewApproval" | "manualRetry", payload}, {
    authorize: async (transaction, user, brand) => {
      await queueAuthorization(db)(transaction, user, brand);
    },
    freezeTargets: async (transaction) => {
      commit = () => undefined;
      const job = (await transaction.get(jobRef)).data();
      if (!job) throw new Error("REQUEST_NOT_FOUND");
      if (job.jobType !== "importSeasonFromURL") stale();
      const target: AdmissionTarget = {targetID: jobID,
        claimKey: typeof job.sourceURL === "string" ? job.sourceURL : jobID,
        collection: "importJobs", jobData: {}};
      const expected: Record<string, unknown> = {status: job.status ?? null,
        queueExecutionID: job.queueExecutionID ?? null};
      const input: Record<string, unknown> = {...payload};
      let executionID: string | null = null;
      if (mode === "reviewApproval") {
        const reviewRef = jobRef.collection("reviews").doc(String(payload.reviewGeneration));
        const review = (await transaction.get(reviewRef)).data();
        if (review) {
          if (review.queueDecisionDigest !== queueHash(payload)) stale();
          if (job.status !== "awaitingReview" ||
              (job.reviewGeneration ?? 0) !== payload.reviewGeneration ||
              job.reviewSnapshotHash !== payload.reviewSnapshotHash) {
            return [{...target, existingJobID: jobID,
              ...(typeof review.queueExecutionID === "string" ?
                {existingExecutionID: review.queueExecutionID} : {})}];
          }
        }
        if (job.status !== "awaitingReview" || (job.reviewGeneration ?? 0) !== payload.reviewGeneration ||
            job.reviewSnapshotHash !== payload.reviewSnapshotHash) stale();
        let keys: string[];
        try {
          keys = approvedCandidateKeys({decision: requiredReviewDecision(payload.decision),
            candidateKeys: Array.isArray(job.reviewCandidateKeys) ? job.reviewCandidateKeys : [],
            excludedCandidateKeys: payload.excludedCandidateKeys as string[]});
        } catch (error) {
          throw new HttpsError("invalid-argument", String(error));
        }
        Object.assign(expected, {reviewGeneration: job.reviewGeneration ?? null,
          reviewSnapshotHash: job.reviewSnapshotHash ?? null});
        Object.assign(input, {approvedCandidateKeys: keys, resumeFrom: "materializing"});
        executionID = typeof job.queueExecutionID === "string" ? job.queueExecutionID :
          queueHash([brandID, jobID, "legacy-review-execution"]);
        commit = review ? () => undefined : (tx) => {
          const now = FieldValue.serverTimestamp();
          tx.create(reviewRef, {brandID, jobID, ...payload,
            positiveCandidateKeys: keys, negativeCandidateKeys: payload.excludedCandidateKeys,
            queueDecisionDigest: queueHash(payload), queueExecutionID: executionID,
            reviewedBy: uid, reviewedAt: now,
            resultStatus: "queued", qualityStatus: job.extractionQualityStatus ?? null,
            qualityReasons: job.extractionQualityReasons ?? [], templateSignature: job.templateSignature ?? null,
            imageExtractorVersion: job.imageExtractorVersion ?? null,
            platformAdapterKey: job.platformAdapterKey ?? null, platformAdapterVersion: job.platformAdapterVersion ?? null,
            domainAdapterKey: job.domainAdapterKey ?? null, domainAdapterVersion: job.domainAdapterVersion ?? null,
            issueFingerprint: job.issueFingerprint ?? null});
          if (payload.decision === "approved" && job.trustEligible === true &&
              typeof job.trustBaselineID === "string" && /^[a-f0-9]{40}$/.test(job.trustBaselineID)) {
            tx.set(db.doc(`lookbookExtractionTrustBaselines/${job.trustBaselineID}`), {
              isActive: true, brandID, sourceHost: new URL(String(job.sourceURL)).hostname.toLowerCase(),
              templateSignature: job.templateSignature ?? null, imageExtractorVersion: job.imageExtractorVersion ?? null,
              platformAdapterKey: job.platformAdapterKey ?? null, platformAdapterVersion: job.platformAdapterVersion ?? null,
              domainAdapterKey: job.domainAdapterKey ?? null, domainAdapterVersion: job.domainAdapterVersion ?? null,
              approvedBy: uid, approvedAt: now, sourceImportJobID: jobID, updatedAt: now,
            }, {merge: true});
          }
        };
      } else if (mode === "manualRetry") {
        if (job.status !== "awaitingReview" || job.reviewStatus !== "correctionRequired" ||
            !isExtractionFixRetryEligible({issueStatus: job.extractionIssueStatus,
              blockedRuntimeVersion: job.blockedRuntimeVersion,
              retryAvailableRuntimeVersion: job.retryAvailableRuntimeVersion, stage: "seasonImageImport"})) stale();
        Object.assign(expected, {reviewStatus: job.reviewStatus, reviewGeneration: job.reviewGeneration ?? null,
          retryAvailableRuntimeVersion: job.retryAvailableRuntimeVersion ?? null});
        Object.assign(input, {resumeFrom: "parsing", reviewGeneration: nextGeneration(job.reviewGeneration),
          retryRuntimeVersion: job.retryAvailableRuntimeVersion});
      } else if (mode === "repairAnalyze") {
        const season = (await transaction.get(db.doc(`brands/${brandID}/seasons/${payload.seasonID}`))).data();
        if (!season || season.sourceImportJobID !== jobID || job.targetSeasonID !== payload.seasonID) stale();
        let disposition;
        try {
          disposition = repairRequestDisposition({jobStatus: job.status, repairStatus: job.repairStatus,
            repairTargetSeasonID: job.repairTargetSeasonID, requestedSeasonID: String(payload.seasonID)});
        } catch {
          stale();
        }
        if (disposition === "duplicate") return [{...target, existingJobID: jobID}];
        Object.assign(expected, {targetSeasonID: job.targetSeasonID, repairGeneration: job.repairGeneration ?? null});
        Object.assign(input, {resumeFrom: "parsing", repairGeneration: nextGeneration(job.repairGeneration)});
      } else {
        const repair = (await transaction.get(jobRef.collection("repairs").doc(String(payload.repairGeneration)))).data();
        if (!repair || job.repairGeneration !== payload.repairGeneration ||
            job.repairSnapshotHash !== payload.repairSnapshotHash ||
            repair.repairSnapshotHash !== payload.repairSnapshotHash) stale();
        if (repair.status === "applied") return [{...target, existingJobID: jobID}];
        if (!["previewReady", "applying"].includes(repair.status)) stale();
        const seasonID = queueDocumentID(repair.seasonID);
        const season = (await transaction.get(db.doc(`brands/${brandID}/seasons/${seasonID}`))).data();
        if (!season) throw new Error("REQUEST_NOT_FOUND");
        Object.assign(expected, {repairGeneration: job.repairGeneration, repairSnapshotHash: job.repairSnapshotHash});
        Object.assign(input, {seasonID, plan: seasonRepairPlan(repair), resumeFrom: "materializing"});
      }
      return [{...target, continuation: {jobID, mode, expected, input, executionID}}];
    },
    commit: (transaction) => commit(transaction),
  });
}
