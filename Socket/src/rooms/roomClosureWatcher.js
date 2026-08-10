export function createRoomClosureWatcher({ db, io, rooms, logger = console }) {
  const handled = new Set();

  function closeSockets(roomID, data) {
    const lifecycleVersion = Number(data.lifecycleVersion || 0);
    const key = `${roomID}:${lifecycleVersion}`;
    if (handled.has(key)) return;
    handled.add(key);

    io.to(roomID).emit("room:closed", {
      roomID,
      closureType: data.closureType,
      closureNoticeCode: data.closureNoticeCode,
      lifecycleVersion
    });
    if (rooms[roomID]) delete rooms[roomID];
    const roomSet = io.sockets.adapter.rooms.get(roomID);
    if (roomSet) {
      for (const socketID of roomSet) {
        io.sockets.sockets.get(socketID)?.leave(roomID);
      }
    }
  }

  function start() {
    return db.collection("moderationRoomCleanupJobs").onSnapshot(
      (snapshot) => {
        for (const change of snapshot.docChanges()) {
          if (change.type !== "added" && change.type !== "modified") continue;
          const data = change.doc.data() || {};
          const roomID = String(data.roomID || change.doc.id);
          if (!roomID || roomID.includes("/")) continue;
          if (data.closureType !== "closedByOwner" &&
              data.closureType !== "closedByModeration") continue;
          closeSockets(roomID, data);
        }
      },
      (error) => logger.error("[room-closure-watcher] snapshot failed", error)
    );
  }

  return { start };
}
