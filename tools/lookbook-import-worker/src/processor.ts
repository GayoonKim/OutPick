/* eslint-disable max-len */
import {createHash, randomUUID} from "node:crypto";

import type {Firestore} from "firebase-admin/firestore";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import type {Storage} from "firebase-admin/storage";
import sharp from "sharp";

import {
  isRetryableImportError,
  RetryableImportError,
} from "./import-error.js";
import {
  assertPublicHTTPURL,
  fetchPublicHTTP,
  responseBytes,
  retryableStatusError,
} from "./public-http.js";
import {
  completedLifecycle,
  isFinalTaskAttempt,
  type ImportJobLifecycle,
} from "./job-lifecycle.js";
import {
  extractionResult,
  extractionResultWithStrategy,
  mergeExtractionResults,
  selectExtractionCandidates,
  type ExtractionResult,
} from "./extraction/core.js";
import {
  canonicalCandidateURL,
  resolveContentHashDedupe,
} from "./extraction/dedupe.js";
import {
  extractionCandidateKey,
  extractionSourceEvidence,
} from "./extraction/evidence.js";
import {
  collectExpectedCountEvidence,
  type ExpectedCountEvidence,
} from "./extraction/expected-count.js";
import {
  detectProgrammaticGallery,
  type ProgrammaticGalleryEvidence,
} from "./extraction/programmatic-gallery.js";
import {
  evaluateExtractionQuality,
  type ExtractionQuality,
} from "./extraction/quality.js";
import {
  extractionStructureTokens,
  makeReviewContract,
  reviewDisposition,
  type ReviewContract,
} from "./extraction/review.js";
import {
  makeSeasonReconcilePreview,
  seasonRepairPreviewDisposition,
  type ReconcileCandidate,
  type ReconcileExistingPost,
} from "./extraction/reconcile.js";
import {
  buildRetainedExtractionEvidence,
  evidenceExpiresAt,
  extractionEvidenceID,
  extractionEvidenceStoragePath,
  extractionIssueIdentity,
  nextExtractionIssueClusterState,
  type RetainedExtractionEvidence,
} from "./extraction/retained-evidence.js";
import {selectExtractionAdapters} from "./extraction/adapters/registry.js";
import type {
  ContentSectionRule,
  ImageExtractionRules,
} from "./extraction/adapters/types.js";
import {
  CURRENT_EXTRACTION_VERSIONS,
  isReusableExtractionCache,
} from "./extraction/version.js";

type WorkerStatus = ImportJobLifecycle;

export function requiresApprovedReviewSnapshot(input: {
  resumeFrom: "parsing" | "materializing";
  repairTargetSeasonID: string | null;
}): boolean {
  return input.resumeFrom === "materializing" &&
    input.repairTargetSeasonID === null;
}

type ImageCandidate = {
  sourceURL: string;
  alt: string | null;
};

type ImageExtractionResult = ExtractionResult<ImageCandidate>;

type EvaluatedImageExtraction = {
  extraction: ImageExtractionResult;
  expectedCountEvidence: ExpectedCountEvidence[];
  programmaticGalleryEvidence: ProgrammaticGalleryEvidence;
  quality: ExtractionQuality;
  staticCandidateCount: number;
  renderedCandidateCount: number | null;
};

type ReviewGate = ReviewContract & {
  quality: ExtractionQuality;
};

type ParsedExtractionResult = {
  ok: true;
  fallbackUsed: boolean;
  fallbackReason: string | null;
  strategy: string;
  review: ReviewGate;
  retainedEvidence: RetainedExtractionEvidence | null;
};

type ImportJobData = {
  brandID?: unknown;
  jobType?: unknown;
  status?: unknown;
  sourceURL?: unknown;
  sourceImportJobID?: unknown;
  sourceCandidateID?: unknown;
  sourceTitle?: unknown;
  coverRemoteURL?: unknown;
  sourceSortIndex?: unknown;
  imageCandidates?: unknown;
  imageExtractorVersion?: unknown;
  platformAdapterKey?: unknown;
  platformAdapterVersion?: unknown;
  domainAdapterKey?: unknown;
  domainAdapterVersion?: unknown;
  extractionQualityStatus?: unknown;
  extractionQualityReasons?: unknown;
  contentHashResolutionComplete?: unknown;
  imageCandidateContentHashes?: unknown;
  imageExtractionStrategy?: unknown;
  expectedCountEvidence?: unknown;
  programmaticGalleryEvidence?: unknown;
  renderedImageCandidateCount?: unknown;
  templateSignature?: unknown;
  trustBaselineID?: unknown;
  reviewSnapshotHash?: unknown;
  reviewCandidateKeys?: unknown;
  reviewGeneration?: unknown;
  reviewStatus?: unknown;
  trustEligible?: unknown;
  resumeFrom?: unknown;
  approvedCandidateKeys?: unknown;
  dispatchGeneration?: unknown;
  repairGeneration?: unknown;
  repairStatus?: unknown;
  repairTargetSeasonID?: unknown;
  targetSeasonID?: unknown;
  createdPostIDs?: unknown;
  parseStatus?: unknown;
  contentStatus?: unknown;
  assetSyncStatus?: unknown;
  assetTotalCount?: unknown;
  assetRetryRequestID?: unknown;
  leaseOwner?: unknown;
  leaseExpiresAt?: unknown;
  createdAt?: unknown;
  taskEnqueuedAt?: unknown;
};

type SeasonCandidateData = {
  title?: unknown;
  coverImageURL?: unknown;
  sortIndex?: unknown;
};

type SeasonData = {
  coverRemoteURL?: unknown;
};

type PostData = {
  media?: unknown;
  assetSyncErrorMessage?: unknown;
  orderIndex?: unknown;
  sourceSortIndex?: unknown;
  deletionStatus?: unknown;
  createdAt?: unknown;
};

type AssetFailureData = {
  postID?: unknown;
  mediaIndex?: unknown;
  remoteURL?: unknown;
  sourcePageURL?: unknown;
  sourceImportJobID?: unknown;
  attemptCount?: unknown;
};

type MediaData = {
  remoteURL?: unknown;
  sourcePageURL?: unknown;
  thumbPath?: unknown;
  detailPath?: unknown;
  contentHash?: unknown;
};

type JobTarget = {
  brandID: string;
  jobID: string;
};

type ClaimedJob = JobTarget & {
  jobType: "importSeasonFromURL" | "retrySeasonAssets";
  sourceURL: string;
  sourceCandidateID: string | null;
  sourceImportJobID: string | null;
  targetSeasonID: string | null;
  resumeFrom: "parsing" | "materializing";
  reviewGeneration: number;
  reviewSnapshotHash: string | null;
  dispatchGeneration: number;
  repairGeneration: number;
  repairTargetSeasonID: string | null;
};

type JobResult = JobTarget & {
  processed: boolean;
  status: WorkerStatus | "skipped";
  parseStatus?: string;
  contentStatus?: string;
  assetSyncStatus?: string;
  seasonID?: string;
  postCount?: number;
  completedCount?: number;
  failedCount?: number;
  reason?: string;
  errorMessage?: string;
};

type LogContext = JobTarget & {
  workerID: string;
  jobType: "importSeasonFromURL" | "retrySeasonAssets";
  sourceURL: string;
};

export type WakeRequest = {
  brandID?: unknown;
  jobIDs?: unknown;
  batchSize?: unknown;
};

export type ImportJobTaskRequest = {
  mode?: unknown;
  brandID?: unknown;
  jobID?: unknown;
  seasonID?: unknown;
  sourceJobID?: unknown;
  requestID?: unknown;
  maxAttempts?: unknown;
  requestedAt?: unknown;
  dispatchGeneration?: unknown;
  reviewGeneration?: unknown;
  reviewSnapshotHash?: unknown;
};

export type WakeResult = {
  accepted: true;
  workerID: string;
  requestedJobCount: number;
  processedJobCount: number;
  skippedJobCount: number;
  failedJobCount: number;
  results: JobResult[];
};

export type ImportJobTaskResult = {
  accepted: true;
  workerID: string;
  result: JobResult;
};

type ProcessorDependencies = {
  firestore: Firestore;
  storage: Storage;
  assetSyncConcurrency: number;
};

type TaskRetryPolicy = {
  retryCount: number;
  maxAttempts: number;
};

type SyncTarget =
  | {
      kind: "seasonCover";
      brandID: string;
      seasonID: string;
      remoteURL: string;
      sourcePageURL: string;
    }
  | {
      kind: "postImage";
      brandID: string;
      seasonID: string;
      postID: string;
      mediaIndex: number;
      remoteURL: string;
      sourcePageURL: string;
    };

type SyncTargetResult = {
  target: SyncTarget;
  succeeded: boolean;
  skipped: boolean;
  errorMessage?: string;
};

const DEFAULT_BATCH_SIZE = 5;
const MAX_BATCH_SIZE = 20;
const LEASE_DURATION_MS = 5 * 60 * 1000;
const LEASE_REFRESH_MS = 90 * 1000;
const MAX_IMAGE_CANDIDATES_TO_STORE = 120;
const MIN_STRONG_SECTION_WEIGHT = 240;
const MIN_DYNAMIC_PARTIAL_CANDIDATES = 10;
const MIN_RAW_CANDIDATES_FOR_DROP_CHECK = 8;
const FETCH_HTML_TIMEOUT_MS = 15_000;
const FETCH_IMAGE_TIMEOUT_MS = 20_000;
const PLAYWRIGHT_NAVIGATION_TIMEOUT_MS = 20_000;
const PLAYWRIGHT_RENDER_SETTLE_MS = 1_500;
const HTML_MAX_BYTES = 5 * 1024 * 1024;
const REMOTE_IMAGE_MAX_BYTES = 25 * 1024 * 1024;
const GENERIC_CONTENT_SECTION_RULES: ContentSectionRule[] = [
  {
    label: "productDetailContent",
    pattern:
      /prdDetail|detail[_-]?content|detailArea|product[_-]?detail[_-]?area/i,
    weight: 300,
  },
  {
    label: "editorContent",
    pattern: /fr-view|se-main-container|editor|edibot/i,
    weight: 260,
  },
  {
    label: "lookbookContent",
    pattern:
      /lookbook|collection[_-]?detail|collection[_-]?view|campaign|season/i,
    weight: 180,
  },
  {
    label: "mainContent",
    pattern: /\bmain\b|article|content/i,
    weight: 80,
  },
];

