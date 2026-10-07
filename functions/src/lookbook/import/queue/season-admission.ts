/* eslint-disable require-jsdoc, max-len */
import {Timestamp, type Firestore, type Transaction} from "firebase-admin/firestore";
export {queueAdmissionError as seasonAdmissionError} from "../../../shared/lookbookQueue/errors.js";
import {parseQueueRequestEnvelope} from "./contracts.js";
import {admitQueueRequest} from "./admission.js";
import {queueAuthorization} from "./authorization.js";
import {queueDocumentID, type AdmissionTarget} from "./model.js";
import {assetRetrySource} from "./asset-retry.js";

function text(value: unknown, max: number): string {
  if (typeof value !== "string" || !value.trim() || value.length > max) {
    throw new Error("INVALID_CONTRACT");
  }
  return value.trim();
}

function httpURL(value: unknown): string {
  const raw = text(value, 2048);
  let url: URL;
  try {
    url = new URL(raw.includes("://") ? raw : `https://${raw}`);
  } catch {
    throw new Error("INVALID_CONTRACT");
  }
  if (!["http:", "https:"].includes(url.protocol) || !url.hostname) {
    throw new Error("INVALID_CONTRACT");
  }
  return url.toString();
}

function retryTarget(jobID: string, data: Record<string, unknown>, targetID: string): AdmissionTarget {
  const input = assetRetrySource(data);
  const target: AdmissionTarget = {
    targetID, claimKey: input.sourceURL, collection: "importJobs", jobData: {},
  };
  if (["queued", "processing"].includes(String(data.assetRetryStatus)) &&
      typeof data.assetRetryRequestID === "string") {
    return {...target, existingJobID: jobID};
  }
  return {...target, assetRetry: {jobID, ...input}};
}

async function seasonTarget(
  db: Firestore, transaction: Transaction, brandID: string, targetID: string,
  sourceURL: string, sourceCandidateID: string | null,
  seed: Record<string, unknown> = {}
): Promise<AdmissionTarget> {
  const jobs = db.collection(`brands/${brandID}/importJobs`);
  const byURL = await transaction.get(jobs.where("sourceURL", "==", sourceURL));
  const byCandidate = sourceCandidateID ? await transaction.get(
    jobs.where("sourceCandidateID", "==", sourceCandidateID)) : null;
  const existing = [...byURL.docs, ...(byCandidate?.docs ?? [])]
    .filter((snapshot) => snapshot.data().jobType === "importSeasonFromURL");
  const retryable = existing.find((snapshot) => {
    const job = snapshot.data();
    return ["partialFailed", "failed"].includes(job.status) &&
      typeof job.targetSeasonID === "string" && Number(job.assetFailedCount) > 0;
  });
  if (retryable) return retryTarget(retryable.id, retryable.data(), targetID);
  const duplicate = existing.find((snapshot) =>
    ["queued", "processing", "awaitingReview", "succeeded", "partialFailed"]
      .includes(snapshot.data().status));
  const target: AdmissionTarget = {
    targetID, claimKey: sourceURL, collection: "importJobs",
    jobData: {
      jobType: "importSeasonFromURL", sourceURL, sourceCandidateID,
      sourceTitle: typeof seed.title === "string" ? seed.title.trim() : null,
      coverRemoteURL: typeof seed.coverImageURL === "string" ? seed.coverImageURL.trim() : null,
      sourceSortIndex: Number.isInteger(seed.sortIndex) ? seed.sortIndex : null,
      errorMessage: null, assetCompletedCount: 0, assetFailedCount: 0,
      dispatchGeneration: 0, reviewGeneration: 0, reviewStatus: null,
      resumeFrom: "parsing",
    },
  };
  return duplicate ? {...target, existingJobID: duplicate.id} : target;
}

