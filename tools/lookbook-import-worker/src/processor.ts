/* eslint-disable max-len */
import {randomUUID} from "node:crypto";

import type {Firestore} from "firebase-admin/firestore";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import type {Storage} from "firebase-admin/storage";
import sharp from "sharp";

import {
  isRetryableImportError,
  RetryableImportError,
} from "./import-error.js";
import {
  fetchPublicHTTP,
  responseBytes,
  retryableStatusError,
} from "./public-http.js";
import {
  completedLifecycle,
  isFinalTaskAttempt,
  type ImportJobLifecycle,
} from "./job-lifecycle.js";

type WorkerStatus = ImportJobLifecycle;

type ImageCandidate = {
  sourceURL: string;
  alt: string | null;
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
  targetSeasonID?: unknown;
  createdPostIDs?: unknown;
  parseStatus?: unknown;
  contentStatus?: unknown;
  assetSyncStatus?: unknown;
  assetTotalCount?: unknown;
  leaseOwner?: unknown;
  leaseExpiresAt?: unknown;
  createdAt?: unknown;
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
};

type MediaData = {
  remoteURL?: unknown;
  sourcePageURL?: unknown;
  thumbPath?: unknown;
  detailPath?: unknown;
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

export type WakeRequest = {
  brandID?: unknown;
  jobIDs?: unknown;
  batchSize?: unknown;
};

export type ImportJobTaskRequest = {
  brandID?: unknown;
  jobID?: unknown;
  maxAttempts?: unknown;
  requestedAt?: unknown;
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
const FETCH_HTML_TIMEOUT_MS = 15_000;
const FETCH_IMAGE_TIMEOUT_MS = 20_000;
const HTML_MAX_BYTES = 5 * 1024 * 1024;
const REMOTE_IMAGE_MAX_BYTES = 25 * 1024 * 1024;
const ASSET_SYNC_CONCURRENCY = 3;

const CONTENT_SECTION_RULES: Array<{
  label: string;
  pattern: RegExp;
  weight: number;
}> = [
  {
    label: "cafe24ProductAdditional",
    pattern:
      /xans-product-additional|prdDetailContentLazy|product-additional/i,
    weight: 360,
  },
  {
    label: "productDetailContent",
    pattern:
      /prdDetail|detail[_-]?content|detailArea|product[_-]?detail[_-]?area/i,
    weight: 300,
  },
  {
    label: "editorContent",
    pattern: /NNEditor|fr-view|se-main-container|editor|edibot/i,
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
  /(?:sprite|blank|placeholder|loading)\.(?:gif|png|svg)(?:\?|$)/i,
];

const NOISE_CONTEXT_PATTERN =
  /product\/list\.html|category\/|view all|gnb|lnb|menu|header|footer/i;

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
): Promise<JobResult> {
  const db = dependencies.firestore;
  const jobRef = importJobRef(db, target);
  const claim = await claimJob(db, target, workerID);
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
  };

  const leaseTimer = setInterval(() => {
    void refreshLease(jobRef, workerID).catch((error: unknown) => {
      console.warn("[lookbook-import-worker] lease refresh failed", error);
    });
  }, LEASE_REFRESH_MS);

  try {
    if (claimedJob.jobType === "retrySeasonAssets") {
      return await processAssetRetryJob(
        dependencies,
        jobRef,
        claimedJob,
      );
    }

    const parseResult = await ensureParsed(db, jobRef, claimedJob);
    if (!parseResult.ok) {
      return await failJob(jobRef, target, parseResult.errorMessage, {
        parseStatus: "failed",
      });
    }

    const materializeResult = await ensureMaterialized(db, jobRef, claimedJob);
    if (!materializeResult.ok) {
      return await failJob(jobRef, target, materializeResult.errorMessage, {
        contentStatus: "failed",
      });
    }

    const assetResult = await syncAssets(
      dependencies,
      jobRef,
      claimedJob,
      materializeResult.seasonID,
    );

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

    return {
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
  } catch (error) {
    if (isRetryableImportError(error)) {
      if (
        retryPolicy &&
        isFinalTaskAttempt(
          retryPolicy.retryCount,
          retryPolicy.maxAttempts,
        )
      ) {
        return failJob(jobRef, target, error.message, {
          parseStatus: "failed",
          errorCode: "retryExhausted",
        });
      }
      await releaseJobForTaskRetry(jobRef, error.message);
      throw error;
    }
    return await failJob(jobRef, target, errorMessage(error), {});
  } finally {
    clearInterval(leaseTimer);
  }
}

async function claimJob(
  db: Firestore,
  target: JobTarget,
  workerID: string,
): Promise<
  | {
      claimed: true;
      jobType: "importSeasonFromURL" | "retrySeasonAssets";
      sourceURL: string;
      sourceCandidateID: string | null;
      sourceImportJobID: string | null;
      targetSeasonID: string | null;
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

    transaction.update(jobRef, {
      status: "processing",
      phase: "parsing",
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
    };
  });
}

async function processAssetRetryJob(
  dependencies: ProcessorDependencies,
  jobRef: FirebaseFirestore.DocumentReference,
  claim: ClaimedJob,
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
  const assetResult = await syncAssets(
    dependencies,
    jobRef,
    claim,
    claim.targetSeasonID,
  );
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
): Promise<{ok: true} | {ok: false; errorMessage: string}> {
  const snapshot = await jobRef.get();
  const data = snapshot.data() as ImportJobData | undefined;
  if (parsedImageCandidates(data?.imageCandidates).length > 0) {
    await jobRef.update({
      parseStatus: "succeeded",
      parsedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {ok: true};
  }

  await jobRef.update({
    phase: "parsing",
    parseStatus: "running",
    updatedAt: FieldValue.serverTimestamp(),
  });

  try {
    const html = await withImmediateRetry(() => fetchHTML(claim.sourceURL));
    const extraction = extractImageCandidates(html, claim.sourceURL);
    if (extraction.candidates.length === 0) {
      throw new Error("이미지 후보를 찾지 못했습니다.");
    }

    await jobRef.update({
      parseStatus: "succeeded",
      imageCandidateCount: extraction.candidates.length,
      imageCandidates: extraction.candidates.slice(0, MAX_IMAGE_CANDIDATES_TO_STORE),
      imageExtractionStrategy: extraction.strategy,
      rawImageCandidateCount: extraction.rawCandidateCount,
      parsedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {ok: true};
  } catch (error) {
    if (isRetryableImportError(error)) {
      throw error;
    }
    return {ok: false, errorMessage: errorMessage(error)};
  }
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
    const imageCandidates = parsedImageCandidates(data.imageCandidates);
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
    {length: Math.min(ASSET_SYNC_CONCURRENCY, targets.length)},
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

function extractImageCandidates(
  html: string,
  baseURL: string,
): {candidates: ImageCandidate[]; strategy: string; rawCandidateCount: number} {
  const rawCandidates = collectImageCandidates(html, baseURL, false, true);
  const sections = contentSections(html)
    .map((section) => {
      const candidates = collectImageCandidates(section.html, baseURL, false, false);
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
    return {
      candidates: bestSection.candidates,
      strategy: bestSection.label,
      rawCandidateCount: rawCandidates.length,
    };
  }
  const filteredCandidates = collectImageCandidates(html, baseURL, true, false);
  return {
    candidates: filteredCandidates.length > 0 ? filteredCandidates : rawCandidates,
    strategy: filteredCandidates.length > 0 ? "filteredPageImages" : "allPageImages",
    rawCandidateCount: rawCandidates.length,
  };
}

function collectImageCandidates(
  html: string,
  baseURL: string,
  applyNoiseFilter: boolean,
  includeMetaImages: boolean,
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
    );
  }
  return candidates;
}

function contentSections(html: string): Array<{
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
    const rule = CONTENT_SECTION_RULES.find((item) => item.pattern.test(match[0]));
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
): void {
  for (const rawValue of rawValues) {
    const normalizedURL = normalizedImageURL(rawValue, baseURL);
    if (
      !normalizedURL ||
      seen.has(normalizedURL) ||
      (applyNoiseFilter && isLikelyNoiseImage(normalizedURL, context))
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
  try {
    const url = new URL(trimmed, baseURL);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return null;
    }
    return url.toString();
  } catch {
    return null;
  }
}

function isLikelyNoiseImage(imageURL: string, context: string): boolean {
  return NOISE_IMAGE_URL_PATTERNS.some((pattern) => pattern.test(imageURL)) ||
    NOISE_CONTEXT_PATTERN.test(context);
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
  thumbPath: string,
  detailPath: string,
): Promise<void> {
  const postRef = postRefFor(db, brandID, seasonID, postID);
  const snapshot = await postRef.get();
  const postData = snapshot.data() as PostData | undefined;
  const mediaItems = Array.isArray(postData?.media) ? [...postData.media] : [];
  const firstMedia = firstMediaData(mediaItems);
  if (firstMedia === null) {
    throw new Error("포스트 미디어 정보가 없습니다.");
  }
  mediaItems[0] = {...firstMedia, thumbPath, detailPath};
  await postRef.set({
    media: mediaItems,
    assetSyncStatus: "ready",
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
