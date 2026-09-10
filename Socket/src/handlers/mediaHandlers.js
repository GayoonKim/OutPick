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
  validateMediaUploadContract,
  validateMediaUploadContractV2
} from "../media/mediaUploadService.js";
import { normalizeUID } from "../utils/strings.js";
import { rejectMissingCapability } from "../moderation/capabilities.js";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isValidClientMutationID(value) {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

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
    if (rejectMissingCapability(socket, "createUGC", callback)) return;
    try {
      const {
        roomID,
        messageID,
        uploadID,
        clientMutationID,
        contractVersion,
        kind,
        attachmentCount,
        expectedPathCount,
        sources
      } = data || {};
      if (!roomID || !isValidRoomID(String(roomID))) {
        return callback?.({ ok: false, error: "invalid_room_id" });
      }
      const effectiveUploadID = uploadID || messageID;
      if (!effectiveUploadID || String(effectiveUploadID).includes("/")) {
        return callback?.({ ok: false, error: "invalid_message_id" });
      }

      const mediaKind = normalizeMediaKind(kind);
      if (!mediaKind) return callback?.({ ok: false, error: "invalid_media_kind" });
      const isV2 = Number(contractVersion) === 2;
      const isDirect = Number(contractVersion) === 3;
      if ((isV2 || isDirect) && !isValidClientMutationID(String(clientMutationID || ""))) {
        return callback?.({ ok: false, error: "invalid_client_mutation_id" });
      }
      const contract = (isV2 ? validateMediaUploadContractV2 : validateMediaUploadContract)(
        mediaKind,
        attachmentCount,
        expectedPathCount
      );
      if (!contract.ok) return callback?.({ ok: false, error: contract.error });

      const senderUID = normalizeUID(socket.userUID);
      const access = isDirect ? {ok: true} : await authorizeSocketRoom({
        socket,
        roomID,
        senderUID,
        context: "chat:mediaPreflight"
      });
      if (!access.ok) return callback?.({ ok: false, error: access.error });

      const rateKey = `${socket.moderationPrincipalID}:${roomID}:mediaPreflight:${mediaKind}`;
      const rateMax = mediaKind === "video" ? RATE_MAX_VIDEOS : RATE_MAX_IMAGES;
      if (!allowRate(rateKey, rateMax, RATE_WINDOW_MS, String(effectiveUploadID))) {
        return callback?.({ ok: false, error: "rate_limited" });
      }

      const result = isDirect
        ? await mediaUploadService.preflightDirect({roomID: String(roomID), uploadID: String(effectiveUploadID),
          clientMutationID: String(clientMutationID), senderUID, moderationPrincipalID: socket.moderationPrincipalID,
          kind: mediaKind, contract, sources})
        : isV2
        ? await mediaUploadService.preflightV2({
          roomID: String(roomID),
          uploadID: String(effectiveUploadID),
          clientMutationID: String(clientMutationID),
          senderUID,
          moderationPrincipalID: socket.moderationPrincipalID,
          kind: mediaKind,
          contract,
          sources
        })
        : await mediaUploadService.preflight({
          roomID,
          messageID: String(effectiveUploadID),
          senderUID,
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
      const effectiveMessageID = (messageID && String(messageID)) ||
        (clientMessageID && String(clientMessageID)) ||
        generateMessageID();
      if (!allowRate(
        `${socket.moderationPrincipalID}:${roomID}:images`,
        RATE_MAX_IMAGES,
        RATE_WINDOW_MS,
        effectiveMessageID
      )) {
        return callback?.({ ok: false, error: "rate_limited" });
      }

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
      const roomAccess = await authorizeSocketRoom({
        socket,
        roomID,
        senderUID,
        context: "chat:mediaFinalize/video"
      });
      if (!roomAccess.ok) return callback?.({ ok: false, error: roomAccess.error });
      const effectiveMessageID = (messageID && String(messageID)) || generateMessageID();
      if (!allowRate(
        `${socket.moderationPrincipalID}:${roomID}:video`,
        RATE_MAX_VIDEOS,
        RATE_WINDOW_MS,
        effectiveMessageID
      )) {
        return callback?.({ ok: false, error: "rate_limited" });
      }

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
    if (rejectMissingCapability(socket, "createUGC", callback)) return;
    if ([2, 3].includes(Number(data?.contractVersion))) {
      try {
        const roomID = String(data?.roomID || "");
        const uploadID = String(data?.uploadID || data?.messageID || "");
        const clientMutationID = String(data?.clientMutationID || "");
        if (!roomID || !isValidRoomID(roomID)) {
          return callback?.({ ok: false, error: "invalid_room_id" });
        }
        if (!uploadID || uploadID.includes("/") ||
            !isValidClientMutationID(clientMutationID)) {
          return callback?.({ ok: false, error: "invalid_request" });
        }
        const senderUID = normalizeUID(socket.userUID);
        const access = Number(data?.contractVersion) === 3 ? {ok: true} : await authorizeSocketRoom({
          socket,
          roomID,
          senderUID,
          context: "chat:mediaFinalize/v2"
        });
        if (!access.ok) return callback?.({ ok: false, error: access.error });
        const mediaKind = normalizeMediaKind(data?.kind || data?.mediaKind || data?.type);
        if (!mediaKind) return callback?.({ ok: false, error: "invalid_media_kind" });
        if (!allowRate(
          `${socket.moderationPrincipalID}:${roomID}:${mediaKind}`,
          mediaKind === "video" ? RATE_MAX_VIDEOS : RATE_MAX_IMAGES,
          RATE_WINDOW_MS,
          uploadID
        )) {
          return callback?.({ ok: false, error: "rate_limited" });
        }
        const finalize = Number(data?.contractVersion) === 3
          ? mediaUploadService.finalizeDirect : mediaUploadService.finalizeV2;
        const result = await finalize({
          roomID,
          uploadID,
          clientMutationID,
          senderUID,
          moderationPrincipalID: socket.moderationPrincipalID
        });
        return callback?.(result);
      } catch (error) {
        logger.error("[chat:mediaFinalize/v2] handler error:", error);
        return callback?.({ ok: false, error: "internal_error" });
      }
    }
    return handleMediaFinalize(data, callback);
  });

  socket.on("chat:mediaRefreshUploadTargets", async (data, callback) => {
    if (rejectMissingCapability(socket, "createUGC", callback)) return;
    try {
      const roomID = String(data?.roomID || "");
      const uploadID = String(data?.uploadID || "");
      const clientMutationID = String(data?.clientMutationID || "");
      if (!roomID || !isValidRoomID(roomID) || !uploadID || uploadID.includes("/") ||
          !isValidClientMutationID(clientMutationID)) {
        return callback?.({ok: false, error: "invalid_request"});
      }
      const senderUID = normalizeUID(socket.userUID);
      const access = await authorizeSocketRoom({
        socket,
        roomID,
        senderUID,
        context: "chat:mediaRefreshUploadTargets"
      });
      if (!access.ok) return callback?.({ok: false, error: access.error});
      return callback?.(await mediaUploadService.refreshUploadTargetsV2({
        roomID,
        uploadID,
        clientMutationID,
        senderUID,
        moderationPrincipalID: socket.moderationPrincipalID
      }));
    } catch (error) {
      logger.error("[chat:mediaRefreshUploadTargets] handler error:", error);
      return callback?.({ok: false, error: "internal_error"});
    }
  });

  socket.on("chat:mediaProcessingStatus", async (data, callback) => {
    try {
      const roomID = String(data?.roomID || "");
      const uploadID = String(data?.uploadID || "");
      const clientMutationID = String(data?.clientMutationID || "");
      if (!roomID || !isValidRoomID(roomID) || !uploadID || uploadID.includes("/") ||
          !isValidClientMutationID(clientMutationID)) {
        return callback?.({ ok: false, error: "invalid_request" });
      }
      return callback?.(await mediaUploadService.statusV2({
        roomID,
        uploadID,
        clientMutationID,
        senderUID: normalizeUID(socket.userUID),
        moderationPrincipalID: socket.moderationPrincipalID
      }));
    } catch (error) {
      logger.error("[chat:mediaProcessingStatus] handler error:", error);
      return callback?.({ ok: false, error: "internal_error" });
    }
  });

  socket.on("chat:mediaCancel", async (data, callback) => {
    try {
      const roomID = String(data?.roomID || "");
      const uploadID = String(data?.uploadID || "");
      const clientMutationID = String(data?.clientMutationID || "");
      if (!roomID || !isValidRoomID(roomID) || !uploadID || uploadID.includes("/") ||
          !isValidClientMutationID(clientMutationID)) {
        return callback?.({ ok: false, error: "invalid_request" });
      }
      return callback?.(await mediaUploadService.cancelV2({
        roomID,
        uploadID,
        clientMutationID,
        senderUID: normalizeUID(socket.userUID),
        moderationPrincipalID: socket.moderationPrincipalID
      }));
    } catch (error) {
      logger.error("[chat:mediaCancel] handler error:", error);
      return callback?.({ ok: false, error: "internal_error" });
    }
  });
}
