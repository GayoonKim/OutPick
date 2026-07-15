import { deriveLastMessage } from "./preview.js";

export function createSequenceStore({ db, admin }) {
  async function allocateSeqAndPersist(roomID, messageID, messageData, options = {}) {
    const roomRef = db.collection("Rooms").doc(roomID);
    const msgRef = roomRef.collection("Messages").doc(messageID);
    const lastMessageText = deriveLastMessage(messageData);

    return db.runTransaction(async (tx) => {
      const existing = await tx.get(msgRef);
      if (existing.exists) {
        const ed = existing.data() || {};
        if (typeof ed.seq === "number") {
          return { seq: ed.seq, created: false };
        }
      }

      const roomSnap = await tx.get(roomRef);
      const cur = Number((roomSnap.exists && typeof roomSnap.data().seq === "number") ? roomSnap.data().seq : 0);
      const next = cur + 1;

      tx.set(msgRef, { ...messageData, seq: next }, { merge: true });
      tx.set(roomRef, {
        seq: next,
        lastMessage: lastMessageText,
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessageSeq: next
      }, { merge: true });
      if (options.mediaUploadRef) {
        tx.delete(options.mediaUploadRef);
      }

      return { seq: next, created: true };
    });
  }

  return { allocateSeqAndPersist };
}
