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
    db.recursiveDelete(db.collection("chatMessageCleanupJobs")),
    db.recursiveDelete(db.collection("moderationRoomCleanupJobs")),
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
  });
  await Promise.all([
    room.collection("members").doc(ownerUID).set({role: "owner"}),
    room.collection("members").doc(memberUID).set({role: "member"}),
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
