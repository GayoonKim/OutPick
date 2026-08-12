export function createRoomBanWatcher({ db, io, rooms, logger = console }) {
  const handled = new Set();

  function removeSockets(roomID, principalID, data) {
    if (data.isActive !== true) return;
    const stateVersion = Number(data.stateVersion || 0);
    const key = `${roomID}:${principalID}:${stateVersion}`;
    if (handled.has(key)) return;
    handled.add(key);

    const roomSet = io.sockets.adapter.rooms.get(roomID);
    if (!roomSet) return;
    for (const socketID of [...roomSet]) {
      const socket = io.sockets.sockets.get(socketID);
      if (!socket || socket.moderationPrincipalID !== principalID) continue;
      socket.emit("room:membership-removed", {
        roomID,
        reason: "room_banned",
        stateVersion
      });
      socket.leave(roomID);
      if (rooms[roomID] && socket.username) {
        rooms[roomID] = rooms[roomID].filter((name) => name !== socket.username);
      }
    }
    if (rooms[roomID]) io.to(roomID).emit("user list", rooms[roomID]);
  }

  function start() {
    return db.collectionGroup("bans").onSnapshot(
      (snapshot) => {
        for (const change of snapshot.docChanges()) {
          if (change.type !== "added" && change.type !== "modified") continue;
          const roomRef = change.doc.ref?.parent?.parent;
          const roomID = roomRef?.id;
          const principalID = change.doc.id;
          if (!roomID || roomID.includes("/") || !principalID || principalID.includes("/")) {
            continue;
          }
          removeSockets(roomID, principalID, change.doc.data() || {});
        }
      },
      (error) => logger.error("[room-ban-watcher] snapshot failed", error)
    );
  }

  return { start };
}
