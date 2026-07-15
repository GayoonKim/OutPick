import {
  MAX_CHAT_MESSAGE_BYTES,
  MAX_LOOKBOOK_SHARE_PAYLOAD_BYTES,
  MAX_LOOKBOOK_SHARE_TEXT_BYTES,
  RATE_MAX_LOOKBOOK_SHARE,
  RATE_WINDOW_MS
} from "../config.js";
import { lookbookShareFallbackPreview } from "../messages/preview.js";
import { sanitizeLookbookSharedContent } from "./sharedContentValidator.js";
import {
  normalizeEmail,
  normalizeUID,
  normalizeSentAt,
  trimString,
  utf8Bytes,
  validatePayloadSize
} from "../utils/strings.js";

function buildServerLookbookShareMessage({
  roomID,
  messageID,
  msg,
  sharedContent,
  senderUID,
  senderEmail,
  senderNickname,
  senderAvatarPath,
  sentAt
}) {
  return {
    ID: messageID,
    roomID,
    roomName: roomID,
    senderUID,
    ...(senderEmail ? { senderEmail } : {}),
    senderNickname,
    ...(senderAvatarPath ? { senderAvatarPath } : {}),
    msg,
    message: msg,
    sentAt: sentAt || new Date().toISOString(),
    messageType: "lookbookShare",
    attachments: [],
    sharedContent,
    replyPreview: null,
    isFailed: false,
    isDeleted: false
  };
}

export function createLookbookShareHandler({
  io,
  rooms,
  isValidRoomID,
  ensureRoomLoaded,
  loadRoomAccess,
  allocateSeqAndPersist,
  messageDeliverySingleFlight,
  fanoutChatPush,
  allowRate,
  clock,
  generateMessageID,
  logger = console
}) {
  return async function handleLookbookShare(socket, data, callback) {
    try {
      const {
        ID,
        messageID: rawMessageID,
        roomID: rawRoomID,
        roomName,
        msg: rawMsg,
        message,
        senderNickname,
        senderNickName,
        senderAvatarPath,
        sentAt,
        sharedContent
      } = data || {};

      if (!validatePayloadSize(data, MAX_LOOKBOOK_SHARE_PAYLOAD_BYTES)) {
        return callback && callback({
          ok: false,
          message: "payload_too_large",
          error: "payload_too_large"
        });
      }

      const roomID = rawRoomID || roomName;
      if (!roomID || !isValidRoomID(roomID)) {
        return callback && callback({
          ok: false,
          message: "invalid_room_id",
          error: "invalid_room_id"
        });
      }

      if (!rooms[roomID]) {
        const loaded = await ensureRoomLoaded(roomID);
        if (!loaded) {
          return callback && callback({
            ok: false,
            message: "room_not_found",
            error: "room_not_found"
          });
        }
      }

      if (!socket.rooms.has(roomID)) {
        return callback && callback({
          ok: false,
          message: "not_joined",
          error: "not_joined"
        });
      }

      const senderUID = normalizeUID(socket.userUID);
      const senderEmail = normalizeEmail(socket.userEmail);
      if (!senderUID) {
        return callback && callback({
          ok: false,
          message: "unauthenticated",
          error: "unauthenticated"
        });
      }

      const access = await loadRoomAccess(roomID, senderUID);
      if (!access.ok) {
        return callback && callback({
          ok: false,
          message: access.error,
          error: access.error
        });
      }

      const sharedContentResult = sanitizeLookbookSharedContent(sharedContent);
      if (sharedContentResult.error) {
        return callback && callback({
          ok: false,
          message: sharedContentResult.error,
          error: sharedContentResult.error
        });
      }

      const normalizedSharedContent = sharedContentResult.value;
      const incomingText = typeof rawMsg === "string"
        ? rawMsg
        : (typeof message === "string" ? message : "");
      const trimmedMsg = trimString(incomingText, MAX_CHAT_MESSAGE_BYTES);
      if (utf8Bytes(trimmedMsg) > MAX_LOOKBOOK_SHARE_TEXT_BYTES) {
        return callback && callback({
          ok: false,
          message: "message_too_long",
          error: "message_too_long"
        });
      }

      const finalMsg = trimmedMsg || lookbookShareFallbackPreview(normalizedSharedContent.contentType);

      const shareRateKey = `${socket.id}:${roomID}:lookbookShare`;
      if (!allowRate(shareRateKey, RATE_MAX_LOOKBOOK_SHARE, RATE_WINDOW_MS)) {
        return callback && callback({
          ok: false,
          message: "rate_limited",
          error: "rate_limited"
        });
      }

      const effectiveMessageID = String(
        rawMessageID || ID || generateMessageID()
      );
      const sentAtISO = normalizeSentAt(sentAt) || clock.nowDate().toISOString();
      const nickname = senderNickname || senderNickName || "";
      const messageDoc = buildServerLookbookShareMessage({
        roomID,
        messageID: effectiveMessageID,
        msg: finalMsg,
        sharedContent: normalizedSharedContent,
        senderUID,
        senderEmail,
        senderNickname: nickname,
        senderAvatarPath,
        sentAt: sentAtISO
      });

      let delivery;
      try {
        delivery = await messageDeliverySingleFlight.run({
          kind: "lookbook",
          roomID,
          messageID: effectiveMessageID
        }, async () => {
          const outcome = await allocateSeqAndPersist(
            roomID,
            effectiveMessageID,
            messageDoc
          );
          if (outcome.created) {
            const serverMsg = { ...messageDoc, seq: outcome.seq };
            io.to(roomID).emit("chat message", serverMsg);
            void fanoutChatPush({
              roomID,
              messageData: serverMsg
            });
            logger.log("[chat:lookbookShare] shared", {
              roomID,
              senderUID,
              messageID: effectiveMessageID,
              contentType: normalizedSharedContent.contentType,
              seq: outcome.seq
            });
          }
          return outcome;
        });
      } catch (e) {
        logger.error("[chat:lookbookShare] seq allocation/persist error:", e);
        return callback && callback({
          ok: false,
          message: "seq_persist_error",
          error: "seq_persist_error"
        });
      }

      const duplicate = delivery.duplicate || !delivery.value.created;
      return callback && callback({
        ok: true,
        success: true,
        duplicate,
        seq: delivery.value.seq,
        messageID: effectiveMessageID
      });
    } catch (error) {
      logger.error("[chat:lookbookShare] handler error:", error);
      return callback && callback({
        ok: false,
        message: "internal_error",
        error: "internal_error"
      });
    }
  };
}
