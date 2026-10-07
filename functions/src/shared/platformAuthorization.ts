/* eslint-disable require-jsdoc, valid-jsdoc */
import {
  Timestamp,
  type DocumentData,
  type Firestore,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

/** 관리자 권한 전환 중에도 새 API가 legacy 관리자 문서를 fallback으로 쓰지 않게 한다. */
export function hasActivePlatformAdminData(
  data: DocumentData | undefined
): boolean {
  return data?.isActive === true && !(data.revokedAt instanceof Timestamp);
}

export async function assertActivePlatformAdmin(
  firestore: Firestore,
  uid: string
): Promise<void> {
  const snapshot = await firestore.collection("platformAdmins").doc(uid).get();
  if (!snapshot.exists || !hasActivePlatformAdminData(snapshot.data())) {
    throw new HttpsError("permission-denied", "플랫폼 관리자 권한이 필요합니다.");
  }
}

export async function isActivePlatformAdmin(
  firestore: Firestore,
  uid: string
): Promise<boolean> {
  const snapshot = await firestore.collection("platformAdmins").doc(uid).get();
  return snapshot.exists && hasActivePlatformAdminData(snapshot.data());
}
