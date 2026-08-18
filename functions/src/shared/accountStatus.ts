/* eslint-disable require-jsdoc, max-len */
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../core/firebase.js";
import {Timestamp} from "firebase-admin/firestore";
import {
  ModerationStatus,
  moderationCapabilities,
} from "../moderation/contracts.js";

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
  await assertAccountCapability(uid, "createUGC", store);
}

export type ModerationCapability =
  typeof moderationCapabilities[ModerationStatus][number];

function effectiveStatus(
  data: FirebaseFirestore.DocumentData | undefined,
  now: Date,
): ModerationStatus | null {
  const status = data?.moderationStatus;
  if (status !== "active" && status !== "restricted" && status !== "suspended") {
    return null;
  }
  if (status === "restricted" && data?.restrictedUntil instanceof Timestamp &&
    data.restrictedUntil.toMillis() <= now.getTime()) {
    return "active";
  }
  return status;
}

export async function assertAccountCapability(
  uid: string,
  capability: ModerationCapability,
  store: AccountStore = db,
  now = new Date(),
): Promise<void> {
  const accountSnapshot = await store.collection("moderationAccounts").doc(uid).get();
  requireAccountCapabilityData(
    accountSnapshot.exists ? accountSnapshot.data() : undefined,
    capability,
    now,
  );
}

export function requireAccountCapabilityData(
  data: FirebaseFirestore.DocumentData | undefined,
  capability: ModerationCapability,
  now = new Date(),
): FirebaseFirestore.DocumentData {
  requireActiveAccountData(data);
  const status = effectiveStatus(data, now);
  const capabilities: readonly string[] = status ? moderationCapabilities[status] : [];
  if (!status || !capabilities.includes(capability)) {
    throw new HttpsError(
      "permission-denied",
      "현재 계정 상태에서는 이 작업을 수행할 수 없습니다.",
    );
  }
  return data as FirebaseFirestore.DocumentData;
}

export async function assertModerationCapability(
  uid: string,
  capability: ModerationCapability,
  store: AccountStore = db,
  now = new Date(),
): Promise<void> {
  const moderationSnapshot = await store
    .collection("moderationAccounts")
    .doc(uid)
    .get();
  const status = effectiveStatus(
    moderationSnapshot.exists ? moderationSnapshot.data() : undefined,
    now,
  );
  const capabilities: readonly string[] = status ?
    moderationCapabilities[status] : [];
  if (!status || !capabilities.includes(capability)) {
    throw new HttpsError(
      "permission-denied",
      "현재 계정 상태에서는 이 작업을 수행할 수 없습니다.",
    );
  }
}
