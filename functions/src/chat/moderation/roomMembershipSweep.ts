/* eslint-disable require-jsdoc, max-len */
import {createHash, randomUUID} from "node:crypto";
import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {db} from "../../core/firebase.js";
import {effectiveModerationState} from "../../moderation/state.js";

export type RoomMembershipSweepCause = "accountDeletion" | "permanentSuspension";

const MEMBER_PAGE_SIZE = 25;
const JOB_MAX_ATTEMPTS = 20;
const JOB_LEASE_MILLIS = 10 * 60 * 1000;

function validID(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && !value.includes("/");
}

function activeRoom(data: FirebaseFirestore.DocumentData | undefined): boolean {
  return Boolean(data) && data?.isClosed !== true &&
    (data?.lifecycleStatus === undefined || data?.lifecycleStatus === "active");
}

function eligibleAccount(
  snapshot: FirebaseFirestore.DocumentSnapshot,
  now: Date,
): {eligible: boolean; principalID: string | null} {
  const data = snapshot.data();
  if (!snapshot.exists || data?.accountStatus !== "active") {
    return {eligible: false, principalID: null};
  }
  const principalID = validID(data.moderationPrincipalID) ? data.moderationPrincipalID : null;
  if (!principalID) return {eligible: false, principalID: null};
  try {
    return {
      eligible: effectiveModerationState(data, now).moderationStatus === "active",
      principalID,
    };
  } catch {
    return {eligible: false, principalID};
  }
}

function sortedCandidates(
  targetUID: string,
  members: FirebaseFirestore.QuerySnapshot,
): FirebaseFirestore.QueryDocumentSnapshot[] {
  return members.docs
    .filter((candidate) => candidate.id !== targetUID)
    .sort((lhs, rhs) => {
      const left = lhs.get("joinedAt") instanceof Timestamp ?
        lhs.get("joinedAt").toMillis() : Number.MAX_SAFE_INTEGER;
      const right = rhs.get("joinedAt") instanceof Timestamp ?
        rhs.get("joinedAt").toMillis() : Number.MAX_SAFE_INTEGER;
      return left === right ? lhs.id.localeCompare(rhs.id) : left - right;
    });
}

async function selectSuccessor(
  firestore: Firestore,
  roomRef: FirebaseFirestore.DocumentReference,
  targetUID: string,
  now: Date,
): Promise<{
  member: FirebaseFirestore.QueryDocumentSnapshot;
  accountRef: FirebaseFirestore.DocumentReference;
  principalID: string;
} | null> {
  const members = await roomRef.collection("members").get();
  const candidates = sortedCandidates(targetUID, members);
  if (candidates.length === 0) return null;
  const accountRefs = candidates.map((candidate) =>
    firestore.collection("moderationAccounts").doc(candidate.id));
  const accounts = await firestore.getAll(...accountRefs);
  for (let index = 0; index < candidates.length; index += 1) {
    const state = eligibleAccount(accounts[index], now);
    if (!state.eligible || !state.principalID) continue;
    const ban = await roomRef.collection("bans").doc(state.principalID).get();
    if (!ban.exists || ban.get("isActive") !== true) {
      return {
        member: candidates[index],
        accountRef: accountRefs[index],
        principalID: state.principalID,
      };
    }
  }
  return null;
}

function membershipRefs(
  firestore: Firestore,
  roomRef: FirebaseFirestore.DocumentReference,
  uid: string,
): {
  member: FirebaseFirestore.DocumentReference;
  joined: FirebaseFirestore.DocumentReference;
  state: FirebaseFirestore.DocumentReference;
} {
  const user = firestore.collection("users").doc(uid);
  return {
    member: roomRef.collection("members").doc(uid),
    joined: user.collection("joinedRooms").doc(roomRef.id),
    state: user.collection("roomStates").doc(roomRef.id),
  };
}

async function removeOrdinaryMembership(
  firestore: Firestore,
  roomRef: FirebaseFirestore.DocumentReference,
  targetUID: string,
  now: Date,
): Promise<void> {
  const refs = membershipRefs(firestore, roomRef, targetUID);
  await firestore.runTransaction(async (transaction) => {
    const [room, member] = await Promise.all([
      transaction.get(roomRef),
      transaction.get(refs.member),
    ]);
    if (!member.exists) return;
    const currentCount = Number(room.get("memberCount"));
    if (room.exists) {
      transaction.update(roomRef, {
        memberCount: Math.max(0, (Number.isSafeInteger(currentCount) ? currentCount : 0) - 1),
        updatedAt: Timestamp.fromDate(now),
      });
    }
    transaction.delete(refs.member);
    transaction.delete(refs.joined);
    transaction.delete(refs.state);
  });
}

