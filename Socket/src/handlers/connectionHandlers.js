import { getClientKey } from "../auth/handshake.js";

export function registerConnectionHandlers({
  socket,
  io,
  rooms,
  clock,
  reconnectPolicy,
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

  socket.on("set username", (username) => {
    socket.username = username || "Anonymous";
    logger.log(`Username set: ${socket.username}`);
    socket.emit("username set", socket.username);
  });

  socket.on("disconnect", () => {
    logger.log("User disconnected:", socket.id);
    for (const roomID in rooms) {
      rooms[roomID] = rooms[roomID].filter((user) => user !== socket.username);
      io.to(roomID).emit("user list", rooms[roomID]);
    }
  });
}
