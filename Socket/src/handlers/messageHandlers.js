import {
  MAX_CHAT_MESSAGE_BYTES,
  RATE_MAX_CHAT,
  RATE_WINDOW_MS
} from "../config.js";
import { buildTextMessageDocument } from "../messages/messagePayload.js";
import { normalizeUID } from "../utils/strings.js";
import { rejectMissingCapability } from "../moderation/capabilities.js";

export function registerMessageHandlers({
  socket,
  io,
  isValidRoomID,
  authorizeSocketRoom,
  allowRate,
  generateMessageID,
  clock,
  allocateSeqAndPersist,
  messageDeliverySingleFlight,
  fanoutChatPush,
  handleLookbookShare,
  logger = console
}) {
  socket.on("chat message", async (data, callback) => {
    if (rejectMissingCapability(socket, "createUGC", callback)) return;
    try {
      const roomID = data?.roomID || data?.roomName;
      const msg = typeof data?.msg === "string"
        ? data.msg
        : (typeof data?.message === "string" ? data.message : "");
      const nickname = data?.senderNickname || data?.senderNickName || "";
      const senderUID = normalizeUID(socket.userUID);

      if (!roomID || msg.trim().length === 0) {
        logger.warn?.("[Chat] invalid payload", {
          event: "chat message",
          hasRoomID: Boolean(roomID),
          payloadBytes: Buffer.byteLength(msg, "utf8")
        });
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
      const messageID = String(data?.ID || generateMessageID());
      const rateKey = `${socket.moderationPrincipalID}:${roomID}:text`;
      if (!allowRate(rateKey, RATE_MAX_CHAT, RATE_WINDOW_MS, messageID)) {
        callback?.({ ok: false, message: "rate_limited", error: "rate_limited" });
        return;
      }

      const messageDocument = buildTextMessageDocument({
        data,
        roomID,
        messageID,
        msg,
        senderUID,
        nickname,
        nowDate: clock.nowDate()
      });

      let delivery;
      try {
        delivery = await messageDeliverySingleFlight.run({
          kind: "text",
          roomID,
          messageID
        }, async () => {
          const outcome = await allocateSeqAndPersist(
            roomID,
            messageID,
            messageDocument
          );
          const serverMessage = { ...messageDocument, seq: outcome.seq };
          if (outcome.created) {
            io.to(roomID).emit("chat message", serverMessage);
            void fanoutChatPush({ roomID, messageData: serverMessage });
            logger.log("[Chat] message persisted", {
              event: "chat message",
              roomID,
              messageID,
              seq: outcome.seq,
              payloadBytes: Buffer.byteLength(msg, "utf8")
            });
          }
          return outcome;
        });
      } catch (error) {
        logger.error("[Chat] seq allocation/persist error:", error);
        callback?.({
          ok: false,
          message: "seq_persist_error",
          error: "seq_persist_error"
        });
        return;
      }

      const duplicate = delivery.duplicate || !delivery.value.created;
      callback?.({
        ok: true,
        success: true,
        duplicate,
        seq: delivery.value.seq,
        messageID
      });
    } catch (error) {
      logger.error("[Chat] Error processing message:", error);
      callback?.({ ok: false, message: error.message, error: error.message });
    }
  });

  socket.on("chat:lookbookShare", async (data, callback) => {
    if (rejectMissingCapability(socket, "createUGC", callback)) return;
    return handleLookbookShare(socket, data, callback);
  });
}
