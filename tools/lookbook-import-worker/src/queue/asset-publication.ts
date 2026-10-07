/* eslint-disable require-jsdoc, max-len */
import type {Firestore} from "firebase-admin/firestore";
import type {AssetPathIdentity, AssetWritePaths} from "./asset-paths.js";
import {readOwnedBatch, type BatchOwnership} from "./coordinator.js";

export type QueueAssetWrite = AssetPathIdentity & {
  ordinal: number;
  paths: AssetWritePaths;
};
export type AssetObjectMetadata = {generation: string; size: number};

type AssetTarget = {
  refPath: string;
  thumbPath: string | null;
  detailPath: string | null;
  sourceURL: string | null;
  writeLedger: {jobID: string; executionID: string; assetKey: string;
    writeID: string} | null;
};

function safePathID(value: string): string {
  if (!value || value.length > 128 || value.includes("/") || value === "." ||
      value === ".." || [...value].some((character) => character.charCodeAt(0) < 32)) {
    throw new Error("INVALID_ASSET_WRITE");
  }
  return value;
}

function ledgerPath(input: QueueAssetWrite): string {
  return `brands/${safePathID(input.brandID)}/importJobs/` +
    `${safePathID(input.jobID)}/executions/${safePathID(input.executionID)}/` +
    `assets/${input.paths.assetKey}/writes/${safePathID(input.writeID)}`;
}

function targetPath(input: QueueAssetWrite): string {
  const base = `brands/${safePathID(input.brandID)}/seasons/` +
    safePathID(input.seasonID);
  return input.kind === "seasonCover" ? base :
    `${base}/posts/${safePathID(String(input.postID))}`;
}

function snapshotTarget(input: QueueAssetWrite, data: Record<string, unknown>): AssetTarget {
  if (input.kind === "seasonCover") {
    return {
      refPath: targetPath(input),
      thumbPath: typeof data.coverThumbPath === "string" ? data.coverThumbPath :
        typeof data.coverPath === "string" ? data.coverPath.replace(/\.jpg$/i, "_thumb.jpg") : null,
      detailPath: typeof data.coverPath === "string" ? data.coverPath : null,
      sourceURL: typeof data.coverRemoteURL === "string" ? data.coverRemoteURL : null,
      writeLedger: readWriteLedger(data.coverAsset ?? data),
    };
  }
  const mediaItems = Array.isArray(data.media) ? data.media : [];
  const media = mediaItems[Number(input.mediaIndex)] as Record<string, unknown> | undefined;
  if (!media || typeof media !== "object") throw new Error("ASSET_TARGET_MISSING");
  return {
    refPath: targetPath(input),
    thumbPath: typeof media.thumbPath === "string" ? media.thumbPath : null,
    detailPath: typeof media.detailPath === "string" ? media.detailPath : null,
    sourceURL: typeof media.remoteURL === "string" ? media.remoteURL : null,
    writeLedger: readWriteLedger(media),
  };
}

function readWriteLedger(data: unknown): AssetTarget["writeLedger"] {
  if (!data || typeof data !== "object") return null;
  const value = data as Record<string, unknown>;
  const jobID = value._assetJobID ?? value._coverAssetJobID ?? value.coverAssetJobID;
  const executionID = value._assetExecutionID ?? value._coverAssetExecutionID ??
    value.coverAssetExecutionID;
  const assetKey = value._assetKey ?? value._coverAssetKey ?? value.coverAssetKey;
  const writeID = value._assetWriteID ?? value._coverAssetWriteID ?? value.coverAssetWriteID;
  return typeof jobID === "string" && typeof executionID === "string" &&
    typeof assetKey === "string" && typeof writeID === "string" ?
    {jobID, executionID, assetKey, writeID} : null;
}

function priorTarget(input: QueueAssetWrite,
  data: Record<string, unknown>): AssetTarget {
  if (input.kind === "seasonCover") return snapshotTarget(input, data);
  const media = (Array.isArray(data.media) ? data.media : [])[
    Number(input.mediaIndex)] as Record<string, unknown> | undefined;
  if (!media) throw new Error("ASSET_TARGET_MISSING");
  return {
    refPath: targetPath(input),
    thumbPath: typeof media.thumbPath === "string" ? media.thumbPath : null,
    detailPath: typeof media.detailPath === "string" ? media.detailPath : null,
    sourceURL: typeof media.remoteURL === "string" ? media.remoteURL : null,
    writeLedger: readWriteLedger(media),
  };
}

