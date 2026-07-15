import {
  MAX_IMAGES_PER_MESSAGE,
  MAX_THUMB_PAYLOAD_BYTES,
  RATE_MAX_IMAGES,
  RATE_MAX_VIDEOS,
  RATE_WINDOW_MS
} from "../config.js";
import {
  buildServerImageMessage,
  buildServerVideoMessage,
  enforceThumbBudget,
  normalizeImageAttachment,
  sanitizeImageItem,
  withDerivedImageURLs
} from "../media/mediaPayload.js";
import {
  normalizeMediaKind,
  validateExistingMediaMessage,
  validateMediaUploadContract
} from "../media/mediaUploadService.js";
import { normalizeEmail, normalizeUID } from "../utils/strings.js";

export function registerMediaHandlers({
  socket,
  io,
  isValidRoomID,
  authorizeSocketRoom,
  allowRate,
  generateMessageID,
  clock,
  mediaUploadService,
  allocateSeqAndPersist,
  messageDeliverySingleFlight,
  fanoutChatPush,
  imageCdnBase,
  logger = console
}) {
  socket.on("chat:mediaPreflight", async (data, callback) => {
    try {
      const { roomID, messageID, kind, attachmentCount, expectedPathCount } = data || {};
      if (!roomID || !isValidRoomID(String(roomID))) {
        return callback?.({ ok: false, error: "invalid_room_id" });
      }
      if (!messageID || String(messageID).includes("/")) {
        return callback?.({ ok: false, error: "invalid_message_id" });
      }

      const mediaKind = normalizeMediaKind(kind);
      if (!mediaKind) return callback?.({ ok: false, error: "invalid_media_kind" });
      const contract = validateMediaUploadContract(
        mediaKind,
        attachmentCount,
        expectedPathCount
      );
      if (!contract.ok) return callback?.({ ok: false, error: contract.error });

      const senderUID = normalizeUID(socket.userUID);
      const senderEmail = normalizeEmail(socket.userEmail);
      const access = await authorizeSocketRoom({
        socket,
        roomID,
        senderUID,
        context: "chat:mediaPreflight"
      });
      if (!access.ok) return callback?.({ ok: false, error: access.error });

      const rateKey = `${socket.id}:${roomID}:mediaPreflight:${mediaKind}`;
      const rateMax = mediaKind === "video" ? RATE_MAX_VIDEOS : RATE_MAX_IMAGES;
      if (!allowRate(rateKey, rateMax, RATE_WINDOW_MS)) {
        return callback?.({ ok: false, error: "rate_limited" });
      }

      const result = await mediaUploadService.preflight({
        roomID,
        messageID: String(messageID),
        senderUID,
        senderEmail,
        kind: mediaKind,
        contract
      });
      return callback?.(result);
    } catch (error) {
      logger.error("[chat:mediaPreflight] handler error:", error);
      return callback?.({ ok: false, error: "internal_error" });
    }
  });

  async function finalizeImages(data, callback) {
    try {
      const {
        roomID,
        messageID,
        clientMessageID,
        attachments,
        images,
        senderNickname,
        senderNickName,
        senderAvatarPath,
        sentAt,
        msg
      } = data || {};

      if (!roomID) return callback?.({ ok: false, error: "invalid_room_id" });
      const senderUID = normalizeUID(socket.userUID);
      const senderEmail = normalizeEmail(socket.userEmail);
      const roomAccess = await authorizeSocketRoom({
        socket,
        roomID,
        senderUID,
        context: "chat:mediaFinalize/images"
      });
      if (!roomAccess.ok) return callback?.({ ok: false, error: roomAccess.error });

      const incoming = Array.isArray(attachments)
        ? attachments
        : (Array.isArray(images) ? images : []);
      if (incoming.length === 0) return callback?.({ ok: false, error: "no_images" });
      if (incoming.length > MAX_IMAGES_PER_MESSAGE) {
        return callback?.({ ok: false, error: "invalid_attachment_count" });
      }
      if (!allowRate(`${socket.id}:${roomID}:images`, RATE_MAX_IMAGES, RATE_WINDOW_MS)) {
        return callback?.({ ok: false, error: "rate_limited" });
      }

      const effectiveMessageID = (messageID && String(messageID)) ||
        (clientMessageID && String(clientMessageID)) ||
        generateMessageID();

      const prepared = Array.isArray(attachments)
        ? incoming
        : incoming
          .map(sanitizeImageItem)
          .map((item) => withDerivedImageURLs(item, imageCdnBase));
      const { images: budgeted, thumbTrimmed } = enforceThumbBudget(
        prepared,
        MAX_THUMB_PAYLOAD_BYTES
      );
      const normalized = budgeted.map((item, index) => normalizeImageAttachment({
        index: item.index ?? index,
        pathThumb: item.pathThumb ?? item.thumbUrl ?? item.thumbURL,
        pathOriginal: item.pathOriginal ?? item.originalUrl ?? item.originalURL ??
          item.storagePath ?? item.url,
        w: item.w ?? item.width,
        h: item.h ?? item.height,
        bytesOriginal: item.bytesOriginal ?? item.size,
        hash: item.hash,
        blurhash: item.blurhash
      }, index)).filter((attachment) => attachment.pathThumb || attachment.pathOriginal);

      if (normalized.length === 0) {
        return callback?.({ ok: false, error: "no_valid_attachments" });
      }

      const storagePaths = normalized.flatMap((attachment) => [
        attachment.pathThumb,
        attachment.pathOriginal
      ]);
      const contract = validateMediaUploadContract(
        "images",
        normalized.length,
        storagePaths.filter(Boolean).length
      );
      if (!contract.ok) {
        return callback?.({ ok: false, error: contract.error });
      }

      const existingResult = validateExistingMediaMessage({
        existingMessage: await mediaUploadService.loadExistingMessage(
          roomID,
          effectiveMessageID
        ),
        senderUID,
        kind: "images",
        storagePaths
      });
      if (!existingResult.ok) {
        return callback?.({ ok: false, error: existingResult.error });
      }
      if (existingResult.exists) {
        return callback?.({
          ok: true,
          duplicate: true,
          messageID: effectiveMessageID,
          seq: existingResult.seq,
          thumbTrimmed
        });
      }

      const reservation = await mediaUploadService.assertReservation({
        roomID,
        messageID: effectiveMessageID,
        senderUID,
        kind: "images",
        attachmentCount: contract.attachmentCount,
        expectedPathCount: contract.expectedPathCount,
        storagePaths
      });
      if (!reservation.ok) {
        const completedResult = validateExistingMediaMessage({
          existingMessage: await mediaUploadService.loadExistingMessage(
            roomID,
            effectiveMessageID
          ),
          senderUID,
          kind: "images",
          storagePaths
        });
        if (!completedResult.ok) {
          return callback?.({ ok: false, error: completedResult.error });
        }
        if (completedResult.exists) {
          return callback?.({
            ok: true,
            duplicate: true,
            messageID: effectiveMessageID,
            seq: completedResult.seq,
            thumbTrimmed
          });
        }
        return callback?.({ ok: false, error: reservation.error });
      }

      const when = (() => {
        try {
          if (!sentAt) return clock.nowDate();
          if (typeof sentAt === "string") return new Date(sentAt);
          if (typeof sentAt === "number") {
            return new Date(sentAt > 3e9 ? sentAt : sentAt * 1000);
          }
          return clock.nowDate();
        } catch {
          return clock.nowDate();
        }
      })();
      const serverMessage = buildServerImageMessage({
        roomID,
        messageID: effectiveMessageID,
        msg: typeof msg === "string" ? msg : "",
        attachments: normalized,
        senderUID,
        senderEmail,
        senderNickname: senderNickname || senderNickName || "",
        senderAvatarPath,
        sentAt: when.toISOString()
      }, clock.nowDate());

      let delivery;
      try {
        delivery = await messageDeliverySingleFlight.run({
          kind: "images",
          roomID,
          messageID: effectiveMessageID
        }, async () => {
          const outcome = await allocateSeqAndPersist(
            roomID,
            effectiveMessageID,
            serverMessage,
            { mediaUploadRef: reservation.ref }
          );
          if (outcome.created) {
            const persistedMessage = { ...serverMessage, seq: outcome.seq };
            io.to(roomID).emit("receiveImages", persistedMessage);
            void fanoutChatPush({ roomID, messageData: persistedMessage });
          }
          return outcome;
        });
      } catch (error) {
        logger.error("[chat:mediaFinalize/images] seq allocation/persist error:", error);
        return callback?.({ ok: false, error: "seq_persist_error" });
      }

      return callback?.({
        ok: true,
        duplicate: delivery.duplicate || !delivery.value.created,
        messageID: effectiveMessageID,
        seq: delivery.value.seq,
        thumbTrimmed
      });
    } catch (error) {
      logger.error("[chat:mediaFinalize/images] handler error:", error);
      return callback?.({ ok: false, error: "internal_error" });
    }
  }

  async function finalizeVideo(data, callback) {
    try {
      const {
        roomID,
        messageID,
        storagePath,
        thumbnailPath,
        duration,
        width,
        height,
        sizeBytes,
        approxBitrateMbps,
        preset,
        senderNickname,
        senderNickName,
        senderAvatarPath,
        sentAt,
        msg
      } = data || {};

      if (!roomID) return callback?.({ ok: false, error: "invalid_room_id" });
      const senderUID = normalizeUID(socket.userUID);
      const senderEmail = normalizeEmail(socket.userEmail);
      const roomAccess = await authorizeSocketRoom({
        socket,
        roomID,
        senderUID,
        context: "chat:mediaFinalize/video"
      });
      if (!roomAccess.ok) return callback?.({ ok: false, error: roomAccess.error });
      if (!allowRate(`${socket.id}:${roomID}:video`, RATE_MAX_VIDEOS, RATE_WINDOW_MS)) {
        return callback?.({ ok: false, error: "rate_limited" });
      }

      const effectiveMessageID = (messageID && String(messageID)) || generateMessageID();

      const storagePaths = [storagePath, thumbnailPath];
      const contract = validateMediaUploadContract(
        "video",
        1,
        storagePaths.filter(Boolean).length
      );
      if (!contract.ok) {
        return callback?.({ ok: false, error: contract.error });
      }

      const existingResult = validateExistingMediaMessage({
        existingMessage: await mediaUploadService.loadExistingMessage(
          roomID,
          effectiveMessageID
        ),
        senderUID,
        kind: "video",
        storagePaths
      });
      if (!existingResult.ok) {
        return callback?.({ ok: false, error: existingResult.error });
      }
      if (existingResult.exists) {
        return callback?.({
          ok: true,
          duplicate: true,
          messageID: effectiveMessageID,
          seq: existingResult.seq
        });
      }

      const reservation = await mediaUploadService.assertReservation({
        roomID,
        messageID: effectiveMessageID,
        senderUID,
        kind: "video",
        attachmentCount: contract.attachmentCount,
        expectedPathCount: contract.expectedPathCount,
        storagePaths
      });
      if (!reservation.ok) {
        const completedResult = validateExistingMediaMessage({
          existingMessage: await mediaUploadService.loadExistingMessage(
            roomID,
            effectiveMessageID
          ),
          senderUID,
          kind: "video",
          storagePaths
        });
        if (!completedResult.ok) {
          return callback?.({ ok: false, error: completedResult.error });
        }
        if (completedResult.exists) {
          return callback?.({
            ok: true,
            duplicate: true,
            messageID: effectiveMessageID,
            seq: completedResult.seq
          });
        }
        return callback?.({ ok: false, error: reservation.error });
      }

      const serverMessage = buildServerVideoMessage({
        roomID,
        messageID: effectiveMessageID,
        msg: typeof msg === "string" ? msg : "",
        attachments: [{
          pathOriginal: storagePath,
          pathThumb: thumbnailPath,
          width,
          height,
          sizeBytes,
          duration,
          approxBitrateMbps,
          preset
        }],
        senderUID,
        senderEmail,
        senderNickname: senderNickname || senderNickName || "",
        senderAvatarPath,
        sentAt
      }, clock.nowDate());

      let delivery;
      try {
        delivery = await messageDeliverySingleFlight.run({
          kind: "video",
          roomID,
          messageID: effectiveMessageID
        }, async () => {
          const outcome = await allocateSeqAndPersist(
            roomID,
            effectiveMessageID,
            serverMessage,
            { mediaUploadRef: reservation.ref }
          );
          if (outcome.created) {
            const persistedMessage = { ...serverMessage, seq: outcome.seq };
            io.to(roomID).emit("receiveVideo", persistedMessage);
            void fanoutChatPush({ roomID, messageData: persistedMessage });
          }
          return outcome;
        });
      } catch (error) {
        logger.error("[chat:mediaFinalize/video] seq allocation/persist error:", error);
        return callback?.({ ok: false, error: "seq_persist_error" });
      }

      return callback?.({
        ok: true,
        duplicate: delivery.duplicate || !delivery.value.created,
        messageID: effectiveMessageID,
        seq: delivery.value.seq
      });
    } catch (error) {
      logger.error("[chat:mediaFinalize/video] handler error:", error);
      return callback?.({ ok: false, error: "internal_error" });
    }
  }

  async function handleMediaFinalize(data, callback, forcedKind) {
    const mediaKind = normalizeMediaKind(
      forcedKind || data?.kind || data?.mediaKind || data?.type
    );
    if (mediaKind === "images") return finalizeImages(data, callback);
    if (mediaKind === "video") return finalizeVideo(data, callback);
    return callback?.({ ok: false, error: "invalid_media_kind" });
  }

  socket.on("chat:mediaFinalize", async (data, callback) => {
    return handleMediaFinalize(data, callback);
  });
}
