import {createHash} from "node:crypto";

export const DEVELOPMENT_PROJECT_ID = "outpick-test";
export const PRODUCTION_PROJECT_ID = "outpick-664ae";
export const DEVELOPMENT_CONFIRMATION = "APPLY_ROOM_MODERATOR_CUTOVER_TO_DEVELOPMENT";
export const PRODUCTION_CONFIRMATION = "APPLY_ROOM_MODERATOR_CUTOVER_TO_PRODUCTION";

const ROLES = new Set(["owner", "moderator", "member"]);

function nonNegativeInteger(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : null;
}

function validID(value) {
  return typeof value === "string" && value.length > 0 && !value.includes("/");
}

export function joinedProjectionInventory(roomIDs, projections) {
  const knownRoomIDs = new Set(roomIDs);
  const byRoomID = new Map(roomIDs.map((roomID) => [roomID, []]));
  const blockers = [];
  for (const projection of projections) {
    const userID = projection.id;
    const documentRoomID = projection.documentRoomID;
    if (!validID(userID) || !validID(documentRoomID)) {
      blockers.push({
        roomID: validID(documentRoomID) ? documentRoomID : "invalid-room",
        blocker: `JOINED_PROJECTION_ID_INVALID:${validID(userID) ? userID : "invalid-user"}`,
      });
      continue;
    }
    if (projection.roomID !== documentRoomID) {
      blockers.push({
        roomID: documentRoomID,
        blocker: `JOINED_ROOM_ID_MISMATCH:${userID}`,
      });
    }
    if (!knownRoomIDs.has(documentRoomID)) {
      blockers.push({
        roomID: documentRoomID,
        blocker: `JOINED_PROJECTION_ORPHAN:${userID}`,
      });
      continue;
    }
    byRoomID.get(documentRoomID).push(projection);
  }
  for (const projectionsForRoom of byRoomID.values()) {
    projectionsForRoom.sort((lhs, rhs) => lhs.id.localeCompare(rhs.id));
  }
  return {
    byRoomID,
    blockers: blockers.sort((lhs, rhs) => lhs.roomID.localeCompare(rhs.roomID) ||
      lhs.blocker.localeCompare(rhs.blocker)),
  };
}

function normalizedRole(value) {
  if (value === undefined || value === null) return null;
  return ROLES.has(value) ? value : "invalid";
}

function isRoleEvent(message) {
  return message.type === "roomRoleEvent" || message.messageType === "roomRoleEvent" ||
    (message.serverGenerated === true && message.roleEvent && typeof message.roleEvent === "object");
}

