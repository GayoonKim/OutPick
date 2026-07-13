import admin from "firebase-admin";

const DEFAULT_STORAGE_BUCKET = "outpick-664ae.appspot.com";

export function initializeFirebaseAdmin({
  env = process.env,
  firebaseAdmin = admin
} = {}) {
  if (firebaseAdmin.apps.length === 0) {
    const storageBucket =
      env.OUTPICK_FIREBASE_STORAGE_BUCKET ||
      env.FIREBASE_STORAGE_BUCKET ||
      DEFAULT_STORAGE_BUCKET;

    const serviceAccountJSON = env.FIREBASE_SERVICE_ACCOUNT_JSON;
    if (serviceAccountJSON) {
      firebaseAdmin.initializeApp({
        credential: firebaseAdmin.credential.cert(JSON.parse(serviceAccountJSON)),
        storageBucket
      });
    } else {
      firebaseAdmin.initializeApp({
        credential: firebaseAdmin.credential.applicationDefault(),
        storageBucket
      });
    }
  }

  return {
    admin: firebaseAdmin,
    db: firebaseAdmin.firestore()
  };
}