function validateOwnerRun(batch: Record<string, unknown>, input: QueueAssetWrite): void {
  const items = batch.items as Array<Record<string, unknown>>;
  const item = items?.[input.ordinal];
  if (!item || item.admissionStatus !== "created" ||
      item.jobID !== input.jobID || item.executionID !== input.executionID) {
    throw new Error("QUEUE_ITEM_MISMATCH");
  }
}

function validateLiveTarget(input: QueueAssetWrite, target: AssetTarget,
  raw: Record<string, unknown>): void {
  if (target.sourceURL !== input.sourceURL) throw new Error("ASSET_SOURCE_CHANGED");
  if (raw.deletionStatus === "deleted") {
    throw new Error("ASSET_TARGET_DELETING");
  }
}

async function validateDeletionState(
  db: Firestore, transaction: FirebaseFirestore.Transaction,
  input: QueueAssetWrite, targetSnapshot: FirebaseFirestore.DocumentSnapshot,
): Promise<void> {
  const brandRef = db.doc(`brands/${input.brandID}`);
  const seasonRef = db.doc(`brands/${input.brandID}/seasons/${input.seasonID}`);
  const [brandSnapshot, seasonSnapshot] = await Promise.all([
    transaction.get(brandRef),
    input.kind === "seasonCover" ? Promise.resolve(targetSnapshot) :
      transaction.get(seasonRef),
  ]);
  if (!brandSnapshot.exists || !seasonSnapshot.exists ||
      brandSnapshot.data()?.deletionStatus === "deletionRequested" ||
      seasonSnapshot.data()?.deletionStatus === "deleted") {
    throw new Error("ASSET_TARGET_DELETING");
  }
}

export async function beginAssetWrite(
  db: Firestore, ownership: BatchOwnership, input: QueueAssetWrite, now = Date.now(),
): Promise<void> {
  const writeRef = db.doc(ledgerPath(input));
  const executionRef = db.doc(`brands/${input.brandID}/importJobs/${input.jobID}/` +
    `executions/${input.executionID}`);
  const targetRef = db.doc(targetPath(input));
  await db.runTransaction(async (transaction) => {
    const batch = await readOwnedBatch(db, transaction, ownership);
    validateOwnerRun(batch, input);
    const execution = (await transaction.get(executionRef)).data();
    const targetSnapshot = await transaction.get(targetRef);
    const targetData = targetSnapshot.data() as Record<string, unknown> | undefined;
    if (!execution || execution.activeRunID !== ownership.runID ||
        !targetSnapshot.exists || !targetData) throw new Error("QUEUE_ASSET_RUN_LOST");
    await validateDeletionState(db, transaction, input, targetSnapshot);
    const target = priorTarget(input, targetData);
    validateLiveTarget(input, target, targetData);
    transaction.create(writeRef, {
      status: "uploading", brandID: input.brandID,
      seasonID: input.seasonID, targetPath: target.refPath,
      targetSeasonPath: `brands/${input.brandID}/seasons/${input.seasonID}`,
      assetKey: input.paths.assetKey,
      writeID: input.writeID, executionID: input.executionID,
      batchID: ownership.batchID, runID: ownership.runID,
      epoch: ownership.epoch, kind: input.kind,
      thumbPath: input.paths.thumbPath, detailPath: input.paths.detailPath,
      transformPolicyVersion: input.transformPolicyVersion,
      previous: {thumbPath: target.thumbPath, detailPath: target.detailPath,
        writeLedger: target.writeLedger},
      objects: {}, createdAt: now, updatedAt: now,
    });
  });
}

