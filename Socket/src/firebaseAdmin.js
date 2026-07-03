import admin from "firebase-admin";

const DEFAULT_STORAGE_BUCKET = "outpick-664ae.appspot.com";

export function initializeFirebaseAdmin() {
  if (admin.apps.length > 0) return;

  const storageBucket =
    process.env.OUTPICK_FIREBASE_STORAGE_BUCKET ||
    process.env.FIREBASE_STORAGE_BUCKET ||
    DEFAULT_STORAGE_BUCKET;

  const serviceAccountJSON = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (serviceAccountJSON) {
    admin.initializeApp({
      credential: admin.credential.cert(JSON.parse(serviceAccountJSON)),
      storageBucket
    });
    return;
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    storageBucket
  });
}

initializeFirebaseAdmin();

export { admin };
export const db = admin.firestore();
