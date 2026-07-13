import { normalizeUID } from "../utils/strings.js";

export function registerRoomHandlers({
  socket,
  io,
  rooms,
  isValidRoomID,
  ensureRoomLoaded,
  loadRoomAccess,
  leaveOrCloseRoom,
  logger = console
}) {
  socket.on("create room", (roomID, callback) => {
    if (!roomID || !isValidRoomID(roomID)) {
      callback?.({ ok: false, message: "invalid_room_id" });
      return;
    }

    if (!rooms[roomID]) {
      rooms[roomID] = [];
      logger.log(`Room created: ${roomID}`);
    }

    socket.join(roomID);
    const username = socket.username || "Anonymous";
    if (!rooms[roomID].includes(username)) rooms[roomID].push(username);
    callback?.({ ok: true, roomID });
  });

  socket.on("join room", async (roomID, callback) => {
    const username = socket.username || "Anonymous";
    logger.log(`Join request: ${username} → ${roomID}`);

    if (!roomID || !isValidRoomID(roomID)) {
      callback?.({ ok: false, message: "invalid_room_id" });
      return;
    }

    const roomExists = await ensureRoomLoaded(roomID);
    if (!roomExists) {
      logger.warn(`Join failed: ${username} → ${roomID} (room does not exist)`);
      socket.emit("error", `Room ${roomID} does not exist`);
      callback?.({ ok: false, message: "room_not_found" });
      return;
    }

    const access = await loadRoomAccess(roomID, socket.userUID);
    if (!access.ok) {
      callback?.({ ok: false, message: access.error, error: access.error });
      return;
    }

    socket.join(roomID);
    if (!rooms[roomID].includes(username)) rooms[roomID].push(username);
    logger.log(`${username} joined room: ${roomID}`);
    socket.emit("joined room", roomID);
    callback?.({ ok: true, roomID });
  });

  socket.on("leave room", (roomID, callback) => {
    if (!roomID || !isValidRoomID(roomID)) {
      callback?.({ ok: false, message: "invalid_room_id" });
      return;
    }

    socket.leave(roomID);
    if (rooms[roomID]) {
      rooms[roomID] = rooms[roomID].filter((name) => name !== socket.username);
      io.to(roomID).emit("user list", rooms[roomID]);
    }

    logger.log(`Leave room request: ${socket.username || "Anonymous"} → ${roomID}`);
    callback?.({ ok: true, roomID });
  });

  socket.on("room:leave-or-close", async (payload = {}, callback) => {
    const { roomID } = payload || {};
    const userUID = normalizeUID(socket.userUID);

    if (!roomID || !isValidRoomID(roomID)) {
      callback?.({ ok: false, error: "invalid_room_id" });
      return;
    }
    if (!userUID) {
      callback?.({ ok: false, error: "unauthenticated" });
      return;
    }

    try {
      const result = await leaveOrCloseRoom({ roomID, userUID });
      if (!result.ok) {
        const fallback = result.mode === "closed" ? "close_failed" : "leave_failed";
        callback?.({ ok: false, error: result.error || fallback });
        return;
      }

      if (result.mode === "closed") {
        if (result.skipSocketCloseEffects !== true) {
          io.to(roomID).emit("room:closed", {
            roomID,
            closedByUID: userUID
          });
          if (rooms[roomID]) delete rooms[roomID];

          const roomSet = io.sockets.adapter.rooms.get(roomID);
          if (roomSet) {
            for (const socketID of roomSet) {
              io.sockets.sockets.get(socketID)?.leave(roomID);
            }
          }
        }

        callback?.({
          ok: true,
          mode: "closed",
          alreadyDeleted: result.alreadyDeleted === true
        });
        return;
      }

      socket.leave(roomID);
      if (rooms[roomID]) {
        rooms[roomID] = rooms[roomID].filter((name) => name !== socket.username);
        io.to(roomID).emit("user list", rooms[roomID]);
      }
      callback?.({ ok: true, mode: "left" });
    } catch (error) {
      logger.error("[room:leave-or-close] internal error", error);
      callback?.({ ok: false, error: "internal_error" });
    }
  });
}
