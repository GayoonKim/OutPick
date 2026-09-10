import { createHash } from "node:crypto";

import { MAX_IMAGES_PER_MESSAGE } from "../config.js";
import { normalizeUID } from "../utils/strings.js";
import { boundedMap } from "./boundedMap.js";

const MEDIA_UPLOAD_RESERVATION_TTL_MS = 24 * 60 * 60 * 1000;
const MEDIA_V2_UPLOAD_TTL_MS = 24 * 60 * 60 * 1000;
const MEDIA_V2_PROCESSING_DEADLINE_MS = 6 * 60 * 60 * 1000;
const MEDIA_V2_TERMINAL_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const MEDIA_V2_MAX_IMAGE_BYTES = 15 * 1024 * 1024;
const MEDIA_V2_MAX_IMAGE_AGGREGATE_BYTES = 150 * 1024 * 1024;
const MEDIA_V2_MAX_VIDEO_BYTES = 350 * 1024 * 1024;

export function normalizeMediaKind(kind) {
  if (kind === "image" || kind === "images") return "images";
  if (kind === "video") return "video";
  return "";
}

export function validateMediaUploadContract(kind, attachmentCount, expectedPathCount) {
  const count = Number(attachmentCount);
  const pathCount = Number(expectedPathCount);
  if (!Number.isInteger(count) || !Number.isInteger(pathCount)) {
    return { ok: false, error: "invalid_attachment_count" };
  }
  if (kind === "images") {
    if (count < 1 || count > MAX_IMAGES_PER_MESSAGE) {
      return { ok: false, error: "invalid_attachment_count" };
    }
    if (pathCount !== count * 2) {
      return { ok: false, error: "invalid_expected_path_count" };
    }
    return { ok: true, attachmentCount: count, expectedPathCount: pathCount };
  }
  if (kind === "video") {
    if (count !== 1) return { ok: false, error: "invalid_attachment_count" };
    if (pathCount !== 2) {
      return { ok: false, error: "invalid_expected_path_count" };
    }
    return { ok: true, attachmentCount: count, expectedPathCount: pathCount };
  }
  return { ok: false, error: "invalid_media_kind" };
}

export function validateMediaUploadContractV2(kind, attachmentCount, expectedPathCount) {
  const count = Number(attachmentCount);
  const pathCount = Number(expectedPathCount);
  if (!Number.isInteger(count) || !Number.isInteger(pathCount)) {
    return { ok: false, error: "invalid_attachment_count" };
  }
  if (kind === "images" && count >= 1 && count <= MAX_IMAGES_PER_MESSAGE) {
    return pathCount === count
      ? { ok: true, attachmentCount: count, expectedPathCount: pathCount }
      : { ok: false, error: "invalid_expected_path_count" };
  }
  if (kind === "video" && count === 1) {
    return pathCount === 1
      ? { ok: true, attachmentCount: 1, expectedPathCount: 1 }
      : { ok: false, error: "invalid_expected_path_count" };
  }
  return { ok: false, error: kind === "images" || kind === "video"
    ? "invalid_attachment_count"
    : "invalid_media_kind" };
}

function stableAttachmentID(uploadID, index, kind) {
  return createHash("sha256")
    .update(`${uploadID}:${index}:${kind}`)
    .digest("hex")
    .slice(0, 32);
}

function v2SourceContentTypeAllowed(kind, contentType) {
  if (kind === "video") return contentType === "video/mp4";
  return ["image/jpeg", "image/png", "image/gif"].includes(contentType);
}

function v2SourceByteLimit(kind) {
  return kind === "video" ? MEDIA_V2_MAX_VIDEO_BYTES : MEDIA_V2_MAX_IMAGE_BYTES;
}

function normalizedSourceDescriptors(entries) {
  if (!Array.isArray(entries)) return [];
  return entries.map((entry, index) => ({
    index: Number.isInteger(Number(entry?.index)) ? Number(entry.index) : index,
    contentType: String(entry?.contentType || "").toLowerCase(),
    sizeBytes: Number(entry?.sizeBytes),
    sha256: String(entry?.sha256 || "").toLowerCase()
  })).sort((lhs, rhs) => lhs.index - rhs.index);
}

function validSHA256(value) {
  return /^[0-9a-f]{64}$/.test(value);
}