async function resolveOwnedRoom(
  firestore: Firestore,
  roomRef: FirebaseFirestore.DocumentReference,
  targetUID: string,
  cause: RoomMembershipSweepCause,
  now: Date,
): Promise<void> {
  const successor = await selectSuccessor(firestore, roomRef, targetUID, now);
  const targetRefs = membershipRefs(firestore, roomRef, targetUID);
  const successorRefs = successor ? membershipRefs(firestore, roomRef, successor.member.id) : null;
  const cleanupRef = firestore.collection("moderationRoomCleanupJobs").doc(roomRef.id);
  await firestore.runTransaction(async (transaction) => {
    const reads: Promise<FirebaseFirestore.DocumentSnapshot>[] = [
      transaction.get(roomRef),
      transaction.get(targetRefs.member),
    ];
    if (successor && successorRefs) {
      reads.push(
        transaction.get(successorRefs.member),
        transaction.get(successor.accountRef),
        transaction.get(roomRef.collection("bans").doc(successor.principalID)),
      );
    } else {
      reads.push(transaction.get(cleanupRef));
    }
    const snapshots = await Promise.all(reads);
    const room = snapshots[0];
    const targetMember = snapshots[1];
    if (!room.exists || !activeRoom(room.data()) || room.get("creatorUID") !== targetUID) {
      return;
    }
    const currentCount = Number(room.get("memberCount"));
    const nextCount = Math.max(
      0,
      (Number.isSafeInteger(currentCount) ? currentCount : 0) - (targetMember.exists ? 1 : 0),
    );
    const nowTimestamp = Timestamp.fromDate(now);
    if (successor && successorRefs) {
      const successorMember = snapshots[2];
      const successorAccount = snapshots[3];
      const successorBan = snapshots[4];
      const state = eligibleAccount(successorAccount, now);
      if (!successorMember.exists || !state.eligible ||
        state.principalID !== successor.principalID ||
        (successorBan.exists && successorBan.get("isActive") === true)) {
        throw new Error("room_successor_changed");
      }
      transaction.update(roomRef, {
        creatorUID: successor.member.id,
        memberCount: nextCount,
        updatedAt: nowTimestamp,
      });
      transaction.set(successorRefs.member, {
        role: "owner",
        updatedAt: nowTimestamp,
      }, {merge: true});
      transaction.set(successorRefs.joined, {
        role: "owner",
        updatedAt: nowTimestamp,
      }, {merge: true});
    } else {
      const existingJob = snapshots[2];
      if (existingJob.exists) throw new Error("room_cleanup_job_conflict");
      const currentVersion = Number(room.get("lifecycleVersion"));
      const lifecycleVersion = (Number.isSafeInteger(currentVersion) && currentVersion > 0 ?
        currentVersion : 1) + 1;
      const closureType = cause === "accountDeletion" ?
        "closedByOwner" : "closedByModeration";
      const closureNoticeCode = cause === "accountDeletion" ?
        "ownerDeleted" : "communityGuidelineViolation";
      transaction.update(roomRef, {
        isClosed: true,
        lifecycleStatus: closureType,
        lifecycleVersion,
        closureNoticeCode,
        closedAt: nowTimestamp,
        moderationClosedAt: cause === "permanentSuspension" ? nowTimestamp : null,
        moderationClosureNoticeCode: cause === "permanentSuspension" ? closureNoticeCode : null,
        memberCount: nextCount,
        updatedAt: nowTimestamp,
      });
      transaction.create(cleanupRef, {
        schemaVersion: 2,
        roomID: roomRef.id,
        lifecycleVersion,
        closureType,
        closureNoticeCode,
        cleanupPhase: "content",
        status: "pending",
        attempt: 0,
        nextAttemptAt: nowTimestamp,
        leaseExpiresAt: null,
        lastErrorCode: null,
        createdAt: nowTimestamp,
        updatedAt: nowTimestamp,
        expiresAt: null,
      });
    }
    if (targetMember.exists) transaction.delete(targetRefs.member);
    transaction.delete(targetRefs.joined);
    transaction.delete(targetRefs.state);
  });
}

