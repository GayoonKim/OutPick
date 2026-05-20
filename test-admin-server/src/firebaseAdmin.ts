import {readFileSync} from "node:fs";
import {
  cert,
  getApps,
  initializeApp,
  type App,
  type ServiceAccount
} from "firebase-admin/app";
import {getAuth, type Auth} from "firebase-admin/auth";
import {getFirestore, type Firestore} from "firebase-admin/firestore";
import {validateProjectID, type ServerConfig} from "./config.js";

interface ServiceAccountFile {
  readonly project_id?: string;
  readonly client_email?: string;
  readonly private_key?: string;
}

export interface FirebaseAdminContext {
  readonly app: App;
  readonly auth: Auth;
  readonly firestore: Firestore;
  readonly serviceAccountProjectID: string;
}

export function initializeFirebaseAdmin(
  config: ServerConfig
): FirebaseAdminContext {
  validateProjectID(config.firebaseProjectID);

  const serviceAccount = readServiceAccount(config.serviceAccountPath);
  const serviceAccountProjectID = requireServiceAccountProjectID(
    serviceAccount,
    config.serviceAccountPath
  );
  validateProjectID(serviceAccountProjectID);

  const app = getApps()[0] ?? initializeApp({
    credential: cert(toAdminServiceAccount(serviceAccount)),
    projectId: config.firebaseProjectID
  });

  return {
    app,
    auth: getAuth(app),
    firestore: getFirestore(app),
    serviceAccountProjectID
  };
}

function toAdminServiceAccount(
  serviceAccount: ServiceAccountFile
): ServiceAccount {
  return {
    projectId: serviceAccount.project_id,
    clientEmail: serviceAccount.client_email,
    privateKey: serviceAccount.private_key
  };
}

function readServiceAccount(path: string): ServiceAccountFile {
  const raw = readFileSync(path, "utf8");
  return JSON.parse(raw) as ServiceAccountFile;
}

function requireServiceAccountProjectID(
  serviceAccount: ServiceAccountFile,
  path: string
): string {
  const projectID = serviceAccount.project_id?.trim() ?? "";
  if (projectID.length === 0) {
    throw new Error(`service account에 project_id가 없습니다: ${path}`);
  }

  return projectID;
}
