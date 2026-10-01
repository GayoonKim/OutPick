import {after, before, beforeEach, describe, test} from "node:test";
import {readFileSync} from "node:fs";
import {
  assertFails,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, updateDoc} from "firebase/firestore";

const projectId = "outpick-rules-test";
const senderUID = "media-sender";
const otherUID = "media-other";
const roomID = "media-room";
const firestoreRules = readFileSync(
  new URL("../firestore.rules", import.meta.url),
  "utf8",
);
const storageRules = readFileSync(
  new URL("../storage.rules", import.meta.url),
  "utf8",
);

let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {host: "127.0.0.1", port: 8080, rules: firestoreRules},
    storage: {host: "127.0.0.1", port: 9199, rules: storageRules},
  });
});

beforeEach(async () => {
  await Promise.all([
    testEnvironment.clearFirestore(),
    testEnvironment.clearStorage(),
  ]);
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await Promise.all([
      setDoc(doc(firestore, "moderationAccounts", senderUID), {
        schemaVersion: 2,
        accountStatus: "active",
        moderationStatus: "active",
        stateVersion: 1,
      }),
      setDoc(doc(firestore, "moderationAccounts", otherUID), {
        schemaVersion: 2,
        accountStatus: "active",
        moderationStatus: "active",
        stateVersion: 1,
      }),
      setDoc(doc(firestore, "Rooms", roomID), {
        creatorUID: senderUID,
        isClosed: false,
        lifecycleStatus: "active",
      }),
    ]);
  });
});

after(async () => testEnvironment.cleanup());

function uploadJpeg(reference) {
  return reference.put(
    new Uint8Array([0xff, 0xd8, 0xff, 0xd9]),
    {contentType: "image/jpeg"},
  );
}

function readyReference(context, messageID, variant = "display") {
  return context.storage().ref(
    `rooms/${roomID}/messages/${messageID}/attachments/attachment-1/${variant}`,
  );
}

function legacyMediaReference(context, messageID, path) {
  return context.storage().ref(`rooms/${roomID}/messages/${messageID}/${path}`);
}

async function seedReadyMessage(messageID, overrides = {}) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "Rooms", roomID, "Messages", messageID), {
      ID: messageID,
      mediaContractVersion: 3,
      mediaExpiresAt: new Date(Date.now() + 60_000),
      readyAttachmentIDs: ["attachment-1"],
      attachments: [{attachmentID: "attachment-1", type: "video"}],
      moderationVisibilityState: "visible",
      isDeleted: false,
      ...overrides,
    });
  });
}

describe("chat media storage boundary", () => {
  test("클라이언트는 서버 전용 만료 정리 원장을 읽거나 쓸 수 없다", async () => {
    const sender = testEnvironment.authenticatedContext(senderUID).firestore();
    const job = doc(sender, "chatMediaExpiryJobs", "job-1");

    await assertFails(setDoc(job, {status: "scheduled"}));
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "chatMediaExpiryJobs", "job-1"), {
        status: "scheduled",
        roomID,
        messageID: "message-1",
      });
    });
    await assertFails(getDoc(job));
    await assertFails(updateDoc(job, {status: "processing"}));
  });

  test("구형 images/video 경로는 읽기와 클라이언트 업로드를 모두 거부한다", async () => {
    const sender = testEnvironment.authenticatedContext(senderUID);
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await Promise.all([
        uploadJpeg(legacyMediaReference(context, "legacy-image", "images/0/thumb.jpg")),
        uploadJpeg(legacyMediaReference(context, "legacy-video", "video/thumb.jpg")),
        uploadJpeg(legacyMediaReference(context, "legacy-video", "video/original.mp4")),
      ]);
    });

    for (const [messageID, path] of [
      ["legacy-image", "images/0/thumb.jpg"],
      ["legacy-video", "video/thumb.jpg"],
      ["legacy-video", "video/original.mp4"],
    ]) {
      const reference = legacyMediaReference(sender, messageID, path);
      await assertFails(reference.getDownloadURL());
      await assertFails(uploadJpeg(reference));
    }
  });

  test("미만료 ready 원본과 썸네일도 클라이언트 SDK 직접 읽기를 거부한다", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await uploadJpeg(readyReference(context, "ready-message"));
      await uploadJpeg(readyReference(context, "ready-message", "thumbnail"));
    });
    const sender = testEnvironment.authenticatedContext(senderUID);
    const other = testEnvironment.authenticatedContext(otherUID);
    await assertFails(readyReference(sender, "ready-message").getDownloadURL());
    await assertFails(uploadJpeg(readyReference(sender, "ready-message")));
    await seedReadyMessage("ready-message");
    await assertFails(readyReference(sender, "ready-message").getDownloadURL());
    await assertFails(readyReference(other, "ready-message").getDownloadURL());
    await assertFails(readyReference(sender, "ready-message", "thumbnail").getDownloadURL());

    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), "moderationAccounts", otherUID), {
        moderationStatus: "restricted",
        restrictedUntil: new Date(Date.now() + 60_000),
      });
    });
    await assertFails(readyReference(other, "ready-message").getDownloadURL());
  });

  test("기한 누락·오류·만료·계약2·삭제·숨김·폐쇄 방의 ready 객체는 읽지 못한다", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await uploadJpeg(readyReference(context, "bad-contract"));
      await uploadJpeg(readyReference(context, "missing-expiry"));
      await uploadJpeg(readyReference(context, "wrong-expiry"));
      await uploadJpeg(readyReference(context, "expired"));
      await uploadJpeg(readyReference(context, "deleted"));
      await uploadJpeg(readyReference(context, "hidden"));
      await uploadJpeg(readyReference(context, "closed-room"));
    });
    const sender = testEnvironment.authenticatedContext(senderUID);
    await seedReadyMessage("bad-contract", {mediaContractVersion: 2});
    await seedReadyMessage("missing-expiry", {mediaExpiresAt: null});
    await seedReadyMessage("wrong-expiry", {mediaExpiresAt: "2099-01-01T00:00:00.000Z"});
    await seedReadyMessage("expired", {mediaExpiresAt: new Date(Date.now() - 1_000)});
    await seedReadyMessage("deleted", {isDeleted: true});
    await seedReadyMessage("hidden", {moderationVisibilityState: "hiddenPendingReview"});
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "Rooms", "closed-room"), {
        isClosed: true,
        lifecycleStatus: "closedByOwner",
      });
      await uploadJpeg(context.storage().ref(
        `rooms/closed-room/messages/closed-room/attachments/attachment-1/display`,
      ));
      await setDoc(doc(
        context.firestore(), "Rooms", "closed-room", "Messages", "closed-room",
      ), {
        mediaContractVersion: 3,
        mediaExpiresAt: new Date(Date.now() + 60_000),
        readyAttachmentIDs: ["attachment-1"],
        isDeleted: false,
      });
    });

    for (const messageID of [
      "bad-contract", "missing-expiry", "wrong-expiry", "expired", "deleted", "hidden",
    ]) {
      await assertFails(readyReference(sender, messageID).getDownloadURL());
    }
    const closed = testEnvironment.authenticatedContext(senderUID).storage().ref(
      `rooms/closed-room/messages/closed-room/attachments/attachment-1/display`,
    );
    await assertFails(closed.getDownloadURL());
  });
});
