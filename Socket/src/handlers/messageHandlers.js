import {
  MAX_CHAT_MESSAGE_BYTES,
  RATE_MAX_CHAT,
  RATE_WINDOW_MS
} from "../config.js";
import { buildTextMessageDocument } from "../messages/messagePayload.js";
import { normalizeEmail, normalizeUID } from "../utils/strings.js";

export function registerMessageHandlers({
  socket,
  io,
  isValidRoomID,
  authorizeSocketRoom,
  allowRate,
  generateMessageID,
  clock,
  allocateSeqAndPersist,
  fanoutChatPush,
  handleLookbookShare,
  logger = console
}) {
  socket.on("chat message", async (data, callback) => {
    try {
      const roomID = data?.roomID || data?.roomName;
      const msg = typeof data?.msg === "string"
        ? data.msg
        : (typeof data?.message === "string" ? data.message : "");
      const nickname = data?.senderNickname || data?.senderNickName || "";
      const senderUID = normalizeUID(socket.userUID);
      const senderEmail = normalizeEmail(socket.userEmail);

      if (!roomID || msg.trim().length === 0) {
        logger.error("[Chat] Invalid data received:", data);
        callback?.({ ok: false, message: "Invalid data", error: "invalid_data" });
        return;
      }
      if (!isValidRoomID(roomID)) {
        callback?.({
          ok: false,
          message: "invalid_room_id",
          error: "invalid_room_id"
        });
        return;
      }

      const roomAccess = await authorizeSocketRoom({
        socket,
        roomID,
        senderUID,
        context: "Chat"
      });
      if (!roomAccess.ok) {
        callback?.({
          ok: false,
          message: roomAccess.error,
          error: roomAccess.error
        });
        return;
      }

      if (Buffer.byteLength(msg, "utf8") > MAX_CHAT_MESSAGE_BYTES) {
        callback?.({
          ok: false,
          message: "message_too_long",
          error: "message_too_long"
        });
        return;
      }
      if (!allowRate(`${socket.id}:${roomID}:chat`, RATE_MAX_CHAT, RATE_WINDOW_MS)) {
        callback?.({ ok: false, message: "rate_limited", error: "rate_limited" });
        return;
      }

      const messageID = String(data?.ID || generateMessageID());
      const messageDocument = buildTextMessageDocument({
        data,
        roomID,
        messageID,
        msg,
        senderUID,
        senderEmail,
        nickname,
        nowDate: clock.nowDate()
      });

      let seq = 0;
      try {
        seq = await allocateSeqAndPersist(roomID, messageID, messageDocument);
      } catch (error) {
        logger.error("[Chat] seq allocation/persist error:", error);
        callback?.({
          ok: false,
          message: "seq_persist_error",
          error: "seq_persist_error"
        });
        return;
      }

      const serverMessage = { ...messageDocument, seq };
      io.to(roomID).emit("chat message", serverMessage);
      void fanoutChatPush({ roomID, messageData: serverMessage });
      logger.log(`[Chat][${roomID}] ${nickname || "Anonymous"}: ${msg}`, serverMessage);
      callback?.({ ok: true, success: true, seq, messageID });
    } catch (error) {
      logger.error("[Chat] Error processing message:", error);
      callback?.({ ok: false, message: error.message, error: error.message });
    }
  });

  socket.on("chat:lookbookShare", async (data, callback) => {
    return handleLookbookShare(socket, data, callback);
  });
}
