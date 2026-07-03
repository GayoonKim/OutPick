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

    const normalizedSenderUID = normalizeUID(senderUID);
    if (!normalizedSenderUID || normalizedSenderUID.includes("/")) {
      return { ok: false, error: "not_joined" };
    }

    const memberSnap = await roomRef
      .collection("members")
      .doc(normalizedSenderUID)
      .get();
    if (!memberSnap.exists) {
      return { ok: false, error: "not_joined" };
    }

    return { ok: true, roomData, memberData: memberSnap.data() || {} };
  }

  return { loadRoomAccess };
}
