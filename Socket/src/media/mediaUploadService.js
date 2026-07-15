import { MAX_IMAGES_PER_MESSAGE } from "../config.js";
import { normalizeUID } from "../utils/strings.js";

const MEDIA_UPLOAD_RESERVATION_TTL_MS = 24 * 60 * 60 * 1000;

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

export function createMediaUploadService({ db, admin, clock }) {
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
    senderEmail,
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
      ...(senderEmail ? { senderEmail } : {}),
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

  return { assertReservation, loadExistingMessage, preflight };
}
