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
  senderID,
  senderNickname,
  senderAvatarPath,
  sentAt
}) {
  return {
    ID: messageID,
    roomID,
    roomName: roomID,
    senderID,
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
  fanoutChatPush,
  allowRate
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
        senderID: rawSenderID,
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

      const senderEmail = socket.userEmail || normalizeEmail(rawSenderID);
      if (!senderEmail) {
        return callback && callback({
          ok: false,
          message: "unauthenticated",
          error: "unauthenticated"
        });
      }

      const access = await loadRoomAccess(roomID, senderEmail);
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
        rawMessageID || ID || `${Date.now()}-${Math.random().toString(16).slice(2)}`
      );
      const sentAtISO = normalizeSentAt(sentAt) || new Date().toISOString();
      const nickname = senderNickname || senderNickName || "";
      const messageDoc = buildServerLookbookShareMessage({
        roomID,
        messageID: effectiveMessageID,
        msg: finalMsg,
        sharedContent: normalizedSharedContent,
        senderID: senderEmail,
        senderNickname: nickname,
        senderAvatarPath,
        sentAt: sentAtISO
      });

      let seq = 0;
      try {
        seq = await allocateSeqAndPersist(roomID, effectiveMessageID, messageDoc);
      } catch (e) {
        console.error("[chat:lookbookShare] seq allocation/persist error:", e);
        return callback && callback({
          ok: false,
          message: "seq_persist_error",
          error: "seq_persist_error"
        });
      }

      const serverMsg = { ...messageDoc, seq };
      io.to(roomID).emit("chat message", serverMsg);
      void fanoutChatPush({
        roomID,
        messageData: serverMsg
      });

      console.log("[chat:lookbookShare] shared", {
        roomID,
        senderID: senderEmail,
        messageID: effectiveMessageID,
        contentType: normalizedSharedContent.contentType,
        seq
      });

      return callback && callback({
        ok: true,
        success: true,
        seq,
        messageID: effectiveMessageID
      });
    } catch (error) {
      console.error("[chat:lookbookShare] handler error:", error);
      return callback && callback({
        ok: false,
        message: "internal_error",
        error: "internal_error"
      });
    }
  };
}
