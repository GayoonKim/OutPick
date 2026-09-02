import assert from "node:assert/strict";
import {after, beforeEach, describe, test} from "node:test";
import {db} from "../functions/lib/core/firebase.js";
import {
  acknowledgeRoomClosureService,
  closeOwnedChatRoomService,
  deleteChatMessageService,
  messageCleanupJobID,
} from "../functions/lib/chat/moderation/service.js";
import {
  getMyRoomAccessService,
  listRoomBansService,
  removeRoomMemberService,
  unbanRoomMemberService,
} from "../functions/lib/chat/moderation/roomBanService.js";
import {
  assignRoomModeratorService,
  leaveChatRoomService,
  resignRoomModeratorService,
  revokeRoomModeratorService,
  transferRoomOwnershipAndLeaveService,
} from "../functions/lib/chat/moderation/roomRoleService.js";
import {
  accountDeletionSuccessionJobID,
  resolveRoomMembershipPage,
} from "../functions/lib/chat/moderation/roomMembershipSweep.js";
import {
  processRoomOwnershipSuccessionJob,
  processRoomSuccessionAttempt,
} from "../functions/lib/chat/moderation/roomSuccessionJobs.js";
import {
  processMessageCleanupJob,
  processRoomCleanupJob,
} from "../functions/lib/chat/cleanup/moderationCleanup.js";
import {
  hasIncompleteAccountDeletionMessageCleanup,
  resolveRoomPage,
  scrubMessagePage,
} from "../functions/lib/accountDeletion/cleanup.js";

const ownerUID = "chat-owner";
const memberUID = "chat-member";
const moderatorUID = "chat-moderator";
const roomID = "chat-moderation-room";
const messageID = "message-1";
const requestID = "123e4567-e89b-42d3-a456-426614174000";
const now = new Date("2026-08-10T08:00:00.000Z");
const bulkMemberUIDs = Array.from(
  {length: 170},
  (_, index) => `bulk-member-${String(index).padStart(3, "0")}`,
);

function cleanupBucketResolver(bucket) {
  return {
    defaultBucket: bucket,
    bucket: () => bucket,
    roomBuckets: [bucket],
  };
}

async function clearFixtures() {
  await Promise.all([
    db.recursiveDelete(db.collection("Rooms").doc(roomID)),
    db.recursiveDelete(db.collection("users").doc(ownerUID)),
    db.recursiveDelete(db.collection("users").doc(memberUID)),
    db.recursiveDelete(db.collection("moderationAccounts").doc(ownerUID)),
    db.recursiveDelete(db.collection("moderationAccounts").doc(memberUID)),
    db.recursiveDelete(db.collection("moderationAccounts").doc(moderatorUID)),
    db.recursiveDelete(db.collection("users").doc(moderatorUID)),
    db.recursiveDelete(db.collection("userPublicProfiles").doc(moderatorUID)),
    db.recursiveDelete(db.collection("userPublicProfiles").doc(memberUID)),
    db.recursiveDelete(db.collection("chatMessageCleanupJobs")),
    db.recursiveDelete(db.collection("chatMessageDeletionDeliveryJobs")),
    db.recursiveDelete(db.collection("moderationRoomCleanupJobs")),
    db.recursiveDelete(db.collection("roomOwnershipSuccessionJobs")),
    db.recursiveDelete(db.collection("moderationAuditLogs")),
    db.recursiveDelete(db.collection("roomModerationStates")),
    db.recursiveDelete(db.collection("roomRoleMutationReceipts")),
    db.recursiveDelete(db.collection("chatRoleEventDeliveryJobs")),
    db.recursiveDelete(db.collection("accountDeletionRequests")),
    db.recursiveDelete(db.collection("Rooms").doc("account-deletion-room")),
    ...bulkMemberUIDs.map((uid) => db.recursiveDelete(db.collection("users").doc(uid))),
  ]);
}

