import {getApps, initializeApp, type App} from "firebase-admin/app";
import {getFirestore, type Firestore} from "firebase-admin/firestore";
import {getStorage, type Storage} from "firebase-admin/storage";

export interface FirebaseClients {
  app: App;
  firestore: Firestore;
  storage: Storage;
}

export function initializeFirebaseClients(
  projectID: string,
  storageBucket: string,
): FirebaseClients {
  const app = getApps()[0] ?? initializeApp({
    projectId: projectID,
    storageBucket,
  });

  return {
    app,
    firestore: getFirestore(app),
    storage: getStorage(app),
  };
}
