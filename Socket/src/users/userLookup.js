import { USERS_COLLECTION } from "../config.js";

export function createUserLookup({ db }) {
  async function findUserByUID(uid) {
    const normalizedUID = typeof uid === "string" ? uid.trim() : "";
    if (!normalizedUID || normalizedUID.includes("/")) return null;

    const directRef = db.collection(USERS_COLLECTION).doc(normalizedUID);
    const directSnap = await directRef.get();
    if (directSnap.exists) {
      return {
        ref: directRef,
        data: directSnap.data() || {}
      };
    }

    const snapshot = await db.collection(USERS_COLLECTION)
      .where("identityKey", "==", normalizedUID)
      .limit(1)
      .get();

    if (snapshot.empty) return null;

    const doc = snapshot.docs[0];
    return {
      ref: doc.ref,
      data: doc.data() || {}
    };
  }

  return {
    findUserByUID
  };
}
