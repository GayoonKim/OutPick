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
          const unreadMessageSeq = Number.isInteger(ed.unreadMessageSeq)
            ? ed.unreadMessageSeq
            : ed.seq;
          return { seq: ed.seq, unreadMessageSeq, created: false };
        }
      }

      const roomSnap = await tx.get(roomRef);
      const roomData = roomSnap.exists ? (roomSnap.data() || {}) : {};
      const cur = Number(typeof roomData.seq === "number" ? roomData.seq : 0);
      const next = cur + 1;
      // 역할 이벤트 도입 전 Room은 두 counter가 같으므로 legacy fallback은 현재 seq다.
      const currentUnreadMessageSeq = Number.isInteger(roomData.unreadMessageSeq)
        ? roomData.unreadMessageSeq
        : cur;
      const nextUnreadMessageSeq = currentUnreadMessageSeq + 1;

      tx.set(msgRef, {
        ...messageData,
        seq: next,
        unreadMessageSeq: nextUnreadMessageSeq
      }, { merge: true });
      tx.set(roomRef, {
        seq: next,
        unreadMessageSeq: nextUnreadMessageSeq,
        lastMessage: lastMessageText,
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessageSeq: next
      }, { merge: true });
      if (options.mediaUploadRef) {
        tx.delete(options.mediaUploadRef);
      }

      return { seq: next, unreadMessageSeq: nextUnreadMessageSeq, created: true };
    });
  }

  return { allocateSeqAndPersist };
}
