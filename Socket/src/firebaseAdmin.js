import admin from "firebase-admin";

export function initializeFirebaseAdmin() {
  if (admin.apps.length > 0) return;

  const serviceAccountJSON = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (serviceAccountJSON) {
    admin.initializeApp({
      credential: admin.credential.cert(JSON.parse(serviceAccountJSON))
    });
    return;
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault()
  });
}

initializeFirebaseAdmin();

export { admin };
export const db = admin.firestore();
