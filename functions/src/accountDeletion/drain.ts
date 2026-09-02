/* eslint-disable require-jsdoc, max-len */
import {createHmac, randomUUID} from "node:crypto";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {db, firebaseAuth} from "../core/firebase.js";
import {FUNCTIONS_REGION} from "../core/runtime.js";
import {
  hasIncompleteAccountDeletionMessageCleanup,
  hasRemainingUIDReferences,
  removeEngagementPage,
  removePrivateState,
  removePublicIdentity,
  removeRolePage,
  resolveRoomPage,
  scrubCommentPage,
  scrubAssociationPage,
  scrubMessagePage,
} from "./cleanup.js";
import {
  deletionLedgerHmacKey,
  kakaoAdminKey,
  unlinkKakaoAccount,
} from "./providerCleanup.js";
import {retryDelayMillis} from "./policy.js";
import {accountDeletionSuccessionJobID} from "../chat/moderation/roomMembershipSweep.js";

const LEASE_MS = 10 * 60 * 1000;
const REQUEST_LIMIT = 10;

type ClaimedRequest = {
  requestID: string;
  uid: string;
  accountGenerationID: string;
  provider: string;
  providerUserID: string | null;
  stage: string;
  attemptCount: number;
  leaseOwner: string;
};

function timestampMillis(value: unknown): number | null {
  return value instanceof Timestamp ? value.toMillis() : null;
}

async function dueRequestIDs(now: Timestamp): Promise<string[]> {
  const [grace, retry, stale] = await Promise.all([
    db.collection("accountDeletionRequests")
      .where("status", "==", "grace")
      .where("cancelableUntil", "<=", now)
      .orderBy("cancelableUntil", "asc")
      .limit(REQUEST_LIMIT)
      .get(),
    db.collection("accountDeletionRequests")
      .where("status", "==", "retryPending")
      .where("retryAfter", "<=", now)
      .orderBy("retryAfter", "asc")
      .limit(REQUEST_LIMIT)
      .get(),
    db.collection("accountDeletionRequests")
      .where("status", "==", "finalizing")
      .where("leaseExpiresAt", "<=", now)
      .orderBy("leaseExpiresAt", "asc")
      .limit(REQUEST_LIMIT)
      .get(),
  ]);
  return [...new Set(
    [...grace.docs, ...retry.docs, ...stale.docs]
      .map((document) => document.id),
  )]
    .slice(0, REQUEST_LIMIT);
}