async function seedFixtures() {
  await Promise.all([
    db.collection("users").doc(ownerUID).set({accountStatus: "active"}),
    db.collection("users").doc(memberUID).set({accountStatus: "active"}),
    db.collection("moderationAccounts").doc(ownerUID).set({
      accountStatus: "active",
      moderationPrincipalID: "principal-chat-owner",
      moderationStatus: "active",
      stateVersion: 1,
    }),
    db.collection("moderationAccounts").doc(memberUID).set({
      accountStatus: "active",
      moderationPrincipalID: "principal-chat-member",
      moderationStatus: "active",
      stateVersion: 1,
    }),
    db.collection("userPublicProfiles").doc(memberUID).set({nickname: "참여자"}),
  ]);
  const room = db.collection("Rooms").doc(roomID);
  await room.set({
    roomName: "정리 테스트방",
    creatorUID: ownerUID,
    isClosed: false,
    lifecycleStatus: "active",
    lifecycleVersion: 1,
    seq: 2,
    lastMessageSeq: 1,
    lastMessage: "삭제 대상",
    memberCount: 2,
  });
  await db.collection("roomModerationStates").doc(roomID).set({
    moderatorCount: 0,
    updatedAt: now,
  });
  await Promise.all([
    room.collection("members").doc(ownerUID).set({
      role: "owner", userID: ownerUID, joinedAt: new Date("2026-01-01T00:00:00Z"),
    }),
    room.collection("members").doc(memberUID).set({
      role: "member", userID: memberUID, joinedAt: new Date("2026-01-02T00:00:00Z"),
    }),
    db.collection("users").doc(ownerUID).collection("joinedRooms").doc(roomID).set({roomID, role: "owner"}),
    db.collection("users").doc(memberUID).collection("joinedRooms").doc(roomID).set({roomID, role: "member"}),
    room.collection("Messages").doc(messageID).set({
      ID: messageID,
      roomID,
      senderUID: ownerUID,
      senderNickname: "방장",
      senderAvatarPath: "avatars/owner/profile.jpg",
      seq: 1,
      msg: "삭제 대상",
      sentAt: now,
      isDeleted: false,
      replyPreview: {
        messageID: "source-message",
        sender: "이전 작성자",
        text: "이전 메시지",
      },
      attachments: [{
        pathOriginal: `rooms/${roomID}/messages/${messageID}/images/1/original.jpg`,
      }],
    }),
    room.collection("Messages").doc("reply-1").set({
      ID: "reply-1",
      roomID,
      senderUID: memberUID,
      seq: 2,
      msg: "답글",
      isDeleted: false,
      replyPreview: {messageID, sender: "방장", text: "삭제 대상"},
    }),
    room.collection("mediaIndex").doc("media-1").set({messageID}),
  ]);
}

beforeEach(async () => {
  await clearFixtures();
  await seedFixtures();
});
after(clearFixtures);