export function roomCutoverPlan(input) {
  const blockers = [];
  const writes = [];
  const room = input.room;
  if (!validID(room.id)) blockers.push("ROOM_ID_INVALID");
  const hasOwnerUID = room.ownerUID !== undefined && room.ownerUID !== null;
  const ownerUID = hasOwnerUID ? (validID(room.ownerUID) ? room.ownerUID : null) :
    (validID(room.creatorUID) ? room.creatorUID : null);
  if (hasOwnerUID && !validID(room.ownerUID)) blockers.push("ROOM_OWNER_INVALID");
  if (!ownerUID) blockers.push("ROOM_OWNER_MISSING");
  if (validID(room.ownerUID) && validID(room.creatorUID) && room.ownerUID !== room.creatorUID) {
    blockers.push("ROOM_OWNER_CONFLICT");
  }

  const roomSeq = nonNegativeInteger(room.seq);
  if (roomSeq === null) blockers.push("ROOM_SEQ_INVALID");
  const ordinaryMessages = [];
  let expectedUnreadMessageSeq = 0;
  let maxTimelineSeq = 0;
  for (const message of input.messages) {
    const seq = nonNegativeInteger(message.seq);
    if (seq === null) {
      blockers.push(`MESSAGE_SEQ_INVALID:${message.id}`);
      continue;
    }
    maxTimelineSeq = Math.max(maxTimelineSeq, seq);
    if (isRoleEvent(message)) continue;
    const unread = message.unreadMessageSeq === undefined ? seq : nonNegativeInteger(message.unreadMessageSeq);
    if (unread === null) {
      blockers.push(`MESSAGE_UNREAD_SEQ_INVALID:${message.id}`);
      continue;
    }
    if (unread > seq) blockers.push(`MESSAGE_COUNTER_REVERSED:${message.id}`);
    expectedUnreadMessageSeq = Math.max(expectedUnreadMessageSeq, unread);
    ordinaryMessages.push({seq, unread});
  }
  if (roomSeq !== null && maxTimelineSeq > roomSeq) blockers.push("ROOM_SEQ_BEHIND_TIMELINE");
  if (roomSeq !== null && expectedUnreadMessageSeq > roomSeq) blockers.push("ROOM_COUNTER_REVERSED");
  const storedUnread = room.unreadMessageSeq === undefined ? null : nonNegativeInteger(room.unreadMessageSeq);
  if (room.unreadMessageSeq !== undefined && storedUnread === null) blockers.push("ROOM_UNREAD_SEQ_INVALID");
  if (storedUnread !== null && storedUnread > expectedUnreadMessageSeq) blockers.push("ROOM_UNREAD_SEQ_AHEAD");
  if (storedUnread === null || storedUnread < expectedUnreadMessageSeq) {
    writes.push({path: `Rooms/${room.id}`, fields: {unreadMessageSeq: expectedUnreadMessageSeq}});
  }
  if (!hasOwnerUID && ownerUID) {
    writes.push({path: `Rooms/${room.id}`, fields: {ownerUID}});
  }

  const membersByID = new Map(input.members.map((member) => [member.id, member]));
  const joinedByID = new Map(input.joined.map((joined) => [joined.id, joined]));
  const explicitMemberOwners = input.members.filter((member) => normalizedRole(member.role) === "owner");
  const explicitJoinedOwners = input.joined.filter((joined) => normalizedRole(joined.role) === "owner");
  if (explicitMemberOwners.some((member) => member.id !== ownerUID) || explicitMemberOwners.length > 1) {
    blockers.push("MEMBER_OWNER_DUPLICATE_OR_CONFLICT");
  }
  if (explicitJoinedOwners.some((joined) => joined.id !== ownerUID) || explicitJoinedOwners.length > 1) {
    blockers.push("JOINED_OWNER_DUPLICATE_OR_CONFLICT");
  }

  let moderatorCount = 0;
  for (const member of input.members) {
    const memberRole = normalizedRole(member.role);
    const joined = joinedByID.get(member.id);
    const joinedRole = normalizedRole(joined?.role);
    if (memberRole === "invalid" || joinedRole === "invalid") {
      blockers.push(`ROLE_INVALID:${member.id}`);
      continue;
    }
    if (!joined) {
      blockers.push(`JOINED_PROJECTION_MISSING:${member.id}`);
      continue;
    }
    const expectedRole = member.id === ownerUID ? "owner" : memberRole ?? joinedRole ?? "member";
    if (memberRole && memberRole !== expectedRole) blockers.push(`MEMBER_ROLE_CONFLICT:${member.id}`);
    if (joinedRole && joinedRole !== expectedRole) blockers.push(`JOINED_ROLE_CONFLICT:${member.id}`);
    if (!memberRole) writes.push({path: `Rooms/${room.id}/members/${member.id}`, fields: {role: expectedRole}});
    if (!joinedRole) writes.push({path: `users/${member.id}/joinedRooms/${room.id}`, fields: {role: expectedRole}});
    if (expectedRole === "moderator") {
      moderatorCount += 1;
      if (!member.moderatorSince || !joined.moderatorSince) {
        blockers.push(`MODERATOR_SINCE_MISSING:${member.id}`);
      }
    }

    const lastReadSeq = nonNegativeInteger(joined.lastReadSeq) ?? 0;
    const expectedReadUnread = ordinaryMessages.reduce(
      (maximum, message) => message.seq <= lastReadSeq ? Math.max(maximum, message.unread) : maximum,
      0,
    );
    const storedReadUnread = joined.lastReadUnreadMessageSeq === undefined ? null :
      nonNegativeInteger(joined.lastReadUnreadMessageSeq);
    if (joined.lastReadUnreadMessageSeq !== undefined && storedReadUnread === null) {
      blockers.push(`JOINED_READ_UNREAD_INVALID:${member.id}`);
    } else if (storedReadUnread !== null && storedReadUnread > expectedReadUnread) {
      blockers.push(`JOINED_READ_UNREAD_AHEAD:${member.id}`);
    } else if (storedReadUnread === null || storedReadUnread < expectedReadUnread) {
      writes.push({
        path: `users/${member.id}/joinedRooms/${room.id}`,
        fields: {lastReadUnreadMessageSeq: expectedReadUnread},
      });
    }
  }
  for (const joined of input.joined) {
    if (!membersByID.has(joined.id)) blockers.push(`MEMBER_PROJECTION_MISSING:${joined.id}`);
  }
  if (ownerUID && (!membersByID.has(ownerUID) || !joinedByID.has(ownerUID))) {
    blockers.push("OWNER_PROJECTION_MISSING");
  }
  const storedModeratorCount = input.moderationState === null ? null :
    nonNegativeInteger(input.moderationState.moderatorCount);
  if (input.moderationState !== null && storedModeratorCount === null) {
    blockers.push("MODERATOR_COUNT_INVALID");
  } else if (storedModeratorCount !== null && storedModeratorCount > moderatorCount) {
    blockers.push("MODERATOR_COUNT_AHEAD");
  } else if (storedModeratorCount === null || storedModeratorCount < moderatorCount) {
    writes.push({path: `roomModerationStates/${room.id}`, fields: {schemaVersion: 1, moderatorCount}});
  }

  const writesByPath = new Map();
  for (const write of writes) {
    writesByPath.set(write.path, {...(writesByPath.get(write.path) ?? {}), ...write.fields});
  }
  return {
    roomID: room.id,
    ownerUID,
    expectedUnreadMessageSeq,
    moderatorCount,
    blockers: [...new Set(blockers)].sort(),
    writes: [...writesByPath.entries()].map(([path, fields]) => ({path, fields}))
      .sort((lhs, rhs) => lhs.path.localeCompare(rhs.path)),
  };
}

