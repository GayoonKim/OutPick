export function createSocketRoomAuthorizer({
  rooms,
  ensureRoomLoaded,
  loadRoomAccess,
  logger = console
}) {
  return async function authorizeSocketRoom({
    socket,
    roomID,
    senderUID,
    context
  }) {
    if (!rooms[roomID]) {
      const roomExists = await ensureRoomLoaded(roomID);
      if (!roomExists) return { ok: false, error: "room_not_found" };
    }

    const access = await loadRoomAccess(roomID, senderUID);
    if (!access.ok) return access;

    if (!socket.rooms.has(roomID)) {
      socket.join(roomID);
      logger.warn(`[${context}] socket room membership restored`, {
        roomID,
        socketID: socket.id,
        senderUID
      });
    }

    return access;
  };
}