async function retryFailedSessionRevocations(): Promise<number> {
  const snapshot = await db.collection("accountDeletionRequests")
    .where("sessionRevocationStatus", "==", "failed")
    .limit(REQUEST_LIMIT)
    .get();
  let completed = 0;
  for (const document of snapshot.docs) {
    const uid = document.data().uid;
    if (typeof uid !== "string" || uid.length === 0) continue;
    try {
      await firebaseAuth.revokeRefreshTokens(uid);
      await document.ref.update({
        sessionRevocationStatus: "completed",
        sessionRevocationUpdatedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      completed += 1;
    } catch (error) {
      console.error("[accountDeletion] session revoke retry failed", {
        requestID: document.id,
        code: (error as {code?: string})?.code,
      });
    }
  }
  return completed;
}

async function claimRequest(
  requestID: string,
  nowMillis: number,
): Promise<ClaimedRequest | null> {
  const requestRef = db.collection("accountDeletionRequests").doc(requestID);
  const leaseOwner = randomUUID();
  return db.runTransaction(async (transaction) => {
    const requestSnapshot = await transaction.get(requestRef);
    if (!requestSnapshot.exists) return null;
    const data = requestSnapshot.data() ?? {};
    const status = data.status;
    const dueMillis = status === "grace" ?
      timestampMillis(data.cancelableUntil) :
      status === "retryPending" ?
        timestampMillis(data.retryAfter) :
        timestampMillis(data.leaseExpiresAt);
    const leaseExpiresAt = timestampMillis(data.leaseExpiresAt);
    if (
      !["grace", "retryPending", "finalizing"].includes(status) ||
      dueMillis === null ||
      dueMillis > nowMillis ||
      (leaseExpiresAt !== null && leaseExpiresAt > nowMillis)
    ) {
      return null;
    }
    const uid = typeof data.uid === "string" ? data.uid : "";
    const generation = typeof data.accountGenerationID === "string" ?
      data.accountGenerationID : "";
    if (!uid || !generation) return null;

    if (data.stage === "waiting") {
      const userSnapshot = await transaction.get(db.collection("users").doc(uid));
      if (
        !userSnapshot.exists ||
        userSnapshot.data()?.accountStatus !== "deletionPending" ||
        userSnapshot.data()?.accountGenerationID !== generation
      ) {
        return null;
      }
    }

    const attemptCount = Number.isInteger(data.attemptCount) ?
      Math.max(0, data.attemptCount) + 1 : 1;
    transaction.update(requestRef, {
      status: "finalizing",
      claimedAt: Timestamp.fromMillis(nowMillis),
      leaseOwner,
      leaseExpiresAt: Timestamp.fromMillis(nowMillis + LEASE_MS),
      attemptCount,
      lastErrorCode: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      requestID,
      uid,
      accountGenerationID: generation,
      provider: typeof data.provider === "string" ? data.provider : "unknown",
      providerUserID:
        typeof data.providerUserID === "string" ? data.providerUserID : null,
      stage: typeof data.stage === "string" ? data.stage : "waiting",
      attemptCount,
      leaseOwner,
    };
  });
}

async function advance(
  claim: ClaimedRequest,
  nextStage: string,
): Promise<void> {
  const ref = db.collection("accountDeletionRequests").doc(claim.requestID);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (
      !snapshot.exists ||
      snapshot.data()?.status !== "finalizing" ||
      snapshot.data()?.leaseOwner !== claim.leaseOwner
    ) {
      throw new Error("account_deletion_lease_lost");
    }
    if (nextStage === "rooms") {
      const jobRef = db.collection("roomOwnershipSuccessionJobs")
        .doc(accountDeletionSuccessionJobID(claim.requestID));
      transaction.create(jobRef, {
        schemaVersion: 3,
        targetUID: claim.uid,
        phase: "ownedCanonical",
        cursor: null,
        pendingRoomCount: 0,
        failedRoomCount: 0,
        cause: "accountDeletion",
        accountDeletionRequestID: claim.requestID,
        accountGenerationID: claim.accountGenerationID,
        expectedStateVersion: null,
        status: "pending",
        attempt: 0,
        nextAttemptAt: FieldValue.serverTimestamp(),
        leaseOwner: null,
        leaseExpiresAt: null,
        lastErrorCode: null,
        result: null,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        completedAt: null,
        expiresAt: null,
      });
    }
    transaction.update(ref, {
      stage: nextStage,
      leaseExpiresAt: Timestamp.fromMillis(Date.now() + LEASE_MS),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  claim.stage = nextStage;
}

async function yieldForRetry(
  claim: ClaimedRequest,
  errorCode: string | null,
): Promise<void> {
  const ref = db.collection("accountDeletionRequests").doc(claim.requestID);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (
      !snapshot.exists ||
      snapshot.data()?.leaseOwner !== claim.leaseOwner
    ) return;
    transaction.update(ref, {
      status: "retryPending",
      retryAfter: Timestamp.fromMillis(
        Date.now() + retryDelayMillis(claim.attemptCount),
      ),
      leaseOwner: null,
      leaseExpiresAt: null,
      lastErrorCode: errorCode,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

async function deleteProviderAndAuth(claim: ClaimedRequest): Promise<void> {
  if (claim.provider === "kakao" && claim.providerUserID) {
    await unlinkKakaoAccount(claim.providerUserID, kakaoAdminKey.value());
  }
  try {
    await firebaseAuth.deleteUser(claim.uid);
  } catch (error) {
    const code = (error as {code?: string})?.code;
    if (code !== "auth/user-not-found") throw error;
  }
}

async function finalize(claim: ClaimedRequest): Promise<void> {
  const requestRef = db.collection("accountDeletionRequests").doc(claim.requestID);
  const ledgerID = createHmac("sha256", deletionLedgerHmacKey.value())
    .update(`${claim.uid}|${claim.accountGenerationID}`, "utf8")
    .digest("hex");
  const suppressionRef = db
    .collection("completedDeletionSuppressions")
    .doc(ledgerID);
  const outboxRef = db
    .collection("accountDeletionNotificationOutbox")
    .doc(`${claim.requestID}-completed`);
  const auditRef = db.collection("accountDeletionAuditLogs").doc();
  const successionJobRef = db.collection("roomOwnershipSuccessionJobs")
    .doc(accountDeletionSuccessionJobID(claim.requestID));

  await db.runTransaction(async (transaction) => {
    const [requestSnapshot, successionJob] = await Promise.all([
      transaction.get(requestRef),
      transaction.get(successionJobRef),
    ]);
    if (
      !requestSnapshot.exists ||
      requestSnapshot.data()?.status !== "finalizing" ||
      requestSnapshot.data()?.leaseOwner !== claim.leaseOwner
    ) {
      throw new Error("account_deletion_lease_lost");
    }
    if (!successionJob.exists || successionJob.get("status") !== "completed" ||
      successionJob.get("result") !== "resolved") {
      throw new Error("room_succession_pending");
    }
    transaction.set(suppressionRef, {
      requestID: claim.requestID,
      completedAt: FieldValue.serverTimestamp(),
      schemaVersion: 1,
    });
    transaction.set(outboxRef, {
      requestID: claim.requestID,
      event: "completed",
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000),
    });
    transaction.set(auditRef, {
      requestID: claim.requestID,
      outcome: "completed",
      stage: "completed",
      attemptCount: claim.attemptCount,
      completedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + 90 * 24 * 60 * 60 * 1000),
      schemaVersion: 1,
    });
    transaction.update(requestRef, {
      uid: FieldValue.delete(),
      accountGenerationID: FieldValue.delete(),
      provider: FieldValue.delete(),
      providerUserID: FieldValue.delete(),
      status: "completed",
      stage: "completed",
      completedAt: FieldValue.serverTimestamp(),
      leaseOwner: null,
      leaseExpiresAt: null,
      lastErrorCode: null,
      expiresAt: Timestamp.fromMillis(
        Date.now() + 30 * 24 * 60 * 60 * 1000,
      ),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

async function processClaim(claim: ClaimedRequest): Promise<void> {
  try {
    for (let steps = 0; steps < 12; steps += 1) {
      switch (claim.stage) {
      case "waiting":
        await advance(claim, "publicIdentity");
        break;
      case "publicIdentity":
        if (!(await removePublicIdentity(claim.uid))) {
          await yieldForRetry(claim, null);
          return;
        }
        await advance(claim, "engagement");
        break;
      case "engagement":
        if (!(await removeEngagementPage(claim.uid))) {
          await yieldForRetry(claim, null);
          return;
        }
        await advance(claim, "comments");
        break;
      case "comments":
        if (!(await scrubCommentPage(claim.uid))) {
          await yieldForRetry(claim, null);
          return;
        }
        await advance(claim, "associations");
        break;
      case "associations":
        if (!(await scrubAssociationPage(claim.uid))) {
          await yieldForRetry(claim, null);
          return;
        }
        await advance(claim, "messages");
        break;
      case "messages":
        if (!(await scrubMessagePage(
          claim.uid,
          claim.requestID,
          claim.accountGenerationID,
        ))) {
          await yieldForRetry(claim, null);
          return;
        }
        await advance(claim, "rooms");
        break;
      case "rooms":
        if (!(await resolveRoomPage(claim.requestID))) {
          await yieldForRetry(claim, null);
          return;
        }
        await advance(claim, "roles");
        break;
      case "roles":
        if (!(await removeRolePage(claim.uid))) {
          await yieldForRetry(claim, null);
          return;
        }
        await advance(claim, "privateState");
        break;
      case "privateState":
        await removePrivateState(claim.uid);
        await advance(claim, "verify");
        break;
      case "verify":
        if (await hasRemainingUIDReferences(claim.uid)) {
          throw new Error("uid_references_remaining");
        }
        if (await hasIncompleteAccountDeletionMessageCleanup(claim.requestID)) {
          await yieldForRetry(claim, "message_cleanup_pending");
          return;
        }
        await advance(claim, "providerAndAuth");
        break;
      case "providerAndAuth":
        await deleteProviderAndAuth(claim);
        await advance(claim, "finalize");
        break;
      case "finalize":
        await finalize(claim);
        return;
      default:
        throw new Error("invalid_account_deletion_stage");
      }
    }
    await yieldForRetry(claim, "invocation_step_limit");
  } catch (error) {
    const code = error instanceof Error ? error.message.slice(0, 120) : "unknown";
    await yieldForRetry(claim, code);
  }
}

export async function runAccountDeletionDrain(nowMillis = Date.now()) {
  const sessionRevocations = await retryFailedSessionRevocations();
  const requestIDs = await dueRequestIDs(Timestamp.fromMillis(nowMillis));
  let claimed = 0;
  for (const requestID of requestIDs) {
    const claim = await claimRequest(requestID, nowMillis);
    if (!claim) continue;
    claimed += 1;
    await processClaim(claim);
  }
  return {scanned: requestIDs.length, claimed, sessionRevocations};
}

export const finalizeExpiredAccountDeletions = onSchedule(
  {
    schedule: "0 * * * *",
    timeZone: "Asia/Seoul",
    region: FUNCTIONS_REGION,
    timeoutSeconds: 540,
    memory: "1GiB",
    secrets: [kakaoAdminKey, deletionLedgerHmacKey],
  },
  async () => {
    await runAccountDeletionDrain();
  },
);
