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
  processRoomOwnershipSuccessionJob,
  resolveRoomMembershipPage,
} from "../functions/lib/chat/moderation/roomMembershipSweep.js";
import {
  processMessageCleanupJob,
  processRoomCleanupJob,
} from "../functions/lib/chat/cleanup/moderationCleanup.js";

const ownerUID = "chat-owner";
const memberUID = "chat-member";
const roomID = "chat-moderation-room";
const messageID = "message-1";
const requestID = "123e4567-e89b-42d3-a456-426614174000";
const now = new Date("2026-08-10T08:00:00.000Z");
const bulkMemberUIDs = Array.from(
  {length: 170},
  (_, index) => `bulk-member-${String(index).padStart(3, "0")}`,
);

async function clearFixtures() {
  await Promise.all([
    db.recursiveDelete(db.collection("Rooms").doc(roomID)),
    db.recursiveDelete(db.collection("users").doc(ownerUID)),
    db.recursiveDelete(db.collection("users").doc(memberUID)),
    db.recursiveDelete(db.collection("moderationAccounts").doc(ownerUID)),
    db.recursiveDelete(db.collection("moderationAccounts").doc(memberUID)),
    db.recursiveDelete(db.collection("userPublicProfiles").doc(memberUID)),
    db.recursiveDelete(db.collection("chatMessageCleanupJobs")),
    db.recursiveDelete(db.collection("moderationRoomCleanupJobs")),
    db.recursiveDelete(db.collection("roomOwnershipSuccessionJobs")),
    db.recursiveDelete(db.collection("moderationAuditLogs")),
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
  await Promise.all([
    room.collection("members").doc(ownerUID).set({
      role: "owner", userID: ownerUID, joinedAt: new Date("2026-01-01T00:00:00Z"),
    }),
    room.collection("members").doc(memberUID).set({
      role: "member", userID: memberUID, joinedAt: new Date("2026-01-02T00:00:00Z"),
    }),
    db.collection("users").doc(ownerUID).collection("joinedRooms").doc(roomID).set({roomID}),
    db.collection("users").doc(memberUID).collection("joinedRooms").doc(roomID).set({roomID}),
    room.collection("Messages").doc(messageID).set({
      ID: messageID,
      roomID,
      senderUID: ownerUID,
      senderNickname: "방장",
      seq: 1,
      msg: "삭제 대상",
      isDeleted: false,
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
  test("계정 삭제 시 가장 오래된 유효 참여자에게 방장을 승계하고 기존 소유자를 제거한다", async () => {
    const completed = await resolveRoomMembershipPage(
      ownerUID,
      "accountDeletion",
      now,
      db,
    );
    assert.equal(completed, false);
    const room = await db.collection("Rooms").doc(roomID).get();
    assert.equal(room.data()?.creatorUID, memberUID);
    assert.equal(room.data()?.memberCount, 1);
    assert.equal((await room.ref.collection("members").doc(ownerUID).get()).exists, false);
    assert.equal((await room.ref.collection("members").doc(memberUID).get()).data()?.role, "owner");
    assert.equal((await db.collection("users").doc(memberUID)
      .collection("joinedRooms").doc(roomID).get()).data()?.role, "owner");
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
    assert.deepEqual(await getMyRoomAccessService(memberUID, {roomID}, db), {status: "member"});
    const removed = await removeRoomMemberService(ownerUID, {
      roomID,
      targetUID: memberUID,
      reasonCode: "harassment",
      clientRequestID: "623e4567-e89b-42d3-a456-426614174000",
    }, now, db);
    assert.deepEqual(removed, {removed: true, roomBanned: true, memberCount: 1});

    const room = db.collection("Rooms").doc(roomID);
    const banRef = room.collection("bans").doc("principal-chat-member");
    assert.equal((await room.collection("members").doc(memberUID).get()).exists, false);
    assert.equal((await db.collection("users").doc(memberUID)
      .collection("joinedRooms").doc(roomID).get()).exists, false);
    assert.equal((await room.get()).data()?.memberCount, 1);
    assert.equal((await banRef.get()).data()?.stateVersion, 1);
    assert.deepEqual(await getMyRoomAccessService(memberUID, {roomID}, db), {status: "banned"});

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
    assert.deepEqual(await getMyRoomAccessService(memberUID, {roomID}, db), {status: "joinable"});
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
    await processMessageCleanupJob(messageCleanupJobID(roomID, messageID), db, bucket, now);

    const room = await db.collection("Rooms").doc(roomID).get();
    const message = await room.ref.collection("Messages").doc(messageID).get();
    const reply = await room.ref.collection("Messages").doc("reply-1").get();
    const media = await room.ref.collection("mediaIndex").get();
    assert.equal(room.data()?.lastMessage, "삭제된 메시지입니다.");
    assert.equal(message.data()?.seq, 1);
    assert.equal(message.data()?.isDeleted, true);
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
    assert.deepEqual(deletedPrefixes, [`rooms/${roomID}/messages/${messageID}/`]);
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

    await processRoomCleanupJob(roomID, db, {
      deleteFiles: async ({prefix}) => deletedPrefixes.push(prefix),
    }, now);
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
    const retained = await processRoomCleanupJob(roomID, db, {
      deleteFiles: async () => {},
    }, now);

    assert.equal(retained, true);
    assert.equal((await room.get()).exists, true);
    const afterFourteenDays = new Date(now.getTime() + 14 * 24 * 60 * 60 * 1000);
    const completed = await processRoomCleanupJob(roomID, db, {
      deleteFiles: async () => {},
    }, afterFourteenDays);
    assert.equal(completed, true);
    assert.equal((await room.get()).exists, false);
    for (const uid of [bulkMemberUIDs[0], bulkMemberUIDs.at(-1)]) {
      const joined = await db.collection("users").doc(uid)
        .collection("joinedRooms").doc(roomID).get();
      assert.equal(joined.exists, false);
    }
  });
});