export async function resolveRoomMembershipPage(
  targetUID: string,
  cause: RoomMembershipSweepCause,
  now = new Date(),
  firestore: Firestore = db,
): Promise<boolean> {
  const ownedRooms = await firestore.collection("Rooms")
    .where("creatorUID", "==", targetUID)
    .where("isClosed", "==", false)
    .limit(1)
    .get();
  if (!ownedRooms.empty) {
    await resolveOwnedRoom(firestore, ownedRooms.docs[0].ref, targetUID, cause, now);
    return false;
  }
  const members = await firestore.collectionGroup("members")
    .where("userID", "==", targetUID)
    .limit(MEMBER_PAGE_SIZE)
    .get();
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
  return createHash("sha256")
    .update(`${targetUID}:${cause}:${expectedStateVersion}`)
    .digest("hex");
}

export async function processRoomOwnershipSuccessionJob(
  jobID: string,
  firestore: Firestore = db,
  now = new Date(),
): Promise<boolean> {
  const ref = firestore.collection("roomOwnershipSuccessionJobs").doc(jobID);
  const leaseOwner = randomUUID();
  const claimed = await firestore.runTransaction(async (transaction) => {
    const job = await transaction.get(ref);
    if (!job.exists) return null;
    const status = job.get("status");
    const nextAttemptAt = job.get("nextAttemptAt");
    const leaseExpiresAt = job.get("leaseExpiresAt");
    const due = nextAttemptAt instanceof Timestamp && nextAttemptAt.toMillis() <= now.getTime();
    const stale = leaseExpiresAt instanceof Timestamp && leaseExpiresAt.toMillis() <= now.getTime();
    if (!["pending", "retryPending", "processing"].includes(status) ||
      (!due && !(status === "processing" && stale))) return null;
    const attempt = Number(job.get("attempt")) + 1;
    if (!Number.isSafeInteger(attempt) || attempt > JOB_MAX_ATTEMPTS) return null;
    transaction.update(ref, {
      status: "processing",
      attempt,
      leaseOwner,
      leaseExpiresAt: Timestamp.fromMillis(now.getTime() + JOB_LEASE_MILLIS),
      updatedAt: Timestamp.fromDate(now),
    });
    return {
      targetUID: job.get("targetUID"),
      cause: job.get("cause") as RoomMembershipSweepCause,
      attempt,
    };
  });
  if (!claimed || !validID(claimed.targetUID) || claimed.cause !== "permanentSuspension") {
    return false;
  }
  try {
    const completed = await resolveRoomMembershipPage(
      claimed.targetUID,
      claimed.cause,
      now,
      firestore,
    );
    await ref.update(completed ? {
      status: "completed",
      completedAt: Timestamp.fromDate(now),
      leaseOwner: null,
      leaseExpiresAt: null,
      nextAttemptAt: null,
      updatedAt: Timestamp.fromDate(now),
      expiresAt: Timestamp.fromMillis(now.getTime() + 30 * 24 * 60 * 60 * 1000),
    } : {
      status: "retryPending",
      leaseOwner: null,
      leaseExpiresAt: null,
      nextAttemptAt: Timestamp.fromMillis(now.getTime() + 1_000),
      updatedAt: Timestamp.fromDate(now),
    });
    return completed;
  } catch (error) {
    const terminal = claimed.attempt >= JOB_MAX_ATTEMPTS;
    await ref.update({
      status: terminal ? "failed" : "retryPending",
      leaseOwner: null,
      leaseExpiresAt: null,
      nextAttemptAt: terminal ? null : Timestamp.fromMillis(now.getTime() + 60_000),
      lastErrorCode: error instanceof Error ? error.message.slice(0, 120) : "unknown",
      updatedAt: Timestamp.fromDate(now),
    });
    return false;
  }
}

export async function dueRoomOwnershipSuccessionJobIDs(
  firestore: Firestore = db,
  now = new Date(),
  limit = 25,
): Promise<string[]> {
  const snapshot = await firestore.collection("roomOwnershipSuccessionJobs")
    .where("status", "in", ["pending", "retryPending", "processing"])
    .where("nextAttemptAt", "<=", Timestamp.fromDate(now))
    .orderBy("nextAttemptAt")
    .limit(limit)
    .get();
  return snapshot.docs.map((document) => document.id);
}