export function validateMediaSourceDescriptors(kind, contract, entries) {
  const descriptors = normalizedSourceDescriptors(entries);
  if (descriptors.length !== contract.attachmentCount) {
    return {ok: false, error: "media_source_count_mismatch"};
  }
  let aggregateBytes = 0;
  for (let index = 0; index < descriptors.length; index += 1) {
    const descriptor = descriptors[index];
    if (descriptor.index !== index ||
        !v2SourceContentTypeAllowed(kind, descriptor.contentType) ||
        !Number.isInteger(descriptor.sizeBytes) || descriptor.sizeBytes <= 0 ||
        descriptor.sizeBytes > v2SourceByteLimit(kind) ||
        !validSHA256(descriptor.sha256)) {
      return {ok: false, error: "media_source_invalid"};
    }
    aggregateBytes += descriptor.sizeBytes;
  }
  if (kind === "images" && aggregateBytes > MEDIA_V2_MAX_IMAGE_AGGREGATE_BYTES) {
    return {ok: false, error: "media_aggregate_too_large"};
  }
  return {ok: true, descriptors, aggregateBytes};
}

function normalizedManifestEntries(entries) {
  if (!Array.isArray(entries)) return [];
  return entries.map((entry) => ({
    attachmentID: String(entry?.attachmentID || ""),
    path: String(entry?.path || ""),
    generation: String(entry?.generation || ""),
    sizeBytes: Number(entry?.sizeBytes),
    contentType: String(entry?.contentType || "").toLowerCase()
  })).sort((lhs, rhs) => lhs.attachmentID.localeCompare(rhs.attachmentID));
}

function timestampMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return null;
}

function normalizedPaths(paths) {
  return paths.filter(Boolean).map(String).sort();
}

function existingMediaDetails(existingMessage) {
  const attachments = Array.isArray(existingMessage?.attachments)
    ? existingMessage.attachments
    : [];
  return {
    attachments,
    kind: String(existingMessage?.messageType || "").toLowerCase() === "image"
      ? "images"
      : (String(existingMessage?.messageType || "").toLowerCase() === "video"
          ? "video"
          : ""),
    storagePaths: normalizedPaths(attachments.flatMap((attachment) => [
      attachment?.pathThumb,
      attachment?.pathOriginal
    ]))
  };
}

function existingMediaIdentityMatches(existingMessage, senderUID, kind) {
  const details = existingMediaDetails(existingMessage);
  return normalizeUID(existingMessage?.senderUID) === normalizeUID(senderUID) &&
    details.kind === kind;
}

export function validateExistingMediaPreflight({
  existingMessage,
  senderUID,
  kind,
  contract
}) {
  if (!existingMessage) return { ok: true, exists: false };
  const details = existingMediaDetails(existingMessage);
  if (
    typeof existingMessage.seq !== "number" ||
    !existingMediaIdentityMatches(existingMessage, senderUID, kind) ||
    details.attachments.length !== contract.attachmentCount ||
    details.storagePaths.length !== contract.expectedPathCount
  ) {
    return { ok: false, error: "media_message_conflict" };
  }
  return { ok: true, exists: true, seq: existingMessage.seq };
}

export function validateExistingMediaMessage({
  existingMessage,
  senderUID,
  kind,
  storagePaths
}) {
  if (!existingMessage) return { ok: true, exists: false };
  if (kind !== "images" && kind !== "video") {
    return { ok: false, error: "media_message_conflict" };
  }

  const details = existingMediaDetails(existingMessage);
  const requestedPaths = normalizedPaths(storagePaths);
  const pathsMatch = details.storagePaths.length === requestedPaths.length &&
    details.storagePaths.every((path, index) => path === requestedPaths[index]);

  if (
    typeof existingMessage.seq !== "number" ||
    !existingMediaIdentityMatches(existingMessage, senderUID, kind) ||
    !pathsMatch
  ) {
    return { ok: false, error: "media_message_conflict" };
  }

  return { ok: true, exists: true, seq: existingMessage.seq };
}

