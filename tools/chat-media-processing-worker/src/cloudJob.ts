import {createHash} from "node:crypto";
import {createReadStream} from "node:fs";
import {mkdir, mkdtemp, rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import path from "node:path";

import {getApp, getApps, initializeApp} from "firebase-admin/app";
import {
  FieldValue,
  Timestamp,
  getFirestore,
  type DocumentData,
  type DocumentReference,
  type Firestore,
} from "firebase-admin/firestore";
import {getStorage, type Storage} from "firebase-admin/storage";

import {
  MEDIA_PROCESSING_CONTRACT,
  MediaProcessingError,
  classifyUnexpectedProcessingError,
} from "./contracts.js";
import {processImage, type ImageProcessingResult} from "./imageProcessor.js";
import {processVideo, type VideoProcessingResult} from "./videoProcessor.js";
import {boundedMap} from "./boundedMap.js";

const AUTOMATIC_ATTEMPTS = 3;
const TERMINAL_RETENTION_MILLISECONDS = 7 * 24 * 60 * 60 * 1000;

export type CloudJobKind = "images" | "video";

export interface CloudJobEnvironment {
  readonly uploadPath: string;
  readonly leaseToken: string;
  readonly kind: CloudJobKind;
  readonly readyBucket: string;
  readonly imageConcurrency?: number;
}

interface SourceManifestEntry {
  readonly attachmentID: string;
  readonly path: string;
  readonly generation: string;
  readonly sizeBytes: number;
  readonly contentType: string;
  readonly sha256: string;
}

interface JobReservation {
  readonly roomID: string;
  readonly uploadID: string;
  readonly kind: CloudJobKind;
  readonly quarantineBucket: string;
  readonly sourceManifest: readonly SourceManifestEntry[];
}

interface NormalizedManifestEntry {
  readonly attachmentID: string;
  readonly displayBucket: string;
  readonly displayPath: string;
  readonly displayGeneration: string;
  readonly displayBytes: number;
  readonly displayContentType: string;
  readonly thumbnailBucket: string;
  readonly thumbnailPath: string;
  readonly thumbnailGeneration: string;
  readonly thumbnailBytes: number;
  readonly thumbnailContentType: "image/jpeg";
}

interface CloudJobDependencies {
  readonly firestore: Firestore;
  readonly storage: Storage;
  readonly nowMillis: () => number;
}

export function cloudJobEnvironment(
  environment: NodeJS.ProcessEnv = process.env,
): CloudJobEnvironment | null {
  const uploadPath = environment.CHAT_MEDIA_UPLOAD_PATH?.trim();
  if (!uploadPath) return null;
  const leaseToken = requiredValue(environment.CHAT_MEDIA_LEASE_TOKEN, "CHAT_MEDIA_LEASE_TOKEN");
  const rawKind = requiredValue(environment.CHAT_MEDIA_KIND, "CHAT_MEDIA_KIND");
  if (rawKind !== "images" && rawKind !== "video") {
    throw new Error("CHAT_MEDIA_KIND는 images 또는 video여야 합니다.");
  }
  return {
    uploadPath,
    leaseToken,
    kind: rawKind,
    readyBucket: requiredValue(environment.CHAT_MEDIA_READY_BUCKET, "CHAT_MEDIA_READY_BUCKET"),
  };
}

export function readyObjectPath(
  roomID: string,
  uploadID: string,
  attachmentID: string,
  variant: "display" | "thumbnail",
): string {
  return `rooms/${roomID}/messages/${uploadID}/attachments/${attachmentID}/${variant}`;
}

export async function runCloudMediaJob(
  environment: CloudJobEnvironment,
  dependencies: CloudJobDependencies = runtimeDependencies(),
): Promise<void> {
  const uploadRef = dependencies.firestore.doc(environment.uploadPath);
  const snapshot = await uploadRef.get();
  const reservation = validateReservation(snapshot.data(), environment);
  const workingDirectory = await mkdtemp(path.join(tmpdir(), "chat-media-job-"));
  const writtenObjects: Array<{path: string; generation: string}> = [];
  const cpuStarted = process.cpuUsage();
  let peakRSSBytes = process.memoryUsage().rss;
  const memorySampler = setInterval(() => { peakRSSBytes = Math.max(peakRSSBytes, process.memoryUsage().rss); }, 50);
  memorySampler.unref();
  const allReadyPaths = reservation.sourceManifest.flatMap((source) => [
    readyObjectPath(
      reservation.roomID, reservation.uploadID, source.attachmentID, "display",
    ),
    readyObjectPath(
      reservation.roomID, reservation.uploadID, source.attachmentID, "thumbnail",
    ),
  ]);
  try {
    const concurrency = reservation.kind === "images" ? environment.imageConcurrency ?? 1 : 1;
    const startedAt = Date.now();
    const results = await boundedMap(reservation.sourceManifest, concurrency, async (source, index) => {
      const attachmentDirectory = path.join(workingDirectory, String(index));
      const stageStartedAt = Date.now();
      let stageAt = stageStartedAt;
      const timings: Record<string, number> = {};
      const mark = (stage: string): void => { const now = Date.now(); timings[stage] = now - stageAt; stageAt = now; };
      try {
      await assertLease(dependencies.firestore, environment);
      const inputPath = path.join(attachmentDirectory, "source");
      const outputDirectory = path.join(attachmentDirectory, "output");
      await mkdir(attachmentDirectory, {recursive: true});
      await dependencies.storage.bucket(reservation.quarantineBucket)
        .file(source.path, {generation: source.generation})
        .download({destination: inputPath, validation: "crc32c"});
      mark("downloadMs");
      if (await sha256File(inputPath) !== source.sha256) {
        throw new MediaProcessingError("invalidInput", "업로드 source SHA-256이 예약과 다릅니다.");
      }
      mark("hashMs");
      const result = reservation.kind === "images" ?
        await processImage(inputPath, outputDirectory, source.contentType) :
        await processVideo(inputPath, outputDirectory);
      mark("transformMs");
      const displayPath = readyObjectPath(
        reservation.roomID, reservation.uploadID, source.attachmentID, "display",
      );
      const thumbnailPath = readyObjectPath(
        reservation.roomID, reservation.uploadID, source.attachmentID, "thumbnail",
      );
      const [display, thumbnail] = await boundedMap([
        {
          storage: dependencies.storage,
          bucketName: environment.readyBucket,
          localPath: result.normalizedPath,
          objectPath: displayPath,
          contentType: resultContentType(result),
          environment,
          source,
        },
        {
          storage: dependencies.storage,
          bucketName: environment.readyBucket,
          localPath: result.thumbnailPath,
          objectPath: thumbnailPath,
          contentType: "image/jpeg",
          environment,
          source,
        },
      ], 2, async (input) => {
        return uploadResult({...input, firestore: dependencies.firestore,
          onStored: (objectPath, generation) => { writtenObjects.push({path: objectPath, generation}); }});
      });
      mark("storeMs");
      const manifest: NormalizedManifestEntry = {
        attachmentID: source.attachmentID,
        displayBucket: environment.readyBucket,
        displayPath,
        displayGeneration: display.generation,
        displayBytes: display.sizeBytes,
        displayContentType: resultContentType(result),
        thumbnailBucket: environment.readyBucket,
        thumbnailPath,
        thumbnailGeneration: thumbnail.generation,
        thumbnailBytes: thumbnail.sizeBytes,
        thumbnailContentType: "image/jpeg",
      };
      console.info(JSON.stringify({event: "media_worker_attachment", uploadID: reservation.uploadID,
        index, concurrency, ...timings, durationMs: Date.now() - stageStartedAt, rssBytes: process.memoryUsage().rss}));
      return {manifest, technical: technicalResult(source.attachmentID, result)};
      } finally {
        await rm(attachmentDirectory, {recursive: true, force: true});
      }
    });
    await recordWorkerCompletion({
      firestore: dependencies.firestore,
      uploadRef,
      environment,
      normalizedManifest: results.map((result) => result.manifest),
      technicalValidationResult: results.map((result) => result.technical),
    });
    console.info(JSON.stringify({event: "media_worker_completed", uploadID: reservation.uploadID,
      concurrency, count: results.length, durationMs: Date.now() - startedAt, peakRSSBytes,
      cpuMicroseconds: process.cpuUsage(cpuStarted)}));
  } catch (error) {
    const classified = classifyUnexpectedProcessingError(error);
    const terminal = await settleWorkerFailure({
      firestore: dependencies.firestore,
      uploadRef,
      environment,
      error: classified,
      nowMillis: dependencies.nowMillis(),
    });
    if (terminal) {
      await cleanupTerminalObjects({
        storage: dependencies.storage,
        uploadRef,
        quarantineBucket: reservation.quarantineBucket,
        quarantinePaths: reservation.sourceManifest.map((entry) => entry.path),
        readyBucket: environment.readyBucket,
        readyPaths: allReadyPaths,
      });
    } else {
      // 취소/lease 교체 후 늦게 완료된 저장은 이 실행이 생성한 generation만 정리한다.
      const current = await uploadRef.get();
      if (current.data()?.processingStatus !== "ready") {
        await boundedMap(writtenObjects, 2, async (object) => {
          try {
            await dependencies.storage.bucket(environment.readyBucket)
              .file(object.path, {generation: object.generation})
              .delete({ignoreNotFound: true, ifGenerationMatch: object.generation});
          } catch (error) {
            if (Number((error as {code?: number}).code) !== 412) throw error;
          }
        });
      }
    }
    throw classified;
  } finally {
    clearInterval(memorySampler);
    await rm(workingDirectory, {recursive: true, force: true});
  }
}

async function assertLease(firestore: Firestore, environment: CloudJobEnvironment): Promise<void> {
  const snapshot = await firestore.doc(environment.uploadPath).get();
  validateReservation(snapshot.data(), environment);
}

function runtimeDependencies(): CloudJobDependencies {
  const app = getApps().length > 0 ? getApp() : initializeApp();
  return {
    firestore: getFirestore(app),
    storage: getStorage(app),
    nowMillis: Date.now,
  };
}

function validateReservation(
  data: DocumentData | undefined,
  environment: CloudJobEnvironment,
): JobReservation {
  if (!data || data.contractVersion !== 2 || data.processingStatus !== "processing" ||
      data.leaseToken !== environment.leaseToken || data.kind !== environment.kind) {
    throw new MediaProcessingError("invalidInput", "현재 execution이 소유한 media lease가 아닙니다.");
  }
  const roomID = boundedString(data.roomID, "roomID");
  const uploadID = boundedString(data.uploadID, "uploadID");
  const quarantineBucket = boundedString(data.quarantineBucket, "quarantineBucket");
  if (!Array.isArray(data.sourceManifest) || data.sourceManifest.length < 1 ||
      data.sourceManifest.length !== data.attachmentCount) {
    throw new MediaProcessingError("invalidInput", "source manifest 개수가 예약과 다릅니다.");
  }
  const expectedPaths = new Set(
    Array.isArray(data.quarantinePaths) ? data.quarantinePaths : [],
  );
  const expectedAttachmentIDs = new Set(
    Array.isArray(data.attachmentIDs) ? data.attachmentIDs : [],
  );
  const sourceManifest = data.sourceManifest.map((entry: unknown) => {
    const value = objectValue(entry);
    const attachmentID = boundedString(value.attachmentID, "attachmentID");
    const sourcePath = boundedString(value.path, "source path");
    const generation = boundedString(value.generation, "source generation");
    const contentType = boundedString(value.contentType, "source contentType");
    const sha256 = boundedString(value.sha256, "source sha256").toLowerCase();
    const sizeBytes = Number(value.sizeBytes);
    if (!expectedAttachmentIDs.has(attachmentID) || !expectedPaths.has(sourcePath) ||
        !sourcePath.endsWith(`/${attachmentID}/source`) ||
        !Number.isSafeInteger(sizeBytes) || sizeBytes <= 0 ||
        !/^[0-9a-f]{64}$/.test(sha256)) {
      throw new MediaProcessingError("invalidInput", "source manifest 항목이 예약과 다릅니다.");
    }
    return {attachmentID, path: sourcePath, generation, contentType, sizeBytes, sha256};
  });
  return {roomID, uploadID, kind: environment.kind, quarantineBucket, sourceManifest};
}

export async function sha256File(filePath: string): Promise<string> {
  const digest = createHash("sha256");
  for await (const chunk of createReadStream(filePath)) digest.update(chunk);
  return digest.digest("hex");
}

async function uploadResult(input: {
  firestore: Firestore;
  onStored: (path: string, generation: string) => void;
  storage: Storage;
  bucketName: string;
  localPath: string;
  objectPath: string;
  contentType: string;
  environment: CloudJobEnvironment;
  source: SourceManifestEntry;
}): Promise<{generation: string; sizeBytes: number}> {
  const bucket = input.storage.bucket(input.bucketName);
  let previousGeneration: string | number = 0;
  try {
    const [previous] = await bucket.file(input.objectPath).getMetadata();
    previousGeneration = String(previous.generation);
  } catch (error) {
    if (Number((error as {code?: number}).code) !== 404) throw error;
  }
  await assertLease(input.firestore, input.environment);
  const [file] = await bucket.upload(input.localPath, {
    destination: input.objectPath,
    resumable: true,
    validation: "crc32c",
    preconditionOpts: {ifGenerationMatch: previousGeneration},
    metadata: {
      contentType: input.contentType,
      cacheControl: "private, max-age=0, no-store",
      metadata: {
        uploadPath: input.environment.uploadPath,
        leaseToken: input.environment.leaseToken,
        attachmentID: input.source.attachmentID,
        sourceGeneration: input.source.generation,
      },
    },
  });
  // 업로드 응답에 들어 있는 generation을 사용한다. 최신 경로를 재조회하지 않는다.
  const metadata = file.metadata;
  const generation = String(metadata.generation ?? "");
  const sizeBytes = Number(metadata.size);
  if (!generation || !Number.isSafeInteger(sizeBytes) || sizeBytes <= 0) {
    throw new MediaProcessingError("processingFailed", "업로드 결과 metadata가 올바르지 않습니다.", {
      retryable: true,
    });
  }
  input.onStored(input.objectPath, generation);
  return {generation, sizeBytes};
}

async function recordWorkerCompletion(input: {
  firestore: Firestore;
  uploadRef: DocumentReference;
  environment: CloudJobEnvironment;
  normalizedManifest: readonly NormalizedManifestEntry[];
  technicalValidationResult: readonly Record<string, unknown>[];
}): Promise<void> {
  await input.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(input.uploadRef);
    const data = snapshot.data();
    if (!snapshot.exists || data?.contractVersion !== 2 ||
        data.processingStatus !== "processing" ||
        data.leaseToken !== input.environment.leaseToken) {
      throw new MediaProcessingError("invalidInput", "완료 결과를 기록할 media lease가 없습니다.");
    }
    transaction.update(input.uploadRef, {
      normalizedManifest: input.normalizedManifest,
      technicalValidationResult: input.technicalValidationResult,
      metadataRemovalVersion: MEDIA_PROCESSING_CONTRACT.metadataRemovalVersion,
      workerCompletedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

async function settleWorkerFailure(input: {
  firestore: Firestore;
  uploadRef: DocumentReference;
  environment: CloudJobEnvironment;
  error: MediaProcessingError;
  nowMillis: number;
}): Promise<boolean> {
  return input.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(input.uploadRef);
    const data = snapshot.data();
    if (!snapshot.exists || data?.processingStatus !== "processing" ||
        data.leaseToken !== input.environment.leaseToken) return false;
    const processingSlotID = typeof data.processingSlotID === "string" ?
      data.processingSlotID : null;
    const attempt = Number(data.processingAttempt) || 0;
    const deadlineMillis = timestampMillis(data.processingDeadlineAt) ?? 0;
    const retry = input.error.retryable && attempt < AUTOMATIC_ATTEMPTS &&
      deadlineMillis > input.nowMillis;
    const slotRef = processingSlotID ? input.firestore
      .collection("chatMediaProcessingSlots").doc(processingSlotID) : null;
    const slot = slotRef ? await transaction.get(slotRef) : null;
    const principalSlotID = typeof data.principalSlotID === "string" ?
      data.principalSlotID : null;
    const principalRef = !retry && principalSlotID ? input.firestore
      .collection("chatMediaPrincipalUploadSlots").doc(principalSlotID) : null;
    const principal = principalRef ? await transaction.get(principalRef) : null;
    if (slotRef && slot?.data()?.leaseToken === input.environment.leaseToken) {
      transaction.set(slotRef, {
        leaseToken: null,
        leaseOwnerUploadPath: null,
        leaseExpiresAt: null,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    if (retry) {
      transaction.update(input.uploadRef, {
        processingStatus: "queued",
        dispatchGeneration: FieldValue.increment(1),
        leaseToken: null,
        leaseExpiresAt: null,
        processingSlotID: null,
        executionName: null,
        retryable: true,
        failureCode: input.error.code,
        nextAttemptAt: Timestamp.fromMillis(input.nowMillis + attempt * 30_000),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return false;
    }
    if (principalRef && principal?.data()?.ownerUploadPath === input.uploadRef.path) {
      transaction.set(principalRef, {
        ownerUploadPath: null,
        clientMutationID: null,
        leaseExpiresAt: null,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    transaction.update(input.uploadRef, {
      processingStatus: "failed",
      retryable: false,
      failureCode: input.error.code,
      leaseToken: null,
      leaseExpiresAt: null,
      processingSlotID: null,
      executionName: null,
      nextAttemptAt: null,
      cleanupStatus: "pending",
      terminalAt: Timestamp.fromMillis(input.nowMillis),
      expiresAt: Timestamp.fromMillis(input.nowMillis + TERMINAL_RETENTION_MILLISECONDS),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

async function cleanupTerminalObjects(input: {
  storage: Storage;
  uploadRef: DocumentReference;
  quarantineBucket: string;
  quarantinePaths: readonly string[];
  readyBucket: string;
  readyPaths: readonly string[];
}): Promise<void> {
  try {
    await Promise.all([
      ...input.quarantinePaths.map((objectPath) => input.storage
        .bucket(input.quarantineBucket).file(objectPath).delete({ignoreNotFound: true})),
      ...input.readyPaths.map((objectPath) => input.storage
        .bucket(input.readyBucket).file(objectPath).delete({ignoreNotFound: true})),
    ]);
    await input.uploadRef.set({
      cleanupStatus: "completed",
      cleanupCompletedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  } catch (error) {
    await input.uploadRef.set({
      cleanupStatus: "failed",
      cleanupFailureCode: "worker_terminal_cleanup_failed",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    throw new MediaProcessingError("processingFailed", "terminal media 객체 정리에 실패했습니다.", {
      retryable: true,
      cause: error,
    });
  }
}

function resultContentType(result: ImageProcessingResult | VideoProcessingResult): string {
  if (result.kind === "video") return "video/mp4";
  if (result.outputFormat === "jpeg") return "image/jpeg";
  if (result.outputFormat === "png") return "image/png";
  return "image/gif";
}

function technicalResult(
  attachmentID: string,
  result: ImageProcessingResult | VideoProcessingResult,
): Record<string, unknown> {
  return result.kind === "image" ? {
    attachmentID,
    actualFormat: result.probe.format,
    width: result.probe.width,
    height: result.probe.height,
    frameCount: result.probe.frameCount,
    animated: result.probe.animated,
  } : {
    attachmentID,
    container: result.probe.container,
    videoCodec: result.probe.videoCodec,
    audioCodec: result.probe.audioCodec,
    width: result.probe.width,
    height: result.probe.height,
    durationSeconds: result.probe.durationSeconds,
    sourceStreamCount: result.probe.sourceStreamCount,
    thumbnailAtSeconds: result.thumbnailAtSeconds,
  };
}

function requiredValue(value: string | undefined, name: string): string {
  const normalized = value?.trim();
  if (!normalized) throw new Error(`필수 환경 변수가 없습니다: ${name}`);
  return normalized;
}

function boundedString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length < 1 || value.length > 1024) {
    throw new MediaProcessingError("invalidInput", `${field} 값이 올바르지 않습니다.`);
  }
  return value;
}

function objectValue(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new MediaProcessingError("invalidInput", "source manifest 항목이 객체가 아닙니다.");
  }
  return value as Record<string, unknown>;
}

function timestampMillis(value: unknown): number | null {
  if (value instanceof Timestamp) return value.toMillis();
  if (value && typeof value === "object" && "toMillis" in value &&
      typeof value.toMillis === "function") return value.toMillis();
  return null;
}
