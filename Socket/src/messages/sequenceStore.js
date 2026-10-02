import { deriveLastMessage } from "./preview.js";
import { withMessageSearchProjection } from "./messageSearchIndex.js";

export function createSequenceStore({ db, admin }) {
  async function allocateSeqAndPersist(roomID, messageID, messageData, options = {}) {
    const roomRef = db.collection("Rooms").doc(roomID);
    const msgRef = roomRef.collection("Messages").doc(messageID);
    const lastMessageText = deriveLastMessage(messageData);
    const indexedMessage = withMessageSearchProjection(messageData);

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

      const storedMessage = {...indexedMessage};
      // seq 없는 기존 문서를 merge할 때에도 제외 대상의 오래된 검색 필드를 남기지 않는다.
      for (const key of ["searchNormalized", "searchChars", "searchNgrams2", "searchIndexVersion"]) {
        if (!(key in storedMessage) && existing.exists && key in (existing.data() || {})) {
          storedMessage[key] = admin.firestore.FieldValue.delete();
        }
      }
      tx.set(msgRef, {
        ...storedMessage,
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
