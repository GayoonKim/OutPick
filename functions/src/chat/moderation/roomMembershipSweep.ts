/* eslint-disable require-jsdoc, max-len */
import {createHash} from "node:crypto";
import {FieldValue, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {db} from "../../core/firebase.js";
import {effectiveModerationState} from "../../moderation/state.js";
import {appendRoomRoleEvent, storedModeratorCount} from "./roomRoleService.js";

export type RoomMembershipSweepCause = "accountDeletion" | "permanentSuspension";

type Successor = {uid: string; principalID: string; moderatorSinceMillis: number};

const MEMBER_PAGE_SIZE = 25;

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

export async function removeOrdinaryMembership(
  firestore: Firestore,
  roomRef: FirebaseFirestore.DocumentReference,
  targetUID: string,
  now: Date,
  guard?: (transaction: Transaction) => Promise<void>,
): Promise<void> {
  const refs = membershipRefs(firestore, roomRef, targetUID);
  const moderationStateRef = firestore.collection("roomModerationStates").doc(roomRef.id);
  await firestore.runTransaction(async (transaction) => {
    const [room, member, moderationState] = await Promise.all([
      transaction.get(roomRef), transaction.get(refs.member), transaction.get(moderationStateRef),
    ]);
    if (guard) await guard(transaction);
    if (!member.exists) return;
    // 실패·진행 중인 방장 승계는 일반 참여방 정리가 대신 삭제하지 않는다.
    if (room.exists && canonicalOwnerUID(room.data()) === targetUID) return;
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
  prepareCompletion?: (transaction: Transaction) => Promise<() => void>,
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
    // 최종 읽기 이후 현재 시각·세대·작업 상태를 다시 확인하고 완료를 같은 commit에 묶는다.
    const complete = prepareCompletion ? await prepareCompletion(transaction) : () => undefined;
    if (!room.exists || !activeRoom(room.data()) || canonicalOwnerUID(room.data()) !== targetUID) {
      complete();
      return "settled";
    }
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
    complete();
    return "settled";
  });
}

export async function resolveOwnedRoom(
  firestore: Firestore,
  roomRef: FirebaseFirestore.DocumentReference,
  targetUID: string,
  cause: RoomMembershipSweepCause,
  now: Date,
  prepareCompletion?: (transaction: Transaction) => Promise<() => void>,
): Promise<void> {
  for (let retry = 0; retry < 5; retry += 1) {
    const successor = await selectSuccessor(firestore, roomRef, targetUID, now);
    const result = await applyOwnedRoomResolution(firestore, roomRef, targetUID, cause, successor, now, prepareCompletion);
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
