import { chunkArray, normalizeEmail } from "../utils/strings.js";
import { USERS_COLLECTION } from "../config.js";

export function createUserLookup({ db }) {
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
    findUserDocRefByEmail,
    findUserDocRefsByEmails
  };
}
