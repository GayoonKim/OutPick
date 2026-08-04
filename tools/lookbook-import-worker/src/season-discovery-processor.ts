/* eslint-disable max-len */
import {createHash, randomUUID} from "node:crypto";
import type {Firestore} from "firebase-admin/firestore";
import {FieldValue, Timestamp} from "firebase-admin/firestore";

import {RetryableImportError} from "./import-error.js";
import {
  processDiscoverSeasonsDiagnosticRequest,
  type DiscoverSeasonsDiagnosticResponse,
} from "./season-discovery.js";
import {
  resolveSeasonCandidateIdentities,
  type ExistingSeasonIdentity,
} from "./season-identity.js";

const LEGACY_SEASON_DISCOVERY_CONTRACT_REVISION = 1;

export type SeasonDiscoveryTaskRequest = {
  brandID?: unknown;
  jobID?: unknown;
  generation?: unknown;
  dispatchGeneration?: unknown;
  extractorVersion?: unknown;
  extractionContractRevision?: unknown;
  maxAttempts?: unknown;
};

type ProcessResult = {
  accepted: true;
  status: string;
  candidateCount?: number;
  duplicate?: boolean;
};

export async function processSeasonDiscoveryTaskRequest(
  firestore: Firestore,
  request: SeasonDiscoveryTaskRequest,
  taskRetryCount: number,
): Promise<ProcessResult> {
  const brandID = documentID(request.brandID, "brandID");
  const jobID = documentID(request.jobID, "jobID");
  const generation = integer(request.generation, "generation");
  const dispatchGeneration = integer(request.dispatchGeneration, "dispatchGeneration");
  const extractorVersion = stringValue(request.extractorVersion, "extractorVersion");
  const extractionContractRevision = request.extractionContractRevision === undefined ?
    LEGACY_SEASON_DISCOVERY_CONTRACT_REVISION :
    integer(request.extractionContractRevision, "extractionContractRevision");
  const maxAttempts = integer(request.maxAttempts, "maxAttempts");
  const jobRef = firestore.collection("brands").doc(brandID)
    .collection("seasonDiscoveryJobs").doc(jobID);
  const leaseOwner = randomUUID();

  const claim = await firestore.runTransaction(async (transaction) => {
    const jobSnap = await transaction.get(jobRef);
    const job = jobSnap.data();
    if (!jobSnap.exists || !job) return null;
    if (!canClaimSeasonDiscoveryJob(job, {
      generation, dispatchGeneration, extractorVersion,
      extractionContractRevision,
    })) return null;
    transaction.update(jobRef, {
      status: "running",
      phase: "fetching",
      attemptCount: FieldValue.increment(1),
      lastTaskRetryCount: taskRetryCount,
      leaseOwner,
      leaseExpiresAt: Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
      startedAt: job.startedAt ?? FieldValue.serverTimestamp(),
      lastAttemptAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      sourceArchiveURL: stringValue(job.sourceArchiveURL, "sourceArchiveURL"),
      requestedBy: stringValue(job.requestedBy, "requestedBy"),
      limits: job.limits,
    };
  });
  if (claim === null) return {accepted: true, status: "ignored", duplicate: true};

  try {
    const diagnostic = await processDiscoverSeasonsDiagnosticRequest({
      brandID,
      archiveURL: claim.sourceArchiveURL,
      requestedBy: claim.requestedBy,
      diagnosticID: jobID,
      limits: claim.limits,
    });
    return await publishDiscovery({
      firestore, brandID, jobID, generation, dispatchGeneration,
      extractionContractRevision, leaseOwner,
      sourceArchiveURL: claim.sourceArchiveURL, diagnostic,
    });
  } catch (error) {
    const permanent = isPermanentFailure(error);
    const exhausted = taskRetryCount + 1 >= maxAttempts;
    const failureResult = await finalizeFailure({
      firestore, brandID, jobID, generation, dispatchGeneration, leaseOwner,
      error, permanent, exhausted,
    });
    if (failureResult === "ignored") {
      return {accepted: true, status: "ignored", duplicate: true};
    }
    if (failureResult === "cancelled") {
      return {accepted: true, status: "cancelled"};
    }
    if (failureResult === "failed") {
      return {accepted: true, status: "failed"};
    }
    throw new RetryableImportError(errorMessage(error), {cause: error});
  }
}

async function finalizeFailure(input: {
  firestore: Firestore;
  brandID: string;
  jobID: string;
  generation: number;
  dispatchGeneration: number;
  leaseOwner: string;
  error: unknown;
  permanent: boolean;
  exhausted: boolean;
}): Promise<"ignored" | "cancelled" | "failed" | "retry"> {
  const brandRef = input.firestore.collection("brands").doc(input.brandID);
  const jobRef = brandRef.collection("seasonDiscoveryJobs").doc(input.jobID);
  return input.firestore.runTransaction(async (transaction) => {
    const [brandSnap, jobSnap] = await Promise.all([
      transaction.get(brandRef), transaction.get(jobRef),
    ]);
    const brand = brandSnap.data();
    const job = jobSnap.data();
    const current = brandSnap.exists && jobSnap.exists &&
      isCurrentSeasonDiscoveryAttempt(brand, job, input);
    if (!current) return "ignored";

    if (job?.cancelRequestedAt) {
      const expiresAt = Timestamp.fromMillis(
        Date.now() + 30 * 24 * 60 * 60 * 1000,
      );
      transaction.update(jobRef, {
        status: "cancelled", phase: "completed",
        recommendedAction: "none", completedAt: FieldValue.serverTimestamp(),
        expiresAt, leaseOwner: null, leaseExpiresAt: null,
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.update(brandRef, {
        activeSeasonDiscoveryJobID: null,
        discoveryStatus: "cancelled",
        lastDiscoveryCompletedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return "cancelled";
    }

    if (input.permanent || input.exhausted) {
      transaction.update(jobRef, {
        status: "failed",
        phase: "completed",
        failureClass: input.permanent ?
          "permanentInput" : "transientInfrastructure",
        errorCode: input.permanent ?
          permanentErrorCode(input.error) : "retry_exhausted",
        errorMessage: errorMessage(input.error),
        retryable: !input.permanent,
        recommendedAction: input.permanent ? "updateSourceURL" : "retry",
        leaseOwner: null,
        leaseExpiresAt: null,
        completedAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromMillis(
          Date.now() + 60 * 24 * 60 * 60 * 1000,
        ),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.update(brandRef, {
        discoveryStatus: "failed",
        lastDiscoveryCompletedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return "failed";
    }

    transaction.update(jobRef, {
      status: "dispatching",
      phase: "dispatching",
      failureClass: "transientInfrastructure",
      errorCode: "transient_worker_failure",
      errorMessage: errorMessage(input.error),
      retryable: true,
      recommendedAction: "retry",
      leaseOwner: null,
      leaseExpiresAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return "retry";
  });
}

async function publishDiscovery(input: {
  firestore: Firestore;
  brandID: string;
  jobID: string;
  generation: number;
  dispatchGeneration: number;
  extractionContractRevision: number;
  leaseOwner: string;
  sourceArchiveURL: string;
  diagnostic: DiscoverSeasonsDiagnosticResponse;
}): Promise<ProcessResult> {
  const brandRef = input.firestore.collection("brands").doc(input.brandID);
  const jobRef = brandRef.collection("seasonDiscoveryJobs").doc(input.jobID);
  const seasons = await brandRef.collection("seasons").limit(500).get();
  const existing: ExistingSeasonIdentity[] = seasons.docs
    .filter((doc) => doc.data().deletionStatus !== "deleted" && doc.data().status !== "deleted")
    .map((doc) => ({
      seasonID: doc.id,
      title: optionalString(doc.data().sourceTitle) ?? optionalString(doc.data().displayTitle) ?? "",
      sourceURL: optionalString(doc.data().sourceURL) ?? `https://invalid.local/${doc.id}`,
    }));
  const candidateInputs = input.diagnostic.candidates.map((candidate) => ({
    candidateID: candidateID(candidate.seasonURL),
    title: candidate.title,
    seasonURL: candidate.seasonURL,
  }));
  const resolutions = resolveSeasonCandidateIdentities(candidateInputs, existing);
  const resolutionByID = new Map(resolutions.map((item) => [item.candidateID, item]));
  const snapshotPayload = input.diagnostic.candidates.map((candidate, sortIndex) => {
    const candidateIDValue = candidateID(candidate.seasonURL);
    const resolution = resolutionByID.get(candidateIDValue);
    return {
      candidateID: candidateIDValue,
      title: candidate.title,
      seasonURL: candidate.seasonURL,
      coverImageURL: candidate.coverImageURL,
      extractionScore: candidate.score,
      sortIndex,
      normalizedTitleKey: resolution?.normalizedTitleKey ?? null,
      resolution: resolution?.resolution ?? "newSeason",
      matchedSeasonID: resolution?.matchedSeasonID ?? null,
    };
  });
  const snapshotHash = createHash("sha256")
    .update(JSON.stringify(snapshotPayload))
    .digest("hex");
  const hasReview = resolutions.some((item) => item.resolution.startsWith("awaitingReview"));
  const extractionIncomplete = input.diagnostic.status !== "passed" || snapshotPayload.length === 0;
  const status = extractionIncomplete ? "correctionRequired" : hasReview ? "awaitingReview" : "succeeded";
  const expiresAt = status === "succeeded" ?
    Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000) : null;

  const batch = input.firestore.batch();
  for (const candidate of snapshotPayload) {
    batch.set(jobRef.collection("candidates").doc(candidate.candidateID), {
      ...candidate,
      brandID: input.brandID,
      jobID: input.jobID,
      generation: input.generation,
      sourceArchiveURL: input.sourceArchiveURL,
      snapshotHash,
      expiresAt,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  const published = await input.firestore.runTransaction(async (transaction) => {
    const [brandSnap, jobSnap] = await Promise.all([
      transaction.get(brandRef), transaction.get(jobRef),
    ]);
    const brand = brandSnap.data();
    const job = jobSnap.data();
    const valid = brandSnap.exists && jobSnap.exists &&
      (!brand?.deletionStatus || brand.deletionStatus === "active") &&
      brand?.activeSeasonDiscoveryJobID === input.jobID &&
      brand?.lastSeasonDiscoveryGeneration === input.generation &&
      job?.generation === input.generation &&
      job?.dispatchGeneration === input.dispatchGeneration &&
      job?.leaseOwner === input.leaseOwner &&
      !job?.cancelRequestedAt;
    if (!valid) {
      const cancelled = Boolean(job?.cancelRequestedAt);
      transaction.update(jobRef, {
        status: cancelled ? "cancelled" : "superseded",
        phase: "completed",
        recommendedAction: "none",
        completedAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000),
        leaseOwner: null,
        leaseExpiresAt: null,
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (brand?.activeSeasonDiscoveryJobID === input.jobID) {
        transaction.update(brandRef, {
          activeSeasonDiscoveryJobID: null,
          discoveryStatus: cancelled ? "cancelled" : "superseded",
          lastDiscoveryCompletedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      for (const candidate of snapshotPayload) {
        transaction.update(
          jobRef.collection("candidates").doc(candidate.candidateID),
          {
            expiresAt: Timestamp.fromMillis(
              Date.now() + 30 * 24 * 60 * 60 * 1000,
            ),
          },
        );
      }
      return false;
    }
    for (const candidate of snapshotPayload) {
      if (candidate.resolution === "matchedByUniqueNormalizedTitle" && candidate.matchedSeasonID) {
        transaction.update(brandRef.collection("seasons").doc(candidate.matchedSeasonID), {
          sourceURL: candidate.seasonURL,
          sourceURLMatchMethod: "uniqueNormalizedTitle",
          sourceURLUpdatedAt: FieldValue.serverTimestamp(),
          sourceDiscoveryJobID: input.jobID,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }
    transaction.update(jobRef, {
      status,
      phase: "completed",
      candidateCount: snapshotPayload.length,
      newSeasonCandidateCount: snapshotPayload.filter((item) => item.resolution === "newSeason").length,
      reviewCandidateCount: snapshotPayload.filter((item) => item.resolution.startsWith("awaitingReview")).length,
      matchedCandidateCount: snapshotPayload.filter((item) => item.resolution.startsWith("matchedBy")).length,
      candidateSnapshotHash: snapshotHash,
      parserStrategy: input.diagnostic.diagnostic.parserStrategy,
      adapterKey: input.diagnostic.diagnostic.adapterKey,
      failureReasons: input.diagnostic.diagnostic.failureReasons,
      failureClass: extractionIncomplete ? "extractionInsufficient" : null,
      issueFingerprint: extractionIncomplete ?
        seasonDiscoveryIssueFingerprint(input.diagnostic) : null,
      blockedByExtractionContractRevision: extractionIncomplete ?
        input.extractionContractRevision : null,
      improvementRequested: false,
      availableExtractionContractRevision: null,
      resolvedByJobID: null,
      retryable: false,
      recommendedAction: extractionIncomplete ? "waitForExtractorFix" : hasReview ? "reviewCandidates" : "none",
      leaseOwner: null,
      leaseExpiresAt: null,
      completedAt: FieldValue.serverTimestamp(),
      expiresAt,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(brandRef, {
      activeSeasonDiscoveryJobID: null,
      publishedSeasonDiscoveryJobID: input.jobID,
      publishedSeasonDiscoveryGeneration: input.generation,
      publishedSeasonDiscoverySnapshotHash: snapshotHash,
      publishedSeasonDiscoveryExpiresAt: expiresAt,
      discoveryStatus: status,
      lastDiscoveryErrorMessage: input.diagnostic.diagnostic.errorMessage,
      lastDiscoveryCompletedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
  return {
    accepted: true,
    status: published ? status : "superseded",
    candidateCount: snapshotPayload.length,
  };
}

export function seasonDiscoveryIssueFingerprint(
  response: DiscoverSeasonsDiagnosticResponse,
): string {
  return createHash("sha256").update(JSON.stringify({
    failureReasons: [...response.diagnostic.failureReasons].sort(),
    parserStrategy: response.diagnostic.parserStrategy,
    adapterKey: response.diagnostic.adapterKey,
    sourceHost: new URL(response.sourceURL).hostname.toLowerCase(),
  })).digest("hex").slice(0, 40);
}
function candidateID(url: string): string {
  return createHash("sha256").update(url).digest("hex").slice(0, 24);
}
function isPermanentFailure(error: unknown): boolean {
  return /invalid|올바르지|HTML 응답이 아닙니다|HTTP 4(?:00|01|03|04)/i.test(errorMessage(error));
}
function permanentErrorCode(error: unknown): string {
  return /404/.test(errorMessage(error)) ? "source_not_found" : "invalid_source_url";
}
function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
function optionalString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}
function stringValue(value: unknown, name: string): string {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${name} 값이 필요합니다.`);
  return value.trim();
}
function documentID(value: unknown, name: string): string {
  const result = stringValue(value, name);
  if (result.includes("/")) throw new Error(`${name} 값이 올바르지 않습니다.`);
  return result;
}
function integer(value: unknown, name: string): number {
  if (!Number.isInteger(value) || Number(value) < 0) throw new Error(`${name} 값이 올바르지 않습니다.`);
  return Number(value);
}

export function canClaimSeasonDiscoveryJob(
  job: Record<string, unknown>,
  request: {
    generation: number;
    dispatchGeneration: number;
    extractorVersion: string;
    extractionContractRevision: number;
  },
): boolean {
  return ["queued", "dispatching"].includes(String(job.status)) &&
    job.generation === request.generation &&
    job.dispatchGeneration === request.dispatchGeneration &&
    job.extractorVersion === request.extractorVersion &&
    (Number.isInteger(job.extractionContractRevision) ?
      Number(job.extractionContractRevision) :
      LEGACY_SEASON_DISCOVERY_CONTRACT_REVISION) ===
        request.extractionContractRevision;
}

export function isCurrentSeasonDiscoveryAttempt(
  brand: Record<string, unknown> | undefined,
  job: Record<string, unknown> | undefined,
  attempt: {
    jobID: string;
    generation: number;
    dispatchGeneration: number;
    leaseOwner: string;
  },
): boolean {
  return brand?.activeSeasonDiscoveryJobID === attempt.jobID &&
    brand?.lastSeasonDiscoveryGeneration === attempt.generation &&
    job?.status === "running" &&
    job?.generation === attempt.generation &&
    job?.dispatchGeneration === attempt.dispatchGeneration &&
    job?.leaseOwner === attempt.leaseOwner;
}
