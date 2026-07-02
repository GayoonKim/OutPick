import { normalizeUID } from "../utils/strings.js";

export function createRoomAccess({ db }) {
  async function loadRoomAccess(roomID, senderUID) {
    const roomRef = db.collection("Rooms").doc(roomID);
    const snap = await roomRef.get();

    if (!snap.exists) {
      return { ok: false, error: "room_not_found" };
    }

    const roomData = snap.data() || {};
    if (roomData.isClosed === true) {
      return { ok: false, error: "room_closed" };
    }

    const participantUIDs = Array.isArray(roomData.participantUIDs)
      ? roomData.participantUIDs.map(normalizeUID).filter(Boolean)
      : [];

    const normalizedSenderUID = normalizeUID(senderUID);
    if (!normalizedSenderUID || !participantUIDs.includes(normalizedSenderUID)) {
      return { ok: false, error: "not_joined" };
    }

    return { ok: true, roomData };
  }

  return { loadRoomAccess };
}
