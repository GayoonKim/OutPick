/* eslint-disable require-jsdoc */
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../core/firebase.js";

interface AccountSnapshot {
  exists: boolean;
  data(): FirebaseFirestore.DocumentData | undefined;
}

interface AccountDocumentReference {
  get(): Promise<AccountSnapshot>;
}

interface AccountStore {
  collection(name: string): {
    doc(id: string): AccountDocumentReference;
  };
}

export function requireActiveAccountData(
  data: FirebaseFirestore.DocumentData | undefined,
): void {
  if (!data || data.accountStatus !== "active") {
    throw new HttpsError(
      "failed-precondition",
      "활성 상태의 사용자 계정이 필요합니다.",
    );
  }
}

export async function assertAccountActive(
  uid: string,
  store: AccountStore = db,
): Promise<void> {
  const snapshot = await store.collection("users").doc(uid).get();
  requireActiveAccountData(snapshot.exists ? snapshot.data() : undefined);
}
