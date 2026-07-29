export type AccountDeletionStatus =
  | "grace"
  | "finalizing"
  | "retryPending"
  | "completed"
  | "cancelled";

export type AccountDeletionStage =
  | "waiting"
  | "publicIdentity"
  | "engagement"
  | "comments"
  | "associations"
  | "messages"
  | "rooms"
  | "roles"
  | "privateState"
  | "providerAndAuth"
  | "verify";

export interface AccountDeletionAuthContext {
  uid: string;
  authTimeSeconds: number;
  provider: string;
  providerUserID: string | null;
}

export interface AccountDeletionIntentInput {
  intentID: string;
  nonce: string;
}

export interface AccountDeletionReceiptInput {
  requestID: string;
  receiptToken: string;
}

export interface AccountDeletionStatusResult {
  status: AccountDeletionStatus;
  requestedAt: string | null;
  cancelableUntil: string | null;
  completedAt: string | null;
  message: string;
}