describe("chat moderation lifecycle transactions", () => {
  test("관리자 임명·재생·회수는 projection, count, event, receipt를 원자 갱신한다", async () => {
    await db.collection("roomModerationStates").doc(roomID).delete();
    const assigned = await assignRoomModeratorService(ownerUID, {
      roomID,
      targetUID: memberUID,
      clientRequestID: "823e4567-e89b-42d3-a456-426614174000",
    }, now, db);
    assert.equal(assigned.role, "moderator");
    assert.equal(assigned.moderatorCount, 1);
    assert.equal((await db.collection("Rooms").doc(roomID).collection("members").doc(memberUID).get()).data()?.role, "moderator");
    assert.equal((await db.collection("users").doc(memberUID).collection("joinedRooms").doc(roomID).get()).data()?.role, "moderator");
    assert.equal((await db.collection("roomModerationStates").doc(roomID).get()).data()?.moderatorCount, 1);
    assert.equal((await db.collection("roomModerationStates").doc(roomID).get()).data()?.schemaVersion, 1);
    const event = await db.collection("Rooms").doc(roomID).collection("Messages").doc(assigned.eventID).get();
    assert.equal(event.data()?.messageType, "roomRoleEvent");
    assert.equal(event.data()?.serverGenerated, true);
    assert.deepEqual(event.data()?.roleEvent, {
      kind: "moderatorAssigned",
      subjectUID: memberUID,
      subjectNicknameSnapshot: "참여자",
    });
    assert.equal((await db.collection("chatRoleEventDeliveryJobs").doc(assigned.eventID).get()).exists, true);

    const replay = await assignRoomModeratorService(ownerUID, {
      roomID,
      targetUID: memberUID,
      clientRequestID: "823e4567-e89b-42d3-a456-426614174000",
    }, now, db);
    assert.equal(replay.eventID, assigned.eventID);
    assert.equal(replay.deduplicated, true);
    assert.equal((await db.collection("Rooms").doc(roomID).collection("Messages")
      .where("messageType", "==", "roomRoleEvent").get()).size, 1);

    await assert.rejects(assignRoomModeratorService(ownerUID, {
      roomID,
      targetUID: ownerUID,
      clientRequestID: "823e4567-e89b-42d3-a456-426614174000",
    }, now, db), (error) => error?.details?.errorCode === "REQUEST_ID_CONFLICT");

    const revoked = await revokeRoomModeratorService(ownerUID, {
      roomID,
      targetUID: memberUID,
      clientRequestID: "923e4567-e89b-42d3-a456-426614174000",
    }, new Date(now.getTime() + 1_000), db);
    assert.equal(revoked.role, "member");
    assert.equal(revoked.moderatorCount, 0);
  });

  test("관리자는 사임하거나 event와 count를 남기며 퇴장할 수 있고 방장은 직접 퇴장할 수 없다", async () => {
    await assignRoomModeratorService(ownerUID, {
      roomID, targetUID: memberUID, clientRequestID: "a23e4567-e89b-42d3-a456-426614174000",
    }, now, db);
    const resigned = await resignRoomModeratorService(memberUID, {
      roomID, clientRequestID: "b23e4567-e89b-42d3-a456-426614174000",
    }, new Date(now.getTime() + 1_000), db);
    assert.equal(resigned.role, "member");
    await assignRoomModeratorService(ownerUID, {
      roomID, targetUID: memberUID, clientRequestID: "c23e4567-e89b-42d3-a456-426614174000",
    }, new Date(now.getTime() + 2_000), db);
    const left = await leaveChatRoomService(memberUID, {
      roomID, clientRequestID: "d23e4567-e89b-42d3-a456-426614174000",
    }, new Date(now.getTime() + 3_000), db);
    assert.equal(left.mode, "left");
    assert.equal(left.moderatorCount, 0);
    assert.equal((await db.collection("Rooms").doc(roomID).collection("members").doc(memberUID).get()).exists, false);
    await assert.rejects(leaveChatRoomService(ownerUID, {
      roomID, clientRequestID: "e23e4567-e89b-42d3-a456-426614174000",
    }, now, db), (error) => error?.details?.errorCode === "OWNER_TRANSFER_REQUIRED");
  });

  test("소유권 이전은 임명 관리자만 owner로 올리고 기존 방장을 제거한다", async () => {
    await assignRoomModeratorService(ownerUID, {
      roomID, targetUID: memberUID, clientRequestID: "f23e4567-e89b-42d3-a456-426614174000",
    }, now, db);
    const transferred = await transferRoomOwnershipAndLeaveService(ownerUID, {
      roomID,
      successorUID: memberUID,
      clientRequestID: "133e4567-e89b-42d3-a456-426614174001",
    }, new Date(now.getTime() + 1_000), db);
    assert.equal(transferred.ownerUID, memberUID);
    const room = await db.collection("Rooms").doc(roomID).get();
    assert.equal(room.data()?.ownerUID, memberUID);
    assert.equal(room.data()?.creatorUID, ownerUID);
    assert.equal((await room.ref.collection("members").doc(ownerUID).get()).exists, false);
    assert.equal((await room.ref.collection("members").doc(memberUID).get()).data()?.role, "owner");
    assert.equal((await db.collection("roomModerationStates").doc(roomID).get()).data()?.moderatorCount, 0);
  });

  test("임명 관리자는 일반·퇴장 사용자를 제재하지만 현재 방장·관리자는 제재할 수 없다", async () => {
    const room = db.collection("Rooms").doc(roomID);
    await Promise.all([
      db.collection("users").doc(moderatorUID).set({accountStatus: "active"}),
      db.collection("moderationAccounts").doc(moderatorUID).set({
        accountStatus: "active",
        moderationPrincipalID: "principal-chat-moderator",
        moderationStatus: "active",
        stateVersion: 1,
      }),
      db.collection("userPublicProfiles").doc(moderatorUID).set({nickname: "관리자"}),
      room.collection("members").doc(moderatorUID).set({role: "moderator", userID: moderatorUID, moderatorSince: now}),
      db.collection("users").doc(moderatorUID).collection("joinedRooms").doc(roomID).set({roomID, role: "moderator", moderatorSince: now}),
      db.collection("roomModerationStates").doc(roomID).update({moderatorCount: 1}),
      room.update({memberCount: 3}),
    ]);

    await assert.rejects(removeRoomMemberService(moderatorUID, {
      roomID, targetUID: ownerUID, reasonCode: "harassment",
      clientRequestID: "233e4567-e89b-42d3-a456-426614174001",
    }, now, db), (error) => error?.details?.errorCode === "TARGET_IS_OWNER");

    const removed = await removeRoomMemberService(moderatorUID, {
      roomID, targetUID: memberUID, reasonCode: "harassment",
      clientRequestID: "333e4567-e89b-42d3-a456-426614174001",
    }, now, db);
    assert.equal(removed.memberCount, 2);
    const bans = await listRoomBansService(moderatorUID, {roomID, pageSize: 10, cursor: null}, db);
    assert.equal(bans.items.length, 1);
    await unbanRoomMemberService(moderatorUID, {
      roomID, banEntryToken: bans.items[0].banEntryToken,
      clientRequestID: "433e4567-e89b-42d3-a456-426614174001",
    }, now, db);

    await room.collection("Messages").doc("departed-message").set({
      ID: "departed-message",
      roomID,
      senderUID: "departed-user",
      senderNickname: "퇴장 사용자",
      messageType: "text",
      seq: 3,
      msg: "과거 메시지",
      sentAt: now,
      isDeleted: false,
    });
    await room.update({seq: 3});
    const deleted = await deleteChatMessageService(moderatorUID, null, {
      roomID,
      messageID: "departed-message",
      expectedSeq: 3,
      reasonCode: "chatMessageDeletion",
      reportTargetType: null,
      reportTargetID: null,
      clientRequestID: "533e4567-e89b-42d3-a456-426614174001",
    }, now, db);
    assert.equal(deleted.isDeleted, true);

    await assert.rejects(deleteChatMessageService(moderatorUID, null, {
      roomID,
      messageID,
      expectedSeq: 1,
      reasonCode: "chatMessageDeletion",
      reportTargetType: null,
      reportTargetID: null,
      clientRequestID: "633e4567-e89b-42d3-a456-426614174001",
    }, now, db), (error) => error?.details?.errorCode === "TARGET_IS_OWNER");

    const ownerRemoval = await removeRoomMemberService(ownerUID, {
      roomID, targetUID: moderatorUID, reasonCode: "harassment",
      clientRequestID: "733e4567-e89b-42d3-a456-426614174001",
    }, now, db);
    assert.equal(ownerRemoval.moderatorCount, 0);
    assert.equal(typeof ownerRemoval.eventID, "string");
  });
  test("계정 삭제 시 일반 참여자를 건너뛰고 가장 오래된 적격 관리자에게만 승계한다", async () => {
    const roomRef = db.collection("Rooms").doc(roomID);
    await Promise.all([
      db.collection("moderationAccounts").doc(moderatorUID).set({
        accountStatus: "active",
        moderationPrincipalID: "principal-chat-moderator",
        moderationStatus: "active",
        stateVersion: 1,
      }),
      db.collection("userPublicProfiles").doc(moderatorUID).set({nickname: "관리자"}),
      roomRef.collection("members").doc(moderatorUID).set({
        role: "moderator", userID: moderatorUID, joinedAt: new Date("2026-01-03T00:00:00Z"),
        moderatorSince: new Date("2026-02-01T00:00:00Z"),
      }),
      db.collection("users").doc(moderatorUID).collection("joinedRooms").doc(roomID).set({
        roomID, role: "moderator", moderatorSince: new Date("2026-02-01T00:00:00Z"),
      }),
      roomRef.update({ownerUID, memberCount: 3}),
      db.collection("roomModerationStates").doc(roomID).set({moderatorCount: 1}, {merge: true}),
    ]);
    const completed = await resolveRoomMembershipPage(
      ownerUID,
      "accountDeletion",
      now,
      db,
    );
    assert.equal(completed, false);
    const room = await db.collection("Rooms").doc(roomID).get();
    assert.equal(room.data()?.ownerUID, moderatorUID);
    assert.equal(room.data()?.creatorUID, ownerUID);
    assert.equal(room.data()?.memberCount, 2);
    assert.equal((await room.ref.collection("members").doc(ownerUID).get()).exists, false);
    assert.equal((await room.ref.collection("members").doc(memberUID).get()).data()?.role, "member");
    assert.equal((await room.ref.collection("members").doc(moderatorUID).get()).data()?.role, "owner");
    assert.equal((await db.collection("users").doc(moderatorUID)
      .collection("joinedRooms").doc(roomID).get()).data()?.role, "owner");
    assert.equal((await db.collection("roomModerationStates").doc(roomID).get()).data()?.moderatorCount, 0);
  });

  test("영구 정지된 단독 방장은 방을 moderation 종료시키고 정리 작업을 남긴다", async () => {
    const room = db.collection("Rooms").doc(roomID);
    await room.collection("members").doc(memberUID).delete();
    await db.collection("users").doc(memberUID).collection("joinedRooms").doc(roomID).delete();
    await room.update({memberCount: 1});

    const completed = await resolveRoomMembershipPage(
      ownerUID,
      "permanentSuspension",
      now,
      db,
    );
    assert.equal(completed, false);
    const closed = await room.get();
    assert.equal(closed.data()?.lifecycleStatus, "closedByModeration");
    assert.equal(closed.data()?.memberCount, 0);
    assert.equal((await room.collection("members").doc(ownerUID).get()).exists, false);
    const job = await db.collection("moderationRoomCleanupJobs").doc(roomID).get();
    assert.equal(job.data()?.closureType, "closedByModeration");
    assert.equal(job.data()?.status, "pending");
  });

  test("계정 삭제 시 적격 관리자가 없으면 일반 참여자에게 넘기지 않고 방을 종료한다", async () => {
    const room = db.collection("Rooms").doc(roomID);
    await room.update({ownerUID});

    const completed = await resolveRoomMembershipPage(ownerUID, "accountDeletion", now, db);

    assert.equal(completed, false);
    const closed = await room.get();
    assert.equal(closed.data()?.lifecycleStatus, "closedByOwner");
    assert.equal(closed.data()?.closureNoticeCode, "ownerDeleted");
    assert.equal((await room.collection("members").doc(memberUID).get()).data()?.role, "member");
    assert.equal((await room.collection("members").doc(ownerUID).get()).exists, false);
  });

  test("계정 삭제 finalizer gate는 현재 generation의 승계 job resolved 완료만 허용한다", async () => {
    const generation = "room-succession-generation";
    const deletionRequestID = "room-succession-deletion-request";
    const jobID = accountDeletionSuccessionJobID(deletionRequestID);
    const jobRef = db.collection("roomOwnershipSuccessionJobs").doc(jobID);
    await Promise.all([
      db.collection("Rooms").doc(roomID).update({ownerUID}),
      db.collection("users").doc(ownerUID).set({
        accountStatus: "deletionPending",
        accountGenerationID: generation,
      }, {merge: true}),
      db.collection("accountDeletionRequests").doc(deletionRequestID).set({
        uid: ownerUID,
        accountGenerationID: generation,
        status: "finalizing",
        stage: "rooms",
      }),
      jobRef.set({
        schemaVersion: 2,
        targetUID: ownerUID,
        cause: "accountDeletion",
        accountDeletionRequestID: deletionRequestID,
        accountGenerationID: generation,
        expectedStateVersion: null,
        status: "pending",
        attempt: 0,
        nextAttemptAt: now,
        leaseOwner: null,
        leaseExpiresAt: null,
      }),
    ]);

    assert.equal(await resolveRoomPage(deletionRequestID), false);
    assert.equal(await processRoomOwnershipSuccessionJob(jobID, db, now), false);
    const continued = await jobRef.get();
    assert.equal(continued.data()?.status, "retryPending");
    assert.equal(continued.data()?.attempt, 0);
    assert.equal(await resolveRoomPage(deletionRequestID), false);

    await processRoomSuccessionAttempt(jobID, roomID, 1, db, () => now);
    await processRoomOwnershipSuccessionJob(jobID, db, now);
    await processRoomOwnershipSuccessionJob(jobID, db, now);
    assert.equal(await processRoomOwnershipSuccessionJob(jobID, db, now), true);
    const completed = await jobRef.get();
    assert.equal(completed.data()?.status, "completed");
    assert.equal(completed.data()?.result, "resolved");
    assert.equal(await resolveRoomPage(deletionRequestID), true);
  });

  test("stale 영구 정지 fence는 방을 변경하지 않고 job만 안전하게 종료한다", async () => {
    const jobRef = db.collection("roomOwnershipSuccessionJobs").doc("stale-suspension-job");
    await jobRef.set({
      schemaVersion: 2,
      targetUID: ownerUID,
      cause: "permanentSuspension",
      expectedStateVersion: 99,
      status: "pending",
      attempt: 0,
      nextAttemptAt: now,
      leaseOwner: null,
      leaseExpiresAt: null,
    });

    assert.equal(await processRoomOwnershipSuccessionJob(jobRef.id, db, now), true);
    const [job, room] = await Promise.all([
      jobRef.get(),
      db.collection("Rooms").doc(roomID).get(),
    ]);
    assert.equal(job.data()?.status, "completed");
    assert.equal(job.data()?.result, "staleFence");
    assert.equal(room.data()?.isClosed, false);
    assert.equal((await room.ref.collection("members").doc(ownerUID).get()).exists, true);
  });

  test("최대 시도에서 lease가 만료된 승계 작업은 failed로 종결한다", async () => {
    const jobRef = db.collection("roomOwnershipSuccessionJobs").doc("max-attempt-job");
    await jobRef.set({
      targetUID: ownerUID,
      cause: "permanentSuspension",
      status: "processing",
      attempt: 20,
      nextAttemptAt: new Date(now.getTime() - 2_000),
      leaseOwner: "crashed-worker",
      leaseExpiresAt: new Date(now.getTime() - 1_000),
      updatedAt: new Date(now.getTime() - 2_000),
    });

    assert.equal(await processRoomOwnershipSuccessionJob(jobRef.id, db, now), false);
    const job = await jobRef.get();
    assert.equal(job.data()?.status, "failed");
    assert.equal(job.data()?.attempt, 20);
    assert.equal(job.data()?.leaseOwner, null);
    assert.equal(job.data()?.leaseExpiresAt, null);
    assert.equal(job.data()?.nextAttemptAt, null);
    assert.equal(job.data()?.lastErrorCode, "max_attempts_exceeded");
  });

  test("유효한 lease의 processing 승계 작업은 due여도 재점유하지 않는다", async () => {
    const jobRef = db.collection("roomOwnershipSuccessionJobs").doc("active-lease-job");
    const leaseExpiresAt = new Date(now.getTime() + 60_000);
    await jobRef.set({
      targetUID: ownerUID,
      cause: "permanentSuspension",
      status: "processing",
      attempt: 3,
      nextAttemptAt: new Date(now.getTime() - 2_000),
      leaseOwner: "active-worker",
      leaseExpiresAt,
      updatedAt: new Date(now.getTime() - 2_000),
    });

    assert.equal(await processRoomOwnershipSuccessionJob(jobRef.id, db, now), false);
    const job = await jobRef.get();
    assert.equal(job.data()?.status, "processing");
    assert.equal(job.data()?.attempt, 3);
    assert.equal(job.data()?.leaseOwner, "active-worker");
    assert.equal(job.data()?.leaseExpiresAt.toMillis(), leaseExpiresAt.getTime());
  });

  test("방장 추방은 밴과 참여 projection을 원자적으로 갱신하고 해제 후 재가입만 허용한다", async () => {
    assert.deepEqual(await getMyRoomAccessService(memberUID, {roomID}, db), {status: "member", role: "member"});
    const removed = await removeRoomMemberService(ownerUID, {
      roomID,
      targetUID: memberUID,
      reasonCode: "harassment",
      clientRequestID: "623e4567-e89b-42d3-a456-426614174000",
    }, now, db);
    assert.deepEqual(removed, {
      removed: true,
      roomBanned: true,
      memberCount: 1,
      moderatorCount: null,
      eventID: null,
      seq: null,
    });

    const room = db.collection("Rooms").doc(roomID);
    const banRef = room.collection("bans").doc("principal-chat-member");
    assert.equal((await room.collection("members").doc(memberUID).get()).exists, false);
    assert.equal((await db.collection("users").doc(memberUID)
      .collection("joinedRooms").doc(roomID).get()).exists, false);
    assert.equal((await room.get()).data()?.memberCount, 1);
    assert.equal((await banRef.get()).data()?.stateVersion, 1);
    assert.deepEqual(await getMyRoomAccessService(memberUID, {roomID}, db), {status: "banned", role: null});

    const replay = await removeRoomMemberService(ownerUID, {
      roomID,
      targetUID: memberUID,
      reasonCode: "harassment",
      clientRequestID: "623e4567-e89b-42d3-a456-426614174000",
    }, now, db);
    assert.deepEqual(replay, removed);
    assert.equal((await room.get()).data()?.memberCount, 1);

    const listed = await listRoomBansService(ownerUID, {
      roomID,
      pageSize: 10,
      cursor: null,
    }, db);
    assert.equal(listed.items.length, 1);
    assert.equal(listed.items[0].displayNameSnapshot, "참여자");
    assert.equal("moderationPrincipalID" in listed.items[0], false);
    assert.equal("currentUID" in listed.items[0], false);

    const unbanned = await unbanRoomMemberService(ownerUID, {
      roomID,
      banEntryToken: listed.items[0].banEntryToken,
      clientRequestID: "723e4567-e89b-42d3-a456-426614174000",
    }, new Date(now.getTime() + 1_000), db);
    assert.deepEqual(unbanned, {roomBanned: false, membershipRestored: false});
    assert.equal((await banRef.get()).data()?.isActive, false);
    assert.equal((await banRef.get()).data()?.stateVersion, 2);
    assert.deepEqual(await getMyRoomAccessService(memberUID, {roomID}, db), {status: "joinable", role: null});
    assert.equal((await room.collection("members").doc(memberUID).get()).exists, false);
    assert.equal((await listRoomBansService(ownerUID, {
      roomID,
      pageSize: 10,
      cursor: null,
    }, db)).items.length, 0);
  });

  test("메시지 삭제는 tombstone을 유지하고 공개 projection과 Storage를 수렴시킨다", async () => {
    const deletedPrefixes = [];
    const bucket = {
      deleteFiles: async ({prefix}) => deletedPrefixes.push(prefix),
    };
    const result = await deleteChatMessageService(ownerUID, null, {
      roomID,
      messageID,
      expectedSeq: 1,
      reasonCode: "chatMessageDeletion",
      reportTargetType: null,
      reportTargetID: null,
      clientRequestID: requestID,
    }, now, db);
    assert.equal(result.isDeleted, true);
    await processMessageCleanupJob(
      messageCleanupJobID(roomID, messageID),
      db,
      cleanupBucketResolver(bucket),
      now,
    );

    const room = await db.collection("Rooms").doc(roomID).get();
    const message = await room.ref.collection("Messages").doc(messageID).get();
    const reply = await room.ref.collection("Messages").doc("reply-1").get();
    const media = await room.ref.collection("mediaIndex").get();
    assert.equal(room.data()?.lastMessage, "삭제된 메시지입니다");
    assert.equal(room.data()?.messageDeletionRevision, 1);
    assert.equal(message.data()?.seq, 1);
    assert.equal(message.data()?.isDeleted, true);
    assert.equal(message.data()?.deletionRevision, 1);
    assert.deepEqual(Object.keys(message.data()).sort(), [
      "ID", "deletedAt", "deletionRevision", "isDeleted", "replyPreview", "roomID",
      "senderAnonymized", "senderAvatarPath", "senderNickname", "senderUID", "sentAt", "seq",
    ]);
    assert.equal(message.data()?.senderUID, ownerUID);
    assert.equal(message.data()?.senderNickname, "방장");
    assert.equal(message.data()?.senderAvatarPath, "avatars/owner/profile.jpg");
    assert.equal(message.data()?.sentAt.toMillis(), now.getTime());
    assert.deepEqual(message.data()?.replyPreview, {
      messageID: "source-message",
      sender: "이전 작성자",
      text: "이전 메시지",
    });
    assert.equal(message.data()?.senderAnonymized, false);
    assert.equal("msg" in message.data(), false);
    assert.equal("attachments" in message.data(), false);
    assert.deepEqual(reply.data()?.replyPreview, {
      messageID,
      sender: "",
      text: "",
      imagesCount: 0,
      videosCount: 0,
      isDeleted: true,
    });
    assert.equal(media.empty, true);
    assert.equal((await db.collection("chatMessageDeletionDeliveryJobs").get()).size, 1);
    assert.deepEqual(deletedPrefixes, [`rooms/${roomID}/messages/${messageID}/`]);

    const replay = await deleteChatMessageService(ownerUID, null, {
      roomID,
      messageID,
      expectedSeq: 1,
      reasonCode: "chatMessageDeletion",
      reportTargetType: null,
      reportTargetID: null,
      clientRequestID: "223e4567-e89b-42d3-a456-426614174000",
    }, now, db);
    assert.equal(replay.deduplicated, true);
    assert.equal((await room.ref.get()).data()?.messageDeletionRevision, 1);
    assert.equal((await db.collection("chatMessageDeletionDeliveryJobs").get()).size, 1);
  });

  test("계정 탈퇴 메시지는 방별 연속 revision과 cleanup 완료 gate로 수렴한다", async () => {
    const generation = "generation-1";
    const deletionRequestID = "account-deletion-request-1";
    await db.collection("users").doc(ownerUID).set({
      accountStatus: "deletionPending",
      accountGenerationID: generation,
    }, {merge: true});
    const secondRoom = db.collection("Rooms").doc("account-deletion-room");
    await secondRoom.set({
      lifecycleStatus: "active",
      messageDeletionRevision: 4,
      lastMessageSeq: 11,
      lastMessage: "개인정보 원문",
    });
    await Promise.all([
      secondRoom.collection("Messages").doc("account-message-b").set({
        ID: "account-message-b", roomID: secondRoom.id, senderUID: ownerUID,
        senderNickname: "탈퇴 대상", sentAt: now.toISOString(), seq: 11,
        msg: "두 번째", message: "두 번째", isDeleted: false,
      }),
      secondRoom.collection("Messages").doc("account-message-a").set({
        ID: "account-message-a", roomID: secondRoom.id, senderUID: ownerUID,
        senderNickname: "탈퇴 대상", sentAt: now.toISOString(), seq: 10,
        msg: "첫 번째", message: "첫 번째", isDeleted: false,
      }),
      secondRoom.collection("Messages").doc("role-event-owner").set({
        ID: "role-event-owner", roomID: secondRoom.id, senderUID: "system",
        senderNickname: "OutPick", sentAt: now.toISOString(), seq: 12,
        messageType: "roomRoleEvent", serverGenerated: true,
        roleEvent: {
          kind: "moderatorAssigned",
          subjectUID: ownerUID,
          subjectNicknameSnapshot: "탈퇴 대상",
        },
      }),
    ]);

    assert.equal(await scrubMessagePage(
      ownerUID,
      deletionRequestID,
      generation,
      now,
    ), true);
    const [first, second, roleEvent, secondRoomAfter] = await Promise.all([
      secondRoom.collection("Messages").doc("account-message-a").get(),
      secondRoom.collection("Messages").doc("account-message-b").get(),
      secondRoom.collection("Messages").doc("role-event-owner").get(),
      secondRoom.get(),
    ]);
    assert.equal(first.data()?.deletionRevision, 5);
    assert.equal(second.data()?.deletionRevision, 6);
    assert.equal(secondRoomAfter.data()?.messageDeletionRevision, 6);
    assert.equal(secondRoomAfter.data()?.lastMessage, "삭제된 메시지입니다");
    assert.equal("senderUID" in first.data(), false);
    assert.equal(first.data()?.senderNickname, "알 수 없는 사용자");
    assert.equal(first.data()?.senderAnonymized, true);
    assert.equal("msg" in first.data(), false);
    assert.equal("message" in first.data(), false);
    assert.equal("senderAvatarPath" in first.data(), false);
    assert.equal(first.data()?.sentAt, now.toISOString());
    assert.equal((await db.collection("chatMessageDeletionDeliveryJobs").get()).size, 2);
    assert.equal(roleEvent.data()?.roleEvent?.subjectUID, undefined);
    assert.equal(roleEvent.data()?.roleEvent?.subjectNicknameSnapshot, "알 수 없는 사용자");
    const privacyDelivery = await db.collection("chatRoleEventDeliveryJobs")
      .doc("role-event-owner-privacy").get();
    assert.equal(privacyDelivery.data()?.eventID, "role-event-owner");
    assert.equal(privacyDelivery.data()?.status, "pending");
    assert.equal(await hasIncompleteAccountDeletionMessageCleanup(deletionRequestID), true);

    const jobs = await db.collection("chatMessageCleanupJobs")
      .where("accountDeletionRequestID", "==", deletionRequestID).get();
    const bucket = {deleteFiles: async () => {}};
    for (const job of jobs.docs) {
      assert.equal(await processMessageCleanupJob(
        job.id,
        db,
        cleanupBucketResolver(bucket),
        now,
      ), true);
    }
    assert.equal(await hasIncompleteAccountDeletionMessageCleanup(deletionRequestID), false);
  });

  test("방장 종료는 공용 tombstone을 남기고 확인한 참여자만 정리한다", async () => {
    const deletedPrefixes = [];
    const result = await closeOwnedChatRoomService(ownerUID, {
      roomID,
      expectedLifecycleVersion: 1,
      clientRequestID: requestID,
    }, now, db);
    assert.equal(result.lifecycleStatus, "closedByOwner");
    const closed = await db.collection("Rooms").doc(roomID).get();
    assert.equal(closed.data()?.isClosed, true);

    await processRoomCleanupJob(roomID, db, cleanupBucketResolver({
      deleteFiles: async ({prefix}) => deletedPrefixes.push(prefix),
    }), now);
    const roomAfterCleanup = await db.collection("Rooms").doc(roomID).get();
    assert.equal(roomAfterCleanup.exists, true);
    assert.equal(roomAfterCleanup.data()?.tombstoneSchemaVersion, 1);
    assert.equal(roomAfterCleanup.data()?.roomName, "정리 테스트방");
    assert.equal(roomAfterCleanup.data()?.lastMessage, undefined);
    assert.equal(
      roomAfterCleanup.data()?.expiresAt.toMillis() - roomAfterCleanup.data()?.closedAt.toMillis(),
      14 * 24 * 60 * 60 * 1000,
    );
    const replay = await closeOwnedChatRoomService(ownerUID, {
      roomID,
      expectedLifecycleVersion: 1,
      clientRequestID: requestID,
    }, now, db);
    assert.deepEqual(replay, result);
    assert.equal((await db.collection("users").doc(ownerUID)
      .collection("joinedRooms").doc(roomID).get()).exists, false);
    assert.equal((await db.collection("users").doc(memberUID)
      .collection("joinedRooms").doc(roomID).get()).exists, true);
    assert.equal((await roomAfterCleanup.ref.collection("members").doc(memberUID).get()).exists, true);

    const acknowledged = await acknowledgeRoomClosureService(memberUID, {
      roomID,
      clientRequestID: "323e4567-e89b-42d3-a456-426614174000",
    }, db);
    assert.equal(acknowledged.acknowledged, true);
    assert.equal((await db.collection("users").doc(memberUID)
      .collection("joinedRooms").doc(roomID).get()).exists, false);
    assert.equal((await roomAfterCleanup.ref.collection("members").doc(memberUID).get()).exists, false);
    const replayedAcknowledgement = await acknowledgeRoomClosureService(memberUID, {
      roomID,
      clientRequestID: "423e4567-e89b-42d3-a456-426614174000",
    }, db);
    assert.equal(replayedAcknowledgement.deduplicated, true);
    assert.deepEqual(deletedPrefixes, [`rooms/${roomID}/`]);
  });

  test("활성 방은 종료 확인으로 참여 projection을 지울 수 없다", async () => {
    await assert.rejects(
      acknowledgeRoomClosureService(memberUID, {
        roomID,
        clientRequestID: "523e4567-e89b-42d3-a456-426614174000",
      }, db),
      (error) => error?.code === "failed-precondition",
    );
    assert.equal((await db.collection("users").doc(memberUID)
      .collection("joinedRooms").doc(roomID).get()).exists, true);
    assert.equal((await db.collection("Rooms").doc(roomID)
      .collection("members").doc(memberUID).get()).exists, true);
  });

  test("대규모 참여자 방 종료도 Firestore batch write 한도 안에서 수렴한다", async () => {
    const room = db.collection("Rooms").doc(roomID);
    const batch = db.batch();
    for (const uid of bulkMemberUIDs) {
      batch.set(room.collection("members").doc(uid), {role: "member"});
      batch.set(db.collection("users").doc(uid).collection("joinedRooms").doc(roomID), {roomID});
    }
    await batch.commit();

    await closeOwnedChatRoomService(ownerUID, {
      roomID,
      expectedLifecycleVersion: 1,
      clientRequestID: "223e4567-e89b-42d3-a456-426614174000",
    }, now, db);
    const retained = await processRoomCleanupJob(roomID, db, cleanupBucketResolver({
      deleteFiles: async () => {},
    }), now);

    assert.equal(retained, true);
    assert.equal((await room.get()).exists, true);
    const afterFourteenDays = new Date(now.getTime() + 14 * 24 * 60 * 60 * 1000);
    const completed = await processRoomCleanupJob(roomID, db, cleanupBucketResolver({
      deleteFiles: async () => {},
    }), afterFourteenDays);
    assert.equal(completed, true);
    assert.equal((await room.get()).exists, false);
    for (const uid of [bulkMemberUIDs[0], bulkMemberUIDs.at(-1)]) {
      const joined = await db.collection("users").doc(uid)
        .collection("joinedRooms").doc(roomID).get();
      assert.equal(joined.exists, false);
    }
  });
});
