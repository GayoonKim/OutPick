import { normalizeEmail } from "../utils/strings.js";

export function createRoomAccess({ db }) {
  async function loadRoomAccess(roomID, senderEmail) {
    const roomRef = db.collection("Rooms").doc(roomID);
    const snap = await roomRef.get();

    if (!snap.exists) {
      return { ok: false, error: "room_not_found" };
    }

    const roomData = snap.data() || {};
    if (roomData.isClosed === true) {
      return { ok: false, error: "room_closed" };
    }

    const participantIDs = Array.isArray(roomData.participantIDs)
      ? roomData.participantIDs.map(normalizeEmail).filter(Boolean)
      : [];

    if (!senderEmail || !participantIDs.includes(senderEmail)) {
      return { ok: false, error: "not_joined" };
    }

    return { ok: true, roomData };
  }

  return { loadRoomAccess };
}
