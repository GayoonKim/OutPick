import { getClientKey } from "../auth/handshake.js";
import { moderationSession } from "../moderation/capabilities.js";

export function registerConnectionHandlers({
  socket,
  io,
  rooms,
  clock,
  reconnectPolicy,
  watchUserAccountStatus,
  watchModerationAccount,
  logger = console
}) {
  logger.log("User connected:", socket.userUID);

  socket.emit("server:connect:ready", {
    policy: reconnectPolicy,
    serverTime: clock.nowMillis(),
    socketId: socket.id
  });

  socket.on("client:hello", (payload = {}, callback) => {
    callback?.({
      ok: true,
      attempt: Number(payload.attempt ?? 0),
      policy: reconnectPolicy,
      serverTime: clock.nowMillis(),
      key: getClientKey(socket.handshake)
    });
  });

  socket.on("client:ping", (callback) => {
    callback?.({ pong: true, serverTime: clock.nowMillis() });
  });

  socket.emit("room list", Object.keys(rooms));

  const stopAccountStatusWatch = watchUserAccountStatus?.(
    socket.userUID,
    (accountStatus) => {
      logger.warn("[account] inactive socket disconnected", {
        userUID: socket.userUID,
        accountStatus: accountStatus || "missing",
        socketID: socket.id
      });
      socket.emit("account:inactive", {
        accountStatus: accountStatus || "missing"
      });
      socket.disconnect(true);
    },
    (error) => {
      logger.error("[account] status watch failed; disconnecting", {
        userUID: socket.userUID,
        message: error?.message
      });
      socket.disconnect(true);
    }
  );

  const stopModerationWatch = watchModerationAccount?.(
    socket.userUID,
    (data) => {
      const nextSession = moderationSession(data);
      const changed = !nextSession ||
        nextSession.moderationStatus !== socket.moderationStatus ||
        nextSession.stateVersion !== socket.moderationStateVersion;
      if (!changed) return;
      logger.warn("[moderation] changed socket disconnected", {
        userUID: socket.userUID,
        moderationStatus: nextSession?.moderationStatus || "missing",
        socketID: socket.id
      });
      socket.emit("moderation:changed", {
        moderationStatus: nextSession?.moderationStatus || "missing"
      });
      socket.disconnect(true);
    },
    (error) => {
      logger.error("[moderation] status watch failed; disconnecting", {
        userUID: socket.userUID,
        message: error?.message
      });
      socket.disconnect(true);
    }
  );

  socket.on("set username", (username) => {
    socket.username = username || "Anonymous";
    logger.log(`Username set: ${socket.username}`);
    socket.emit("username set", socket.username);
  });

  socket.on("disconnect", () => {
    stopAccountStatusWatch?.();
    stopModerationWatch?.();
    logger.log("User disconnected:", socket.id);
    for (const roomID in rooms) {
      rooms[roomID] = rooms[roomID].filter((user) => user !== socket.username);
      io.to(roomID).emit("user list", rooms[roomID]);
    }
  });
}