export async function admitSeasonRequest(
  db: Firestore, uid: string, data: Record<string, unknown>,
  mode: "url" | "candidates" | "assetRetry", now = Date.now()
) {
  const envelope = parseQueueRequestEnvelope(data);
  const brandID = queueDocumentID(data.brandID);
  let payload: Record<string, unknown>;
  if (mode === "url") {
    payload = {seasonURL: httpURL(data.seasonURL),
      sourceCandidateID: data.sourceCandidateID == null ? null :
        queueDocumentID(data.sourceCandidateID)};
  } else if (mode === "assetRetry") {
    payload = {sourceJobID: queueDocumentID(data.sourceJobID)};
  } else {
    if (!Array.isArray(data.candidateIDs) || data.candidateIDs.length < 1 ||
        data.candidateIDs.length > 80 || !Number.isSafeInteger(data.generation) ||
        Number(data.generation) < 0) throw new Error("INVALID_CONTRACT");
    payload = {candidateIDs: [...new Set(data.candidateIDs.map(queueDocumentID))],
      discoveryJobID: queueDocumentID(data.discoveryJobID),
      generation: data.generation,
      candidateSnapshotHash: text(data.candidateSnapshotHash, 128)};
  }
  return admitQueueRequest(db, uid, {
    ...envelope, brandID, kind: mode === "assetRetry" ? "assetRetry" : "importSeasons",
    payload,
  }, {
    authorize: queueAuthorization(db),
    freezeTargets: async (transaction) => {
      const brandRef = db.doc(`brands/${brandID}`);
      if (mode === "assetRetry") {
        const id = String(payload.sourceJobID);
        const source = (await transaction.get(brandRef.collection("importJobs").doc(id))).data();
        if (!source) throw new Error("REQUEST_NOT_FOUND");
        return [retryTarget(id, source, id)];
      }
      if (mode === "url") {
        const id = payload.sourceCandidateID as string | null;
        const url = String(payload.seasonURL);
        let seed: Record<string, unknown> = {};
        if (id) {
          const candidate = await transaction.get(brandRef.collection("seasonCandidates").doc(id));
          if (!candidate.exists) throw new Error("REQUEST_NOT_FOUND");
          seed = candidate.data()!;
          if (httpURL(seed.seasonURL) !== url) throw new Error("INVALID_CONTRACT");
        }
        return [await seasonTarget(db, transaction, brandID, id ?? "url", url, id, seed)];
      }
      const discovery = brandRef.collection("seasonDiscoveryJobs").doc(String(payload.discoveryJobID));
      const brand = (await transaction.get(brandRef)).data();
      const job = (await transaction.get(discovery)).data();
      const expiry = brand?.publishedSeasonDiscoveryExpiresAt;
      if (!brand || !job || brand.publishedSeasonDiscoveryJobID !== discovery.id ||
          brand.publishedSeasonDiscoveryGeneration !== payload.generation ||
          brand.publishedSeasonDiscoverySnapshotHash !== payload.candidateSnapshotHash ||
          job.generation !== payload.generation || job.candidateSnapshotHash !== payload.candidateSnapshotHash ||
          !["succeeded", "awaitingReview"].includes(job.status) ||
          (expiry instanceof Timestamp && expiry.toMillis() <= now)) {
        throw new Error("SNAPSHOT_STALE");
      }
      const targets: AdmissionTarget[] = [];
      for (const id of payload.candidateIDs as string[]) {
        const candidate = (await transaction.get(discovery.collection("candidates").doc(id))).data();
        const failed = (errorCode: string): AdmissionTarget => ({
          targetID: id, claimKey: id, collection: "importJobs", jobData: {}, errorCode,
        });
        if (!candidate || candidate.resolution !== "newSeason" ||
            candidate.generation !== payload.generation ||
            candidate.snapshotHash !== payload.candidateSnapshotHash) {
          targets.push(failed("CANDIDATE_NOT_AVAILABLE"));
          continue;
        }
        let url: string;
        try {
          url = httpURL(candidate.seasonURL);
        } catch {
          targets.push(failed("INVALID_CANDIDATE_URL"));
          continue;
        }
        // DB 장애는 항목 실패로 숨기지 않고 transaction 전체를 재시도한다.
        targets.push(await seasonTarget(db, transaction, brandID, id, url, id, candidate));
      }
      return targets;
    },
  }, now);
}
