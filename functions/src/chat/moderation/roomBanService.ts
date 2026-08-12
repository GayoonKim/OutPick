/* eslint-disable require-jsdoc, max-len */
import {randomUUID} from "node:crypto";
import {
  FieldPath,
  FieldValue,
  Firestore,
  Query,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../../core/firebase.js";
import {assertAuditReplay, moderationAuditActionID} from "../../moderation/audit/contracts.js";
import {assertAccountCapability} from "../../shared/accountStatus.js";
import {
  GetMyRoomAccessInput,
  ListRoomBansInput,
  RemoveRoomMemberInput,
  UnbanRoomMemberInput,
} from "./contracts.js";

const INACTIVE_BAN_RETENTION_MILLIS = 180 * 24 * 60 * 60 * 1000;

type BanCursor = {bannedAtMillis: number; principalID: string};

export type MyRoomAccessStatus = "member" | "joinable" | "banned" | "closed";

function roomIsActive(data: FirebaseFirestore.DocumentData): boolean {
  return data.isClosed !== true &&
    (data.lifecycleStatus === undefined || data.lifecycleStatus === "active");
}

function nonNegativeMemberCount(value: unknown, decrement: boolean): number {
  const count = typeof value === "number" && Number.isSafeInteger(value) ? value : 0;
  return Math.max(0, count - (decrement ? 1 : 0));
}

function encodeCursor(cursor: BanCursor): string {
  return Buffer.from(JSON.stringify(cursor), "utf8").toString("base64url");
}

function decodeCursor(value: string): BanCursor {
  try {
    const decoded = JSON.parse(Buffer.from(value, "base64url").toString("utf8")) as BanCursor;
    if (!Number.isSafeInteger(decoded.bannedAtMillis) || decoded.bannedAtMillis < 0 ||
      typeof decoded.principalID !== "string" || !decoded.principalID ||
      decoded.principalID.includes("/")) {
      throw new Error("invalid cursor");
    }
    return decoded;
  } catch {
    throw new HttpsError("invalid-argument", "cursor 값이 올바르지 않습니다.");
  }
}

async function assertRoomOwner(
  actorUID: string,
  roomID: string,
  firestore: Firestore,
): Promise<FirebaseFirestore.DocumentSnapshot> {
  await assertAccountCapability(actorUID, "moderateOwnedRoom", firestore);
  const room = await firestore.collection("Rooms").doc(roomID).get();
  if (!room.exists || !room.data()) {
    throw new HttpsError("not-found", "채팅방을 찾을 수 없습니다.");
  }
  if (!roomIsActive(room.data()!)) {
    throw new HttpsError("failed-precondition", "폐쇄된 채팅방입니다.", {
      errorCode: "ROOM_CLOSED",
    });
  }
  if (room.get("creatorUID") !== actorUID) {
    throw new HttpsError("permission-denied", "방장 권한이 필요합니다.");
  }
  return room;
}

export async function getMyRoomAccessService(
  actorUID: string,
  input: GetMyRoomAccessInput,
  firestore: Firestore = db,
): Promise<{status: MyRoomAccessStatus}> {
  await assertAccountCapability(actorUID, "readAppContent", firestore);
  const roomRef = firestore.collection("Rooms").doc(input.roomID);
  const accountRef = firestore.collection("moderationAccounts").doc(actorUID);
  const memberRef = roomRef.collection("members").doc(actorUID);
  const [room, account, member] = await Promise.all([
    roomRef.get(),
    accountRef.get(),
    memberRef.get(),
  ]);
  if (!room.exists || !room.data()) {
    throw new HttpsError("not-found", "채팅방을 찾을 수 없습니다.");
  }
  if (!roomIsActive(room.data()!)) return {status: "closed"};
  if (member.exists) return {status: "member"};

  const principalID = account.get("moderationPrincipalID");
  if (typeof principalID !== "string" || !principalID || principalID.includes("/")) {
    throw new HttpsError("failed-precondition", "제재 식별자를 찾을 수 없습니다.");
  }
  const ban = await roomRef.collection("bans").doc(principalID).get();
  return {status: ban.exists && ban.get("isActive") === true ? "banned" : "joinable"};
}

export async function removeRoomMemberService(
  actorUID: string,
  input: RemoveRoomMemberInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<Record<string, unknown>> {
  if (actorUID === input.targetUID) {
    throw new HttpsError("failed-precondition", "방장은 자신을 내보낼 수 없습니다.");
  }
  const targetID = `${input.roomID}:${input.targetUID}`;
  const auditRef = firestore.collection("moderationAuditLogs")
    .doc(moderationAuditActionID(actorUID, input.clientRequestID));
  const priorAudit = await auditRef.get();
  if (priorAudit.exists && priorAudit.data()) {
    return assertAuditReplay(priorAudit.data()!, {
      action: "removeRoomMember",
      targetType: "roomMember",
      targetID,
      requestID: input.clientRequestID,
    });
  }
  await assertAccountCapability(actorUID, "moderateOwnedRoom", firestore);
  const roomRef = firestore.collection("Rooms").doc(input.roomID);
  const memberRef = roomRef.collection("members").doc(input.targetUID);
  const targetAccountRef = firestore.collection("moderationAccounts").doc(input.targetUID);
  const profileRef = firestore.collection("userPublicProfiles").doc(input.targetUID);
  const joinedRef = firestore.collection("users").doc(input.targetUID)
    .collection("joinedRooms").doc(input.roomID);
  const roomStateRef = firestore.collection("users").doc(input.targetUID)
    .collection("roomStates").doc(input.roomID);

  return firestore.runTransaction(async (transaction) => {
    const [audit, room, member, targetAccount, profile] = await Promise.all([
      transaction.get(auditRef),
      transaction.get(roomRef),
      transaction.get(memberRef),
      transaction.get(targetAccountRef),
      transaction.get(profileRef),
    ]);
    if (audit.exists && audit.data()) {
      return assertAuditReplay(audit.data()!, {
        action: "removeRoomMember",
        targetType: "roomMember",
        targetID,
        requestID: input.clientRequestID,
      });
    }
    if (!room.exists || !room.data()) {
      throw new HttpsError("not-found", "채팅방을 찾을 수 없습니다.");
    }
    const roomData = room.data()!;
    if (!roomIsActive(roomData)) {
      throw new HttpsError("failed-precondition", "폐쇄된 채팅방입니다.", {
        errorCode: "ROOM_CLOSED",
      });
    }
    if (roomData.creatorUID !== actorUID) {
      throw new HttpsError("permission-denied", "방장 권한이 필요합니다.");
    }
    if (!member.exists || member.get("role") === "owner") {
      throw new HttpsError("failed-precondition", "내보낼 수 있는 참여자가 아닙니다.");
    }
    const principalID = targetAccount.get("moderationPrincipalID");
    if (!targetAccount.exists || typeof principalID !== "string" || !principalID) {
      throw new HttpsError("failed-precondition", "참여자의 제재 식별자를 찾을 수 없습니다.");
    }
    const banRef = roomRef.collection("bans").doc(principalID);
    const currentBan = await transaction.get(banRef);
    if (currentBan.exists && currentBan.get("isActive") === true) {
      throw new HttpsError("failed-precondition", "이미 재입장이 제한된 참여자입니다.");
    }
    const previousVersion = currentBan.exists && Number.isSafeInteger(currentBan.get("stateVersion")) ?
      Number(currentBan.get("stateVersion")) : 0;
    const nextVersion = previousVersion + 1;
    const memberCount = nonNegativeMemberCount(roomData.memberCount, true);
    const nowTimestamp = Timestamp.fromDate(now);
    const displayName = profile.exists && typeof profile.get("nickname") === "string" ?
      String(profile.get("nickname")).slice(0, 80) : null;
    const result = {removed: true, roomBanned: true, memberCount};

    transaction.set(banRef, {
      schemaVersion: 1,
      isActive: true,
      banEntryToken: randomUUID(),
      bannedAt: nowTimestamp,
      bannedByUID: actorUID,
      reasonCode: input.reasonCode,
      displayNameSnapshot: displayName,
      stateVersion: nextVersion,
      unbannedAt: null,
      expiresAt: null,
    });
    transaction.update(roomRef, {memberCount, updatedAt: nowTimestamp});
    transaction.delete(memberRef);
    transaction.delete(joinedRef);
    transaction.delete(roomStateRef);
    transaction.create(auditRef, {
      schemaVersion: 1,
      actorUID,
      action: "removeRoomMember",
      targetType: "roomMember",
      targetID,
      before: {member: true, roomBanned: currentBan.get("isActive") === true},
      after: result,
      reasonCode: input.reasonCode,
      reportTargetType: "user",
      reportTargetID: principalID,
      requestID: input.clientRequestID,
      createdAt: nowTimestamp,
      expiresAt: null,
    });
    return result;
  });
}

export async function unbanRoomMemberService(
  actorUID: string,
  input: UnbanRoomMemberInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<Record<string, unknown>> {
  const auditRef = firestore.collection("moderationAuditLogs")
    .doc(moderationAuditActionID(actorUID, input.clientRequestID));
  const priorAudit = await auditRef.get();
  if (priorAudit.exists && priorAudit.data()) {
    return assertAuditReplay(priorAudit.data()!, {
      action: "unbanRoomMember",
      targetType: "roomBan",
      targetID: input.roomID,
      requestID: input.clientRequestID,
    });
  }
  await assertRoomOwner(actorUID, input.roomID, firestore);
  const roomRef = firestore.collection("Rooms").doc(input.roomID);
  const matches = await roomRef.collection("bans")
    .where("banEntryToken", "==", input.banEntryToken)
    .where("isActive", "==", true)
    .limit(2)
    .get();
  if (matches.size !== 1) {
    throw new HttpsError("not-found", "재입장 제한 항목을 찾을 수 없습니다.");
  }
  const banRef = matches.docs[0].ref;
  return firestore.runTransaction(async (transaction) => {
    const [audit, room, ban] = await Promise.all([
      transaction.get(auditRef),
      transaction.get(roomRef),
      transaction.get(banRef),
    ]);
    if (audit.exists && audit.data()) {
      return assertAuditReplay(audit.data()!, {
        action: "unbanRoomMember",
        targetType: "roomBan",
        targetID: input.roomID,
        requestID: input.clientRequestID,
      });
    }
    if (!room.exists || !room.data() || !roomIsActive(room.data()!)) {
      throw new HttpsError("failed-precondition", "활성 채팅방이 아닙니다.");
    }
    if (room.get("creatorUID") !== actorUID) {
      throw new HttpsError("permission-denied", "방장 권한이 필요합니다.");
    }
    if (!ban.exists || ban.get("isActive") !== true ||
      ban.get("banEntryToken") !== input.banEntryToken) {
      throw new HttpsError("not-found", "재입장 제한 항목을 찾을 수 없습니다.");
    }
    const stateVersion = Number(ban.get("stateVersion")) + 1;
    const nowTimestamp = Timestamp.fromDate(now);
    const result = {roomBanned: false, membershipRestored: false};
    transaction.update(banRef, {
      isActive: false,
      banEntryToken: FieldValue.delete(),
      stateVersion,
      unbannedAt: nowTimestamp,
      updatedAt: nowTimestamp,
      expiresAt: Timestamp.fromMillis(now.getTime() + INACTIVE_BAN_RETENTION_MILLIS),
    });
    transaction.create(auditRef, {
      schemaVersion: 1,
      actorUID,
      action: "unbanRoomMember",
      targetType: "roomBan",
      targetID: input.roomID,
      before: {roomBanned: true, stateVersion: ban.get("stateVersion")},
      after: result,
      reasonCode: "ownerUnban",
      reportTargetType: null,
      reportTargetID: null,
      requestID: input.clientRequestID,
      createdAt: nowTimestamp,
      expiresAt: null,
    });
    return result;
  });
}

export async function listRoomBansService(
  actorUID: string,
  input: ListRoomBansInput,
  firestore: Firestore = db,
): Promise<{items: Record<string, unknown>[]; nextCursor: string | null}> {
  await assertRoomOwner(actorUID, input.roomID, firestore);
  let query: Query = firestore.collection("Rooms").doc(input.roomID).collection("bans")
    .where("isActive", "==", true)
    .orderBy("bannedAt", "desc")
    .orderBy(FieldPath.documentId(), "desc");
  if (input.cursor) {
    const cursor = decodeCursor(input.cursor);
    query = query.startAfter(Timestamp.fromMillis(cursor.bannedAtMillis), cursor.principalID);
  }
  const snapshot = await query.limit(input.pageSize + 1).get();
  const visible = snapshot.docs.slice(0, input.pageSize);
  const last = visible.at(-1);
  return {
    items: visible.map((document) => ({
      banEntryToken: document.get("banEntryToken"),
      reasonCode: document.get("reasonCode"),
      displayNameSnapshot: typeof document.get("displayNameSnapshot") === "string" ?
        document.get("displayNameSnapshot") : null,
      bannedAt: document.get("bannedAt") instanceof Timestamp ?
        document.get("bannedAt").toDate().toISOString() : null,
    })),
    nextCursor: snapshot.size > input.pageSize && last && last.get("bannedAt") instanceof Timestamp ?
      encodeCursor({
        bannedAtMillis: last.get("bannedAt").toMillis(),
        principalID: last.id,
      }) : null,
  };
}
