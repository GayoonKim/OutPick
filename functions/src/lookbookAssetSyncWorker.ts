/* eslint-disable require-jsdoc, valid-jsdoc */
import type {Firestore} from "firebase-admin/firestore";
import {FieldValue} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import sharp from "sharp";

type ImportJobData = {
  status?: unknown;
  sourceURL?: unknown;
  targetSeasonID?: unknown;
  createdPostIDs?: unknown;
  assetSyncStatus?: unknown;
  assetTotalCount?: unknown;
  coverRemoteURL?: unknown;
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
};

type AssetSyncJobClaimResult =
  | {
      claimed: true;
      seasonID: string;
      sourceURL: string;
    }
  | {
      claimed: false;
      reason: string;
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
  errorMessage?: string;
};

type AssetSyncJobResult = {
  jobID: string;
  processed: boolean;
  status: "ready" | "partial" | "failed" | "skipped";
  seasonID?: string;
  completedCount?: number;
  failedCount?: number;
  reason?: string;
  errorMessage?: string;
};

const DEFAULT_ASSET_SYNC_CONCURRENCY = 3;
const MAX_ASSET_SYNC_CONCURRENCY = 3;
const FETCH_TIMEOUT_MS = 20_000;
const REMOTE_IMAGE_MAX_BYTES = 25 * 1024 * 1024;

const SEASON_COVER_THUMB = {maxPixel: 512, quality: 75};
const SEASON_COVER_DETAIL = {maxPixel: 1600, quality: 88};
const POST_IMAGE_THUMB = {maxPixel: 768, quality: 82};
const POST_IMAGE_DETAIL = {maxPixel: 1920, quality: 90};

