import {after, before, beforeEach, describe, test} from "node:test";
import {readFileSync} from "node:fs";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {deleteDoc, doc, setDoc, updateDoc} from "firebase/firestore";

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

function imageReference(context, messageID, fileName = "thumb.jpg") {
  return context.storage().ref(
    `rooms/${roomID}/messages/${messageID}/images/0/${fileName}`,
  );
}

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

async function seedReservation(messageID, overrides = {}) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(
      context.firestore(),
      "Rooms", roomID, "MediaUploads", messageID,
    ), {
      roomID,
      messageID,
      senderUID,
      kind: "images",
      status: "pending",
      storagePrefix: `rooms/${roomID}/messages/${messageID}`,
      expiresAt: new Date(Date.now() + 60_000),
      ...overrides,
    });
  });
}

describe("chat media storage boundary", () => {
  test("서버가 발급한 유효한 이미지 예약으로만 업로드할 수 있다", async () => {
    const sender = testEnvironment.authenticatedContext(senderUID);
    await seedReservation("valid");
    await assertSucceeds(uploadJpeg(imageReference(sender, "valid")));
    await assertFails(uploadJpeg(imageReference(sender, "missing")));

    await seedReservation("wrong-kind", {kind: "video"});
    await assertFails(uploadJpeg(imageReference(sender, "wrong-kind")));
    await seedReservation("expired", {expiresAt: new Date(Date.now() - 1_000)});
    await assertFails(uploadJpeg(imageReference(sender, "expired")));
  });

  test("예약 발급자가 아닌 사용자는 업로드할 수 없다", async () => {
    const other = testEnvironment.authenticatedContext(otherUID);
    await seedReservation("owned-by-sender");
    await assertFails(uploadJpeg(imageReference(other, "owned-by-sender")));
  });

  test("활성·제한 계정은 활성 방 이미지를 읽고 비활성 계정은 읽지 못한다", async () => {
    const sender = testEnvironment.authenticatedContext(senderUID);
    const other = testEnvironment.authenticatedContext(otherUID);
    await seedReservation("readable");
    const reference = imageReference(sender, "readable");
    await assertSucceeds(uploadJpeg(reference));
    await assertSucceeds(imageReference(other, "readable").getDownloadURL());

    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), "moderationAccounts", otherUID), {
        accountStatus: "deletionPending",
      });
    });
    await assertFails(imageReference(other, "readable").getDownloadURL());
  });

  test("v2 ready 객체는 계정·message 상태만으로 읽고 비노출 이후 거부한다", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await uploadJpeg(readyReference(context, "ready-message"));
    });
    const sender = testEnvironment.authenticatedContext(senderUID);
    await assertFails(readyReference(sender, "ready-message").getDownloadURL());

    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(
        context.firestore(), "Rooms", roomID, "Messages", "ready-message",
      ), {
        ID: "ready-message",
        mediaContractVersion: 2,
        readyAttachmentIDs: ["attachment-1"],
        moderationVisibilityState: "visible",
        isDeleted: false,
      });
    });
    await assertSucceeds(readyReference(sender, "ready-message").getDownloadURL());

    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await deleteDoc(doc(context.firestore(), "Rooms", roomID));
    });
    await assertSucceeds(readyReference(sender, "ready-message").getDownloadURL());

    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(
        context.firestore(), "Rooms", roomID, "Messages", "ready-message",
      ), {moderationVisibilityState: "hiddenPendingReview"});
    });
    await assertFails(readyReference(sender, "ready-message").getDownloadURL());
  });
});
