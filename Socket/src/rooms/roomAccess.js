import { normalizeUID } from "../utils/strings.js";

export function createRoomAccess({ db }) {
  async function loadRoomAccess(roomID, senderUID) {
    const roomRef = db.collection("Rooms").doc(roomID);
    const snap = await roomRef.get();

    if (!snap.exists) {
      return { ok: false, error: "room_not_found" };
    }

    const roomData = snap.data() || {};
    if (roomData.isClosed === true ||
        (roomData.lifecycleStatus && roomData.lifecycleStatus !== "active")) {
      return { ok: false, error: "room_closed" };
    }

    const normalizedSenderUID = normalizeUID(senderUID);
    if (!normalizedSenderUID || normalizedSenderUID.includes("/")) {
      return { ok: false, error: "not_joined" };
    }

    const moderationAccount = await db.collection("moderationAccounts")
      .doc(normalizedSenderUID)
      .get();
    const moderationPrincipalID = moderationAccount.data()?.moderationPrincipalID;
    if (typeof moderationPrincipalID === "string" && moderationPrincipalID &&
        !moderationPrincipalID.includes("/")) {
      const ban = await roomRef.collection("bans").doc(moderationPrincipalID).get();
      if (ban.exists && ban.data()?.isActive === true) {
        return { ok: false, error: "room_banned" };
      }
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