export async function syncSeasonImportAssetsForJob(
  db: Firestore,
  brandID: string,
  jobID: string
): Promise<AssetSyncJobResult> {
  const jobRef = db
    .collection("brands")
    .doc(brandID)
    .collection("importJobs")
    .doc(jobID);

  const claim = await db.runTransaction<AssetSyncJobClaimResult>(
    async (transaction) => {
      const snapshot = await transaction.get(jobRef);
      const data = snapshot.data() as ImportJobData | undefined;

      if (!snapshot.exists || !data) {
        return {
          claimed: false,
          reason: "notFound",
        };
      }

      if (data.status !== "success") {
        return {
          claimed: false,
          reason: `notReady:${String(data.status ?? "unknown")}`,
        };
      }

      const assetSyncStatus = optionalStringField(data.assetSyncStatus);
      if (assetSyncStatus === "syncing") {
        return {
          claimed: false,
          reason: "alreadySyncing",
        };
      }
      if (assetSyncStatus === "ready") {
        return {
          claimed: false,
          reason: "alreadyReady",
        };
      }

      const seasonID = stringField(data.targetSeasonID, "targetSeasonID");
      const sourceURL = stringField(data.sourceURL, "sourceURL");

      transaction.update(jobRef, {
        assetSyncStatus: "syncing",
        assetSyncErrorMessage: null,
        assetSyncStartedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {
        claimed: true,
        seasonID,
        sourceURL,
      };
    }
  );

  if (!claim.claimed) {
    return {
      jobID,
      processed: false,
      status: "skipped",
      reason: claim.reason,
    };
  }

  try {
    const syncTargets = await assetSyncTargets(
      db,
      brandID,
      claim.seasonID,
      claim.sourceURL,
      jobRef
    );

    if (syncTargets.length === 0) {
      await jobRef.update({
        assetSyncStatus: "failed",
        assetSyncErrorMessage: "동기화할 이미지가 없습니다.",
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {
        jobID,
        processed: true,
        status: "failed",
        seasonID: claim.seasonID,
        errorMessage: "동기화할 이미지가 없습니다.",
      };
    }

    const results = await runSyncTargets(db, syncTargets);
    const succeededCount = results.filter((result) => result.succeeded).length;
    const failedResults = results.filter((result) => !result.succeeded);
    const failedCount = failedResults.length;

    const seasonRef = db
      .collection("brands")
      .doc(brandID)
      .collection("seasons")
      .doc(claim.seasonID);

    const seasonAssetStatus = failedCount === 0 ?
      "ready" :
      (succeededCount > 0 ? "partial" : "failed");

    await Promise.all(failedResults.map(async (result) => {
      if (result.target.kind !== "postImage") {
        return;
      }
      await getPostRef(
        db,
        result.target.brandID,
        result.target.seasonID,
        result.target.postID
      ).set({
        assetSyncStatus: "failed",
        assetSyncErrorMessage: result.errorMessage ?? "이미지 동기화 실패",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }));

    await seasonRef.set({
      assetSyncStatus: seasonAssetStatus,
      assetSyncErrorMessage: failedResults[0]?.errorMessage ?? null,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    await jobRef.update({
      assetSyncStatus: seasonAssetStatus,
      assetCompletedCount: succeededCount,
      assetFailedCount: failedCount,
      assetSyncedAt: FieldValue.serverTimestamp(),
      assetSyncErrorMessage: failedResults[0]?.errorMessage ?? null,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      jobID,
      processed: true,
      status: seasonAssetStatus as "ready" | "partial" | "failed",
      seasonID: claim.seasonID,
      completedCount: succeededCount,
      failedCount,
      errorMessage: failedResults[0]?.errorMessage,
    };
  } catch (error) {
    const message = errorMessage(error);
    await jobRef.update({
      assetSyncStatus: "failed",
      assetSyncErrorMessage: message,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      jobID,
      processed: true,
      status: "failed",
      seasonID: claim.seasonID,
      errorMessage: message,
    };
  }
}

async function assetSyncTargets(
  db: Firestore,
  brandID: string,
  seasonID: string,
  sourceURL: string,
  jobRef: FirebaseFirestore.DocumentReference
): Promise<SyncTarget[]> {
  const [jobSnapshot, seasonSnapshot] = await Promise.all([
    jobRef.get(),
    db
      .collection("brands")
      .doc(brandID)
      .collection("seasons")
      .doc(seasonID)
      .get(),
  ]);

  const jobData = jobSnapshot.data() as ImportJobData | undefined;
  const seasonData = seasonSnapshot.data() as SeasonData | undefined;

  const postIDs = stringArray(jobData?.createdPostIDs);
  const postRefs = postIDs.map((postID) => {
    return db
      .collection("brands")
      .doc(brandID)
      .collection("seasons")
      .doc(seasonID)
      .collection("posts")
      .doc(postID);
  });
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

  for (const postSnapshot of postSnapshots) {
    if (!postSnapshot.exists) {
      continue;
    }

    const postData = postSnapshot.data() as PostData | undefined;
    const firstMedia = firstMediaData(postData?.media);
    const remoteURL = optionalStringField(firstMedia?.remoteURL);
    if (remoteURL === null) {
      continue;
    }

    targets.push({
      kind: "postImage",
      brandID,
      seasonID,
      postID: postSnapshot.id,
      remoteURL,
      sourcePageURL:
        optionalStringField(firstMedia?.sourcePageURL) ?? sourceURL,
    });
  }

  return targets;
}

async function runSyncTargets(
  dbRef: Firestore,
  targets: SyncTarget[],
  concurrency = DEFAULT_ASSET_SYNC_CONCURRENCY
): Promise<SyncTargetResult[]> {
  const safeConcurrency = Math.max(
    1,
    Math.min(MAX_ASSET_SYNC_CONCURRENCY, Math.floor(concurrency))
  );
  const results: SyncTargetResult[] = [];
  let cursor = 0;

  const workers = Array.from(
    {length: Math.min(safeConcurrency, targets.length)},
    async () => {
      for (;;) {
        const currentIndex = cursor;
        cursor += 1;

        const target = targets[currentIndex];
        if (!target) {
          return;
        }

        results[currentIndex] = await syncSingleTarget(dbRef, target);
      }
    }
  );

  await Promise.all(workers);
  return results;
}

async function syncSingleTarget(
  db: Firestore,
  target: SyncTarget
): Promise<SyncTargetResult> {
  try {
    const originalBytes = await fetchRemoteImageBytes(
      target.remoteURL,
      target.sourcePageURL
    );

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
      const thumbPath = seasonCoverThumbPath(target.brandID, target.seasonID);
      const detailPath = seasonCoverDetailPath(target.brandID, target.seasonID);

      await Promise.all([
        uploadJPEG(thumbPath, thumbBytes),
        uploadJPEG(detailPath, detailBytes),
      ]);

      await updateSeasonCoverPaths(
        db,
        target.brandID,
        target.seasonID,
        detailPath
      );
    } else {
      const thumbPath = postThumbPath(
        target.brandID,
        target.seasonID,
        target.postID
      );
      const detailPath = postDetailPath(
        target.brandID,
        target.seasonID,
        target.postID
      );

      await Promise.all([
        uploadJPEG(thumbPath, thumbBytes),
        uploadJPEG(detailPath, detailBytes),
      ]);

      await updatePostMediaPaths(
        db,
        target.brandID,
        target.seasonID,
        target.postID,
        thumbPath,
        detailPath
      );
    }

    return {
      target,
      succeeded: true,
    };
  } catch (error) {
    return {
      target,
      succeeded: false,
      errorMessage: errorMessage(error),
    };
  }
}

async function fetchRemoteImageBytes(
  remoteURL: string,
  sourcePageURL: string
): Promise<Buffer> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

  try {
    const response = await fetch(remoteURL, {
      redirect: "follow",
      signal: controller.signal,
      headers: {
        "user-agent":
          "OutPickLookbookImporter/0.1 (+https://outpick.app)",
        "accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
        "referer": sourcePageURL,
      },
    });

    if (!response.ok) {
      throw new Error(`이미지 응답 실패: HTTP ${response.status}`);
    }

    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.toLowerCase().startsWith("image/")) {
      throw new Error(`이미지 응답이 아닙니다: ${contentType || "unknown"}`);
    }

    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length === 0) {
      throw new Error("이미지 바이트가 비어 있습니다.");
    }
    if (bytes.length > REMOTE_IMAGE_MAX_BYTES) {
      throw new Error("이미지 크기가 너무 큽니다.");
    }
    return bytes;
  } finally {
    clearTimeout(timeout);
  }
}

async function jpegBytes(
  input: Buffer,
  maxPixel: number,
  quality: number
): Promise<Buffer> {
  return sharp(input, {failOn: "none"})
    .rotate()
    .resize({
      width: maxPixel,
      height: maxPixel,
      fit: "inside",
      withoutEnlargement: true,
    })
    .jpeg({
      quality,
      mozjpeg: true,
    })
    .toBuffer();
}

async function uploadJPEG(path: string, bytes: Buffer): Promise<void> {
  await getStorage()
    .bucket()
    .file(path)
    .save(bytes, {
      resumable: false,
      metadata: {
        contentType: "image/jpeg",
        cacheControl: "public,max-age=3600",
      },
    });
}

async function updateSeasonCoverPaths(
  db: Firestore,
  brandID: string,
  seasonID: string,
  detailPath: string
): Promise<void> {
  await getSeasonRef(db, brandID, seasonID).set({
    coverPath: detailPath,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function updatePostMediaPaths(
  db: Firestore,
  brandID: string,
  seasonID: string,
  postID: string,
  thumbPath: string,
  detailPath: string
): Promise<void> {
  const postRef = getPostRef(db, brandID, seasonID, postID);
  const snapshot = await postRef.get();
  const postData = snapshot.data() as PostData | undefined;
  const mediaItems = Array.isArray(postData?.media) ? [...postData.media] : [];
  const firstMedia = firstMediaData(mediaItems);
  if (firstMedia === null) {
    throw new Error("포스트 미디어 정보가 없습니다.");
  }

  mediaItems[0] = {
    ...firstMedia,
    thumbPath,
    detailPath,
  };

  await postRef.set({
    media: mediaItems,
    assetSyncStatus: "ready",
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

function getSeasonRef(
  db: Firestore,
  brandID: string,
  seasonID: string
): FirebaseFirestore.DocumentReference {
  return db
    .collection("brands")
    .doc(brandID)
    .collection("seasons")
    .doc(seasonID);
}

function getPostRef(
  db: Firestore,
  brandID: string,
  seasonID: string,
  postID: string
): FirebaseFirestore.DocumentReference {
  return getSeasonRef(db, brandID, seasonID)
    .collection("posts")
    .doc(postID);
}

function seasonCoverThumbPath(brandID: string, seasonID: string): string {
  return `brands/${brandID}/seasons/${seasonID}/cover_thumb.jpg`;
}

function seasonCoverDetailPath(brandID: string, seasonID: string): string {
  return `brands/${brandID}/seasons/${seasonID}/cover.jpg`;
}

function postThumbPath(
  brandID: string,
  seasonID: string,
  postID: string
): string {
  return `brands/${brandID}/seasons/${seasonID}/posts/${postID}/thumb.jpg`;
}

function postDetailPath(
  brandID: string,
  seasonID: string,
  postID: string
): string {
  return `brands/${brandID}/seasons/${seasonID}/posts/${postID}/detail.jpg`;
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

function errorMessage(error: unknown): string {
  if (error instanceof Error && error.message.trim().length > 0) {
    return error.message;
  }
  return String(error);
}