export function createMediaUploadService({
  db,
  admin,
  clock,
  directService,
  quarantineBucketName = "",
  loadQuarantineObject,
  deleteQuarantineObject,
  createQuarantineSignedUploadTarget,
  metadataConcurrency = 1,
  logger = console
}) {
  if (!Number.isInteger(metadataConcurrency) || metadataConcurrency < 1 || metadataConcurrency > 30) {
    throw new Error("CHAT_MEDIA_METADATA_CONCURRENCY must be 1...30");
  }
  const storagePrefix = (roomID, messageID) => `rooms/${roomID}/messages/${messageID}`;
  const reservationRef = (roomID, messageID) => db
    .collection("Rooms").doc(roomID).collection("MediaUploads").doc(messageID);
  const messageRef = (roomID, messageID) => db
    .collection("Rooms").doc(roomID).collection("Messages").doc(messageID);

  async function loadExistingMessage(roomID, messageID) {
    const snapshot = await messageRef(roomID, messageID).get();
    return snapshot.exists ? (snapshot.data() || {}) : null;
  }

  async function preflight({
    roomID,
    messageID,
    senderUID,
    kind,
    contract
  }) {
    const ref = reservationRef(roomID, messageID);
    const existing = await ref.get();
    const prefix = storagePrefix(roomID, messageID);
    const now = admin.firestore.FieldValue.serverTimestamp();
    const expiresAt = admin.firestore.Timestamp.fromDate(
      new Date(clock.nowMillis() + MEDIA_UPLOAD_RESERVATION_TTL_MS)
    );

    const existingResult = validateExistingMediaPreflight({
      existingMessage: await loadExistingMessage(roomID, messageID),
      senderUID,
      kind,
      contract
    });
    if (!existingResult.ok) {
      return { ok: false, error: existingResult.error };
    }
    if (existingResult.exists) {
      return { ok: true, duplicate: true, messageID, storagePrefix: prefix };
    }

    if (existing.exists) {
      const reservation = existing.data() || {};
      if (
        reservation.status === "pending" &&
        normalizeUID(reservation.senderUID) === senderUID &&
        reservation.kind === kind &&
        Number(reservation.attachmentCount) === contract.attachmentCount &&
        Number(reservation.expectedPathCount) === contract.expectedPathCount
      ) {
        await ref.set({ expiresAt, updatedAt: now }, { merge: true });
        return {
          ok: true,
          duplicate: true,
          status: "pending",
          messageID,
          storagePrefix: reservation.storagePrefix || prefix,
          attachmentCount: contract.attachmentCount,
          expectedPathCount: contract.expectedPathCount
        };
      }
      return { ok: false, error: "media_reservation_conflict" };
    }

    await ref.set({
      roomID,
      messageID,
      senderUID,
      kind,
      status: "pending",
      storagePrefix: prefix,
      attachmentCount: contract.attachmentCount,
      expectedPathCount: contract.expectedPathCount,
      createdAt: now,
      updatedAt: now,
      expiresAt
    });

    return {
      ok: true,
      status: "pending",
      messageID,
      storagePrefix: prefix,
      attachmentCount: contract.attachmentCount,
      expectedPathCount: contract.expectedPathCount
    };
  }

  async function assertReservation({
    roomID,
    messageID,
    senderUID,
    kind,
    attachmentCount,
    expectedPathCount,
    storagePaths
  }) {
    const ref = reservationRef(roomID, messageID);
    const snapshot = await ref.get();
    if (!snapshot.exists) return { ok: false, error: "media_reservation_not_found" };

    const data = snapshot.data() || {};
    if (data.status !== "pending") {
      return { ok: false, error: "media_reservation_not_pending" };
    }
    if (normalizeUID(data.senderUID) !== normalizeUID(senderUID)) {
      return { ok: false, error: "media_reservation_sender_mismatch" };
    }
    if (data.kind !== kind) return { ok: false, error: "media_reservation_kind_mismatch" };
    if (Number(data.attachmentCount) !== attachmentCount) {
      return { ok: false, error: "media_reservation_attachment_count_mismatch" };
    }
    if (Number(data.expectedPathCount) !== expectedPathCount) {
      return { ok: false, error: "media_reservation_path_count_mismatch" };
    }

    const expiresAtMillis = timestampMillis(data.expiresAt);
    if (expiresAtMillis && expiresAtMillis <= clock.nowMillis()) {
      return { ok: false, error: "media_reservation_expired" };
    }

    const prefix = String(data.storagePrefix || "");
    if (!prefix) return { ok: false, error: "media_reservation_missing_prefix" };
    const actualPaths = storagePaths.filter(Boolean).map(String);
    if (actualPaths.length !== expectedPathCount) {
      return { ok: false, error: "media_reservation_path_count_mismatch" };
    }
    if (!actualPaths.every((path) => path.startsWith(`${prefix}/`))) {
      return { ok: false, error: "media_reservation_prefix_mismatch" };
    }

    return { ok: true, ref, data };
  }

  async function preflightV2({
    roomID,
    uploadID,
    clientMutationID,
    senderUID,
    moderationPrincipalID,
    kind,
    contract,
    sources
  }) {
    if (!quarantineBucketName || typeof loadQuarantineObject !== "function" ||
        typeof deleteQuarantineObject !== "function" ||
        typeof createQuarantineSignedUploadTarget !== "function") {
      return { ok: false, error: "media_v2_not_configured" };
    }
    const sourceValidation = validateMediaSourceDescriptors(kind, contract, sources);
    if (!sourceValidation.ok) return sourceValidation;
    const ref = reservationRef(roomID, uploadID);
    const uploadPath = ref.path;
    const attachmentIDs = Array.from(
      { length: contract.attachmentCount },
      (_, index) => stableAttachmentID(uploadID, index, kind)
    );
    const quarantinePaths = attachmentIDs.map((attachmentID) =>
      `${roomID}/${senderUID}/${uploadID}/${attachmentID}/source`
    );
    const uploadSources = sourceValidation.descriptors.map((descriptor, sourceIndex) => ({
        attachmentID: attachmentIDs[sourceIndex],
        sourceIndex,
        path: quarantinePaths[sourceIndex],
        contentType: descriptor.contentType,
        sizeBytes: descriptor.sizeBytes,
        sha256: descriptor.sha256,
        completedGeneration: null
      }));
    const nowMillis = clock.nowMillis();
    const uploadExpiresAt = admin.firestore.Timestamp.fromDate(
      new Date(nowMillis + MEDIA_V2_UPLOAD_TTL_MS)
    );

    const reservationResult = await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(ref);
      if (existing.exists) {
        const data = existing.data() || {};
        if (
          data.contractVersion === 2 &&
          data.clientMutationID === clientMutationID &&
          normalizeUID(data.senderUID) === normalizeUID(senderUID) &&
          data.moderationPrincipalID === moderationPrincipalID &&
          data.kind === kind &&
          Number(data.attachmentCount) === contract.attachmentCount
        ) {
          return {
            ok: true,
            duplicate: true,
            contractVersion: 2,
            uploadID,
            processingStatus: data.processingStatus,
            attachmentIDs: Array.isArray(data.attachmentIDs)
              ? data.attachmentIDs
              : attachmentIDs,
            quarantinePaths: Array.isArray(data.quarantinePaths)
              ? data.quarantinePaths
              : quarantinePaths,
            expiresAt: data.uploadExpiresAt || uploadExpiresAt,
            sourceDescriptors: Array.isArray(data.sourceDescriptors) ?
              data.sourceDescriptors : sourceValidation.descriptors,
            uploadSources: Array.isArray(data.uploadSources) ? data.uploadSources : uploadSources
          };
        }
        return { ok: false, error: "media_reservation_conflict" };
      }

      // 사용자 실행 제한과 요청 identity 보호를 분리한다.
      const receiptID = createHash("sha256")
        .update(JSON.stringify([moderationPrincipalID, kind, clientMutationID]))
        .digest("hex");
      const receiptRef = db.collection("chatMediaReservationReceipts").doc(receiptID);
      const receipt = await transaction.get(receiptRef);
      if (receipt.exists) {
        return { ok: false, error: "media_client_mutation_conflict" };
      }
      transaction.set(receiptRef, {
        uploadPath,
        // 24시간 업로드 + 6시간 처리 + terminal 7일보다 먼저 지우지 않는다.
        expiresAt: admin.firestore.Timestamp.fromDate(new Date(nowMillis + 9 * 24 * 60 * 60 * 1000))
      });
      transaction.set(ref, {
        schemaVersion: 1,
        contractVersion: 2,
        roomID,
        uploadID,
        messageID: uploadID,
        clientMutationID,
        senderUID,
        moderationPrincipalID,
        kind,
        attachmentCount: contract.attachmentCount,
        expectedPathCount: contract.expectedPathCount,
        attachmentIDs,
        quarantineBucket: quarantineBucketName,
        quarantinePaths,
        sourceDescriptors: sourceValidation.descriptors,
        uploadSources,
        processingStatus: "uploading",
        processingAttempt: 0,
        dispatchGeneration: 0,
        retryable: true,
        failureCode: null,
        leaseToken: null,
        leaseExpiresAt: null,
        executionName: null,
        processingSlotID: null,
        nextAttemptAt: null,
        normalizedManifest: null,
        cleanupStatus: "none",
        uploadExpiresAt,
        processingDeadlineAt: null,
        expiresAt: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      return {
        ok: true,
        contractVersion: 2,
        uploadID,
        processingStatus: "uploading",
        attachmentIDs,
        quarantinePaths,
        expiresAt: uploadExpiresAt,
        sourceDescriptors: sourceValidation.descriptors,
        uploadSources
      };
    });
    if (!reservationResult.ok) return reservationResult;
    return refreshUploadTargetsV2({
      roomID,
      uploadID,
      clientMutationID,
      senderUID,
      moderationPrincipalID,
      reservationResult
    });
  }

  async function refreshUploadTargetsV2({
    roomID,
    uploadID,
    clientMutationID,
    senderUID,
    moderationPrincipalID,
    reservationResult = null
  }) {
    const ref = reservationRef(roomID, uploadID);
    const snapshot = await ref.get();
    if (!snapshot.exists) return {ok: false, error: "media_reservation_not_found"};
    const data = snapshot.data() || {};
    if (data.contractVersion !== 2 || data.clientMutationID !== clientMutationID ||
        normalizeUID(data.senderUID) !== normalizeUID(senderUID) ||
        data.moderationPrincipalID !== moderationPrincipalID) {
      return {ok: false, error: "media_reservation_conflict"};
    }
    if (data.processingStatus !== "uploading") {
      return {
        ok: true,
        contractVersion: 2,
        uploadID,
        processingStatus: data.processingStatus,
        completedParts: [],
        uploads: [],
        expiresAtMillis: timestampMillis(data.uploadExpiresAt)
      };
    }
    const nowMillis = clock.nowMillis();
    if ((timestampMillis(data.uploadExpiresAt) || 0) <= nowMillis) {
      return {ok: false, error: "media_reservation_expired"};
    }
    const sources = Array.isArray(data.uploadSources) ? data.uploadSources : [];
    if (sources.length !== Number(data.attachmentCount || 0)) {
      return {ok: false, error: "media_upload_sources_invalid"};
    }
    const completedParts = [];
    const uploads = [];
    for (const rawSource of sources) {
      const source = normalizedStoredSource(rawSource);
      if (!source) return {ok: false, error: "media_upload_sources_invalid"};
      let metadata = null;
      try {
        metadata = await loadQuarantineObject(source.path);
      } catch (error) {
        if (!isObjectNotFound(error)) throw error;
      }
      if (metadata) {
        if (!uploadSourceMetadataMatches(source, metadata)) {
          return {ok: false, error: "media_upload_source_conflict"};
        }
        completedParts.push(publicCompletedSource(source, metadata));
        continue;
      }
      try {
        const target = await createQuarantineSignedUploadTarget({
          ...source,
          uploadID,
          expiresAtMillis: timestampMillis(data.uploadExpiresAt)
        });
        uploads.push(publicUploadTarget(source, target));
      } catch {
        return {ok: false, error: "media_upload_target_create_failed"};
      }
    }
    return {
      ...(reservationResult || {}),
      ok: true,
      contractVersion: 2,
      uploadID,
      processingStatus: "uploading",
      attachmentIDs: Array.isArray(data.attachmentIDs) ? data.attachmentIDs : [],
      quarantinePaths: Array.isArray(data.quarantinePaths) ? data.quarantinePaths : [],
      completedParts,
      uploads,
      expiresAtMillis: timestampMillis(data.uploadExpiresAt)
    };
  }

  async function finalizeV2({
    roomID,
    uploadID,
    clientMutationID,
    senderUID,
    moderationPrincipalID
  }) {
    const ref = reservationRef(roomID, uploadID);
    const snapshot = await ref.get();
    if (!snapshot.exists) return { ok: false, error: "media_reservation_not_found" };
    const reservation = snapshot.data() || {};
    const identityMatches = reservation.contractVersion === 2 &&
      reservation.clientMutationID === clientMutationID &&
      normalizeUID(reservation.senderUID) === normalizeUID(senderUID) &&
      reservation.moderationPrincipalID === moderationPrincipalID;
    if (!identityMatches) return { ok: false, error: "media_reservation_conflict" };
    if (["queued", "processing", "ready"].includes(reservation.processingStatus)) {
      return {
        ok: true,
        duplicate: true,
        contractVersion: 2,
        uploadID,
        processingStatus: reservation.processingStatus,
        messageID: reservation.processingStatus === "ready" ? uploadID : null,
        seq: typeof reservation.seq === "number" ? reservation.seq : null,
        retryable: reservation.retryable === true
      };
    }
    if (reservation.processingStatus !== "uploading") {
      return { ok: false, error: `media_${reservation.processingStatus || "invalid_state"}` };
    }
    if ((timestampMillis(reservation.uploadExpiresAt) || 0) <= clock.nowMillis()) {
      return { ok: false, error: "media_reservation_expired" };
    }

    const descriptors = Array.isArray(reservation.sourceDescriptors) ?
      reservation.sourceDescriptors : [];
    const attachmentIDs = Array.isArray(reservation.attachmentIDs) ?
      reservation.attachmentIDs : [];
    const quarantinePaths = Array.isArray(reservation.quarantinePaths) ?
      reservation.quarantinePaths : [];
    const storedSources = Array.isArray(reservation.uploadSources) ?
      reservation.uploadSources.map(normalizedStoredSource) : [];
    if (descriptors.length !== Number(reservation.attachmentCount) ||
        attachmentIDs.length !== descriptors.length ||
        quarantinePaths.length !== descriptors.length ||
        storedSources.length !== descriptors.length ||
        storedSources.some((source) => !source)) {
      return {ok: false, error: "media_upload_sources_invalid"};
    }

    const verificationStartedAt = Date.now();
    const objects = await boundedMap(descriptors, metadataConcurrency, async (descriptor, index) => {
      try { return await loadQuarantineObject(quarantinePaths[index]); }
      catch (error) { if (isObjectNotFound(error)) return null; throw error; }
    });
    logger.info?.(JSON.stringify({event: "media_finalize_metadata", uploadID, count: descriptors.length,
      concurrency: metadataConcurrency, durationMs: Date.now() - verificationStartedAt}));
    const verified = [];
    let aggregateBytes = 0;
    let missing = false;
    for (let sourceIndex = 0; sourceIndex < descriptors.length; sourceIndex += 1) {
      const descriptor = descriptors[sourceIndex];
      const destinationPath = quarantinePaths[sourceIndex];
      const source = storedSources[sourceIndex];
      const metadata = objects[sourceIndex];
      if (source.path !== destinationPath || source.attachmentID !== attachmentIDs[sourceIndex]) {
        return {ok: false, error: "media_upload_sources_invalid"};
      }
      if (!metadata) { missing = true; continue; }
      if (!uploadSourceMetadataMatches(source, metadata) || !sourceMetadataMatches(descriptor, metadata)) {
        return {ok: false, error: "media_object_metadata_mismatch"};
      }
      aggregateBytes += descriptor.sizeBytes;
      verified.push({
        attachmentID: attachmentIDs[sourceIndex],
        path: destinationPath,
        generation: String(metadata.generation),
        sizeBytes: descriptor.sizeBytes,
        contentType: descriptor.contentType,
        sha256: descriptor.sha256
      });
    }
    if (missing) return {ok: false, error: "media_upload_incomplete"};
    if (reservation.kind === "images" && aggregateBytes > MEDIA_V2_MAX_IMAGE_AGGREGATE_BYTES) {
      return {ok: false, error: "media_aggregate_too_large"};
    }

    const processingDeadlineAt = admin.firestore.Timestamp.fromDate(
      new Date(clock.nowMillis() + MEDIA_V2_PROCESSING_DEADLINE_MS)
    );

    return db.runTransaction(async (transaction) => {
      const current = await transaction.get(ref);
      const data = current.data() || {};
      if (!current.exists || data.contractVersion !== 2 ||
          data.clientMutationID !== clientMutationID ||
          data.moderationPrincipalID !== moderationPrincipalID) {
        return { ok: false, error: "media_reservation_conflict" };
      }
      if (["queued", "processing", "ready"].includes(data.processingStatus)) {
        return {
          ok: true,
          duplicate: true,
          contractVersion: 2,
          uploadID,
          processingStatus: data.processingStatus,
          messageID: data.processingStatus === "ready" ? uploadID : null,
          seq: typeof data.seq === "number" ? data.seq : null,
          retryable: data.retryable === true
        };
      }
      if (data.processingStatus !== "uploading") {
        return { ok: false, error: "media_reservation_not_uploading" };
      }
      const principalSlotRef = typeof data.principalSlotID === "string" ?
        db.collection("chatMediaPrincipalUploadSlots").doc(data.principalSlotID) : null;
      const principalSlot = principalSlotRef ? await transaction.get(principalSlotRef) : null;
      if (principalSlotRef && principalSlot?.data()?.ownerUploadPath === ref.path) {
        transaction.set(principalSlotRef, {
          leaseExpiresAt: processingDeadlineAt,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, {merge: true});
      }
      transaction.update(ref, {
        processingStatus: "queued",
        dispatchGeneration: 1,
        sourceManifest: verified,
        sourceAggregateBytes: aggregateBytes,
        processingDeadlineAt,
        nextAttemptAt: admin.firestore.Timestamp.fromDate(new Date(clock.nowMillis())),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      return {
        ok: true,
        duplicate: false,
        contractVersion: 2,
        uploadID,
        processingStatus: "queued",
        messageID: null,
        seq: null,
        retryable: true
      };
    });
  }

  async function statusV2({
    roomID,
    uploadID,
    clientMutationID,
    senderUID,
    moderationPrincipalID
  }) {
    const snapshot = await reservationRef(roomID, uploadID).get();
    if (!snapshot.exists) return { ok: false, error: "media_reservation_not_found" };
    const data = snapshot.data() || {};
    if (data.contractVersion !== 2 || data.clientMutationID !== clientMutationID ||
        normalizeUID(data.senderUID) !== normalizeUID(senderUID) ||
        data.moderationPrincipalID !== moderationPrincipalID) {
      return { ok: false, error: "media_reservation_conflict" };
    }
    return {
      ok: true,
      contractVersion: 2,
      uploadID,
      processingStatus: data.processingStatus,
      messageID: data.processingStatus === "ready" ? uploadID : null,
      seq: typeof data.seq === "number" ? data.seq : null,
      retryable: data.retryable === true,
      failureCode: typeof data.failureCode === "string" ? data.failureCode : null
    };
  }

  async function cancelV2(input) {
    const ref = reservationRef(input.roomID, input.uploadID);
    const nowMillis = clock.nowMillis();
    const outcome = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      const data = snapshot.data() || {};
      if (!snapshot.exists) {
        const message = await transaction.get(db.collection("Rooms").doc(input.roomID)
          .collection("Messages").doc(input.uploadID));
        if (message.exists) {
          if (normalizeUID(message.data()?.senderUID) !== normalizeUID(input.senderUID)) {
            return {ok: false, error: "media_reservation_conflict"};
          }
          return {ok: true, processingStatus: "ready", uploadID: input.uploadID,
            messageID: input.uploadID, seq: message.data()?.seq ?? null};
        }
        const member = await transaction.get(db.collection("Rooms").doc(input.roomID)
          .collection("members").doc(input.senderUID));
        if (!member.exists) return {ok: false, error: "media_reservation_conflict"};
        // 예약 응답 유실/늦은 preflight를 취소 tombstone으로 차단한다.
        transaction.set(ref, {
          schemaVersion: 1, contractVersion: 2, roomID: input.roomID,
          uploadID: input.uploadID, clientMutationID: input.clientMutationID,
          senderUID: input.senderUID, moderationPrincipalID: input.moderationPrincipalID,
          processingStatus: "canceled", retryable: false, cleanupStatus: "completed",
          terminalAt: admin.firestore.Timestamp.fromDate(new Date(nowMillis)),
          expiresAt: admin.firestore.Timestamp.fromDate(new Date(nowMillis + MEDIA_V2_TERMINAL_TTL_MS))
        });
        return {ok: true, duplicate: true, processingStatus: "canceled", uploadID: input.uploadID, paths: []};
      }
      if (data.contractVersion !== 2 ||
          data.clientMutationID !== input.clientMutationID ||
          normalizeUID(data.senderUID) !== normalizeUID(input.senderUID) ||
          data.moderationPrincipalID !== input.moderationPrincipalID) {
        return { ok: false, error: "media_reservation_conflict" };
      }
      if (data.processingStatus === "ready") {
        return { ok: true, duplicate: true, processingStatus: "ready", paths: [] };
      }
      if (["canceled", "failed", "expired"].includes(data.processingStatus)) {
        return { ok: true, duplicate: true, processingStatus: data.processingStatus, paths: [] };
      }
      const principalSlotRef = typeof data.principalSlotID === "string"
        ? db.collection("chatMediaPrincipalUploadSlots").doc(data.principalSlotID)
        : null;
      const processingSlotRef = typeof data.processingSlotID === "string"
        ? db.collection("chatMediaProcessingSlots").doc(data.processingSlotID)
        : null;
      const principalSlot = principalSlotRef
        ? await transaction.get(principalSlotRef)
        : null;
      const processingSlot = processingSlotRef
        ? await transaction.get(processingSlotRef)
        : null;
      if (principalSlotRef && principalSlot?.data()?.ownerUploadPath === ref.path) {
        transaction.set(principalSlotRef, {
          ownerUploadPath: null,
          clientMutationID: null,
          leaseExpiresAt: null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
      }
      if (processingSlotRef && data.leaseToken &&
          processingSlot?.data()?.leaseToken === data.leaseToken) {
        transaction.set(processingSlotRef, {
          leaseToken: null,
          leaseOwnerUploadPath: null,
          leaseExpiresAt: null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
      }
      transaction.update(ref, {
        processingStatus: "canceled",
        retryable: false,
        failureCode: "canceled_by_sender",
        leaseToken: null,
        leaseExpiresAt: null,
        processingSlotID: null,
        executionName: null,
        nextAttemptAt: null,
        cleanupStatus: "pending",
        terminalAt: admin.firestore.Timestamp.fromDate(new Date(nowMillis)),
        expiresAt: admin.firestore.Timestamp.fromDate(
          new Date(nowMillis + MEDIA_V2_TERMINAL_TTL_MS)
        ),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      return {
        ok: true,
        duplicate: false,
        processingStatus: "canceled",
        paths: [...new Set([
          ...(Array.isArray(data.quarantinePaths) ? data.quarantinePaths : [])
        ].filter(Boolean))],
        readyCleanupRequired: Array.isArray(data.normalizedManifest) &&
          data.normalizedManifest.length > 0
      };
    });
    if (!outcome.ok || outcome.processingStatus !== "canceled" || outcome.duplicate) {
      return outcome;
    }
    try {
      await Promise.all(outcome.paths.map((path) => deleteQuarantineObject(path)));
      await ref.set({
        cleanupStatus: outcome.readyCleanupRequired ? "pending" : "completed",
        ...(outcome.readyCleanupRequired ? {} : {
          cleanupCompletedAt: admin.firestore.FieldValue.serverTimestamp()
        }),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
    } catch {
      await ref.set({
        cleanupStatus: "failed",
        cleanupFailureCode: "quarantine_delete_failed",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
    }
    return {
      ok: true,
      duplicate: false,
      contractVersion: 2,
      uploadID: input.uploadID,
      processingStatus: "canceled",
      messageID: null,
      seq: null
    };
  }

  // 실제 남아 있는 구 예약만 복구하며 신규 요청은 직접 업로드 계약을 사용한다.
  const routeExisting = (modern, legacy) => async args => {
    if (!directService) return legacy(args);
    const old = (await reservationRef(args.roomID, args.uploadID).get()).data();
    return old?.contractVersion === 2 ? legacy(args) : directService[modern](args);
  };
  return {
    assertReservation,
    loadExistingMessage,
    preflight,
    preflightV2,
    preflightDirect: args => directService.preflight(args),
    finalizeDirect: args => directService.finalize(args),
    refreshUploadTargetsV2: routeExisting("refresh", refreshUploadTargetsV2),
    finalizeV2,
    statusV2: routeExisting("status", statusV2),
    cancelV2: routeExisting("cancel", cancelV2)
  };
}

function normalizedStoredSource(entry) {
  const value = {
    attachmentID: String(entry?.attachmentID || ""),
    sourceIndex: Number(entry?.sourceIndex),
    path: String(entry?.path || ""),
    contentType: String(entry?.contentType || "").toLowerCase(),
    sizeBytes: Number(entry?.sizeBytes),
    sha256: String(entry?.sha256 || "").toLowerCase()
  };
  if (!value.attachmentID || !Number.isInteger(value.sourceIndex) || value.sourceIndex < 0 ||
      !value.path || !value.contentType ||
      !Number.isInteger(value.sizeBytes) || value.sizeBytes <= 0 ||
      !validSHA256(value.sha256)) return null;
  return value;
}

function objectMetadataValue(metadata, key) {
  const values = metadata?.metadata || {};
  const kebabKey = key.replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();
  return String(values[key] || values[key.toLowerCase()] || values[kebabKey] || "")
    .toLowerCase();
}

function uploadSourceMetadataMatches(source, metadata) {
  return Boolean(metadata?.generation) &&
    Number(metadata?.sizeBytes) === source.sizeBytes &&
    String(metadata?.contentType || "").toLowerCase() === source.contentType &&
    objectMetadataValue(metadata, "sha256") === source.sha256 &&
    objectMetadataValue(metadata, "attachmentID") === source.attachmentID.toLowerCase();
}

function sourceMetadataMatches(descriptor, metadata) {
  return Boolean(metadata?.generation) &&
    Number(metadata?.sizeBytes) === Number(descriptor?.sizeBytes) &&
    String(metadata?.contentType || "").toLowerCase() ===
      String(descriptor?.contentType || "").toLowerCase() &&
    objectMetadataValue(metadata, "sha256") === String(descriptor?.sha256 || "").toLowerCase();
}

function isObjectNotFound(error) {
  return Number(error?.code) === 404 || Number(error?.statusCode) === 404;
}

function publicCompletedSource(source, metadata) {
  return {
    attachmentID: source.attachmentID,
    sourceIndex: source.sourceIndex,
    path: source.path,
    generation: String(metadata?.generation || ""),
    sizeBytes: source.sizeBytes,
    sha256: source.sha256
  };
}

function publicUploadTarget(source, target) {
  return {
    attachmentID: source.attachmentID,
    sourceIndex: source.sourceIndex,
    path: source.path,
    signedURL: String(target?.signedURL || ""),
    method: "PUT",
    requiredHeaders: target?.requiredHeaders || {},
    contentType: source.contentType,
    sizeBytes: source.sizeBytes,
    sha256: source.sha256
  };
}