export function cutoverPlanHash(plans) {
  const canonical = plans.flatMap((plan) => plan.writes.map((write) => ({
    path: write.path,
    fields: write.fields,
  }))).sort((lhs, rhs) => lhs.path.localeCompare(rhs.path) ||
    JSON.stringify(lhs.fields).localeCompare(JSON.stringify(rhs.fields)));
  return createHash("sha256").update(JSON.stringify(canonical)).digest("hex");
}

export function validateCutoverApply(options, summary) {
  if (summary.blockerCount > 0) throw new Error("미해결 blocker가 있어 apply를 중단합니다.");
  if (options.expectedRoomCount !== summary.roomCount) throw new Error("--expected-room-count가 다릅니다.");
  if (options.expectedWriteCount !== summary.writeCount) throw new Error("--expected-write-count가 다릅니다.");
  if (options.expectedPlanHash !== summary.planHash) throw new Error("--expected-plan-hash가 다릅니다.");
  if (!options.apply) return;
  const expectedConfirmation = options.projectID === PRODUCTION_PROJECT_ID ?
    PRODUCTION_CONFIRMATION : DEVELOPMENT_CONFIRMATION;
  if (options.confirmation !== expectedConfirmation) {
    throw new Error(`apply에는 --confirm ${expectedConfirmation}가 필요합니다.`);
  }
}
