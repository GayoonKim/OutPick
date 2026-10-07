/* eslint-disable require-jsdoc, max-len */
import {type Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {normalizedHTTPURL} from "../../../shared/brandValidation.js";
import {initialSeasonDiscoveryData, canonicalDiscoveryURL} from "../../../shared/seasonDiscoveryCreation.js";
import {isExtractionFixRetryEligible, extractionFixRetryProjection} from "../extractionIssueContract.js";
import {parseQueueRequestEnvelope} from "./contracts.js";
import {admitQueueRequest} from "./admission.js";
import {queueAuthorization} from "./authorization.js";
import {queueDocumentID, type AdmissionTarget} from "./model.js";

export async function admitDiscoveryRequest(
  db: Firestore, uid: string, data: Record<string, unknown>,
  mode: "request" | "retry" | "afterFix"
) {
  const envelope = parseQueueRequestEnvelope(data);
  const brandID = queueDocumentID(data.brandID);
  const payload: Record<string, unknown> = {mode};
  if (mode === "request") {
    if (!["manualRefresh", "archiveURLChanged"].includes(String(data.requestReason))) {
      throw new Error("INVALID_CONTRACT");
    }
    payload.requestReason = data.requestReason;
  } else {
    payload.jobID = queueDocumentID(data.jobID);
    if (mode === "afterFix") {
      if (!Number.isSafeInteger(data.generation) || Number(data.generation) < 0 ||
          typeof data.candidateSnapshotHash !== "string" || !data.candidateSnapshotHash ||
          data.candidateSnapshotHash.length > 128) throw new Error("INVALID_CONTRACT");
      payload.generation = data.generation;
      payload.candidateSnapshotHash = data.candidateSnapshotHash;
    }
  }
  const brandRef = db.doc(`brands/${brandID}`);
  let reservedGeneration: number | null = null;
  return admitQueueRequest(db, uid, {...envelope, brandID, kind: "discoverSeasons", payload}, {
    authorize: async (transaction, user, brand) => {
      await queueAuthorization(db)(transaction, user, brand);
    },
    freezeTargets: async (transaction) => {
      reservedGeneration = null;
      const brand = (await transaction.get(brandRef)).data()!;
      if (typeof brand.lookbookArchiveURL !== "string" || !brand.lookbookArchiveURL.trim()) {
        throw new HttpsError("failed-precondition", "룩북 목록 URL이 등록되어 있지 않습니다.");
      }
      const sourceArchiveURL = normalizedHTTPURL(brand.lookbookArchiveURL, "lookbookArchiveURL");
      const seed = initialSeasonDiscoveryData(brandID, uid, sourceArchiveURL);
      const target: AdmissionTarget = {targetID: "discovery", collection: "seasonDiscoveryJobs",
        claimKey: seed.requestFingerprint, jobData: {...seed, requestReason: payload.requestReason ?? "extractorImproved"}};
      if (mode !== "request") {
        const jobID = String(payload.jobID);
        const job = (await transaction.get(brandRef.collection("seasonDiscoveryJobs").doc(jobID))).data();
        if (!job) throw new Error("REQUEST_NOT_FOUND");
        if (mode === "retry") {
          if (brand.activeSeasonDiscoveryJobID !== jobID || job.status !== "failed" || job.retryable !== true) {
            throw new HttpsError("failed-precondition", "같은 작업으로 재시도할 수 없습니다.");
          }
          return [{...target, continuation: {jobID, mode: "manualRetry", executionID: null,
            expected: {status: job.status, generation: job.generation ?? null,
              queueExecutionID: job.queueExecutionID ?? null},
            input: {resumeFrom: "discovery", sourceArchiveURL: job.sourceArchiveURL,
              generation: job.generation, clearFailure: true}}}];
        }
        if (typeof job.resolvedByJobID === "string") {
          const resolved = await transaction.get(brandRef.collection("seasonDiscoveryJobs").doc(job.resolvedByJobID));
          if (resolved.exists) return [{...target, existingJobID: resolved.id}];
        }
        if (typeof brand.activeSeasonDiscoveryJobID === "string" ||
            brand.publishedSeasonDiscoveryJobID !== jobID || job.status !== "correctionRequired" ||
            job.generation !== payload.generation || job.candidateSnapshotHash !== payload.candidateSnapshotHash ||
            typeof job.sourceArchiveURL !== "string" ||
            canonicalDiscoveryURL(sourceArchiveURL) !== canonicalDiscoveryURL(job.sourceArchiveURL) ||
            !isExtractionFixRetryEligible({issueStatus: job.extractionIssueStatus,
              blockedRuntimeVersion: job.blockedRuntimeVersion,
              retryAvailableRuntimeVersion: job.retryAvailableRuntimeVersion, stage: "seasonDiscovery"})) {
          throw new HttpsError("failed-precondition", "개선이 검증된 최신 탐색 결과만 재분석할 수 있습니다.");
        }
        const projection = extractionFixRetryProjection(job, "seasonDiscovery");
        // Timestamp는 JSON 고정 입력에 넣지 않는다. 원본 이력은 기존 job에 남긴다.
        delete projection.retryAvailableAt;
        Object.assign(target.jobData, projection, {reanalysisSource: {
          jobID, generation: job.generation, candidateSnapshotHash: job.candidateSnapshotHash,
        }});
      } else if (typeof brand.activeSeasonDiscoveryJobID === "string") {
        const active = await transaction.get(brandRef.collection("seasonDiscoveryJobs")
          .doc(brand.activeSeasonDiscoveryJobID));
        if (active.exists && active.data()?.requestFingerprint === seed.requestFingerprint &&
            ["queued", "dispatching", "running"].includes(active.data()?.status)) {
          return [{...target, existingJobID: active.id}];
        }
      }
      reservedGeneration = Number(brand.lastSeasonDiscoveryGeneration ?? 0) + 1;
      if (!Number.isSafeInteger(reservedGeneration) || reservedGeneration < 1) throw new Error("QUEUE_CORRUPT");
      target.jobData.generation = reservedGeneration;
      // 공개 snapshot/현재 실행권은 자기 차례의 활성화에서 변경한다.
      target.jobData.queueActivationRequired = true;
      return [target];
    },
    commit: (transaction) => {
      if (reservedGeneration !== null) {
        transaction.update(brandRef, {lastSeasonDiscoveryGeneration: reservedGeneration});
      }
    },
  });
}