const NOISE_IMAGE_URL_PATTERNS = [
  /\/(?:M_banner|banner|banners|icon|icons|logo|favicon|layout)\//i,
  /\/web\/product\/(?:tiny|small|medium|list)\//i,
  /(?:btn_count_|btn_price_delete|ico_pay_point|icon_(?:facebook|twitter))\.(?:gif|png|jpg|jpeg|webp)(?:\?|$)/i,
  /(?:sprite|blank|placeholder|loading)\.(?:gif|png|svg)(?:\?|$)/i,
];
const HARD_NOISE_IMAGE_URL_PATTERNS = [
  /(?:^|\/\/)(?:www\.)?facebook\.com\/tr\?/i,
  /(?:^|\/\/)(?:www\.)?(?:googletagmanager|google-analytics|googleadservices)\.com\//i,
  /(?:^|\/\/)(?:www\.)?(?:channel|charlla)\.io\//i,
  /(?:chat|talk|kakao)[_-]?icon[^/]*\.(?:gif|png|svg|webp)(?:\?|$)/i,
  /(?:logo|favicon)[^/]*\.(?:gif|png|svg|webp)(?:\?|$)/i,
  /(?:social|sns|facebook|kakao|naver|instagram|twitter|fb_icon|insta_icon)/i,
  /\/img\/common\/global\/[^/?#]*_32x24\.png(?:[?#]|$)/i,
  /\/[^/?#]*(?:bg[_-]?search|youtube[_-]?icon|ic[_-]?(?:arr|star))[^/?#]*\.(?:gif|jpe?g|png|svg|webp)(?:[?#]|$)/i,
  /\/[^/?#]*(?:btn|button|icon-plus|count_|page_(?:first|prev|next)|close|share|menu|copy[_-]?icon|icon[_-]?copy)[^/?#]*\.(?:gif|jpe?g|png|svg|webp)(?:[?#]|$)/i,
  /(?:cursor|txt_progress|img_loading|top_banner|topbanner)/i,
];

const NOISE_CONTEXT_PATTERN =
  /product\/list\.html|category\/|view all|gnb|lnb|menu|header|footer|basket|cart|order|payment|purchase|quantity|option|결제|주문|장바구니|수량|옵션/i;
const DYNAMIC_RENDERING_SIGNAL_PATTERNS = [
  /__NEXT_DATA__/i,
  /__NUXT__|__NUXT_DATA__|\bnuxt(?:App|State)?\b/i,
  /data-reactroot/i,
  /data-reactid/i,
  /\bhydrateRoot\b/i,
  /\bcreateRoot\b/i,
];
const LOW_CONFIDENCE_STRATEGIES = new Set([
  "allPageImages",
  "filteredPageImages",
]);

const SEASON_COVER_THUMB = {maxPixel: 512, quality: 75};
const SEASON_COVER_DETAIL = {maxPixel: 1600, quality: 88};
const POST_IMAGE_THUMB = {maxPixel: 768, quality: 82};
const POST_IMAGE_DETAIL = {maxPixel: 1920, quality: 90};

export async function processWakeRequest(
  dependencies: ProcessorDependencies,
  request: WakeRequest,
): Promise<WakeResult> {
  const workerID = `worker_${randomUUID()}`;
  const batchSize = parseBatchSize(request.batchSize);
  const targets = await resolveJobTargets(dependencies.firestore, request, batchSize);
  const results: JobResult[] = [];

  for (const target of targets) {
    results.push(await processJob(dependencies, target, workerID));
  }

  return {
    accepted: true,
    workerID,
    requestedJobCount: targets.length,
    processedJobCount: results.filter((result) => result.processed).length,
    skippedJobCount: results.filter((result) => result.status === "skipped").length,
    failedJobCount: results.filter((result) => result.status === "failed").length,
    results,
  };
}

export async function processImportJobTaskRequest(
  dependencies: ProcessorDependencies,
  request: ImportJobTaskRequest,
  retryCount: number,
): Promise<ImportJobTaskResult> {
  const workerID = `worker_${randomUUID()}`;
  if (optionalStringField(request.mode) === "assetFailureRetry") {
    const result = await processAssetFailureRetryTask(
      dependencies,
      request,
      workerID,
      {
        retryCount: nonNegativeInteger(retryCount, "retryCount"),
        maxAttempts: positiveInteger(request.maxAttempts, "maxAttempts"),
      },
    );
    return {
      accepted: true,
      workerID,
      result,
    };
  }

  const target = {
    brandID: requiredDocumentID(request.brandID, "brandID"),
    jobID: requiredDocumentID(request.jobID, "jobID"),
  };
  const retryPolicy = {
    retryCount: nonNegativeInteger(retryCount, "retryCount"),
    maxAttempts: positiveInteger(request.maxAttempts, "maxAttempts"),
  };

  const result = await processJob(
    dependencies,
    target,
    workerID,
    retryPolicy,
    {
      dispatchGeneration: nonNegativeInteger(
        request.dispatchGeneration ?? 0,
        "dispatchGeneration",
      ),
      reviewGeneration: optionalNonNegativeInteger(
        request.reviewGeneration,
        "reviewGeneration",
      ),
      reviewSnapshotHash: optionalStringField(request.reviewSnapshotHash),
    },
  );
  return {
    accepted: true,
    workerID,
    result,
  };
}

async function resolveJobTargets(
  db: Firestore,
  request: WakeRequest,
  batchSize: number,
): Promise<JobTarget[]> {
  const brandID = optionalDocumentID(request.brandID, "brandID");
  const jobIDs = optionalDocumentIDList(request.jobIDs, "jobIDs");

  if (jobIDs.length > 0) {
    if (brandID === null) {
      throw new Error("jobIDs를 지정할 때는 brandID 값이 필요합니다.");
    }
    return jobIDs.slice(0, batchSize).map((jobID) => ({brandID, jobID}));
  }

  if (brandID !== null) {
    const snapshot = await db
      .collection("brands")
      .doc(brandID)
      .collection("importJobs")
      .where("status", "in", ["queued", "processing"])
      .limit(Math.max(batchSize * 4, batchSize))
      .get();

    return snapshot.docs
      .filter((doc) => canScanJob(doc.data() as ImportJobData))
      .sort((lhs, rhs) => createdAtMillis(lhs.data()) - createdAtMillis(rhs.data()))
      .slice(0, batchSize)
      .map((doc) => ({brandID, jobID: doc.id}));
  }

  const snapshot = await db
    .collectionGroup("importJobs")
    .where("status", "==", "queued")
    .limit(batchSize)
    .get();

  return snapshot.docs
    .map((doc) => {
      const data = doc.data() as ImportJobData;
      const resolvedBrandID = optionalDocumentID(data.brandID, "brandID");
      if (
        resolvedBrandID === null ||
        (
          data.jobType !== "importSeasonFromURL" &&
          data.jobType !== "retrySeasonAssets"
        )
      ) {
        return null;
      }
      return {brandID: resolvedBrandID, jobID: doc.id};
    })
    .filter((target): target is JobTarget => target !== null);
}

async function processJob(
  dependencies: ProcessorDependencies,
  target: JobTarget,
  workerID: string,
  retryPolicy?: TaskRetryPolicy,
  dispatchContract?: {
    dispatchGeneration: number;
    reviewGeneration: number | null;
    reviewSnapshotHash: string | null;
  },
): Promise<JobResult> {
  const db = dependencies.firestore;
  const jobRef = importJobRef(db, target);
  const claim = await claimJob(
    db,
    target,
    workerID,
    dispatchContract,
  );
  if (!claim.claimed) {
    return {
      ...target,
      processed: false,
      status: "skipped",
      reason: claim.reason,
    };
  }
  const claimedJob: ClaimedJob = {
    ...target,
    jobType: claim.jobType,
    sourceURL: claim.sourceURL,
    sourceCandidateID: claim.sourceCandidateID,
    sourceImportJobID: claim.sourceImportJobID,
    targetSeasonID: claim.targetSeasonID,
    resumeFrom: claim.resumeFrom,
    reviewGeneration: claim.reviewGeneration,
    reviewSnapshotHash: claim.reviewSnapshotHash,
    dispatchGeneration: claim.dispatchGeneration,
    repairGeneration: claim.repairGeneration,
    repairTargetSeasonID: claim.repairTargetSeasonID,
  };
  const logContext: LogContext = {
    brandID: claimedJob.brandID,
    jobID: claimedJob.jobID,
    jobType: claimedJob.jobType,
    sourceURL: claimedJob.sourceURL,
    workerID,
  };
  const jobStartedAt = Date.now();
  const failurePatch = (
    patch: Record<string, unknown>,
  ): Record<string, unknown> => claimedJob.repairTargetSeasonID === null ?
    patch :
    {...patch, repairStatus: "failed"};
  await logJobStarted(jobRef, logContext, retryPolicy);

  const leaseTimer = setInterval(() => {
    void refreshLease(jobRef, workerID).catch((error: unknown) => {
      console.warn("[lookbook-import-worker] lease refresh failed", error);
    });
  }, LEASE_REFRESH_MS);

  try {
    if (claimedJob.jobType === "retrySeasonAssets") {
      const result = await processAssetRetryJob(
        dependencies,
        jobRef,
        claimedJob,
        logContext,
      );
      logJobCompleted(logContext, result, {
        totalDurationMs: elapsedMs(jobStartedAt),
      });
      return result;
    }

    if (claimedJob.resumeFrom === "parsing") {
      const parseStartedAt = Date.now();
      const parseResult = await ensureParsed(db, jobRef, claimedJob);
      logPhaseCompleted(logContext, "parsing", elapsedMs(parseStartedAt), {
        fallbackUsed: parseResult.ok ? parseResult.fallbackUsed : false,
      });
      if (parseResult.ok && parseResult.fallbackUsed) {
        logFallbackUsed(logContext, {
          reason: parseResult.fallbackReason,
          strategy: parseResult.strategy,
        });
      }
      if (!parseResult.ok) {
        await retainExtractionEvidenceSafely(
          dependencies,
          jobRef,
          claimedJob,
          parseResult.retainedEvidence,
        );
        return await failJob(jobRef, target, parseResult.errorMessage, failurePatch({
          parseStatus: "failed",
        }));
      }
      if (parseResult.retainedEvidence !== null) {
        await retainExtractionEvidenceSafely(
          dependencies,
          jobRef,
          claimedJob,
          parseResult.retainedEvidence,
        );
      }
      if (claimedJob.repairTargetSeasonID !== null) {
        return await prepareSeasonRepairPreview(
          dependencies,
          jobRef,
          claimedJob,
        );
      }
      const reviewResult = await pauseForReviewIfNeeded(
        db,
        jobRef,
        claimedJob,
        parseResult.review,
      );
      if (reviewResult !== null) {
        return reviewResult;
      }
    } else if (
      requiresApprovedReviewSnapshot(claimedJob) &&
      (
        claimedJob.reviewSnapshotHash === null ||
        claimedJob.reviewGeneration <= 0
      )
    ) {
      return await failJob(
        jobRef,
        target,
        "승인된 review snapshot 정보가 없습니다.",
        failurePatch({contentStatus: "failed"}),
      );
    }

    const materializeStartedAt = Date.now();
    const materializeResult = await ensureMaterialized(db, jobRef, claimedJob);
    logPhaseCompleted(
      logContext,
      "materializing",
      elapsedMs(materializeStartedAt),
      {
        seasonID: materializeResult.ok ? materializeResult.seasonID : null,
        postCount: materializeResult.ok ? materializeResult.postCount : null,
      },
    );
    if (!materializeResult.ok) {
      return await failJob(jobRef, target, materializeResult.errorMessage, failurePatch({
        contentStatus: "failed",
      }));
    }

    const assetSyncStartedAt = Date.now();
    const assetResult = await syncAssets(
      dependencies,
      jobRef,
      claimedJob,
      materializeResult.seasonID,
      logContext,
    );
    logPhaseCompleted(logContext, "syncingAssets", elapsedMs(assetSyncStartedAt), {
      seasonID: materializeResult.seasonID,
      assetCompletedCount: assetResult.completedCount,
      assetFailedCount: assetResult.failedCount,
      assetStatus: assetResult.status,
    });

    const finalStatus = completedLifecycle(assetResult.status);
    await jobRef.update({
      status: finalStatus,
      phase: "completed",
      assetSyncStatus: assetResult.status,
      assetCompletedCount: assetResult.completedCount,
      assetFailedCount: assetResult.failedCount,
      assetSyncedAt: FieldValue.serverTimestamp(),
      errorMessage: assetResult.errorMessage ?? null,
      assetSyncErrorMessage: assetResult.errorMessage ?? null,
      completedAt: FieldValue.serverTimestamp(),
      leaseOwner: null,
      leaseExpiresAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    });

    const result = {
      ...target,
      processed: true,
      status: finalStatus,
      parseStatus: "succeeded",
      contentStatus: "succeeded",
      assetSyncStatus: assetResult.status,
      seasonID: materializeResult.seasonID,
      postCount: materializeResult.postCount,
      completedCount: assetResult.completedCount,
      failedCount: assetResult.failedCount,
      errorMessage: assetResult.errorMessage,
    };
    logJobCompleted(logContext, result, {
      seasonID: materializeResult.seasonID,
      postCount: materializeResult.postCount,
      totalDurationMs: elapsedMs(jobStartedAt),
    });
    return result;
  } catch (error) {
    if (isRetryableImportError(error)) {
      if (
        retryPolicy &&
        isFinalTaskAttempt(
          retryPolicy.retryCount,
          retryPolicy.maxAttempts,
        )
      ) {
        const source = extractionSourceEvidence(claimedJob.sourceURL);
        const retainedEvidence = buildRetainedExtractionEvidence({
          status: "failed",
          stage: "parsing",
          sourceURL: claimedJob.sourceURL,
          strategy: "unknown",
          failureReasons: ["retry_exhausted"],
          templateSignature: createHash("sha256")
            .update(JSON.stringify({stage: "parsing", source}))
            .digest("hex")
            .slice(0, 32),
          versions: CURRENT_EXTRACTION_VERSIONS,
        });
        await retainExtractionEvidenceSafely(
          dependencies,
          jobRef,
          claimedJob,
          retainedEvidence,
        );
        return failJob(jobRef, target, error.message, failurePatch({
          parseStatus: "failed",
          errorCode: "retryExhausted",
        }));
      }
      await releaseJobForTaskRetry(jobRef, error.message);
      throw error;
    }
    return await failJob(
      jobRef,
      target,
      errorMessage(error),
      failurePatch({}),
    );
  } finally {
    clearInterval(leaseTimer);
  }
}

async function claimJob(
  db: Firestore,
  target: JobTarget,
  workerID: string,
  dispatchContract?: {
    dispatchGeneration: number;
    reviewGeneration: number | null;
    reviewSnapshotHash: string | null;
  },
): Promise<
  | {
      claimed: true;
      jobType: "importSeasonFromURL" | "retrySeasonAssets";
      sourceURL: string;
      sourceCandidateID: string | null;
      sourceImportJobID: string | null;
      targetSeasonID: string | null;
      resumeFrom: "parsing" | "materializing";
      reviewGeneration: number;
      reviewSnapshotHash: string | null;
      dispatchGeneration: number;
      repairGeneration: number;
      repairTargetSeasonID: string | null;
    }
  | {claimed: false; reason: string}
> {
  const jobRef = importJobRef(db, target);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(jobRef);
    const data = snapshot.data() as ImportJobData | undefined;
    if (!snapshot.exists || !data) {
      return {claimed: false, reason: "notFound"};
    }
    if (
      data.jobType !== "importSeasonFromURL" &&
      data.jobType !== "retrySeasonAssets"
    ) {
      return {claimed: false, reason: "invalidJobType"};
    }
    if (stringField(data.brandID, "brandID") !== target.brandID) {
      throw new Error("job 문서의 brandID가 요청 brandID와 다릅니다.");
    }
    if (!isClaimable(data)) {
      return {
        claimed: false,
        reason: `notClaimable:${String(data.status ?? "unknown")}`,
      };
    }
    const dispatchGeneration = integerField(data.dispatchGeneration, 0);
    if (
      dispatchContract !== undefined &&
      dispatchContract.dispatchGeneration !== dispatchGeneration
    ) {
      return {claimed: false, reason: "staleDispatchGeneration"};
    }
    const resumeFrom = data.resumeFrom === "materializing" ?
      "materializing" :
      "parsing";
    const reviewGeneration = integerField(data.reviewGeneration, 0);
    const reviewSnapshotHash = optionalStringField(data.reviewSnapshotHash);
    const repairGeneration = integerField(data.repairGeneration, 0);
    const repairTargetSeasonID = optionalStringField(data.repairTargetSeasonID);
    if (
      dispatchContract?.reviewGeneration !== null &&
      dispatchContract?.reviewGeneration !== undefined &&
      (
        dispatchContract.reviewGeneration !== reviewGeneration ||
        dispatchContract.reviewSnapshotHash !== reviewSnapshotHash
      )
    ) {
      return {claimed: false, reason: "staleReviewSnapshot"};
    }

    transaction.update(jobRef, {
      status: "processing",
      phase: resumeFrom,
      processingEngine: "cloudRunWorker",
      parseStatus: data.parseStatus ?? "pending",
      contentStatus: data.contentStatus ?? "pending",
      assetSyncStatus: data.assetSyncStatus ?? "pending",
      leaseOwner: workerID,
      leaseExpiresAt: Timestamp.fromMillis(Date.now() + LEASE_DURATION_MS),
      processingStartedAt: FieldValue.serverTimestamp(),
      lastAttemptAt: FieldValue.serverTimestamp(),
      attemptCount: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
      errorMessage: null,
    });

    return {
      claimed: true,
      jobType: data.jobType,
      sourceURL: stringField(data.sourceURL, "sourceURL"),
      sourceCandidateID: optionalStringField(data.sourceCandidateID),
      sourceImportJobID: optionalStringField(data.sourceImportJobID),
      targetSeasonID: optionalStringField(data.targetSeasonID),
      resumeFrom,
      reviewGeneration,
      reviewSnapshotHash,
      dispatchGeneration,
      repairGeneration,
      repairTargetSeasonID,
    };
  });
}

async function processAssetRetryJob(
  dependencies: ProcessorDependencies,
  jobRef: FirebaseFirestore.DocumentReference,
  claim: ClaimedJob,
  logContext: LogContext,
): Promise<JobResult> {
  if (claim.targetSeasonID === null || claim.sourceImportJobID === null) {
    return failJob(jobRef, claim, "asset retry 대상 정보가 없습니다.", {
      contentStatus: "failed",
    });
  }

  await jobRef.update({
    parseStatus: "skipped",
    contentStatus: "skipped",
    phase: "syncingAssets",
    updatedAt: FieldValue.serverTimestamp(),
  });
  const assetSyncStartedAt = Date.now();
  const assetResult = await syncAssets(
    dependencies,
    jobRef,
    claim,
    claim.targetSeasonID,
    logContext,
  );
  logPhaseCompleted(logContext, "syncingAssets", elapsedMs(assetSyncStartedAt), {
    seasonID: claim.targetSeasonID,
    assetCompletedCount: assetResult.completedCount,
    assetFailedCount: assetResult.failedCount,
    assetStatus: assetResult.status,
  });
  const finalStatus = completedLifecycle(assetResult.status);
  const finalPatch = {
    status: finalStatus,
    phase: "completed",
    assetSyncStatus: assetResult.status,
    assetCompletedCount: assetResult.completedCount,
    assetFailedCount: assetResult.failedCount,
    assetSyncedAt: FieldValue.serverTimestamp(),
    completedAt: FieldValue.serverTimestamp(),
    errorMessage: assetResult.errorMessage ?? null,
    assetSyncErrorMessage: assetResult.errorMessage ?? null,
    leaseOwner: null,
    leaseExpiresAt: null,
    updatedAt: FieldValue.serverTimestamp(),
  };
  await Promise.all([
    jobRef.update(finalPatch),
    importJobRef(dependencies.firestore, {
      brandID: claim.brandID,
      jobID: claim.sourceImportJobID,
    }).update(finalPatch),
  ]);

  return {
    brandID: claim.brandID,
    jobID: claim.jobID,
    processed: true,
    status: finalStatus,
    parseStatus: "skipped",
    contentStatus: "skipped",
    assetSyncStatus: assetResult.status,
    seasonID: claim.targetSeasonID,
    completedCount: assetResult.completedCount,
    failedCount: assetResult.failedCount,
    errorMessage: assetResult.errorMessage,
  };
}

async function processAssetFailureRetryTask(
  dependencies: ProcessorDependencies,
  request: ImportJobTaskRequest,
  workerID: string,
  retryPolicy: TaskRetryPolicy,
): Promise<JobResult> {
  const brandID = requiredDocumentID(request.brandID, "brandID");
  const seasonID = requiredDocumentID(request.seasonID, "seasonID");
  const sourceJobID = requiredDocumentID(request.sourceJobID, "sourceJobID");
  const requestID = stringField(request.requestID, "requestID");
  const jobRef = importJobRef(dependencies.firestore, {
    brandID,
    jobID: sourceJobID,
  });
  const logContext: LogContext = {
    brandID,
    jobID: sourceJobID,
    workerID,
    jobType: "importSeasonFromURL",
    sourceURL: "",
  };

  try {
    const sourceSnapshot = await jobRef.get();
    const sourceJob = sourceSnapshot.data() as ImportJobData | undefined;
    if (!sourceSnapshot.exists || !sourceJob) {
      return {
        brandID,
        jobID: sourceJobID,
        processed: false,
        status: "skipped",
        reason: "sourceJobNotFound",
      };
    }
    if (optionalStringField(sourceJob.assetRetryRequestID) !== requestID) {
      return {
        brandID,
        jobID: sourceJobID,
        processed: false,
        status: "skipped",
        reason: "staleAssetRetryRequest",
      };
    }

    const sourceURL = stringField(sourceJob.sourceURL, "sourceURL");
    const totalCount = optionalInteger(sourceJob.assetTotalCount);
    logContext.sourceURL = sourceURL;

    await jobRef.update({
      assetRetryStatus: "processing",
      assetRetryStartedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    await ensureAssetFailuresForSourceJob(
      dependencies.firestore,
      brandID,
      seasonID,
      sourceJobID,
      sourceURL,
      sourceJob,
    );

    const failures = await assetFailureTargets(
      dependencies.firestore,
      brandID,
      seasonID,
      sourceJobID,
      sourceURL,
    );
    if (failures.length === 0) {
      await markAssetRetryCompleted(
        dependencies.firestore,
        brandID,
        seasonID,
        sourceJobID,
        totalCount,
        0,
        "ready",
        null,
      );
      return {
        brandID,
        jobID: sourceJobID,
        processed: true,
        status: "succeeded",
        assetSyncStatus: "ready",
        seasonID,
        completedCount: totalCount ?? 0,
        failedCount: 0,
      };
    }

    const results = await runSyncTargets(dependencies, failures);
    const failedResults = results.filter((result) => !result.succeeded);
    failedResults.forEach((result) => {
      logAssetFailed(logContext, result);
    });
    await Promise.all(results.map((result) => updateAssetFailureAfterRetry(
      dependencies.firestore,
      result,
      sourceJobID,
    )));

    const remainingCount = await assetFailureCount(
      dependencies.firestore,
      brandID,
      seasonID,
    );
    const assetStatus = remainingCount === 0 ? "ready" : "partial";
    const finalStatus = remainingCount === 0 ? "succeeded" : "partialFailed";
    const firstError = failedResults[0]?.errorMessage ?? null;
    const completedCount = totalCount === null ?
      Math.max(0, failures.length - remainingCount) :
      Math.max(0, totalCount - remainingCount);

    await markAssetRetryCompleted(
      dependencies.firestore,
      brandID,
      seasonID,
      sourceJobID,
      totalCount,
      remainingCount,
      assetStatus,
      firstError,
    );

    return {
      brandID,
      jobID: sourceJobID,
      processed: true,
      status: finalStatus,
      assetSyncStatus: assetStatus,
      seasonID,
      completedCount,
      failedCount: remainingCount,
      errorMessage: firstError ?? undefined,
    };
  } catch (error) {
    if (
      isRetryableImportError(error) &&
      !isFinalTaskAttempt(retryPolicy.retryCount, retryPolicy.maxAttempts)
    ) {
      await jobRef.update({
        assetRetryStatus: "queued",
        assetRetryErrorMessage: errorMessage(error),
        updatedAt: FieldValue.serverTimestamp(),
      });
      throw error;
    }
    await jobRef.update({
      assetRetryStatus: "failed",
      assetRetryErrorMessage: errorMessage(error),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      brandID,
      jobID: sourceJobID,
      processed: true,
      status: "partialFailed",
      assetSyncStatus: "partial",
      seasonID,
      errorMessage: errorMessage(error),
    };
  }
}

function isClaimable(data: ImportJobData): boolean {
  if (data.status === "queued") {
    return true;
  }
  if (data.status === "processing") {
    return timestampMillis(data.leaseExpiresAt) < Date.now();
  }
  return false;
}

async function ensureParsed(
  db: Firestore,
  jobRef: FirebaseFirestore.DocumentReference,
  claim: ClaimedJob,
): Promise<
  | ParsedExtractionResult
  | {
      ok: false;
      errorMessage: string;
      retainedEvidence: RetainedExtractionEvidence;
    }
> {
  const snapshot = await jobRef.get();
  const data = snapshot.data() as ImportJobData | undefined;
  const cachedCandidates = parsedImageCandidates(data?.imageCandidates);
  const cachedReview = parsedReviewGate(data);
  const canReuseCachedExtraction = isReusableExtractionCache({
    candidateCount: cachedCandidates.length,
    extractorVersion: data?.imageExtractorVersion,
    platformAdapterKey: data?.platformAdapterKey,
    platformAdapterVersion: data?.platformAdapterVersion,
    domainAdapterKey: data?.domainAdapterKey,
    domainAdapterVersion: data?.domainAdapterVersion,
    qualityStatus: data?.extractionQualityStatus,
    contentHashResolutionComplete: data?.contentHashResolutionComplete,
  });
  if (canReuseCachedExtraction && cachedReview !== null) {
    const cachedVersions = {
      extractorVersion: CURRENT_EXTRACTION_VERSIONS.extractorVersion,
      platformAdapterKey: optionalStringField(data?.platformAdapterKey),
      platformAdapterVersion: optionalStringField(data?.platformAdapterVersion),
      domainAdapterKey: optionalStringField(data?.domainAdapterKey),
      domainAdapterVersion: optionalStringField(data?.domainAdapterVersion),
    };
    const cachedExtraction = extractionResult({
      candidates: cachedCandidates,
      strategy: "cached",
      rawCandidateCount: cachedCandidates.length,
      sourceURL: claim.sourceURL,
      candidateKey: (candidate) => extractionCandidateKey(candidate.sourceURL),
      versions: cachedVersions,
    });
    await jobRef.update({
      parseStatus: "succeeded",
      imageCandidateEvidence: cachedExtraction.candidateEvidence.slice(
        0,
        MAX_IMAGE_CANDIDATES_TO_STORE,
      ),
      imageExtractorVersion: CURRENT_EXTRACTION_VERSIONS.extractorVersion,
      platformAdapterKey: cachedVersions.platformAdapterKey,
      platformAdapterVersion: cachedVersions.platformAdapterVersion,
      domainAdapterKey: cachedVersions.domainAdapterKey,
      domainAdapterVersion: cachedVersions.domainAdapterVersion,
      parsedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      ok: true,
      fallbackUsed: false,
      fallbackReason: null,
      strategy: "cached",
      review: cachedReview,
      retainedEvidence: cachedReview.quality.status === "needsReview" ?
        buildRetainedExtractionEvidence({
          status: "needsReview",
          stage: "parsing",
          sourceURL: claim.sourceURL,
          strategy: stringValue(data?.imageExtractionStrategy, "cached"),
          qualityReasons: cachedReview.quality.reasons,
          templateSignature: cachedReview.templateSignature,
          candidateEvidence: cachedExtraction.candidateEvidence,
          versions: cachedExtraction.versions,
        }) :
        null,
    };
  }

  await jobRef.update({
    phase: "parsing",
    parseStatus: "running",
    updatedAt: FieldValue.serverTimestamp(),
  });

  let retainedHTML: string | null = null;
  try {
    const html = await withImmediateRetry(() => fetchHTML(claim.sourceURL));
    retainedHTML = html;
    const staticExtraction = extractImageCandidates(html, claim.sourceURL);
    const expectedCountEvidence = collectExpectedCountEvidence(
      html,
      claim.sourceURL,
    );
    const programmaticGalleryEvidence = detectProgrammaticGallery(
      html,
    );
    const fallbackReason = fallbackReasonForExtraction(
      staticExtraction,
      html,
      programmaticGalleryEvidence,
    );
    const fallbackExtraction = fallbackReason === null ?
      {extraction: staticExtraction, renderedCandidateCount: null} :
      await extractionWithPlaywrightFallback(
        claim.sourceURL,
        staticExtraction,
        fallbackReason,
      );
    const sourceExtraction = fallbackExtraction.extraction;
    if (sourceExtraction.candidates.length === 0) {
      throw new Error("이미지 후보를 찾지 못했습니다.");
    }
    const contentHashDedupe = await resolveContentHashDedupe({
      candidates: sourceExtraction.candidates,
      concurrency: 4,
      loadBytes: async (candidate) => {
        try {
          return await fetchRemoteImageBytes(
            candidate.sourceURL,
            claim.sourceURL,
          );
        } catch {
          return null;
        }
      },
    });
    const quality = evaluateExtractionQuality({
      candidateCount: sourceExtraction.candidates.length,
      rawCandidateCount: sourceExtraction.rawCandidateCount,
      staticCandidateCount: staticExtraction.candidates.length,
      renderedCandidateCount: fallbackExtraction.renderedCandidateCount,
      expectedCountEvidence,
      programmaticGalleryDetected: programmaticGalleryEvidence.detected,
      contentHashComplete: contentHashDedupe.complete,
    });
    const extraction = selectExtractionCandidates({
      result: sourceExtraction,
      candidates: contentHashDedupe.candidates,
      candidateKey: (candidate) => canonicalCandidateURL(candidate.sourceURL),
    });
    const review = {
      ...makeReviewContract({
        brandID: claim.brandID,
        sourceURL: claim.sourceURL,
        strategy: extraction.strategy,
        candidateKeys: extraction.candidateEvidence.map(
          (evidence) => evidence.candidateKey,
        ),
        expectedCountEvidence,
        programmaticGalleryEvidence,
        quality,
        renderedCandidateCount: fallbackExtraction.renderedCandidateCount,
        contentHashComplete: contentHashDedupe.complete,
        versions: extraction.versions,
        structureTokens: extractionStructureTokens(html),
      }),
      quality,
    };

    await jobRef.update({
      parseStatus: "succeeded",
      imageCandidateCount: extraction.candidates.length,
      imageCandidates: extraction.candidates.slice(0, MAX_IMAGE_CANDIDATES_TO_STORE),
      imageExtractionStrategy: extraction.strategy,
      imageExtractionFallbackUsed: extraction.strategy.startsWith("playwright:"),
      imageExtractionFallbackReason: extraction.strategy.startsWith("playwright:") ?
        fallbackReason :
        null,
      rawImageCandidateCount: extraction.rawCandidateCount,
      staticImageCandidateCount: staticExtraction.candidates.length,
      renderedImageCandidateCount: fallbackExtraction.renderedCandidateCount,
      sourceImageCandidateCount: contentHashDedupe.sourceCandidateCount,
      contentHashResolvedCandidateCount:
        contentHashDedupe.resolvedCandidateCount,
      contentHashCandidateCount: contentHashDedupe.contentHashCandidateCount,
      contentHashResolutionFailureCount: contentHashDedupe.failureCount,
      contentHashResolutionComplete: contentHashDedupe.complete,
      imageCandidateContentHashes: contentHashDedupe.contentHashes.map(
        (item) => ({
          candidateKey: extractionCandidateKey(item.canonicalURL),
          contentHash: item.contentHash,
        }),
      ),
      expectedCountEvidence,
      programmaticGalleryEvidence,
      extractionQualityStatus: quality.status,
      extractionQualityReasons: quality.reasons,
      imageCandidateEvidence: extraction.candidateEvidence.slice(
        0,
        MAX_IMAGE_CANDIDATES_TO_STORE,
      ),
      imageExtractorVersion: extraction.versions.extractorVersion,
      platformAdapterKey: extraction.versions.platformAdapterKey,
      platformAdapterVersion: extraction.versions.platformAdapterVersion,
      domainAdapterKey: extraction.versions.domainAdapterKey,
      domainAdapterVersion: extraction.versions.domainAdapterVersion,
      templateSignature: review.templateSignature,
      trustBaselineID: review.trustBaselineID,
      reviewSnapshotHash: review.reviewSnapshotHash,
      reviewCandidateKeys: review.reviewCandidateKeys,
      trustEligible: review.trustEligible,
      parsedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      ok: true,
      fallbackUsed: extraction.strategy.startsWith("playwright:"),
      fallbackReason: extraction.strategy.startsWith("playwright:") ?
        fallbackReason :
        null,
      strategy: extraction.strategy,
      review,
      retainedEvidence: quality.status === "needsReview" ?
        buildRetainedExtractionEvidence({
          status: "needsReview",
          stage: "parsing",
          sourceURL: claim.sourceURL,
          html,
          strategy: extraction.strategy,
          qualityReasons: quality.reasons,
          templateSignature: review.templateSignature,
          candidateEvidence: extraction.candidateEvidence,
          expectedCountEvidence,
          programmaticGalleryEvidence,
          structureTokens: extractionStructureTokens(html),
          versions: extraction.versions,
        }) :
        null,
    };
  } catch (error) {
    if (isRetryableImportError(error)) {
      throw error;
    }
    const structureTokens = retainedHTML === null ?
      [] :
      extractionStructureTokens(retainedHTML);
    const failureVersions = retainedHTML === null ?
      CURRENT_EXTRACTION_VERSIONS :
      selectExtractionAdapters({
        html: retainedHTML,
        sourceURL: claim.sourceURL,
        kind: "season_images",
      }).versions;
    const templateSignature = createHash("sha256")
      .update(JSON.stringify({stage: "parsing", structureTokens}))
      .digest("hex")
      .slice(0, 32);
    return {
      ok: false,
      errorMessage: errorMessage(error),
      retainedEvidence: buildRetainedExtractionEvidence({
        status: "failed",
        stage: "parsing",
        sourceURL: claim.sourceURL,
        html: retainedHTML,
        strategy: "unknown",
        failureReasons: ["parse_failed"],
        qualityReasons: ["no_candidates"],
        templateSignature,
        structureTokens,
        versions: failureVersions,
      }),
    };
  }
}

async function retainExtractionEvidenceSafely(
  dependencies: ProcessorDependencies,
  jobRef: FirebaseFirestore.DocumentReference,
  claim: ClaimedJob,
  evidence: RetainedExtractionEvidence,
): Promise<void> {
  try {
    await retainExtractionEvidence(dependencies, jobRef, claim, evidence);
  } catch (error) {
    console.warn("[lookbook-import-worker] evidence retention failed", {
      brandID: claim.brandID,
      jobID: claim.jobID,
      error: errorMessage(error),
    });
    await jobRef.update({
      evidenceRetentionStatus: "failed",
      evidenceRetentionErrorMessage: "구조 evidence 저장에 실패했습니다.",
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
}

async function retainExtractionEvidence(
  dependencies: ProcessorDependencies,
  jobRef: FirebaseFirestore.DocumentReference,
  claim: ClaimedJob,
  evidence: RetainedExtractionEvidence,
): Promise<void> {
  const issue = extractionIssueIdentity(evidence);
  const evidenceID = extractionEvidenceID({
    brandID: claim.brandID,
    jobID: claim.jobID,
    dispatchGeneration: claim.dispatchGeneration,
    stage: evidence.stage,
    fingerprint: issue.fingerprint,
  });
  const storagePath = extractionEvidenceStoragePath(evidenceID);
  const evidenceRef = dependencies.firestore
    .collection("lookbookExtractionEvidence")
    .doc(evidenceID);
  const existingEvidence = await evidenceRef.get();
  if (existingEvidence.exists) {
    await jobRef.update({
      evidenceRetentionStatus: "stored",
      evidenceID,
      evidenceStoragePath: storagePath,
      evidenceExpiresAt: existingEvidence.data()?.expiresAt ?? null,
      issueFingerprint: issue.fingerprint,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return;
  }

  const nowDate = new Date();
  const expiresAtDate = evidenceExpiresAt(nowDate);
  const expiresAt = Timestamp.fromDate(expiresAtDate);
  const payload = Buffer.from(JSON.stringify({
    evidenceID,
    createdAt: nowDate.toISOString(),
    expiresAt: expiresAtDate.toISOString(),
    evidence,
  }));
  await dependencies.storage.bucket().file(storagePath).save(payload, {
    resumable: false,
    contentType: "application/json",
    metadata: {
      cacheControl: "private, no-store",
      metadata: {
        evidenceID,
        expiresAt: expiresAtDate.toISOString(),
      },
    },
  });

  const clusterRef = dependencies.firestore
    .collection("lookbookExtractionIssueClusters")
    .doc(issue.fingerprint);
  await dependencies.firestore.runTransaction(async (transaction) => {
    const [ledgerSnapshot, clusterSnapshot] = await Promise.all([
      transaction.get(evidenceRef),
      transaction.get(clusterRef),
    ]);
    if (ledgerSnapshot.exists) {
      return;
    }
    const cluster = clusterSnapshot.data() ?? {};
    const sourceHost = new URL(evidence.source.origin).hostname.toLowerCase();
    const clusterState = nextExtractionIssueClusterState({
      previous: cluster,
      sourceHost,
      evidenceID,
      extractorVersion: evidence.versions.extractorVersion,
    });
    const now = FieldValue.serverTimestamp();

    transaction.create(evidenceRef, {
      evidenceID,
      brandID: claim.brandID,
      jobID: claim.jobID,
      dispatchGeneration: claim.dispatchGeneration,
      status: evidence.status,
      stage: evidence.stage,
      issueFingerprint: issue.fingerprint,
      storagePath,
      expiresAt,
      createdAt: now,
      updatedAt: now,
    });
    transaction.set(clusterRef, {
      fingerprint: issue.fingerprint,
      stage: issue.stage,
      platform: issue.platform,
      parserStrategy: issue.strategy,
      failureReasons: issue.failureReasons,
      qualityReasons: issue.qualityReasons,
      templateSignature: issue.templateSignature,
      extractorMajorVersion: issue.extractorMajorVersion,
      occurrenceCount: clusterState.occurrenceCount,
      affectedDomains: clusterState.affectedDomains,
      affectedDomainCount: clusterState.affectedDomainCount,
      sampleEvidenceIDs: clusterState.sampleEvidenceIDs,
      status: clusterState.status,
      recurrenceCount: clusterState.recurrenceCount,
      firstSeenAt: cluster.firstSeenAt ?? now,
      lastSeenAt: now,
      updatedAt: now,
    }, {merge: true});
    transaction.update(jobRef, {
      evidenceRetentionStatus: "stored",
      evidenceID,
      evidenceStoragePath: storagePath,
      evidenceExpiresAt: expiresAt,
      issueFingerprint: issue.fingerprint,
      updatedAt: now,
    });
  });
}

async function pauseForReviewIfNeeded(
  db: Firestore,
  jobRef: FirebaseFirestore.DocumentReference,
  claim: ClaimedJob,
  review: ReviewGate,
): Promise<JobResult | null> {
  const baseline = await db
    .collection("lookbookExtractionTrustBaselines")
    .doc(review.trustBaselineID)
    .get();
  const trusted = baseline.exists && baseline.data()?.isActive === true;
  if (reviewDisposition({
    trusted,
    quality: review.quality,
    trustEligible: review.trustEligible,
  }) === "materialize") {
    await jobRef.update({
      trustBaselineMatched: true,
      resumeFrom: "materializing",
      updatedAt: FieldValue.serverTimestamp(),
    });
    return null;
  }

  const snapshot = await jobRef.get();
  const data = snapshot.data() as ImportJobData | undefined;
  const currentGeneration = integerField(data?.reviewGeneration, 0);
  const generation = data?.reviewStatus === "reanalyzing" ?
    currentGeneration :
    currentGeneration + 1;
  await jobRef.update({
    status: "awaitingReview",
    phase: "reviewing",
    reviewStatus: "pending",
    reviewGeneration: generation,
    reviewSnapshotHash: review.reviewSnapshotHash,
    reviewCandidateKeys: review.reviewCandidateKeys,
    reviewRequestedAt: FieldValue.serverTimestamp(),
    resumeFrom: "materializing",
    trustBaselineMatched: false,
    leaseOwner: null,
    leaseExpiresAt: null,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {
    brandID: claim.brandID,
    jobID: claim.jobID,
    processed: true,
    status: "awaitingReview",
    parseStatus: "succeeded",
    contentStatus: "pending",
    reason: review.quality.reasons.join(",") || "untrustedTemplateSignature",
  };
}

async function prepareSeasonRepairPreview(
  dependencies: ProcessorDependencies,
  jobRef: FirebaseFirestore.DocumentReference,
  claim: ClaimedJob,
): Promise<JobResult> {
  if (claim.repairTargetSeasonID === null || claim.repairGeneration <= 0) {
    return failJob(jobRef, claim, "시즌 보수 generation 정보가 없습니다.", {
      contentStatus: "failed",
      repairStatus: "failed",
    });
  }
  const [jobSnapshot, postSnapshot] = await Promise.all([
    jobRef.get(),
    seasonRefFor(
      dependencies.firestore,
      claim.brandID,
      claim.repairTargetSeasonID,
    ).collection("posts").get(),
  ]);
  const jobData = jobSnapshot.data() as ImportJobData | undefined;
  if (!jobSnapshot.exists || !jobData) {
    return failJob(jobRef, claim, "시즌 보수 job을 읽지 못했습니다.", {
      contentStatus: "failed",
      repairStatus: "failed",
    });
  }
  const candidateHashes = candidateContentHashMap(
    jobData.imageCandidateContentHashes,
  );
  const candidates: ReconcileCandidate[] = parsedImageCandidates(
    jobData.imageCandidates,
  ).map((candidate) => {
    const candidateKey = extractionCandidateKey(candidate.sourceURL);
    return {
      candidateKey,
      sourceURL: candidate.sourceURL,
      alt: candidate.alt,
      contentHash: candidateHashes.get(candidateKey) ?? null,
    };
  });
  const activePosts = postSnapshot.docs.filter((document) => {
    const data = document.data() as PostData;
    return data.deletionStatus === undefined ||
      data.deletionStatus === null ||
      data.deletionStatus === "active";
  });
  const orderedPosts = [...activePosts].sort((left, right) => {
    const leftData = left.data() as PostData;
    const rightData = right.data() as PostData;
    const leftIndex = optionalInteger(leftData.sourceSortIndex) ??
      optionalInteger(leftData.orderIndex);
    const rightIndex = optionalInteger(rightData.sourceSortIndex) ??
      optionalInteger(rightData.orderIndex);
    if (leftIndex !== null && rightIndex !== null) {
      return leftIndex - rightIndex;
    }
    return timestampMillis(rightData.createdAt) -
      timestampMillis(leftData.createdAt);
  });
  const existingPosts = await mapWithLimit(
    orderedPosts,
    4,
    async (document, index): Promise<ReconcileExistingPost | null> => {
      const data = document.data() as PostData;
      const media = firstMediaData(data.media);
      const sourceURL = optionalStringField(media?.remoteURL);
      if (sourceURL === null) {
        return null;
      }
      let contentHash = optionalStringField(media?.contentHash);
      if (contentHash === null) {
        try {
          const bytes = await fetchRemoteImageBytes(
            sourceURL,
            optionalStringField(media?.sourcePageURL) ?? claim.sourceURL,
          );
          contentHash = createHash("sha256").update(bytes).digest("hex");
        } catch {
          contentHash = null;
        }
      }
      return {
        postID: document.id,
        sourceURL,
        contentHash,
        sourceSortIndex: optionalInteger(data.sourceSortIndex) ??
          optionalInteger(data.orderIndex) ??
          index,
      };
    },
  );
  const preview = makeSeasonReconcilePreview({
    existingPosts: existingPosts.filter(
      (post): post is ReconcileExistingPost => post !== null,
    ),
    candidates,
  });
  const repairRef = jobRef.collection("repairs")
    .doc(String(claim.repairGeneration));
  const now = FieldValue.serverTimestamp();
  const disposition = seasonRepairPreviewDisposition(preview);
  const repairStatus = disposition === "noChanges" ?
    "noChanges" :
    "previewReady";
  await repairRef.set({
    brandID: claim.brandID,
    jobID: claim.jobID,
    seasonID: claim.repairTargetSeasonID,
    repairGeneration: claim.repairGeneration,
    repairSnapshotHash: preview.snapshotHash,
    status: repairStatus,
    keep: preview.keep,
    add: preview.add,
    reorder: preview.reorder,
    removeCandidates: preview.removeCandidates,
    orderedPostIDs: preview.orderedPostIDs,
    allPostIDs: preview.allPostIDs,
    resultingPostCount: preview.resultingPostCount,
    imageExtractorVersion: jobData.imageExtractorVersion ?? null,
    templateSignature: jobData.templateSignature ?? null,
    createdAt: now,
    updatedAt: now,
  });
  if (disposition === "noChanges") {
    await jobRef.update({
      status: "succeeded",
      phase: "completed",
      parseStatus: "succeeded",
      contentStatus: "succeeded",
      reviewStatus: null,
      repairStatus,
      repairSnapshotHash: preview.snapshotHash,
      repairKeepCount: preview.keep.length,
      repairAddCount: 0,
      repairReorderCount: 0,
      repairRemoveCandidateCount: 0,
      leaseOwner: null,
      leaseExpiresAt: null,
      completedAt: now,
      updatedAt: now,
    });
    return {
      brandID: claim.brandID,
      jobID: claim.jobID,
      processed: true,
      status: "succeeded",
      parseStatus: "succeeded",
      contentStatus: "succeeded",
      seasonID: claim.repairTargetSeasonID,
      reason: "repairNoChanges",
    };
  }
  await jobRef.update({
    status: "awaitingReview",
    phase: "reviewing",
    reviewStatus: "repairPreviewReady",
    repairStatus: "previewReady",
    repairSnapshotHash: preview.snapshotHash,
    repairKeepCount: preview.keep.length,
    repairAddCount: preview.add.length,
    repairReorderCount: preview.reorder.length,
    repairRemoveCandidateCount: preview.removeCandidates.length,
    leaseOwner: null,
    leaseExpiresAt: null,
    updatedAt: now,
  });
  return {
    brandID: claim.brandID,
    jobID: claim.jobID,
    processed: true,
    status: "awaitingReview",
    parseStatus: "succeeded",
    contentStatus: "pending",
    seasonID: claim.repairTargetSeasonID,
    reason: "repairPreviewReady",
  };
}

async function ensureMaterialized(
  db: Firestore,
  jobRef: FirebaseFirestore.DocumentReference,
  claim: ClaimedJob,
): Promise<
  | {ok: true; seasonID: string; postCount: number}
  | {ok: false; errorMessage: string}
> {
  const snapshot = await jobRef.get();
  const data = snapshot.data() as ImportJobData | undefined;
  const existingSeasonID = optionalStringField(data?.targetSeasonID);
  const existingPostIDs = stringArray(data?.createdPostIDs);
  if (existingSeasonID !== null && existingPostIDs.length > 0) {
    await jobRef.update({
      contentStatus: "succeeded",
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {ok: true, seasonID: existingSeasonID, postCount: existingPostIDs.length};
  }

  await jobRef.update({
    phase: "materializing",
    contentStatus: "running",
    contentErrorMessage: null,
    contentStartedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  try {
    if (!snapshot.exists || !data) {
      throw new Error("import job 문서를 읽지 못했습니다.");
    }
    const allCandidates = parsedImageCandidates(data.imageCandidates);
    const approvedKeys = new Set(stringArray(data.approvedCandidateKeys));
    const imageCandidates = approvedKeys.size === 0 ?
      allCandidates :
      allCandidates.filter((candidate) =>
        approvedKeys.has(extractionCandidateKey(candidate.sourceURL)));
    if (imageCandidates.length === 0) {
      throw new Error("이미지 후보가 없어 시즌을 만들 수 없습니다.");
    }

    const metadata = await seasonMetadata(
      db,
      claim.brandID,
      claim.sourceURL,
      claim.sourceCandidateID,
      data,
      imageCandidates,
    );
    const seasonID = deterministicSeasonID(claim.jobID);
    const seasonRef = db
      .collection("brands")
      .doc(claim.brandID)
      .collection("seasons")
      .doc(seasonID);
    const createdPostIDs = imageCandidates.map((_, index) => deterministicPostID(index));
    const assetTotalCount = imageCandidates.length + (metadata.coverRemoteURL !== null ? 1 : 0);
    const now = Date.now();
    const batch = db.batch();

    batch.set(seasonRef, {
      displayTitle: metadata.displayTitle,
      sourceTitle: metadata.sourceTitle,
      year: metadata.year,
      term: metadata.term,
      coverPath: null,
      coverRemoteURL: metadata.coverRemoteURL,
      description: "",
      tagIDs: [],
      tagConceptIDs: [],
      status: "published",
      assetSyncStatus: "pending",
      metadataStatus: metadata.metadataStatus,
      metadataConfidence: metadata.metadataConfidence,
      sourceURL: claim.sourceURL,
      sourceImportJobID: claim.jobID,
      sourceSortIndex: metadata.sourceSortIndex,
      postCount: imageCandidates.length,
      likeCount: 0,
      createdAt: Timestamp.fromMillis(now),
      updatedAt: Timestamp.fromMillis(now),
    }, {merge: true});

    imageCandidates.forEach((candidate, index) => {
      batch.set(seasonRef.collection("posts").doc(createdPostIDs[index]), {
        brandID: claim.brandID,
        seasonID,
        authorID: null,
        orderIndex: index,
        status: "published",
        assetSyncStatus: "pending",
        sourceImportJobID: claim.jobID,
        media: [{
          type: "image",
          remoteURL: candidate.sourceURL,
          thumbPath: null,
          detailPath: null,
          sourcePageURL: claim.sourceURL,
        }],
        caption: normalizedCaption(candidate.alt),
        tagIDs: [],
        metrics: {
          likeCount: 0,
          commentCount: 0,
          replacementCount: 0,
          saveCount: 0,
          viewCount: 0,
        },
        createdAt: Timestamp.fromMillis(now - index),
        updatedAt: Timestamp.fromMillis(now - index),
      }, {merge: true});
    });

    batch.update(jobRef, {
      contentStatus: "succeeded",
      assetSyncStatus: "pending",
      seasonTitle: metadata.displayTitle,
      sourceTitle: metadata.sourceTitle,
      coverRemoteURL: metadata.coverRemoteURL,
      sourceSortIndex: metadata.sourceSortIndex,
      normalizedYear: metadata.year,
      normalizedTerm: metadata.term,
      metadataStatus: metadata.metadataStatus,
      metadataConfidence: metadata.metadataConfidence,
      targetSeasonID: seasonID,
      createdPostIDs,
      createdPostCount: imageCandidates.length,
      assetTotalCount,
      assetCompletedCount: 0,
      assetFailedCount: 0,
      contentCreatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();

    return {ok: true, seasonID, postCount: imageCandidates.length};
  } catch (error) {
    return {ok: false, errorMessage: errorMessage(error)};
  }
}

async function syncAssets(
  dependencies: ProcessorDependencies,
  jobRef: FirebaseFirestore.DocumentReference,
  claim: ClaimedJob,
  seasonID: string,
  logContext: LogContext,
): Promise<{
  status: "ready" | "partial" | "failed";
  completedCount: number;
  failedCount: number;
  errorMessage?: string;
}> {
  await jobRef.update({
    phase: "syncingAssets",
    assetSyncStatus: "syncing",
    assetSyncErrorMessage: null,
    assetSyncStartedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  const jobSnapshot = await jobRef.get();
  const jobData = jobSnapshot.data() as ImportJobData | undefined;
  const declaredTotalCount = optionalInteger(jobData?.assetTotalCount);

  const targets = await assetSyncTargets(
    dependencies.firestore,
    claim.brandID,
    seasonID,
    claim.sourceURL,
    jobRef,
  );
  const seasonRef = seasonRefFor(
    dependencies.firestore,
    claim.brandID,
    seasonID,
  );
  if (targets.length === 0) {
    await seasonRef.set({
      assetSyncStatus: "ready",
      assetSyncErrorMessage: null,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {
      status: "ready",
      completedCount: declaredTotalCount ?? 0,
      failedCount: 0,
    };
  }

  const results = await runSyncTargets(dependencies, targets);
  const failedResults = results.filter((result) => !result.succeeded);
  failedResults.forEach((result) => {
    logAssetFailed(logContext, result);
  });
  await Promise.all(results.map((result) => updateAssetFailureAfterRetry(
    dependencies.firestore,
    result,
    claim.sourceImportJobID ?? claim.jobID,
  )));
  const failedCount = failedResults.length;
  const completedCount = declaredTotalCount === null ?
    results.filter((result) => result.succeeded || result.skipped).length :
    Math.max(0, declaredTotalCount - failedCount);
  const status = failedCount === 0 ? "ready" : (completedCount > 0 ? "partial" : "failed");
  const error = failedResults[0]?.errorMessage;

  await seasonRef.set({
    assetSyncStatus: status,
    assetSyncErrorMessage: error ?? null,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});

  await Promise.all(failedResults.map(async (result) => {
    if (result.target.kind !== "postImage") {
      return;
    }
    await postRefFor(
      dependencies.firestore,
      result.target.brandID,
      result.target.seasonID,
      result.target.postID,
    ).set({
      assetSyncStatus: "failed",
      assetSyncErrorMessage: result.errorMessage ?? "이미지 동기화 실패",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }));

  return {
    status,
    completedCount,
    failedCount,
    errorMessage: error,
  };
}

async function ensureAssetFailuresForSourceJob(
  db: Firestore,
  brandID: string,
  seasonID: string,
  sourceJobID: string,
  sourceURL: string,
  sourceJob: ImportJobData,
): Promise<void> {
  const existingSnapshot = await assetFailuresCollection(
    db,
    brandID,
    seasonID,
  ).get();
  const existingFailureIDs = new Set(existingSnapshot.docs.map((doc) => doc.id));
  const postIDs = stringArray(sourceJob.createdPostIDs);
  const postRefs = postIDs.map((postID) => postRefFor(db, brandID, seasonID, postID));
  const postSnapshots = postRefs.length > 0 ? await db.getAll(...postRefs) : [];
  const batch = db.batch();
  let writeCount = 0;

  for (const snapshot of postSnapshots) {
    if (!snapshot.exists) {
      continue;
    }
    const postData = snapshot.data() as PostData | undefined;
    const mediaItems = Array.isArray(postData?.media) ? postData.media : [];
    mediaItems.forEach((rawMedia, mediaIndex) => {
      if (!rawMedia || typeof rawMedia !== "object") {
        return;
      }
      const media = rawMedia as MediaData;
      const remoteURL = optionalStringField(media.remoteURL);
      if (remoteURL === null) {
        return;
      }
      if (
        optionalStringField(media.thumbPath) !== null &&
        optionalStringField(media.detailPath) !== null
      ) {
        return;
      }
      const failureID = assetFailureID(snapshot.id, mediaIndex, remoteURL);
      const payload: Record<string, unknown> = {
        brandID,
        seasonID,
        postID: snapshot.id,
        mediaIndex,
        remoteURL,
        sourcePageURL: optionalStringField(media.sourcePageURL) ?? sourceURL,
        sourceImportJobID: sourceJobID,
        kind: "postImage",
        status: "failed",
        lastErrorMessage: optionalStringField(postData?.assetSyncErrorMessage),
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (!existingFailureIDs.has(failureID)) {
        payload.attemptCount = 0;
        payload.createdAt = FieldValue.serverTimestamp();
      }
      batch.set(assetFailureRef(db, brandID, seasonID, failureID), payload, {
        merge: true,
      });
      writeCount += 1;
    });
  }

  if (writeCount > 0) {
    await batch.commit();
  }
}

async function assetFailureTargets(
  db: Firestore,
  brandID: string,
  seasonID: string,
  sourceJobID: string,
  fallbackSourceURL: string,
): Promise<SyncTarget[]> {
  const snapshot = await assetFailuresCollection(db, brandID, seasonID)
    .where("sourceImportJobID", "==", sourceJobID)
    .get();
  return snapshot.docs.flatMap((doc) => {
    const data = doc.data() as AssetFailureData;
    const postID = optionalDocumentID(data.postID, "postID");
    const mediaIndex = optionalInteger(data.mediaIndex);
    const remoteURL = optionalStringField(data.remoteURL);
    if (postID === null || mediaIndex === null || remoteURL === null) {
      return [];
    }
    return [{
      kind: "postImage" as const,
      brandID,
      seasonID,
      postID,
      mediaIndex,
      remoteURL,
      sourcePageURL: optionalStringField(data.sourcePageURL) ?? fallbackSourceURL,
    }];
  });
}

async function updateAssetFailureAfterRetry(
  db: Firestore,
  result: SyncTargetResult,
  sourceImportJobID: string,
): Promise<void> {
  if (result.target.kind !== "postImage") {
    return;
  }
  const target = result.target;
  const failureID = assetFailureID(
    target.postID,
    target.mediaIndex,
    target.remoteURL,
  );
  const failureRef = assetFailureRef(
    db,
    target.brandID,
    target.seasonID,
    failureID,
  );
  if (result.succeeded) {
    await failureRef.delete();
    return;
  }
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(failureRef);
    const payload: Record<string, unknown> = {
      brandID: target.brandID,
      seasonID: target.seasonID,
      postID: target.postID,
      mediaIndex: target.mediaIndex,
      remoteURL: target.remoteURL,
      sourcePageURL: target.sourcePageURL,
      sourceImportJobID,
      kind: "postImage",
      status: "failed",
      attemptCount: FieldValue.increment(1),
      lastErrorMessage: result.errorMessage ?? "이미지 동기화 실패",
      lastAttemptAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (!snapshot.exists) {
      payload.createdAt = FieldValue.serverTimestamp();
    }
    transaction.set(failureRef, payload, {merge: true});
  });
}

async function assetFailureCount(
  db: Firestore,
  brandID: string,
  seasonID: string,
): Promise<number> {
  const snapshot = await assetFailuresCollection(db, brandID, seasonID).get();
  return snapshot.size;
}

async function markAssetRetryCompleted(
  db: Firestore,
  brandID: string,
  seasonID: string,
  sourceJobID: string,
  totalCount: number | null,
  remainingFailureCount: number,
  assetStatus: "ready" | "partial",
  errorMessage: string | null,
): Promise<void> {
  const status = remainingFailureCount === 0 ? "succeeded" : "partialFailed";
  const retryStatus = remainingFailureCount === 0 ? "succeeded" : "failed";
  const completedCount = totalCount === null ?
    0 :
    Math.max(0, totalCount - remainingFailureCount);
  await Promise.all([
    importJobRef(db, {brandID, jobID: sourceJobID}).update({
      status,
      phase: "completed",
      assetSyncStatus: assetStatus,
      assetCompletedCount: completedCount,
      assetFailedCount: remainingFailureCount,
      errorMessage,
      assetSyncErrorMessage: errorMessage,
      assetRetryStatus: retryStatus,
      assetRetryCompletedAt: FieldValue.serverTimestamp(),
      assetRetryErrorMessage: errorMessage,
      updatedAt: FieldValue.serverTimestamp(),
    }),
    seasonRefFor(db, brandID, seasonID).set({
      assetSyncStatus: assetStatus,
      assetSyncErrorMessage: errorMessage,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true}),
  ]);
}

async function assetSyncTargets(
  db: Firestore,
  brandID: string,
  seasonID: string,
  sourceURL: string,
  jobRef: FirebaseFirestore.DocumentReference,
): Promise<SyncTarget[]> {
  const [jobSnapshot, seasonSnapshot] = await Promise.all([
    jobRef.get(),
    seasonRefFor(db, brandID, seasonID).get(),
  ]);
  const jobData = jobSnapshot.data() as ImportJobData | undefined;
  const seasonData = seasonSnapshot.data() as SeasonData | undefined;
  const postIDs = stringArray(jobData?.createdPostIDs);
  const postRefs = postIDs.map((postID) => postRefFor(db, brandID, seasonID, postID));
  const postSnapshots = postRefs.length > 0 ? await db.getAll(...postRefs) : [];
  const targets: SyncTarget[] = [];
  const seasonCoverRemoteURL = firstNonEmptyString([
    optionalStringField(seasonData?.coverRemoteURL),
    optionalStringField(jobData?.coverRemoteURL),
  ]);

  if (seasonCoverRemoteURL !== null) {
    targets.push({
      kind: "seasonCover",
      brandID,
      seasonID,
      remoteURL: seasonCoverRemoteURL,
      sourcePageURL: sourceURL,
    });
  }

  for (const snapshot of postSnapshots) {
    if (!snapshot.exists) {
      continue;
    }
    const postData = snapshot.data() as PostData | undefined;
    const media = firstMediaData(postData?.media);
    const remoteURL = optionalStringField(media?.remoteURL);
    if (remoteURL === null) {
      continue;
    }
    if (
      optionalStringField(media?.thumbPath) !== null &&
      optionalStringField(media?.detailPath) !== null
    ) {
      continue;
    }
    targets.push({
      kind: "postImage",
      brandID,
      seasonID,
      postID: snapshot.id,
      mediaIndex: 0,
      remoteURL,
      sourcePageURL: optionalStringField(media?.sourcePageURL) ?? sourceURL,
    });
  }

  return targets;
}

async function runSyncTargets(
  dependencies: ProcessorDependencies,
  targets: SyncTarget[],
): Promise<SyncTargetResult[]> {
  const results: SyncTargetResult[] = [];
  let cursor = 0;
  const workers = Array.from(
    {length: Math.min(dependencies.assetSyncConcurrency, targets.length)},
    async () => {
      for (;;) {
        const index = cursor;
        cursor += 1;
        const target = targets[index];
        if (!target) {
          return;
        }
        results[index] = await syncSingleTarget(dependencies, target);
      }
    },
  );
  await Promise.all(workers);
  return results;
}

async function syncSingleTarget(
  dependencies: ProcessorDependencies,
  target: SyncTarget,
): Promise<SyncTargetResult> {
  try {
    if (target.kind === "seasonCover") {
      const seasonSnapshot = await seasonRefFor(
        dependencies.firestore,
        target.brandID,
        target.seasonID,
      ).get();
      if (optionalStringField(seasonSnapshot.data()?.coverPath) !== null) {
        return {target, succeeded: true, skipped: true};
      }
    } else {
      const postSnapshot = await postRefFor(
        dependencies.firestore,
        target.brandID,
        target.seasonID,
        target.postID,
      ).get();
      const mediaItems = Array.isArray(postSnapshot.data()?.media) ?
        postSnapshot.data()?.media as unknown[] :
        [];
      const media = mediaItems[target.mediaIndex] as MediaData | undefined;
      if (
        optionalStringField(media?.thumbPath) !== null &&
        optionalStringField(media?.detailPath) !== null
      ) {
        return {target, succeeded: true, skipped: true};
      }
    }

    const originalBytes = await withImmediateRetry(() => fetchRemoteImageBytes(
      target.remoteURL,
      target.sourcePageURL,
    ));
    const thumbPolicy = target.kind === "seasonCover" ?
      SEASON_COVER_THUMB :
      POST_IMAGE_THUMB;
    const detailPolicy = target.kind === "seasonCover" ?
      SEASON_COVER_DETAIL :
      POST_IMAGE_DETAIL;
    const [thumbBytes, detailBytes] = await Promise.all([
      jpegBytes(originalBytes, thumbPolicy.maxPixel, thumbPolicy.quality),
      jpegBytes(originalBytes, detailPolicy.maxPixel, detailPolicy.quality),
    ]);

    if (target.kind === "seasonCover") {
      const detailPath = seasonCoverDetailPath(target.brandID, target.seasonID);
      await Promise.all([
        uploadJPEG(dependencies.storage, seasonCoverThumbPath(target.brandID, target.seasonID), thumbBytes),
        uploadJPEG(dependencies.storage, detailPath, detailBytes),
      ]);
      await seasonRefFor(dependencies.firestore, target.brandID, target.seasonID).set({
        coverPath: detailPath,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    } else {
      const thumbPath = postThumbPath(target.brandID, target.seasonID, target.postID);
      const detailPath = postDetailPath(target.brandID, target.seasonID, target.postID);
      await Promise.all([
        uploadJPEG(dependencies.storage, thumbPath, thumbBytes),
        uploadJPEG(dependencies.storage, detailPath, detailBytes),
      ]);
      await updatePostMediaPaths(
        dependencies.firestore,
        target.brandID,
        target.seasonID,
        target.postID,
        target.mediaIndex,
        thumbPath,
        detailPath,
      );
    }

    return {target, succeeded: true, skipped: false};
  } catch (error) {
    return {
      target,
      succeeded: false,
      skipped: false,
      errorMessage: errorMessage(error),
    };
  }
}

async function failJob(
  jobRef: FirebaseFirestore.DocumentReference,
  target: JobTarget,
  message: string,
  patch: Record<string, unknown>,
): Promise<JobResult> {
  await jobRef.update({
    status: "failed",
    phase: "completed",
    errorMessage: message,
    errorStage: errorStage(patch),
    failedAt: FieldValue.serverTimestamp(),
    completedAt: FieldValue.serverTimestamp(),
    leaseOwner: null,
    leaseExpiresAt: null,
    updatedAt: FieldValue.serverTimestamp(),
    ...patch,
  });
  return {
    ...target,
    processed: true,
    status: "failed",
    errorMessage: message,
    ...patch,
  };
}

async function releaseJobForTaskRetry(
  jobRef: FirebaseFirestore.DocumentReference,
  message: string,
): Promise<void> {
  await jobRef.update({
    status: "queued",
    errorMessage: message,
    errorCode: "retryableNetworkFailure",
    errorStage: "parsing",
    leaseOwner: null,
    leaseExpiresAt: null,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

function errorStage(patch: Record<string, unknown>): string {
  if (patch.parseStatus === "failed") {
    return "parsing";
  }
  if (patch.contentStatus === "failed") {
    return "materializing";
  }
  return "processing";
}

async function refreshLease(
  jobRef: FirebaseFirestore.DocumentReference,
  workerID: string,
): Promise<void> {
  const snapshot = await jobRef.get();
  if (snapshot.data()?.leaseOwner !== workerID) {
    return;
  }
  await jobRef.update({
    leaseExpiresAt: Timestamp.fromMillis(Date.now() + LEASE_DURATION_MS),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

async function fetchHTML(url: string): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_HTML_TIMEOUT_MS);
  try {
    const response = await fetchPublicHTTP(url, {
      signal: controller.signal,
      headers: {
        "user-agent": "OutPickLookbookImporter/0.1 (+https://outpick.app)",
        "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      },
    });
    if (!response.ok) {
      throw retryableStatusError(
        response.status,
        `시즌 URL 응답 실패: HTTP ${response.status}`,
      );
    }
    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.toLowerCase().includes("text/html")) {
      throw new Error(`HTML 응답이 아닙니다: ${contentType || "unknown"}`);
    }
    const bytes = await responseBytes(response, HTML_MAX_BYTES, "HTML 응답");
    return bytes.toString("utf8");
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new RetryableImportError("시즌 URL 요청 시간이 초과되었습니다.", {
        cause: error,
      });
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

export function extractImageCandidates(
  html: string,
  baseURL: string,
): ImageExtractionResult {
  const adapterSelection = selectExtractionAdapters({
    html,
    sourceURL: baseURL,
    kind: "season_images",
  });
  const rules = adapterSelection.imageRules;
  const rawCandidates = collectImageCandidates(
    html,
    baseURL,
    false,
    true,
    rules,
  );
  const sections = contentSections(
    html,
    [...rules.contentSectionRules, ...GENERIC_CONTENT_SECTION_RULES],
  )
    .map((section) => {
      const candidates = collectImageCandidates(
        section.html,
        baseURL,
        true,
        false,
        rules,
      );
      return {
        candidates,
        label: section.label,
        score: section.weight + candidates.length * 10,
      };
    })
    .filter((section) => section.candidates.length > 0)
    .sort((lhs, rhs) => rhs.score - lhs.score);
  const bestSection = sections[0];
  if (
    bestSection &&
    (bestSection.score >= MIN_STRONG_SECTION_WEIGHT || bestSection.candidates.length >= 2)
  ) {
    return extractionResult({
      candidates: bestSection.candidates,
      strategy: bestSection.label,
      rawCandidateCount: rawCandidates.length,
      sourceURL: baseURL,
      candidateKey: (candidate) => extractionCandidateKey(candidate.sourceURL),
      versions: adapterSelection.versions,
    });
  }
  const filteredCandidates = collectImageCandidates(
    html,
    baseURL,
    true,
    false,
    rules,
  );
  return extractionResult({
    candidates: filteredCandidates.length > 0 ? filteredCandidates : rawCandidates,
    strategy: filteredCandidates.length > 0 ? "filteredPageImages" : "allPageImages",
    rawCandidateCount: rawCandidates.length,
    sourceURL: baseURL,
    candidateKey: (candidate) => extractionCandidateKey(candidate.sourceURL),
    versions: adapterSelection.versions,
  });
}

export function fallbackReasonForExtraction(
  extraction: Pick<
    ImageExtractionResult,
    "candidates" | "strategy" | "rawCandidateCount"
  >,
  html: string,
  programmaticGalleryEvidence = detectProgrammaticGallery(html),
): string | null {
  const candidateCount = extraction.candidates.length;
  if (candidateCount === 0) {
    return "noStaticCandidates";
  }
  if (programmaticGalleryEvidence.detected) {
    return "programmaticGallerySignals";
  }
  if (candidateCount === 1 && LOW_CONFIDENCE_STRATEGIES.has(extraction.strategy)) {
    return "singleLowConfidenceCandidate";
  }
  const dynamicSignalCount = dynamicRenderingSignalCount(html);
  if (
    dynamicSignalCount > 0 &&
    candidateCount < MIN_DYNAMIC_PARTIAL_CANDIDATES &&
    LOW_CONFIDENCE_STRATEGIES.has(extraction.strategy)
  ) {
    return "partialCandidatesWithDynamicSignals";
  }
  if (
    extraction.rawCandidateCount >= MIN_RAW_CANDIDATES_FOR_DROP_CHECK &&
    candidateCount <= Math.max(1, Math.floor(extraction.rawCandidateCount / 3)) &&
    LOW_CONFIDENCE_STRATEGIES.has(extraction.strategy)
  ) {
    return "rawCandidateDropWithLowConfidenceStrategy";
  }
  return null;
}

async function extractionWithPlaywrightFallback(
  sourceURL: string,
  staticExtraction: ImageExtractionResult,
  fallbackReason: string,
): Promise<Pick<
  EvaluatedImageExtraction,
  "extraction" | "renderedCandidateCount"
>> {
  console.log("[lookbook-import-worker] playwright fallback start", {
    source: extractionSourceEvidence(sourceURL),
    fallbackReason,
    staticStrategy: staticExtraction.strategy,
    staticCandidateCount: staticExtraction.candidates.length,
    staticRawCandidateCount: staticExtraction.rawCandidateCount,
  });
  const startedAt = Date.now();
  try {
    const renderedHTML = await renderHTMLWithPlaywright(sourceURL);
    const renderedExtraction = extractImageCandidates(renderedHTML, sourceURL);
    console.log("[lookbook-import-worker] playwright fallback completed", {
      source: extractionSourceEvidence(sourceURL),
      fallbackReason,
      elapsedMs: Date.now() - startedAt,
      renderedStrategy: renderedExtraction.strategy,
      renderedCandidateCount: renderedExtraction.candidates.length,
      renderedRawCandidateCount: renderedExtraction.rawCandidateCount,
    });
    if (renderedExtraction.candidates.length > staticExtraction.candidates.length) {
      const renderedResult = extractionResultWithStrategy(
        renderedExtraction,
        `playwright:${renderedExtraction.strategy}`,
        "rendered_dom",
      );
      return {
        extraction: mergeExtractionResults({
          results: [staticExtraction, renderedResult],
          strategy: `${renderedResult.strategy}+staticMerge`,
          candidateKey: (candidate) =>
            canonicalCandidateURL(candidate.sourceURL),
        }),
        renderedCandidateCount: renderedExtraction.candidates.length,
      };
    }
    return {
      extraction: extractionResultWithStrategy(
        staticExtraction,
        `static:${staticExtraction.strategy}`,
        "static_dom",
      ),
      renderedCandidateCount: renderedExtraction.candidates.length,
    };
  } catch (error) {
    console.warn("[lookbook-import-worker] playwright fallback failed", {
      source: extractionSourceEvidence(sourceURL),
      fallbackReason,
      elapsedMs: Date.now() - startedAt,
      errorMessage: errorMessage(error),
    });
    if (staticExtraction.candidates.length > 0) {
      return {
        extraction: extractionResultWithStrategy(
          staticExtraction,
          `static:${staticExtraction.strategy}`,
          "static_dom",
        ),
        renderedCandidateCount: null,
      };
    }
    throw error;
  }
}

async function renderHTMLWithPlaywright(sourceURL: string): Promise<string> {
  await assertPublicHTTPURL(sourceURL);
  const {chromium} = await import("playwright");
  const browser = await chromium.launch({headless: true});
  try {
    const context = await browser.newContext({
      viewport: {width: 1440, height: 1800},
      userAgent:
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/124.0.0.0 Safari/537.36",
    });
    try {
      await context.route("**/*", async (route) => {
        const requestURL = route.request().url();
        try {
          await assertPublicHTTPURL(requestURL);
          await route.continue();
        } catch {
          await route.abort("blockedbyclient");
        }
      });
      const page = await context.newPage();
      await page.goto(sourceURL, {
        waitUntil: "domcontentloaded",
        timeout: PLAYWRIGHT_NAVIGATION_TIMEOUT_MS,
      });
      await page.waitForTimeout(PLAYWRIGHT_RENDER_SETTLE_MS);
      await page.waitForLoadState("networkidle", {timeout: 3_000}).catch(() => {
        // 계속 열린 연결이 있어도 DOM 추출은 진행한다.
      });
      return await page.content();
    } finally {
      await context.close();
    }
  } finally {
    await browser.close();
  }
}

function dynamicRenderingSignalCount(html: string): number {
  return DYNAMIC_RENDERING_SIGNAL_PATTERNS.reduce((count, pattern) => {
    const flags = pattern.flags.includes("g") ? pattern.flags : `${pattern.flags}g`;
    return count + Array.from(html.matchAll(new RegExp(pattern.source, flags))).length;
  }, 0);
}

function collectImageCandidates(
  html: string,
  baseURL: string,
  applyNoiseFilter: boolean,
  includeMetaImages: boolean,
  adapterRules: ImageExtractionRules,
): ImageCandidate[] {
  const candidates: ImageCandidate[] = [];
  const seen = new Set<string>();
  for (const match of html.matchAll(/<img\b[^>]*>/gi)) {
    const tag = match[0];
    appendURLs(
      candidates,
      seen,
      imageURLValues(tag),
      baseURL,
      attributeValue(tag, "alt"),
      tagContext(html, match.index ?? 0),
      applyNoiseFilter,
      adapterRules,
    );
  }
  for (const match of html.matchAll(/<source\b[^>]*>/gi)) {
    const tag = match[0];
    appendURLs(
      candidates,
      seen,
      [
        ...srcsetURLs(attributeValue(tag, "srcset")),
        ...srcsetURLs(attributeValue(tag, "data-srcset")),
      ],
      baseURL,
      null,
      tagContext(html, match.index ?? 0),
      applyNoiseFilter,
      adapterRules,
    );
  }
  if (!includeMetaImages) {
    return candidates;
  }
  for (const match of html.matchAll(/<meta\b[^>]*>/gi)) {
    const tag = match[0];
    const property = attributeValue(tag, "property") ?? attributeValue(tag, "name");
    if (property?.toLowerCase() !== "og:image") {
      continue;
    }
    appendURLs(
      candidates,
      seen,
      [attributeValue(tag, "content")],
      baseURL,
      null,
      tag,
      applyNoiseFilter,
      adapterRules,
    );
  }
  return candidates;
}

function contentSections(
  html: string,
  rules: ContentSectionRule[],
): Array<{
  html: string;
  index: number;
  label: string;
  weight: number;
}> {
  const sections: Array<{
    html: string;
    index: number;
    label: string;
    weight: number;
  }> = [];
  for (const match of html.matchAll(/<(main|article|section|div)\b[^>]*>/gi)) {
    const rule = rules.find((item) => item.pattern.test(match[0]));
    if (!rule) {
      continue;
    }
    const sectionHTML = sliceElementHTML(html, match.index ?? 0, match[1]);
    if (!sectionHTML || Array.from(sectionHTML.matchAll(/<img\b[^>]*>/gi)).length === 0) {
      continue;
    }
    sections.push({
      html: sectionHTML,
      index: match.index ?? 0,
      label: rule.label,
      weight: rule.weight,
    });
  }
  return sections.sort((lhs, rhs) => lhs.index - rhs.index);
}

function sliceElementHTML(html: string, startIndex: number, tagName: string): string {
  const tokenPattern = new RegExp(`<\\/?${tagName}\\b[^>]*>`, "gi");
  tokenPattern.lastIndex = startIndex;
  let depth = 0;
  for (;;) {
    const match = tokenPattern.exec(html);
    if (!match) {
      return html.slice(startIndex);
    }
    if (match[0].startsWith("</")) {
      depth -= 1;
    } else if (!match[0].endsWith("/>")) {
      depth += 1;
    }
    if (depth === 0) {
      return html.slice(startIndex, match.index + match[0].length);
    }
  }
}

function imageURLValues(tag: string): Array<string | null> {
  return [
    attributeValue(tag, "ec-data-src"),
    attributeValue(tag, "data-src"),
    attributeValue(tag, "data-original"),
    attributeValue(tag, "data-original-src"),
    attributeValue(tag, "data-lazy-src"),
    attributeValue(tag, "data-zoom-image"),
    attributeValue(tag, "src"),
    ...srcsetURLs(attributeValue(tag, "srcset")),
    ...srcsetURLs(attributeValue(tag, "data-srcset")),
  ];
}

function appendURLs(
  candidates: ImageCandidate[],
  seen: Set<string>,
  rawValues: Array<string | null>,
  baseURL: string,
  alt: string | null,
  context: string,
  applyNoiseFilter: boolean,
  adapterRules: ImageExtractionRules,
): void {
  for (const rawValue of rawValues) {
    const normalizedURL = normalizedImageURL(rawValue, baseURL);
    if (
      !normalizedURL ||
      seen.has(normalizedURL) ||
      isHardNoiseImage(normalizedURL, adapterRules) ||
      (
        applyNoiseFilter &&
        isLikelyNoiseImage(normalizedURL, context, adapterRules)
      )
    ) {
      continue;
    }
    seen.add(normalizedURL);
    candidates.push({sourceURL: normalizedURL, alt});
  }
}

function attributeValue(tag: string, attributeName: string): string | null {
  const pattern = new RegExp(
    `${attributeName}\\s*=\\s*("([^"]*)"|'([^']*)'|([^\\s>]+))`,
    "i",
  );
  const match = tag.match(pattern);
  return match?.[2] ?? match?.[3] ?? match?.[4] ?? null;
}

function srcsetURLs(srcset: string | null): string[] {
  if (!srcset) {
    return [];
  }
  return srcset
    .split(",")
    .map((candidate) => candidate.trim().split(/\s+/)[0])
    .filter((candidate) => candidate.length > 0);
}

function tagContext(html: string, index: number): string {
  return html.slice(Math.max(0, index - 500), Math.min(html.length, index + 500));
}

function normalizedImageURL(rawValue: string | null, baseURL: string): string | null {
  if (!rawValue) {
    return null;
  }
  const trimmed = rawValue.trim();
  if (!trimmed || trimmed.startsWith("data:")) {
    return null;
  }
  const decoded = htmlDecode(decodeURIComponentSafe(trimmed));
  if (isTemplateImageValue(decoded)) {
    return null;
  }
  try {
    const url = new URL(trimmed, baseURL);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return null;
    }
    if (isTemplateImageValue(htmlDecode(decodeURIComponentSafe(url.toString())))) {
      return null;
    }
    return url.toString();
  } catch {
    return null;
  }
}

function isTemplateImageValue(value: string): boolean {
  return (
    /{{|}}|\$\{?image|image_url|image_medium|image_small|\+\s*src\s*\+/i.test(value) ||
    /\$\([^)]*\)\.attr\((?:'|")src(?:'|")\)/i.test(value) ||
    /(?:'\s*\+|"\s*\+|\+\s*'|\+\s*")/.test(value)
  );
}

function decodeURIComponentSafe(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function htmlDecode(value: string): string {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&#039;|&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

function isLikelyNoiseImage(
  imageURL: string,
  context: string,
  adapterRules: ImageExtractionRules,
): boolean {
  return [
    ...NOISE_IMAGE_URL_PATTERNS,
    ...adapterRules.noiseImageURLPatterns,
  ].some((pattern) => pattern.test(imageURL)) ||
    NOISE_CONTEXT_PATTERN.test(context);
}

function isHardNoiseImage(
  imageURL: string,
  adapterRules: ImageExtractionRules,
): boolean {
  return [
    ...HARD_NOISE_IMAGE_URL_PATTERNS,
    ...adapterRules.hardNoiseImageURLPatterns,
  ].some((pattern) => pattern.test(imageURL));
}

async function seasonMetadata(
  db: Firestore,
  brandID: string,
  sourceURL: string,
  sourceCandidateID: string | null,
  jobData: ImportJobData,
  imageCandidates: ImageCandidate[],
): Promise<{
  displayTitle: string;
  sourceTitle: string;
  year: number | null;
  term: "ss" | "fw" | null;
  metadataStatus: "unresolved" | "inferred" | "confirmed";
  metadataConfidence: number | null;
  coverRemoteURL: string | null;
  sourceSortIndex: number | null;
}> {
  const candidateData = sourceCandidateID === null ?
    null :
    await loadSeasonCandidate(db, brandID, sourceCandidateID);
  const rawTitle = firstNonEmptyString([
    optionalStringField(jobData.sourceTitle),
    optionalStringField((jobData as Record<string, unknown>).seasonTitle),
    optionalStringField(candidateData?.title),
    derivedTitleFromURL(sourceURL),
  ]) ?? "시즌";
  const normalized = normalizedSeasonMetadata(rawTitle);
  return {
    displayTitle: rawTitle,
    sourceTitle: rawTitle,
    year: normalized.year,
    term: normalized.term,
    metadataStatus: normalized.metadataStatus,
    metadataConfidence: normalized.metadataConfidence,
    coverRemoteURL: firstNonEmptyString([
      optionalStringField(jobData.coverRemoteURL),
      optionalStringField(candidateData?.coverImageURL),
      imageCandidates[0]?.sourceURL ?? null,
    ]),
    sourceSortIndex:
      optionalInteger(jobData.sourceSortIndex) ??
      optionalInteger(candidateData?.sortIndex),
  };
}

async function loadSeasonCandidate(
  db: Firestore,
  brandID: string,
  candidateID: string,
): Promise<SeasonCandidateData | null> {
  const snapshot = await db
    .collection("brands")
    .doc(brandID)
    .collection("seasonCandidates")
    .doc(candidateID)
    .get();
  return snapshot.exists ? snapshot.data() as SeasonCandidateData : null;
}

function normalizedSeasonMetadata(title: string): {
  year: number | null;
  term: "ss" | "fw" | null;
  metadataStatus: "unresolved" | "inferred" | "confirmed";
  metadataConfidence: number | null;
} {
  const value = title.normalize("NFKC").trim().toLowerCase();
  const term = inferSeasonTerm(value);
  const year = inferSeasonYear(value);
  if (year !== null && term !== null) {
    return {year, term, metadataStatus: "inferred", metadataConfidence: 0.92};
  }
  if (year !== null || term !== null) {
    return {year, term, metadataStatus: "inferred", metadataConfidence: 0.55};
  }
  return {year: null, term: null, metadataStatus: "unresolved", metadataConfidence: null};
}

function inferSeasonTerm(value: string): "ss" | "fw" | null {
  if (
    /\bs\/s\b/.test(value) ||
    /\bss\b/.test(value) ||
    /spring\s*[-/ ]\s*summer/.test(value) ||
    /spring\s+summer/.test(value)
  ) {
    return "ss";
  }
  if (
    /\bf\/w\b/.test(value) ||
    /\bfw\b/.test(value) ||
    /\ba\/w\b/.test(value) ||
    /\baw\b/.test(value) ||
    /fall\s*[-/ ]\s*winter/.test(value) ||
    /autumn\s*[-/ ]\s*winter/.test(value) ||
    /fall\s+winter/.test(value) ||
    /autumn\s+winter/.test(value)
  ) {
    return "fw";
  }
  return null;
}

function inferSeasonYear(value: string): number | null {
  const fourDigit = value.match(/\b(20\d{2})\b/);
  if (fourDigit) {
    return Number(fourDigit[1]);
  }
  const twoDigit = value.match(
    /\b(\d{2})\b(?=\s*(?:ss|fw|s\/s|f\/w|aw|a\/w|spring|summer|fall|winter))/,
  );
  if (!twoDigit) {
    return null;
  }
  const year = Number(twoDigit[1]);
  if (Number.isNaN(year)) {
    return null;
  }
  return year >= 70 ? 1900 + year : 2000 + year;
}

function derivedTitleFromURL(sourceURL: string): string {
  try {
    const url = new URL(sourceURL);
    const fileName = url.pathname.split("/").filter(Boolean).pop() ?? "";
    const title = fileName
      .replace(/\.(html?|php)$/i, "")
      .replace(/[-_]+/g, " ")
      .trim();
    return title.length > 0 ? title : "시즌";
  } catch {
    return "시즌";
  }
}

async function fetchRemoteImageBytes(
  remoteURL: string,
  sourcePageURL: string,
): Promise<Buffer> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_IMAGE_TIMEOUT_MS);
  try {
    const response = await fetchPublicHTTP(remoteURL, {
      signal: controller.signal,
      headers: {
        "user-agent": "OutPickLookbookImporter/0.1 (+https://outpick.app)",
        "accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
        "referer": sourcePageURL,
      },
    });
    if (!response.ok) {
      throw retryableStatusError(
        response.status,
        `이미지 응답 실패: HTTP ${response.status}`,
      );
    }
    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.toLowerCase().startsWith("image/")) {
      throw new Error(`이미지 응답이 아닙니다: ${contentType || "unknown"}`);
    }
    const bytes = await responseBytes(
      response,
      REMOTE_IMAGE_MAX_BYTES,
      "이미지",
    );
    if (bytes.length === 0) {
      throw new Error("이미지 바이트가 비어 있습니다.");
    }
    return bytes;
  } finally {
    clearTimeout(timeout);
  }
}

async function jpegBytes(input: Buffer, maxPixel: number, quality: number): Promise<Buffer> {
  return sharp(input, {failOn: "none"})
    .rotate()
    .resize({
      width: maxPixel,
      height: maxPixel,
      fit: "inside",
      withoutEnlargement: true,
    })
    .jpeg({quality, mozjpeg: true})
    .toBuffer();
}

async function uploadJPEG(storage: Storage, path: string, bytes: Buffer): Promise<void> {
  await storage.bucket().file(path).save(bytes, {
    resumable: false,
    metadata: {
      contentType: "image/jpeg",
      cacheControl: "public,max-age=3600",
    },
  });
}

async function updatePostMediaPaths(
  db: Firestore,
  brandID: string,
  seasonID: string,
  postID: string,
  mediaIndex: number,
  thumbPath: string,
  detailPath: string,
): Promise<void> {
  const postRef = postRefFor(db, brandID, seasonID, postID);
  const snapshot = await postRef.get();
  const postData = snapshot.data() as PostData | undefined;
  const mediaItems = Array.isArray(postData?.media) ? [...postData.media] : [];
  const media = mediaItems[mediaIndex];
  if (!media || typeof media !== "object") {
    throw new Error("포스트 미디어 정보가 없습니다.");
  }
  mediaItems[mediaIndex] = {...media, thumbPath, detailPath};
  await postRef.set({
    media: mediaItems,
    assetSyncStatus: "ready",
    assetSyncErrorMessage: null,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function withImmediateRetry<T>(operation: () => Promise<T>): Promise<T> {
  let lastError: unknown = null;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      if (attempt < 2) {
        await new Promise((resolve) => setTimeout(resolve, 400 * (attempt + 1)));
      }
    }
  }
  throw lastError;
}

function importJobRef(db: Firestore, target: JobTarget): FirebaseFirestore.DocumentReference {
  return db
    .collection("brands")
    .doc(target.brandID)
    .collection("importJobs")
    .doc(target.jobID);
}

function seasonRefFor(
  db: Firestore,
  brandID: string,
  seasonID: string,
): FirebaseFirestore.DocumentReference {
  return db
    .collection("brands")
    .doc(brandID)
    .collection("seasons")
    .doc(seasonID);
}

function postRefFor(
  db: Firestore,
  brandID: string,
  seasonID: string,
  postID: string,
): FirebaseFirestore.DocumentReference {
  return seasonRefFor(db, brandID, seasonID).collection("posts").doc(postID);
}

function assetFailuresCollection(
  db: Firestore,
  brandID: string,
  seasonID: string,
): FirebaseFirestore.CollectionReference {
  return seasonRefFor(db, brandID, seasonID).collection("assetFailures");
}

function assetFailureRef(
  db: Firestore,
  brandID: string,
  seasonID: string,
  failureID: string,
): FirebaseFirestore.DocumentReference {
  return assetFailuresCollection(db, brandID, seasonID).doc(failureID);
}

function assetFailureID(
  postID: string,
  mediaIndex: number,
  remoteURL: string,
): string {
  const hash = createHash("sha256")
    .update(remoteURL)
    .digest("hex")
    .slice(0, 24);
  return `${postID}_${mediaIndex}_${hash}`;
}

function seasonCoverThumbPath(brandID: string, seasonID: string): string {
  return `brands/${brandID}/seasons/${seasonID}/cover_thumb.jpg`;
}

function seasonCoverDetailPath(brandID: string, seasonID: string): string {
  return `brands/${brandID}/seasons/${seasonID}/cover.jpg`;
}

function postThumbPath(brandID: string, seasonID: string, postID: string): string {
  return `brands/${brandID}/seasons/${seasonID}/posts/${postID}/thumb.jpg`;
}

function postDetailPath(brandID: string, seasonID: string, postID: string): string {
  return `brands/${brandID}/seasons/${seasonID}/posts/${postID}/detail.jpg`;
}

function deterministicSeasonID(jobID: string): string {
  return `import_${jobID}`;
}

function deterministicPostID(index: number): string {
  return `post_${String(index).padStart(4, "0")}`;
}

function normalizedCaption(value: string | null): string | null {
  const trimmed = value?.trim() ?? "";
  return trimmed.length > 0 ? trimmed : null;
}

function firstMediaData(value: unknown): MediaData | null {
  if (!Array.isArray(value) || value.length === 0) {
    return null;
  }
  const first = value[0];
  if (first === null || typeof first !== "object" || Array.isArray(first)) {
    return null;
  }
  return first as MediaData;
}

function parsedImageCandidates(value: unknown): ImageCandidate[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((item) => {
      if (item === null || typeof item !== "object" || Array.isArray(item)) {
        return null;
      }
      const sourceURL = optionalStringField((item as Record<string, unknown>).sourceURL);
      if (sourceURL === null) {
        return null;
      }
      return {
        sourceURL,
        alt: optionalStringField((item as Record<string, unknown>).alt),
      };
    })
    .filter((item): item is ImageCandidate => item !== null);
}

function parsedReviewGate(data: ImportJobData | undefined): ReviewGate | null {
  const templateSignature = optionalStringField(data?.templateSignature);
  const trustBaselineID = optionalStringField(data?.trustBaselineID);
  const reviewSnapshotHash = optionalStringField(data?.reviewSnapshotHash);
  const reviewCandidateKeys = stringArray(data?.reviewCandidateKeys);
  const status = data?.extractionQualityStatus;
  const reasons = stringArray(data?.extractionQualityReasons);
  if (
    templateSignature === null ||
    trustBaselineID === null ||
    reviewSnapshotHash === null ||
    reviewCandidateKeys.length === 0 ||
    (status !== "accepted" && status !== "needsReview" && status !== "failed")
  ) {
    return null;
  }
  return {
    templateSignature,
    trustBaselineID,
    reviewSnapshotHash,
    reviewCandidateKeys,
    trustEligible: data?.trustEligible === true,
    quality: {
      status,
      reasons: reasons as ExtractionQuality["reasons"],
    },
  };
}

function parseBatchSize(value: unknown): number {
  if (value === undefined) {
    return DEFAULT_BATCH_SIZE;
  }
  if (!Number.isInteger(value)) {
    throw new Error("batchSize 값이 올바르지 않습니다.");
  }
  return Math.max(1, Math.min(MAX_BATCH_SIZE, Number(value)));
}

function optionalDocumentID(value: unknown, fieldName: string): string | null {
  if (value === undefined || value === null) {
    return null;
  }
  return documentID(stringField(value, fieldName), fieldName);
}

function requiredDocumentID(value: unknown, fieldName: string): string {
  return documentID(stringField(value, fieldName), fieldName);
}

function optionalDocumentIDList(value: unknown, fieldName: string): string[] {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw new Error(`${fieldName} 값이 올바르지 않습니다.`);
  }
  return Array.from(new Set(value.map((item) => {
    return documentID(stringField(item, fieldName), fieldName);
  })));
}

function documentID(value: string, fieldName: string): string {
  if (value.includes("/") || value.length > 128) {
    throw new Error(`${fieldName} 값이 올바르지 않습니다.`);
  }
  return value;
}

function stringField(value: unknown, fieldName: string): string {
  if (typeof value !== "string") {
    throw new Error(`${fieldName} 값이 필요합니다.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    throw new Error(`${fieldName} 값이 비어 있습니다.`);
  }
  return trimmed;
}

function optionalStringField(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function stringValue(value: unknown, fallback: string): string {
  return optionalStringField(value) ?? fallback;
}

function optionalInteger(value: unknown): number | null {
  if (!Number.isInteger(value)) {
    return null;
  }
  return Number(value);
}

function positiveInteger(value: unknown, fieldName: string): number {
  if (!Number.isInteger(value) || Number(value) < 1) {
    throw new Error(`${fieldName} 값이 올바르지 않습니다.`);
  }
  return Number(value);
}

function nonNegativeInteger(value: unknown, fieldName: string): number {
  if (!Number.isInteger(value) || Number(value) < 0) {
    throw new Error(`${fieldName} 값이 올바르지 않습니다.`);
  }
  return Number(value);
}

function optionalNonNegativeInteger(
  value: unknown,
  fieldName: string,
): number | null {
  if (value === undefined || value === null) {
    return null;
  }
  return nonNegativeInteger(value, fieldName);
}

function integerField(value: unknown, fallback: number): number {
  return Number.isInteger(value) ? Number(value) : fallback;
}

function firstNonEmptyString(values: Array<string | null>): string | null {
  return values.find((value) => {
    return typeof value === "string" && value.trim().length > 0;
  }) ?? null;
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .filter((item) => typeof item === "string")
    .map((item) => item.trim())
    .filter((item) => item.length > 0) as string[];
}

function candidateContentHashMap(value: unknown): Map<string, string> {
  const result = new Map<string, string>();
  if (!Array.isArray(value)) {
    return result;
  }
  value.forEach((item) => {
    if (item === null || typeof item !== "object" || Array.isArray(item)) {
      return;
    }
    const record = item as Record<string, unknown>;
    const candidateKey = optionalStringField(record.candidateKey);
    const contentHash = optionalStringField(record.contentHash);
    if (
      candidateKey !== null &&
      contentHash !== null &&
      /^[a-f0-9]{64}$/.test(contentHash)
    ) {
      result.set(candidateKey, contentHash);
    }
  });
  return result;
}

async function mapWithLimit<Input, Output>(
  values: Input[],
  concurrency: number,
  work: (value: Input, index: number) => Promise<Output>,
): Promise<Output[]> {
  const results: Output[] = [];
  let cursor = 0;
  const workers = Array.from(
    {length: Math.min(Math.max(1, concurrency), values.length)},
    async () => {
      for (;;) {
        const index = cursor;
        cursor += 1;
        const value = values[index];
        if (value === undefined) {
          return;
        }
        results[index] = await work(value, index);
      }
    },
  );
  await Promise.all(workers);
  return results;
}

function timestampMillis(value: unknown): number {
  if (
    value &&
    typeof value === "object" &&
    "toMillis" in value &&
    typeof value.toMillis === "function"
  ) {
    return value.toMillis();
  }
  return 0;
}

function createdAtMillis(data: ImportJobData): number {
  const millis = timestampMillis(data.createdAt);
  return millis > 0 ? millis : Number.MAX_SAFE_INTEGER;
}

function canScanJob(data: ImportJobData): boolean {
  return (
    data.jobType === "importSeasonFromURL" ||
    data.jobType === "retrySeasonAssets"
  ) && isClaimable(data);
}

function errorMessage(error: unknown): string {
  if (error instanceof Error && error.message.trim().length > 0) {
    return error.message;
  }
  return String(error);
}

function elapsedMs(startedAt: number): number {
  return Math.max(0, Date.now() - startedAt);
}

async function logJobStarted(
  jobRef: FirebaseFirestore.DocumentReference,
  context: LogContext,
  retryPolicy: TaskRetryPolicy | undefined,
): Promise<void> {
  const snapshot = await jobRef.get();
  const data = snapshot.data() as ImportJobData | undefined;
  const taskEnqueuedAt = timestampMillis(data?.taskEnqueuedAt);
  const payload: Record<string, unknown> = {
    ...baseLogPayload(context),
    event: "lookbookImport.jobStarted",
    taskRetryCount: retryPolicy?.retryCount ?? null,
    maxAttempts: retryPolicy?.maxAttempts ?? null,
  };
  if (taskEnqueuedAt > 0) {
    payload.dispatchDelayMs = Math.max(0, Date.now() - taskEnqueuedAt);
  }
  console.info(JSON.stringify(payload));
}

function logPhaseCompleted(
  context: LogContext,
  phase: string,
  durationMs: number,
  extra: Record<string, unknown> = {},
): void {
  console.info(JSON.stringify({
    ...baseLogPayload(context),
    event: "lookbookImport.phaseCompleted",
    phase,
    durationMs,
    ...compactLogPayload(extra),
  }));
}

function logFallbackUsed(
  context: LogContext,
  extra: Record<string, unknown>,
): void {
  console.info(JSON.stringify({
    ...baseLogPayload(context),
    event: "lookbookImport.fallbackUsed",
    ...compactLogPayload(extra),
  }));
}

function logAssetFailed(
  context: LogContext,
  result: SyncTargetResult,
): void {
  console.warn(JSON.stringify({
    ...baseLogPayload(context),
    event: "lookbookImport.assetFailed",
    targetKind: result.target.kind,
    seasonID: result.target.seasonID,
    postID: result.target.kind === "postImage" ?
      result.target.postID :
      null,
    stage: "assetSync",
    message: result.errorMessage ?? "asset sync failed",
  }));
}

function logJobCompleted(
  context: LogContext,
  result: JobResult,
  extra: Record<string, unknown>,
): void {
  console.info(JSON.stringify({
    ...baseLogPayload(context),
    event: "lookbookImport.jobCompleted",
    status: result.status,
    processed: result.processed,
    assetCompletedCount: result.completedCount ?? null,
    assetFailedCount: result.failedCount ?? null,
    errorMessage: result.errorMessage ?? null,
    ...compactLogPayload(extra),
  }));
}

function baseLogPayload(context: LogContext): Record<string, unknown> {
  return {
    brandID: context.brandID,
    jobID: context.jobID,
    jobType: context.jobType,
    workerID: context.workerID,
    ...sourceURLLogParts(context.sourceURL),
  };
}

function sourceURLLogParts(sourceURL: string): Record<string, unknown> {
  try {
    const parsed = new URL(sourceURL);
    return {
      sourceURLHost: parsed.hostname,
      sourceURLPath: parsed.pathname,
    };
  } catch {
    return {};
  }
}

function compactLogPayload(
  payload: Record<string, unknown>,
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(payload).filter(([, value]) => value !== null),
  );
}
