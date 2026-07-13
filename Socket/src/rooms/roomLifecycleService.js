import { normalizeUID } from "../utils/strings.js";

export function createRoomLifecycleService({
  db,
  closeRoomImmediately,
  leaveRoomMembership
}) {
  async function leaveOrClose({ roomID, userUID }) {
    const normalizedUID = normalizeUID(userUID);
    const roomRef = db.collection("Rooms").doc(roomID);
    const snapshot = await roomRef.get();

    if (!snapshot.exists) {
      return {
        ok: true,
        mode: "closed",
        alreadyDeleted: true,
        skipSocketCloseEffects: true
      };
    }

    const roomData = snapshot.data() || {};
    const creatorUID = typeof roomData.creatorUID === "string"
      ? normalizeUID(roomData.creatorUID)
      : null;

    if (creatorUID && creatorUID === normalizedUID) {
      const closeResult = await closeRoomImmediately({
        roomID,
        closedByUID: normalizedUID
      });
      if (!closeResult.ok) return { ...closeResult, mode: "closed" };
      return {
        ...closeResult,
        mode: "closed"
      };
    }

    const leaveResult = await leaveRoomMembership({
      roomID,
      userUID: normalizedUID
    });
    if (!leaveResult.ok) return { ...leaveResult, mode: "left" };
    return { ...leaveResult, mode: "left" };
  }

  return { leaveOrClose };
}
