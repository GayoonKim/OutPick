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
          tx.set(msgRef, { ...messageData, seq: ed.seq }, { merge: true });
          return ed.seq;
        }
      }

      const roomSnap = await tx.get(roomRef);
      const cur = Number((roomSnap.exists && typeof roomSnap.data().seq === "number") ? roomSnap.data().seq : 0);
      const next = cur + 1;

      tx.set(msgRef, { ...messageData, seq: next }, { merge: true });
      tx.set(roomRef, {
        seq: next,
        lastMessage: lastMessageText,
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
      if (options.mediaUploadRef) {
        tx.set(options.mediaUploadRef, {
          status: "completed",
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
      }

      return next;
    });
  }

  return { allocateSeqAndPersist };
}