export async function publishAssetWrite(
  db: Firestore, ownership: BatchOwnership, input: QueueAssetWrite,
  objects: Partial<Record<"thumb" | "detail", AssetObjectMetadata>>,
  now = Date.now(),
): Promise<void> {
  const writeRef = db.doc(ledgerPath(input));
  const executionRef = db.doc(`brands/${input.brandID}/importJobs/${input.jobID}/` +
    `executions/${input.executionID}`);
  const targetRef = db.doc(targetPath(input));
  await db.runTransaction(async (transaction) => {
    const batch = await readOwnedBatch(db, transaction, ownership);
    validateOwnerRun(batch, input);
    const execution = (await transaction.get(executionRef)).data();
    const write = (await transaction.get(writeRef)).data();
    const targetSnapshot = await transaction.get(targetRef);
    const targetData = targetSnapshot.data() as Record<string, unknown> | undefined;
    if (!execution || execution.activeRunID !== ownership.runID ||
        !write || write.status !== "uploading" ||
        !targetSnapshot.exists || !targetData) throw new Error("QUEUE_ASSET_RUN_LOST");
    await validateDeletionState(db, transaction, input, targetSnapshot);
    const target = priorTarget(input, targetData);
    validateLiveTarget(input, target, targetData);
    const previous = write.previous as Record<string, unknown>;
    if (target.thumbPath !== previous.thumbPath ||
        target.detailPath !== previous.detailPath ||
        JSON.stringify(target.writeLedger) !== JSON.stringify(previous.writeLedger)) {
      throw new Error("ASSET_TARGET_CHANGED");
    }
    const thumbObject = objects.thumb;
    const detailObject = objects.detail;
    if (!validAssetObject(thumbObject) || !validAssetObject(detailObject)) {
      throw new Error("ASSET_VARIANTS_INCOMPLETE");
    }
    const prior = target.writeLedger;
    const priorRef = prior ? db.doc(`brands/${input.brandID}/importJobs/${safePathID(prior.jobID)}/` +
      `executions/${safePathID(prior.executionID)}/assets/${safePathID(prior.assetKey)}/` +
      `writes/${safePathID(prior.writeID)}`) : null;
    const priorSnapshot = priorRef ? await transaction.get(priorRef) : null;
    if (input.kind === "seasonCover") {
      transaction.update(targetRef, {
        coverPath: input.paths.detailPath,
        coverAssetJobID: input.jobID,
        coverAssetExecutionID: input.executionID,
        coverAssetEpoch: ownership.epoch,
        coverAssetKey: input.paths.assetKey,
        coverAssetWriteID: input.writeID,
      });
    } else {
      const mediaItems = [...(Array.isArray(targetData.media) ? targetData.media : [])];
      const mediaIndex = Number(input.mediaIndex);
      const media = mediaItems[mediaIndex] as Record<string, unknown>;
      mediaItems[mediaIndex] = {...media, thumbPath: input.paths.thumbPath,
        detailPath: input.paths.detailPath, _assetJobID: input.jobID,
        _assetExecutionID: input.executionID, _assetEpoch: ownership.epoch,
        _assetKey: input.paths.assetKey, _assetWriteID: input.writeID};
      transaction.update(targetRef, {media: mediaItems,
        assetSyncStatus: "ready", assetSyncErrorMessage: null});
    }
    transaction.update(writeRef, {status: "published",
      objects: {thumb: thumbObject, detail: detailObject},
      publishedAt: now, updatedAt: now});
    if (priorRef && priorSnapshot?.exists) {
      transaction.update(priorRef, {status: "replaced", replacedAt: now,
        cleanupAfter: now + 24 * 60 * 60 * 1000,
        replacedBy: {executionID: input.executionID, writeID: input.writeID}, updatedAt: now});
    }
  });
}

export async function finishAssetWrite(
  db: Firestore, input: QueueAssetWrite, status: "unpublished" | "failed",
  errorCode: string,
  objects: Partial<Record<"thumb" | "detail", AssetObjectMetadata>> = {},
  now = Date.now(),
): Promise<void> {
  const writeRef = db.doc(ledgerPath(input));
  await db.runTransaction(async (transaction) => {
    const write = (await transaction.get(writeRef)).data();
    if (!write || write.status !== "uploading") return;
    transaction.update(writeRef, {status, objects,
      errorCode: errorCode.slice(0, 128),
      finishedAt: now, cleanupAfter: now + 24 * 60 * 60 * 1000,
      cleanupState: "pending", updatedAt: now});
  });
}

function validAssetObject(value: AssetObjectMetadata | undefined):
  value is AssetObjectMetadata {
  return Boolean(value?.generation) && Number.isSafeInteger(value?.size) &&
    Number(value?.size) >= 0;
}
