import { chunkArray, normalizeEmail } from "../utils/strings.js";
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

  async function findUserDocRefByEmail(email) {
    const normalizedEmail = normalizeEmail(email);
    if (!normalizedEmail) return null;

    const snapshot = await db.collection(USERS_COLLECTION)
      .where("email", "==", normalizedEmail)
      .limit(1)
      .get();

    return snapshot.empty ? null : snapshot.docs[0].ref;
  }

  async function findUserDocRefsByEmails(emails) {
    const normalizedEmails = [...new Set(emails.map(normalizeEmail).filter(Boolean))];
    const refsByEmail = new Map();

    if (!normalizedEmails.length) {
      return refsByEmail;
    }

    const chunks = chunkArray(normalizedEmails, 10);
    const snapshots = await Promise.all(
      chunks.map((chunk) =>
        db.collection(USERS_COLLECTION)
          .where("email", "in", chunk)
          .get()
      )
    );

    for (const snapshot of snapshots) {
      snapshot.forEach((doc) => {
        const email = normalizeEmail(doc.get("email"));
        if (email) {
          refsByEmail.set(email, doc.ref);
        }
      });
    }

    return refsByEmail;
  }

  return {
    findUserByUID,
    findUserDocRefByEmail,
    findUserDocRefsByEmails
  };
}
