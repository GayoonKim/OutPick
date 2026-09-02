/* eslint-disable require-jsdoc, max-len */
import {createHash} from "node:crypto";
import {
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../../core/firebase.js";
import {requireAccountCapabilityData} from "../../shared/accountStatus.js";
import {
  AssignRoomModeratorInput,
  LeaveChatRoomInput,
  ResignRoomModeratorInput,
  RevokeRoomModeratorInput,
  TransferRoomOwnershipAndLeaveInput,
} from "./contracts.js";

export type RoomMemberRole = "owner" | "moderator" | "member";
type RoleOperation =
  "assignRoomModerator" |
  "revokeRoomModerator" |
  "resignRoomModerator" |
  "leaveChatRoom" |
  "transferRoomOwnershipAndLeave";
type RoleEventKind =
  "moderatorAssigned" |
  "moderatorRevoked" |
  "moderatorResigned" |
  "ownershipTransferred";

const MAX_MODERATOR_COUNT = 3;
const RECEIPT_RETENTION_MILLIS = 24 * 60 * 60 * 1000;

export type ResolvedRoomRole = {
  room: FirebaseFirestore.DocumentSnapshot;
  member: FirebaseFirestore.DocumentSnapshot;
  account: FirebaseFirestore.DocumentSnapshot;
  ownerUID: string;
  role: RoomMemberRole;
};

export function roomRoleError(errorCode: string, message: string, code: "permission-denied" | "failed-precondition" = "failed-precondition"): HttpsError {
  return new HttpsError(code, message, {errorCode});
}

function activeRoom(data: FirebaseFirestore.DocumentData): boolean {
  return data.isClosed !== true &&
    (data.lifecycleStatus === undefined || data.lifecycleStatus === "active");
}

export function storedRoomMemberRole(value: unknown): RoomMemberRole | null {
  return value === "owner" || value === "moderator" || value === "member" ? value : null;
}

function canonicalOwnerUID(data: FirebaseFirestore.DocumentData): string | null {
  if (data.ownerUID !== undefined) {
    return typeof data.ownerUID === "string" && data.ownerUID.trim() ? data.ownerUID.trim() : null;
  }
  return typeof data.creatorUID === "string" && data.creatorUID.trim() ? data.creatorUID.trim() : null;
}

function requireModerationCapability(
  snapshot: FirebaseFirestore.DocumentSnapshot,
  now: Date,
  target = false,
): FirebaseFirestore.DocumentData {
  try {
    return requireAccountCapabilityData(
      snapshot.exists ? snapshot.data() : undefined,
      "moderateOwnedRoom",
      now,
    );
  } catch (error) {
    if (target) throw roomRoleError("TARGET_NOT_ELIGIBLE", "운영 권한을 맡을 수 없는 참여자입니다.");
    throw error;
  }
}

export async function resolveRoomRoleInTransaction(
  transaction: Transaction,
  firestore: Firestore,
  roomID: string,
  actorUID: string,
  now: Date,
): Promise<ResolvedRoomRole> {
  const roomRef = firestore.collection("Rooms").doc(roomID);
  const memberRef = roomRef.collection("members").doc(actorUID);
  const accountRef = firestore.collection("moderationAccounts").doc(actorUID);
  const [room, member, account] = await Promise.all([
    transaction.get(roomRef),
    transaction.get(memberRef),
    transaction.get(accountRef),
  ]);
  const roomData = room.data();
  if (!room.exists || !roomData) {
    throw new HttpsError("not-found", "채팅방을 찾을 수 없습니다.");
  }
  if (!activeRoom(roomData)) {
    throw roomRoleError("ROOM_CLOSED", "폐쇄된 채팅방입니다.");
  }
  requireModerationCapability(account, now);
  const ownerUID = canonicalOwnerUID(roomData);
  const role = member.exists ? storedRoomMemberRole(member.get("role")) : null;
  if (!ownerUID || !role || (ownerUID === actorUID) !== (role === "owner")) {
    throw roomRoleError("ROOM_ROLE_STATE_INVALID", "채팅방 역할 상태가 올바르지 않습니다.");
  }
  return {room, member, account, ownerUID, role};
}

export function requireRoomOwner(resolved: ResolvedRoomRole): void {
  if (resolved.role !== "owner") {
    throw roomRoleError("NOT_ROOM_OWNER", "방장 권한이 필요합니다.", "permission-denied");
  }
}

function requireModerator(resolved: ResolvedRoomRole): void {
  if (resolved.role !== "moderator") {
    throw roomRoleError("NOT_ROOM_MODERATOR", "관리자 권한이 필요합니다.", "permission-denied");
  }
}

function receiptID(actorUID: string, clientRequestID: string): string {
  return createHash("sha256").update(`${actorUID}:${clientRequestID}`).digest("hex");
}

function requestFingerprint(operation: RoleOperation, roomID: string, subjectUID: string | null): string {
  return createHash("sha256")
    .update(JSON.stringify({operation, roomID, subjectUID}))
    .digest("hex");
}

export function storedModeratorCount(snapshot: FirebaseFirestore.DocumentSnapshot): number {
  const value = snapshot.get("moderatorCount");
  if (!snapshot.exists || !Number.isSafeInteger(value) || value < 0 || value > MAX_MODERATOR_COUNT) {
    throw roomRoleError("ROOM_ROLE_STATE_INVALID", "채팅방 관리자 수 상태가 올바르지 않습니다.");
  }
  return Number(value);
}

function replayResult(
  receipt: FirebaseFirestore.DocumentSnapshot,
  fingerprint: string,
  now: Date,
): Record<string, unknown> | null {
  if (!receipt.exists || !receipt.data()) return null;
  const expiresAt = receipt.get("expiresAt");
  if (!(expiresAt instanceof Timestamp) || expiresAt.toMillis() <= now.getTime()) return null;
  if (receipt.get("requestFingerprint") !== fingerprint) {
    throw roomRoleError("REQUEST_ID_CONFLICT", "이미 다른 요청에 사용된 요청 ID입니다.");
  }
  const stored = receipt.get("result");
  if (!stored || typeof stored !== "object" || Array.isArray(stored)) {
    throw roomRoleError("ROOM_ROLE_STATE_INVALID", "역할 변경 처리 결과가 올바르지 않습니다.");
  }
  return {...stored, deduplicated: true};
}

function nickname(snapshot: FirebaseFirestore.DocumentSnapshot): string {
  const value = snapshot.get("nickname");
  return typeof value === "string" && value.trim() ? value.trim().slice(0, 80) : "알 수 없는 사용자";
}

export function appendRoomRoleEvent(
  transaction: Transaction,
  firestore: Firestore,
  roomRef: FirebaseFirestore.DocumentReference,
  currentSeq: unknown,
  kind: RoleEventKind,
  subjectUID: string,
  subjectNicknameSnapshot: string,
  nowTimestamp: Timestamp,
): {eventID: string; seq: number} {
  const seq = Number.isSafeInteger(currentSeq) && Number(currentSeq) >= 0 ? Number(currentSeq) + 1 : 1;
  const eventRef = roomRef.collection("Messages").doc();
  transaction.create(eventRef, {
    ID: eventRef.id,
    roomID: roomRef.id,
    messageType: "roomRoleEvent",
    serverGenerated: true,
    roleEvent: {kind, subjectUID, subjectNicknameSnapshot},
    seq,
    sentAt: nowTimestamp,
  });
  transaction.create(firestore.collection("chatRoleEventDeliveryJobs").doc(eventRef.id), {
    schemaVersion: 1,
    roomID: roomRef.id,
    eventID: eventRef.id,
    seq,
    status: "pending",
    attempt: 0,
    nextAttemptAt: nowTimestamp,
    leaseOwner: null,
    leaseExpiresAt: null,
    lastErrorCode: null,
    createdAt: nowTimestamp,
    updatedAt: nowTimestamp,
    expiresAt: null,
  });
  return {eventID: eventRef.id, seq};
}

function persistReceipt(
  transaction: Transaction,
  ref: FirebaseFirestore.DocumentReference,
  actorUID: string,
  operation: RoleOperation,
  roomID: string,
  subjectUID: string | null,
  fingerprint: string,
  result: Record<string, unknown>,
  now: Date,
): void {
  transaction.set(ref, {
    schemaVersion: 1,
    actorUID,
    operation,
    roomID,
    subjectUID,
    requestFingerprint: fingerprint,
    result,
    eventID: result.eventID ?? null,
    createdAt: Timestamp.fromDate(now),
    expiresAt: Timestamp.fromMillis(now.getTime() + RECEIPT_RETENTION_MILLIS),
  });
}

async function mutateTargetModerator(
  actorUID: string,
  input: AssignRoomModeratorInput | RevokeRoomModeratorInput,
  operation: "assignRoomModerator" | "revokeRoomModerator",
  now: Date,
  firestore: Firestore,
): Promise<Record<string, unknown>> {
  const assigning = operation === "assignRoomModerator";
  const fingerprint = requestFingerprint(operation, input.roomID, input.targetUID);
  const receiptRef = firestore.collection("roomRoleMutationReceipts")
    .doc(receiptID(actorUID, input.clientRequestID));
  const roomRef = firestore.collection("Rooms").doc(input.roomID);
  const targetMemberRef = roomRef.collection("members").doc(input.targetUID);
  const targetJoinedRef = firestore.collection("users").doc(input.targetUID)
    .collection("joinedRooms").doc(input.roomID);
  const targetAccountRef = firestore.collection("moderationAccounts").doc(input.targetUID);
  const targetProfileRef = firestore.collection("userPublicProfiles").doc(input.targetUID);
  const stateRef = firestore.collection("roomModerationStates").doc(input.roomID);
  return firestore.runTransaction(async (transaction) => {
    const receipt = await transaction.get(receiptRef);
    const replay = replayResult(receipt, fingerprint, now);
    if (replay) return replay;
    const resolved = await resolveRoomRoleInTransaction(transaction, firestore, input.roomID, actorUID, now);
    requireRoomOwner(resolved);
    const [targetMember, targetJoined, targetAccount, targetProfile, state] = await Promise.all([
      transaction.get(targetMemberRef),
      transaction.get(targetJoinedRef),
      transaction.get(targetAccountRef),
      transaction.get(targetProfileRef),
      transaction.get(stateRef),
    ]);
    if (!targetMember.exists || !targetJoined.exists) {
      throw roomRoleError("TARGET_NOT_MEMBER", "참여 중인 사용자가 아닙니다.");
    }
    const memberRole = storedRoomMemberRole(targetMember.get("role"));
    const joinedRole = storedRoomMemberRole(targetJoined.get("role"));
    if (input.targetUID === resolved.ownerUID || memberRole === "owner" || joinedRole === "owner") {
      throw roomRoleError("TARGET_IS_OWNER", "방장은 대상이 될 수 없습니다.");
    }
    if (memberRole !== joinedRole) {
      throw roomRoleError("ROOM_ROLE_STATE_INVALID", "참여자 역할 상태가 올바르지 않습니다.");
    }
    if (assigning && memberRole === "moderator") {
      throw roomRoleError("TARGET_ALREADY_MODERATOR", "이미 관리자인 사용자입니다.");
    }
    if (!assigning && memberRole !== "moderator") {
      throw roomRoleError("TARGET_NOT_MODERATOR", "관리자가 아닌 사용자입니다.");
    }
    if (assigning && memberRole !== "member") {
      throw roomRoleError("TARGET_NOT_MEMBER", "관리자로 임명할 수 없는 참여자입니다.");
    }
    if (assigning) {
      const targetAccountData = requireModerationCapability(targetAccount, now, true);
      const principalID = targetAccountData.moderationPrincipalID;
      if (typeof principalID !== "string" || !principalID || principalID.includes("/")) {
        throw roomRoleError("TARGET_NOT_ELIGIBLE", "운영 권한을 맡을 수 없는 참여자입니다.");
      }
      const ban = await transaction.get(roomRef.collection("bans").doc(principalID));
      if (ban.exists && ban.get("isActive") === true) {
        throw roomRoleError("TARGET_NOT_ELIGIBLE", "운영 권한을 맡을 수 없는 참여자입니다.");
      }
    }
    // 신규 방은 첫 관리자 임명 전까지 서버 전용 카운터 문서가 없을 수 있다.
    // 회수 경로에서는 누락을 허용하지 않아 역할 projection 불일치를 fail-closed한다.
    const currentCount = state.exists ? storedModeratorCount(state) :
      assigning ? 0 : storedModeratorCount(state);
    if (assigning && currentCount >= MAX_MODERATOR_COUNT) {
      throw roomRoleError("MODERATOR_LIMIT_REACHED", "관리자는 최대 3명까지 임명할 수 있습니다.");
    }
    if (!assigning && currentCount <= 0) {
      throw roomRoleError("ROOM_ROLE_STATE_INVALID", "채팅방 관리자 수 상태가 올바르지 않습니다.");
    }
    const nextCount = currentCount + (assigning ? 1 : -1);
    const nextRole: RoomMemberRole = assigning ? "moderator" : "member";
    const nowTimestamp = Timestamp.fromDate(now);
    const roleFields = assigning ? {role: nextRole, moderatorSince: nowTimestamp, updatedAt: nowTimestamp} :
      {role: nextRole, moderatorSince: FieldValue.delete(), updatedAt: nowTimestamp};
    transaction.update(targetMemberRef, roleFields);
    transaction.update(targetJoinedRef, roleFields);
    if (state.exists) {
      transaction.update(stateRef, {moderatorCount: nextCount, updatedAt: nowTimestamp});
    } else {
      transaction.create(stateRef, {
        schemaVersion: 1,
        moderatorCount: nextCount,
        updatedAt: nowTimestamp,
      });
    }
    const event = appendRoomRoleEvent(
      transaction,
      firestore,
      roomRef,
      resolved.room.get("seq"),
      assigning ? "moderatorAssigned" : "moderatorRevoked",
      input.targetUID,
      nickname(targetProfile),
      nowTimestamp,
    );
    transaction.update(roomRef, {seq: event.seq, updatedAt: nowTimestamp});
    const result = {
      roomID: input.roomID,
      subjectUID: input.targetUID,
      role: nextRole,
      moderatorCount: nextCount,
      eventID: event.eventID,
      seq: event.seq,
      deduplicated: false,
    };
    persistReceipt(transaction, receiptRef, actorUID, operation, input.roomID, input.targetUID, fingerprint, result, now);
    return result;
  });
}

export async function assignRoomModeratorService(
  actorUID: string,
  input: AssignRoomModeratorInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<Record<string, unknown>> {
  return mutateTargetModerator(actorUID, input, "assignRoomModerator", now, firestore);
}

export async function revokeRoomModeratorService(
  actorUID: string,
  input: RevokeRoomModeratorInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<Record<string, unknown>> {
  return mutateTargetModerator(actorUID, input, "revokeRoomModerator", now, firestore);
}

export async function resignRoomModeratorService(
  actorUID: string,
  input: ResignRoomModeratorInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<Record<string, unknown>> {
  const operation: RoleOperation = "resignRoomModerator";
  const fingerprint = requestFingerprint(operation, input.roomID, actorUID);
  const receiptRef = firestore.collection("roomRoleMutationReceipts").doc(receiptID(actorUID, input.clientRequestID));
  const roomRef = firestore.collection("Rooms").doc(input.roomID);
  const joinedRef = firestore.collection("users").doc(actorUID).collection("joinedRooms").doc(input.roomID);
  const profileRef = firestore.collection("userPublicProfiles").doc(actorUID);
  const stateRef = firestore.collection("roomModerationStates").doc(input.roomID);
  return firestore.runTransaction(async (transaction) => {
    const receipt = await transaction.get(receiptRef);
    const replay = replayResult(receipt, fingerprint, now);
    if (replay) return replay;
    const resolved = await resolveRoomRoleInTransaction(transaction, firestore, input.roomID, actorUID, now);
    requireModerator(resolved);
    const [joined, profile, state] = await Promise.all([
      transaction.get(joinedRef), transaction.get(profileRef), transaction.get(stateRef),
    ]);
    if (!joined.exists || joined.get("role") !== "moderator") {
      throw roomRoleError("ROOM_ROLE_STATE_INVALID", "참여자 역할 상태가 올바르지 않습니다.");
    }
    const currentCount = storedModeratorCount(state);
    if (currentCount <= 0) throw roomRoleError("ROOM_ROLE_STATE_INVALID", "채팅방 관리자 수 상태가 올바르지 않습니다.");
    const nowTimestamp = Timestamp.fromDate(now);
    const nextCount = currentCount - 1;
    transaction.update(resolved.member.ref, {role: "member", moderatorSince: FieldValue.delete(), updatedAt: nowTimestamp});
    transaction.update(joinedRef, {role: "member", moderatorSince: FieldValue.delete(), updatedAt: nowTimestamp});
    transaction.update(stateRef, {moderatorCount: nextCount, updatedAt: nowTimestamp});
    const event = appendRoomRoleEvent(transaction, firestore, roomRef, resolved.room.get("seq"), "moderatorResigned", actorUID, nickname(profile), nowTimestamp);
    transaction.update(roomRef, {seq: event.seq, updatedAt: nowTimestamp});
    const result = {roomID: input.roomID, subjectUID: actorUID, role: "member", moderatorCount: nextCount, eventID: event.eventID, seq: event.seq, deduplicated: false};
    persistReceipt(transaction, receiptRef, actorUID, operation, input.roomID, actorUID, fingerprint, result, now);
    return result;
  });
}

export async function leaveChatRoomService(
  actorUID: string,
  input: LeaveChatRoomInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<Record<string, unknown>> {
  const operation: RoleOperation = "leaveChatRoom";
  const fingerprint = requestFingerprint(operation, input.roomID, actorUID);
  const receiptRef = firestore.collection("roomRoleMutationReceipts").doc(receiptID(actorUID, input.clientRequestID));
  const roomRef = firestore.collection("Rooms").doc(input.roomID);
  const joinedRef = firestore.collection("users").doc(actorUID).collection("joinedRooms").doc(input.roomID);
  const roomStateRef = firestore.collection("users").doc(actorUID).collection("roomStates").doc(input.roomID);
  const profileRef = firestore.collection("userPublicProfiles").doc(actorUID);
  const moderationStateRef = firestore.collection("roomModerationStates").doc(input.roomID);
  return firestore.runTransaction(async (transaction) => {
    const receipt = await transaction.get(receiptRef);
    const replay = replayResult(receipt, fingerprint, now);
    if (replay) return replay;
    const resolved = await resolveRoomRoleInTransaction(transaction, firestore, input.roomID, actorUID, now);
    if (resolved.role === "owner") throw roomRoleError("OWNER_TRANSFER_REQUIRED", "방장 권한을 이전하거나 방을 종료해야 합니다.");
    const [joined, profile, state] = await Promise.all([
      transaction.get(joinedRef), transaction.get(profileRef), transaction.get(moderationStateRef),
    ]);
    if (!joined.exists || storedRoomMemberRole(joined.get("role")) !== resolved.role) {
      throw roomRoleError("ROOM_ROLE_STATE_INVALID", "참여자 역할 상태가 올바르지 않습니다.");
    }
    const nowTimestamp = Timestamp.fromDate(now);
    let nextCount = storedModeratorCount(state);
    let event: {eventID: string; seq: number} | null = null;
    if (resolved.role === "moderator") {
      if (nextCount <= 0) throw roomRoleError("ROOM_ROLE_STATE_INVALID", "채팅방 관리자 수 상태가 올바르지 않습니다.");
      nextCount -= 1;
      transaction.update(moderationStateRef, {moderatorCount: nextCount, updatedAt: nowTimestamp});
      event = appendRoomRoleEvent(transaction, firestore, roomRef, resolved.room.get("seq"), "moderatorResigned", actorUID, nickname(profile), nowTimestamp);
    }
    const currentMemberCount = resolved.room.get("memberCount");
    const memberCount = Math.max(0, (Number.isSafeInteger(currentMemberCount) ? Number(currentMemberCount) : 0) - 1);
    transaction.delete(resolved.member.ref);
    transaction.delete(joinedRef);
    transaction.delete(roomStateRef);
    transaction.update(roomRef, {
      memberCount,
      ...(event ? {seq: event.seq} : {}),
      updatedAt: nowTimestamp,
    });
    const result = {roomID: input.roomID, mode: "left", memberCount, moderatorCount: nextCount, eventID: event?.eventID ?? null, seq: event?.seq ?? null, deduplicated: false};
    persistReceipt(transaction, receiptRef, actorUID, operation, input.roomID, actorUID, fingerprint, result, now);
    return result;
  });
}

export async function transferRoomOwnershipAndLeaveService(
  actorUID: string,
  input: TransferRoomOwnershipAndLeaveInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<Record<string, unknown>> {
  const operation: RoleOperation = "transferRoomOwnershipAndLeave";
  const fingerprint = requestFingerprint(operation, input.roomID, input.successorUID);
  const receiptRef = firestore.collection("roomRoleMutationReceipts").doc(receiptID(actorUID, input.clientRequestID));
  const roomRef = firestore.collection("Rooms").doc(input.roomID);
  const successorMemberRef = roomRef.collection("members").doc(input.successorUID);
  const successorJoinedRef = firestore.collection("users").doc(input.successorUID).collection("joinedRooms").doc(input.roomID);
  const successorAccountRef = firestore.collection("moderationAccounts").doc(input.successorUID);
  const successorProfileRef = firestore.collection("userPublicProfiles").doc(input.successorUID);
  const successorBanStateRef = firestore.collection("roomModerationStates").doc(input.roomID);
  const ownerJoinedRef = firestore.collection("users").doc(actorUID).collection("joinedRooms").doc(input.roomID);
  const ownerRoomStateRef = firestore.collection("users").doc(actorUID).collection("roomStates").doc(input.roomID);
  return firestore.runTransaction(async (transaction) => {
    const receipt = await transaction.get(receiptRef);
    const replay = replayResult(receipt, fingerprint, now);
    if (replay) return replay;
    const resolved = await resolveRoomRoleInTransaction(transaction, firestore, input.roomID, actorUID, now);
    requireRoomOwner(resolved);
    const [successorMember, successorJoined, successorAccount, successorProfile, state, ownerJoined] = await Promise.all([
      transaction.get(successorMemberRef), transaction.get(successorJoinedRef), transaction.get(successorAccountRef),
      transaction.get(successorProfileRef), transaction.get(successorBanStateRef), transaction.get(ownerJoinedRef),
    ]);
    if (!successorMember.exists || !successorJoined.exists) throw roomRoleError("TARGET_NOT_MEMBER", "참여 중인 사용자가 아닙니다.");
    if (successorMember.get("role") !== "moderator" || successorJoined.get("role") !== "moderator") {
      throw roomRoleError("TARGET_NOT_MODERATOR", "임명 관리자만 방장이 될 수 있습니다.");
    }
    const successorAccountData = requireModerationCapability(successorAccount, now, true);
    const principalID = successorAccountData.moderationPrincipalID;
    if (typeof principalID !== "string" || !principalID || principalID.includes("/")) throw roomRoleError("TARGET_NOT_ELIGIBLE", "운영 권한을 맡을 수 없는 참여자입니다.");
    const ban = await transaction.get(roomRef.collection("bans").doc(principalID));
    if (ban.exists && ban.get("isActive") === true) throw roomRoleError("TARGET_NOT_ELIGIBLE", "운영 권한을 맡을 수 없는 참여자입니다.");
    if (!ownerJoined.exists || ownerJoined.get("role") !== "owner") throw roomRoleError("ROOM_ROLE_STATE_INVALID", "방장 역할 상태가 올바르지 않습니다.");
    const currentCount = storedModeratorCount(state);
    if (currentCount <= 0) throw roomRoleError("ROOM_ROLE_STATE_INVALID", "채팅방 관리자 수 상태가 올바르지 않습니다.");
    const nowTimestamp = Timestamp.fromDate(now);
    const nextCount = currentCount - 1;
    const currentMemberCount = resolved.room.get("memberCount");
    const memberCount = Math.max(0, (Number.isSafeInteger(currentMemberCount) ? Number(currentMemberCount) : 0) - 1);
    transaction.update(roomRef, {ownerUID: input.successorUID, memberCount, updatedAt: nowTimestamp});
    transaction.update(successorMemberRef, {role: "owner", moderatorSince: FieldValue.delete(), updatedAt: nowTimestamp});
    transaction.update(successorJoinedRef, {role: "owner", moderatorSince: FieldValue.delete(), updatedAt: nowTimestamp});
    transaction.update(successorBanStateRef, {moderatorCount: nextCount, updatedAt: nowTimestamp});
    transaction.delete(resolved.member.ref);
    transaction.delete(ownerJoinedRef);
    transaction.delete(ownerRoomStateRef);
    const event = appendRoomRoleEvent(transaction, firestore, roomRef, resolved.room.get("seq"), "ownershipTransferred", input.successorUID, nickname(successorProfile), nowTimestamp);
    transaction.update(roomRef, {seq: event.seq});
    const result = {roomID: input.roomID, mode: "left", ownerUID: input.successorUID, memberCount, moderatorCount: nextCount, eventID: event.eventID, seq: event.seq, deduplicated: false};
    persistReceipt(transaction, receiptRef, actorUID, operation, input.roomID, input.successorUID, fingerprint, result, now);
    return result;
  });
}
