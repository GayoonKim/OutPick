/* eslint-disable require-jsdoc, max-len */
import {createHash, randomUUID} from "node:crypto";
import {FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {db} from "../../core/firebase.js";
import {effectiveModerationState} from "../../moderation/state.js";
import {appendRoomRoleEvent, storedModeratorCount} from "./roomRoleService.js";

export type RoomMembershipSweepCause = "accountDeletion" | "permanentSuspension";

type SuccessionJobClaim = {
  jobID: string;
  targetUID: string;
  cause: RoomMembershipSweepCause;
  attempt: number;
  leaseOwner: string;
  expectedStateVersion: number | null;
  accountDeletionRequestID: string | null;
  accountGenerationID: string | null;
};

type Successor = {uid: string; principalID: string; moderatorSinceMillis: number};

const MEMBER_PAGE_SIZE = 25;
const JOB_MAX_ATTEMPTS = 4;
const JOB_LEASE_MILLIS = 10 * 60 * 1000;
const COMPLETED_RETENTION_MILLIS = 30 * 24 * 60 * 60 * 1000;
const RETRY_DELAYS_MILLIS: readonly number[] = [
  0, 5_000, 15_000, 30_000,
];

function validID(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && !value.includes("/");
}

function activeRoom(data: FirebaseFirestore.DocumentData | undefined): boolean {
  return Boolean(data) && data?.isClosed !== true &&
    (data?.lifecycleStatus === undefined || data?.lifecycleStatus === "active");
}

function canonicalOwnerUID(data: FirebaseFirestore.DocumentData | undefined): string | null {
  if (data?.ownerUID !== undefined) return validID(data.ownerUID) ? data.ownerUID : null;
  return validID(data?.creatorUID) ? data?.creatorUID : null;
}

function eligibleAccount(
  snapshot: FirebaseFirestore.DocumentSnapshot,
  now: Date,
): {eligible: boolean; principalID: string | null} {
  const data = snapshot.data();
  if (!snapshot.exists || data?.accountStatus !== "active") return {eligible: false, principalID: null};
  const principalID = validID(data.moderationPrincipalID) ? data.moderationPrincipalID : null;
  if (!principalID) return {eligible: false, principalID: null};
  try {
    return {eligible: effectiveModerationState(data, now).moderationStatus === "active", principalID};
  } catch {
    return {eligible: false, principalID};
  }
}

function moderatorSinceMillis(snapshot: FirebaseFirestore.DocumentSnapshot): number | null {
  const value = snapshot.get("moderatorSince");
  return value instanceof Timestamp ? value.toMillis() : null;
}

function membershipRefs(
  firestore: Firestore,
  roomRef: FirebaseFirestore.DocumentReference,
  uid: string,
) {
  const user = firestore.collection("users").doc(uid);
  return {
    member: roomRef.collection("members").doc(uid),
    joined: user.collection("joinedRooms").doc(roomRef.id),
    state: user.collection("roomStates").doc(roomRef.id),
  };
}

async function selectSuccessor(
  firestore: Firestore,
  roomRef: FirebaseFirestore.DocumentReference,
  targetUID: string,
  now: Date,
): Promise<Successor | null> {
  const moderators = await roomRef.collection("members").where("role", "==", "moderator").get();
  const candidates = moderators.docs
    .map((candidate) => ({snapshot: candidate, moderatorSinceMillis: moderatorSinceMillis(candidate)}))
    .filter((candidate): candidate is {snapshot: FirebaseFirestore.QueryDocumentSnapshot; moderatorSinceMillis: number} =>
      candidate.snapshot.id !== targetUID && candidate.moderatorSinceMillis !== null)
    .sort((lhs, rhs) => {
      return lhs.moderatorSinceMillis === rhs.moderatorSinceMillis ?
        lhs.snapshot.id.localeCompare(rhs.snapshot.id) : lhs.moderatorSinceMillis - rhs.moderatorSinceMillis;
    });
  for (const candidate of candidates) {
    const joinedRef = firestore.collection("users").doc(candidate.snapshot.id).collection("joinedRooms").doc(roomRef.id);
    const accountRef = firestore.collection("moderationAccounts").doc(candidate.snapshot.id);
    const [joined, account] = await firestore.getAll(joinedRef, accountRef);
    if (!joined.exists || joined.get("role") !== "moderator") continue;
    const state = eligibleAccount(account, now);
    if (!state.eligible || !state.principalID) continue;
    const ban = await roomRef.collection("bans").doc(state.principalID).get();
    if (ban.exists && ban.get("isActive") === true) continue;
    return {
      uid: candidate.snapshot.id,
      principalID: state.principalID,
      moderatorSinceMillis: candidate.moderatorSinceMillis,
    };
  }
  return null;
}

async function removeOrdinaryMembership(
  firestore: Firestore,
  roomRef: FirebaseFirestore.DocumentReference,
  targetUID: string,
  now: Date,
): Promise<void> {
  const refs = membershipRefs(firestore, roomRef, targetUID);
  const moderationStateRef = firestore.collection("roomModerationStates").doc(roomRef.id);
  await firestore.runTransaction(async (transaction) => {
    const [room, member, moderationState] = await Promise.all([
      transaction.get(roomRef), transaction.get(refs.member), transaction.get(moderationStateRef),
    ]);
    if (!member.exists) return;
    const currentCount = Number(room.get("memberCount"));
    const nowTimestamp = Timestamp.fromDate(now);
    if (room.exists) {
      transaction.update(roomRef, {
        memberCount: Math.max(0, (Number.isSafeInteger(currentCount) ? currentCount : 0) - 1), updatedAt: nowTimestamp,
      });
    }
    if (member.get("role") === "moderator") {
      const moderatorCount = storedModeratorCount(moderationState);
      if (moderatorCount <= 0) throw new Error("room_moderator_count_invalid");
      transaction.update(moderationStateRef, {moderatorCount: moderatorCount - 1, updatedAt: nowTimestamp});
    }
    transaction.delete(refs.member);
    transaction.delete(refs.joined);
    transaction.delete(refs.state);
  });
}

async function applyOwnedRoomResolution(
  firestore: Firestore,
  roomRef: FirebaseFirestore.DocumentReference,
  targetUID: string,
  cause: RoomMembershipSweepCause,
  successor: Successor | null,
  now: Date,
): Promise<"settled" | "candidateChanged"> {
  const targetRefs = membershipRefs(firestore, roomRef, targetUID);
  const successorRefs = successor ? membershipRefs(firestore, roomRef, successor.uid) : null;
  const moderationStateRef = firestore.collection("roomModerationStates").doc(roomRef.id);
  const cleanupRef = firestore.collection("moderationRoomCleanupJobs").doc(roomRef.id);
  return firestore.runTransaction(async (transaction) => {
    const reads: Promise<FirebaseFirestore.DocumentSnapshot>[] = [
      transaction.get(roomRef), transaction.get(targetRefs.member), transaction.get(targetRefs.joined),
    ];
    if (successor && successorRefs) {
      reads.push(
        transaction.get(successorRefs.member),
        transaction.get(successorRefs.joined),
        transaction.get(firestore.collection("moderationAccounts").doc(successor.uid)),
        transaction.get(roomRef.collection("bans").doc(successor.principalID)),
        transaction.get(firestore.collection("userPublicProfiles").doc(successor.uid)),
        transaction.get(moderationStateRef),
      );
    } else {
      reads.push(transaction.get(cleanupRef));
    }
    const snapshots = await Promise.all(reads);
    const room = snapshots[0];
    const targetMember = snapshots[1];
    const targetJoined = snapshots[2];
    if (!room.exists || !activeRoom(room.data()) || canonicalOwnerUID(room.data()) !== targetUID) return "settled";
    if (!targetMember.exists || targetMember.get("role") !== "owner" ||
      !targetJoined.exists || targetJoined.get("role") !== "owner") {
      throw new Error("room_owner_projection_invalid");
    }
    const currentMemberCount = Number(room.get("memberCount"));
    const memberCount = Math.max(0, (Number.isSafeInteger(currentMemberCount) ? currentMemberCount : 0) - 1);
    const nowTimestamp = Timestamp.fromDate(now);
    if (successor && successorRefs) {
      const successorMember = snapshots[3];
      const successorJoined = snapshots[4];
      const successorAccount = snapshots[5];
      const successorBan = snapshots[6];
      const successorProfile = snapshots[7];
      const moderationState = snapshots[8];
      const state = eligibleAccount(successorAccount, now);
      if (!successorMember.exists || successorMember.get("role") !== "moderator" ||
        moderatorSinceMillis(successorMember) !== successor.moderatorSinceMillis ||
        !successorJoined.exists || successorJoined.get("role") !== "moderator" ||
        !state.eligible || state.principalID !== successor.principalID ||
        (successorBan.exists && successorBan.get("isActive") === true)) return "candidateChanged";
      const moderatorCount = storedModeratorCount(moderationState);
      if (moderatorCount <= 0) throw new Error("room_moderator_count_invalid");
      const nicknameValue = successorProfile.get("nickname");
      const nickname = typeof nicknameValue === "string" && nicknameValue.trim() ?
        nicknameValue.trim().slice(0, 80) : "알 수 없는 사용자";
      const event = appendRoomRoleEvent(
        transaction, firestore, roomRef, room.get("seq"), "ownershipTransferred",
        successor.uid, nickname, nowTimestamp,
      );
      transaction.update(roomRef, {ownerUID: successor.uid, memberCount, seq: event.seq, updatedAt: nowTimestamp});
      transaction.update(successorRefs.member, {role: "owner", moderatorSince: FieldValue.delete(), updatedAt: nowTimestamp});
      transaction.update(successorRefs.joined, {role: "owner", moderatorSince: FieldValue.delete(), updatedAt: nowTimestamp});
      transaction.update(moderationStateRef, {moderatorCount: moderatorCount - 1, updatedAt: nowTimestamp});
    } else {
      const existingCleanup = snapshots[3];
      if (existingCleanup.exists) throw new Error("room_cleanup_job_conflict");
      const currentVersion = Number(room.get("lifecycleVersion"));
      const lifecycleVersion = (Number.isSafeInteger(currentVersion) && currentVersion > 0 ? currentVersion : 1) + 1;
      const closureType = cause === "accountDeletion" ? "closedByOwner" : "closedByModeration";
      const closureNoticeCode = cause === "accountDeletion" ? "ownerDeleted" : "communityGuidelineViolation";
      transaction.update(roomRef, {
        isClosed: true, lifecycleStatus: closureType, lifecycleVersion, closureNoticeCode,
        closedAt: nowTimestamp, moderationClosedAt: cause === "permanentSuspension" ? nowTimestamp : null,
        moderationClosureNoticeCode: cause === "permanentSuspension" ? closureNoticeCode : null,
        memberCount, updatedAt: nowTimestamp,
      });
      transaction.create(cleanupRef, {
        schemaVersion: 2, roomID: roomRef.id, lifecycleVersion, closureType, closureNoticeCode,
        cleanupPhase: "content", status: "pending", attempt: 0, nextAttemptAt: nowTimestamp,
        leaseExpiresAt: null, lastErrorCode: null, createdAt: nowTimestamp, updatedAt: nowTimestamp, expiresAt: null,
      });
    }
    transaction.delete(targetRefs.member);
    transaction.delete(targetRefs.joined);
    transaction.delete(targetRefs.state);
    return "settled";
  });
}

async function resolveOwnedRoom(
  firestore: Firestore,
  roomRef: FirebaseFirestore.DocumentReference,
  targetUID: string,
  cause: RoomMembershipSweepCause,
  now: Date,
): Promise<void> {
  for (let retry = 0; retry < 5; retry += 1) {
    const successor = await selectSuccessor(firestore, roomRef, targetUID, now);
    const result = await applyOwnedRoomResolution(firestore, roomRef, targetUID, cause, successor, now);
    if (result === "settled") return;
  }
  throw new Error("room_successor_changed");
}

async function ownedRoomSnapshot(
  firestore: Firestore,
  targetUID: string,
): Promise<FirebaseFirestore.QueryDocumentSnapshot | null> {
  const canonical = await firestore.collection("Rooms")
    .where("ownerUID", "==", targetUID).where("isClosed", "==", false).limit(1).get();
  if (!canonical.empty) return canonical.docs[0];
  const legacy = await firestore.collection("Rooms")
    .where("creatorUID", "==", targetUID).where("isClosed", "==", false).limit(1).get();
  return legacy.docs[0] ?? null;
}

export async function resolveRoomMembershipPage(
  targetUID: string,
  cause: RoomMembershipSweepCause,
  now = new Date(),
  firestore: Firestore = db,
): Promise<boolean> {
  const ownedRoom = await ownedRoomSnapshot(firestore, targetUID);
  if (ownedRoom) {
    await resolveOwnedRoom(firestore, ownedRoom.ref, targetUID, cause, now);
    return false;
  }
  const members = await firestore.collectionGroup("members")
    .where("userID", "==", targetUID).limit(MEMBER_PAGE_SIZE).get();
  for (const member of members.docs) {
    const roomRef = member.ref.parent.parent;
    if (roomRef) await removeOrdinaryMembership(firestore, roomRef, targetUID, now);
    else await member.ref.delete();
  }
  return members.size < MEMBER_PAGE_SIZE;
}

export function roomOwnershipSuccessionJobID(
  targetUID: string,
  cause: RoomMembershipSweepCause,
  expectedStateVersion: number,
): string {
  return createHash("sha256").update(`${targetUID}:${cause}:${expectedStateVersion}`).digest("hex");
}

export function accountDeletionSuccessionJobID(requestID: string): string {
  return createHash("sha256").update(`accountDeletion:${requestID}`).digest("hex");
}

export function successionRetryDelayMillis(attempt: number): number | null {
  return RETRY_DELAYS_MILLIS[attempt] ?? null;
}

export function retryableSuccessionError(error: unknown): boolean {
  const code = (error as {code?: unknown})?.code;
  if ([4, 8, 10, 13, 14].includes(typeof code === "number" ? code : -1)) return true;
  if (typeof code === "string" && [
    "aborted", "deadline-exceeded", "resource-exhausted", "internal", "unavailable",
  ].includes(code)) return true;
  return error instanceof Error && error.message === "room_successor_changed";
}

async function claimJob(jobID: string, firestore: Firestore, now: Date): Promise<SuccessionJobClaim | null> {
  const ref = firestore.collection("roomOwnershipSuccessionJobs").doc(jobID);
  const leaseOwner = randomUUID();
  return firestore.runTransaction(async (transaction) => {
    const job = await transaction.get(ref);
    if (!job.exists) return null;
    const status = job.get("status");
    const nextAttemptAt = job.get("nextAttemptAt");
    const leaseExpiresAt = job.get("leaseExpiresAt");
    const due = nextAttemptAt instanceof Timestamp && nextAttemptAt.toMillis() <= now.getTime();
    const stale = leaseExpiresAt instanceof Timestamp && leaseExpiresAt.toMillis() <= now.getTime();
    const claimable = status === "processing" ? stale :
      (status === "pending" || status === "retryPending") && due;
    if (!claimable) return null;
    const previousAttempt = Number(job.get("attempt"));
    const attempt = Number.isSafeInteger(previousAttempt) ? previousAttempt + 1 : 1;
    if (attempt > JOB_MAX_ATTEMPTS) {
      transaction.update(ref, {
        status: "failed", nextAttemptAt: null, leaseOwner: null, leaseExpiresAt: null,
        lastErrorCode: "max_attempts_exceeded", updatedAt: Timestamp.fromDate(now),
      });
      return null;
    }
    const targetUID = job.get("targetUID");
    const cause = job.get("cause") as RoomMembershipSweepCause;
    if (!validID(targetUID) || (cause !== "accountDeletion" && cause !== "permanentSuspension")) {
      transaction.update(ref, {
        status: "failed", nextAttemptAt: null, leaseOwner: null, leaseExpiresAt: null,
        lastErrorCode: "invalid_job_contract", updatedAt: Timestamp.fromDate(now),
      });
      return null;
    }
    transaction.update(ref, {
      status: "processing", attempt, leaseOwner,
      leaseExpiresAt: Timestamp.fromMillis(now.getTime() + JOB_LEASE_MILLIS), updatedAt: Timestamp.fromDate(now),
    });
    return {
      jobID, targetUID, cause, attempt, leaseOwner,
      expectedStateVersion: Number.isSafeInteger(job.get("expectedStateVersion")) ? Number(job.get("expectedStateVersion")) : null,
      accountDeletionRequestID: validID(job.get("accountDeletionRequestID")) ? job.get("accountDeletionRequestID") : null,
      accountGenerationID: validID(job.get("accountGenerationID")) ? job.get("accountGenerationID") : null,
    };
  });
}

async function fenceIsCurrent(claim: SuccessionJobClaim, firestore: Firestore): Promise<boolean> {
  if (claim.cause === "permanentSuspension") {
    if (claim.expectedStateVersion === null) return false;
    const account = await firestore.collection("moderationAccounts").doc(claim.targetUID).get();
    return account.exists && account.get("accountStatus") === "active" &&
      account.get("moderationStatus") === "suspended" && account.get("stateVersion") === claim.expectedStateVersion;
  }
  if (!claim.accountDeletionRequestID || !claim.accountGenerationID) return false;
  const [request, user] = await firestore.getAll(
    firestore.collection("accountDeletionRequests").doc(claim.accountDeletionRequestID),
    firestore.collection("users").doc(claim.targetUID),
  );
  return request.exists && request.get("uid") === claim.targetUID &&
    request.get("accountGenerationID") === claim.accountGenerationID &&
    ["finalizing", "retryPending"].includes(request.get("status")) && request.get("stage") === "rooms" &&
    user.exists && user.get("accountStatus") === "deletionPending" &&
    user.get("accountGenerationID") === claim.accountGenerationID;
}

async function finishClaim(
  claim: SuccessionJobClaim,
  firestore: Firestore,
  patch: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>,
): Promise<void> {
  const ref = firestore.collection("roomOwnershipSuccessionJobs").doc(claim.jobID);
  await firestore.runTransaction(async (transaction) => {
    const job = await transaction.get(ref);
    if (!job.exists || job.get("status") !== "processing" || job.get("leaseOwner") !== claim.leaseOwner) {
      throw new Error("room_succession_lease_lost");
    }
    transaction.update(ref, patch);
  });
}

export async function processRoomOwnershipSuccessionJob(
  jobID: string,
  firestore: Firestore = db,
  now = new Date(),
): Promise<boolean> {
  const claim = await claimJob(jobID, firestore, now);
  if (!claim) return false;
  try {
    if (!(await fenceIsCurrent(claim, firestore))) {
      await finishClaim(claim, firestore, {
        status: "completed", result: "staleFence", completedAt: Timestamp.fromDate(now),
        leaseOwner: null, leaseExpiresAt: null, nextAttemptAt: null, lastErrorCode: null,
        updatedAt: Timestamp.fromDate(now), expiresAt: Timestamp.fromMillis(now.getTime() + COMPLETED_RETENTION_MILLIS),
      });
      return true;
    }
    const completed = await resolveRoomMembershipPage(claim.targetUID, claim.cause, now, firestore);
    if (completed) {
      await finishClaim(claim, firestore, {
        status: "completed", result: "resolved", completedAt: Timestamp.fromDate(now),
        leaseOwner: null, leaseExpiresAt: null, nextAttemptAt: null, lastErrorCode: null,
        updatedAt: Timestamp.fromDate(now), expiresAt: Timestamp.fromMillis(now.getTime() + COMPLETED_RETENTION_MILLIS),
      });
      return true;
    }
    // 정상적인 pagination은 실패 재시도 횟수로 계산하지 않는다.
    await finishClaim(claim, firestore, {
      status: "retryPending", attempt: Math.max(0, claim.attempt - 1),
      leaseOwner: null, leaseExpiresAt: null, nextAttemptAt: Timestamp.fromDate(now),
      lastErrorCode: null, updatedAt: Timestamp.fromDate(now),
    });
    return false;
  } catch (error) {
    const delay = successionRetryDelayMillis(claim.attempt);
    const terminal = delay === null || !retryableSuccessionError(error);
    const code = error instanceof Error ? error.message.slice(0, 120) : "unknown";
    await finishClaim(claim, firestore, {
      status: terminal ? "failed" : "retryPending", leaseOwner: null, leaseExpiresAt: null,
      nextAttemptAt: terminal ? null : Timestamp.fromMillis(now.getTime() + delay),
      lastErrorCode: code, updatedAt: Timestamp.fromDate(now),
    });
    if (terminal) {
      console.error("[roomSuccession] terminal failure", {
        severity: "ERROR", alertType: "ROOM_OWNERSHIP_SUCCESSION_FAILED",
        jobID, cause: claim.cause, attempt: claim.attempt, code,
      });
    }
    return false;
  }
}

export async function replayFailedRoomOwnershipSuccessionJob(
  jobID: string,
  firestore: Firestore = db,
  now = new Date(),
): Promise<boolean> {
  const ref = firestore.collection("roomOwnershipSuccessionJobs").doc(jobID);
  return firestore.runTransaction(async (transaction) => {
    const job = await transaction.get(ref);
    if (!job.exists || job.get("status") !== "failed") return false;
    transaction.update(ref, {
      status: "retryPending", attempt: 0, nextAttemptAt: Timestamp.fromDate(now),
      leaseOwner: null, leaseExpiresAt: null, lastErrorCode: null, completedAt: null,
      expiresAt: null, updatedAt: Timestamp.fromDate(now),
    });
    return true;
  });
}

export async function dueRoomOwnershipSuccessionJobIDs(
  firestore: Firestore = db,
  now = new Date(),
  limit = 25,
): Promise<string[]> {
  const snapshot = await firestore.collection("roomOwnershipSuccessionJobs")
    .where("status", "in", ["pending", "retryPending", "processing"])
    .where("nextAttemptAt", "<=", Timestamp.fromDate(now))
    .orderBy("nextAttemptAt").limit(limit).get();
  return snapshot.docs.map((document) => document.id);
}
