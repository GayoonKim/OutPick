/* eslint-disable require-jsdoc, max-len */
import {randomBytes, randomUUID} from "node:crypto";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../core/firebase.js";
import {
  AccountDeletionAuthContext,
  AccountDeletionIntentInput,
  AccountDeletionStatusResult,
} from "./contracts.js";
import {
  canCancelDeletion,
  DELETION_INTENT_TTL_MS,
  DELETION_PROCESSING_MS,
  deletionRequestID,
  sha256,
} from "./policy.js";
import {MODERATION_ACCOUNT_SCHEMA_VERSION} from "../moderation/contracts.js";

function timestampOrNull(value: unknown): Timestamp | null {
  return value instanceof Timestamp ? value : null;
}

function statusMessage(status: string): string {
  switch (status) {
  case "grace":
    return "계정 접근은 종료됐으며 데이터 삭제를 처리하고 있어요.";
  case "finalizing":
  case "retryPending":
    return "계정 데이터를 안전하게 삭제하고 있어요.";
  case "completed":
    return "계정과 연결된 데이터 삭제가 완료됐어요.";
  case "cancelled":
    return "계정 삭제 요청이 취소됐어요.";
  default:
    return "계정 삭제 상태를 확인하고 있어요.";
  }
}

export async function createDeletionIntent(
  context: AccountDeletionAuthContext,
  nowMillis: number,
) {
  const userRef = db.collection("users").doc(context.uid);
  const moderationAccountRef = db.collection("moderationAccounts").doc(context.uid);
  const intentID = randomUUID();
  const nonce = randomBytes(32).toString("base64url");
  const intentRef = db.collection("accountDeletionIntents").doc(intentID);
  let generation = "";

  await db.runTransaction(async (transaction) => {
    const [userSnapshot, moderationAccountSnapshot] = await Promise.all([
      transaction.get(userRef),
      transaction.get(moderationAccountRef),
    ]);
    if (!userSnapshot.exists || userSnapshot.data()?.accountStatus !== "active" ||
      !moderationAccountSnapshot.exists ||
      moderationAccountSnapshot.data()?.accountStatus !== "active") {
      throw new HttpsError(
        "failed-precondition",
        "삭제할 수 있는 활성 계정이 없습니다.",
      );
    }
    const existingGeneration = userSnapshot.data()?.accountGenerationID;
    generation = typeof existingGeneration === "string" &&
      existingGeneration.length > 0 ? existingGeneration : randomUUID();
    if (generation !== existingGeneration) {
      transaction.update(userRef, {
        accountGenerationID: generation,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.create(intentRef, {
      uid: context.uid,
      accountGenerationID: generation,
      provider: context.provider,
      providerUserID: context.providerUserID,
      authTimeSeconds: context.authTimeSeconds,
      nonceHash: sha256(nonce),
      issuedAt: Timestamp.fromMillis(nowMillis),
      expiresAt: Timestamp.fromMillis(nowMillis + DELETION_INTENT_TTL_MS),
      usedAt: null,
    });
  });

  return {
    intentID,
    nonce,
    expiresAt: new Date(nowMillis + DELETION_INTENT_TTL_MS).toISOString(),
  };
}

export async function requestDeletion(
  context: AccountDeletionAuthContext,
  input: AccountDeletionIntentInput,
  nowMillis: number,
) {
  const userRef = db.collection("users").doc(context.uid);
  const moderationAccountRef = db.collection("moderationAccounts").doc(context.uid);
  const intentRef = db.collection("accountDeletionIntents").doc(input.intentID);
  const receiptToken = randomBytes(32).toString("base64url");
  let requestID = "";
  let cancelableUntilMillis = 0;

  await db.runTransaction(async (transaction) => {
    const [userSnapshot, moderationAccountSnapshot, intentSnapshot] = await Promise.all([
      transaction.get(userRef),
      transaction.get(moderationAccountRef),
      transaction.get(intentRef),
    ]);
    const userData = userSnapshot.data();
    const generation = typeof userData?.accountGenerationID === "string" ?
      userData.accountGenerationID : "";
    if (
      !userSnapshot.exists ||
      userData?.accountStatus !== "active" ||
      generation.length === 0
    ) {
      throw new HttpsError(
        "failed-precondition",
        "삭제할 수 있는 활성 계정이 없습니다.",
      );
    }
    if (!moderationAccountSnapshot.exists ||
      moderationAccountSnapshot.data()?.accountStatus !== "active") {
      throw new HttpsError(
        "failed-precondition",
        "계정 권한 상태를 확인할 수 없습니다.",
      );
    }

    const intentData = intentSnapshot.data();
    const expiresAt = timestampOrNull(intentData?.expiresAt);
    if (
      !intentSnapshot.exists ||
      intentData?.uid !== context.uid ||
      intentData?.accountGenerationID !== generation ||
      intentData?.provider !== context.provider ||
      intentData?.usedAt != null ||
      intentData?.nonceHash !== sha256(input.nonce) ||
      !expiresAt ||
      expiresAt.toMillis() <= nowMillis
    ) {
      throw new HttpsError(
        "failed-precondition",
        "계정 삭제 인증이 만료됐습니다. 다시 인증해 주세요.",
      );
    }

    requestID = deletionRequestID(context.uid, generation);
    const requestRef = db.collection("accountDeletionRequests").doc(requestID);
    const outboxRef = db
      .collection("accountDeletionNotificationOutbox")
      .doc(`${requestID}-requested`);
    const existingRequest = await transaction.get(requestRef);
    const existingStatus = existingRequest.data()?.status;
    if (
      existingRequest.exists &&
      existingStatus !== "cancelled" &&
      existingStatus !== "completed"
    ) {
      throw new HttpsError(
        "already-exists",
        "이미 처리 중인 계정 삭제 요청이 있습니다.",
      );
    }

    cancelableUntilMillis = nowMillis + DELETION_PROCESSING_MS;
    transaction.update(userRef, {
      accountStatus: "deletionPending",
      deletionRequestedAt: Timestamp.fromMillis(nowMillis),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(moderationAccountRef, {
      schemaVersion: MODERATION_ACCOUNT_SCHEMA_VERSION,
      accountStatus: "deletionPending",
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(requestRef, {
      uid: context.uid,
      accountGenerationID: generation,
      provider: context.provider,
      providerUserID: context.providerUserID,
      status: "grace",
      stage: "waiting",
      cursors: {},
      requestedAt: Timestamp.fromMillis(nowMillis),
      cancelableUntil: Timestamp.fromMillis(cancelableUntilMillis),
      claimedAt: null,
      retryAfter: Timestamp.fromMillis(cancelableUntilMillis),
      attemptCount: 0,
      leaseOwner: null,
      leaseExpiresAt: null,
      lastErrorCode: null,
      notificationState: {
        requested: "pending",
        completed: "pending",
      },
      sessionRevocationStatus: "pending",
      receiptTokenHash: sha256(receiptToken),
      completedAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(outboxRef, {
      requestID,
      recipientUID: context.uid,
      event: "requested",
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(
        cancelableUntilMillis + 30 * 24 * 60 * 60 * 1000,
      ),
    });
    transaction.update(intentRef, {
      usedAt: Timestamp.fromMillis(nowMillis),
    });
  });

  return {
    requestID,
    receiptToken,
    requestedAt: new Date(nowMillis).toISOString(),
    cancelableUntil: new Date(cancelableUntilMillis).toISOString(),
    accountStatus: "deletionPending",
  };
}

export async function recordSessionRevocation(
  requestID: string,
  succeeded: boolean,
): Promise<void> {
  await db.collection("accountDeletionRequests").doc(requestID).set({
    sessionRevocationStatus: succeeded ? "completed" : "failed",
    sessionRevocationUpdatedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

export async function cancelDeletion(
  context: AccountDeletionAuthContext,
  nowMillis: number,
) {
  const userRef = db.collection("users").doc(context.uid);
  const moderationAccountRef = db.collection("moderationAccounts").doc(context.uid);

  return db.runTransaction(async (transaction) => {
    const [userSnapshot, moderationAccountSnapshot] = await Promise.all([
      transaction.get(userRef),
      transaction.get(moderationAccountRef),
    ]);
    const generation = userSnapshot.data()?.accountGenerationID;
    if (
      !userSnapshot.exists ||
      userSnapshot.data()?.accountStatus !== "deletionPending" ||
      typeof generation !== "string" ||
      generation.length === 0
    ) {
      throw new HttpsError("failed-precondition", "취소할 삭제 요청이 없습니다.");
    }
    if (!moderationAccountSnapshot.exists ||
      moderationAccountSnapshot.data()?.accountStatus !== "deletionPending") {
      throw new HttpsError(
        "failed-precondition",
        "계정 권한 상태를 확인할 수 없습니다.",
      );
    }
    const requestID = deletionRequestID(context.uid, generation);
    const requestRef = db.collection("accountDeletionRequests").doc(requestID);
    const requestSnapshot = await transaction.get(requestRef);
    const cancelableUntil = timestampOrNull(requestSnapshot.data()?.cancelableUntil);
    if (
      !requestSnapshot.exists ||
      requestSnapshot.data()?.uid !== context.uid ||
      requestSnapshot.data()?.accountGenerationID !== generation ||
      requestSnapshot.data()?.status !== "grace" ||
      !cancelableUntil ||
      !canCancelDeletion(nowMillis, cancelableUntil.toMillis())
    ) {
      throw new HttpsError(
        "failed-precondition",
        "계정 삭제 취소 가능 기간이 지났습니다.",
      );
    }

    transaction.update(userRef, {
      accountStatus: "active",
      deletionRequestedAt: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(moderationAccountRef, {
      schemaVersion: MODERATION_ACCOUNT_SCHEMA_VERSION,
      accountStatus: "active",
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(requestRef, {
      status: "cancelled",
      cancelledAt: Timestamp.fromMillis(nowMillis),
      expiresAt: Timestamp.fromMillis(
        nowMillis + 30 * 24 * 60 * 60 * 1000,
      ),
      leaseOwner: null,
      leaseExpiresAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(
      db.collection("accountDeletionNotificationOutbox")
        .doc(`${requestID}-cancelled`),
      {
        requestID,
        event: "cancelled",
        status: "pending",
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromMillis(
          nowMillis + 30 * 24 * 60 * 60 * 1000,
        ),
      },
    );
    return {
      requestID,
      accountStatus: "active",
      cancelledAt: new Date(nowMillis).toISOString(),
    };
  });
}

export async function loadDeletionStatus(
  requestID: string,
  receiptToken: string,
): Promise<AccountDeletionStatusResult> {
  const snapshot = await db.collection("accountDeletionRequests").doc(requestID).get();
  const data = snapshot.data();
  if (
    !snapshot.exists ||
    typeof data?.receiptTokenHash !== "string" ||
    data.receiptTokenHash !== sha256(receiptToken)
  ) {
    throw new HttpsError("not-found", "계정 삭제 상태를 찾을 수 없습니다.");
  }
  const status = typeof data.status === "string" ? data.status : "";
  if (!["grace", "finalizing", "retryPending", "completed", "cancelled"].includes(status)) {
    throw new HttpsError("internal", "계정 삭제 상태가 올바르지 않습니다.");
  }
  return {
    status: status as AccountDeletionStatusResult["status"],
    requestedAt: timestampOrNull(data.requestedAt)?.toDate().toISOString() ?? null,
    cancelableUntil:
      timestampOrNull(data.cancelableUntil)?.toDate().toISOString() ?? null,
    completedAt: timestampOrNull(data.completedAt)?.toDate().toISOString() ?? null,
    message: statusMessage(status),
  };
}
