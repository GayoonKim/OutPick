import {after, before, beforeEach, describe, test} from "node:test";
import {readFileSync} from "node:fs";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, setDoc} from "firebase/firestore";

const projectId = "outpick-rules-test";
const bucket = `${projectId}.appspot.com`;
const senderUID = "quarantine-sender";
const otherUID = "quarantine-other";
const roomID = "quarantine-room";
const uploadID = "upload-v2";
const attachmentID = "attachment-a";
const firestoreRules = readFileSync(
  new URL("../firestore.rules", import.meta.url),
  "utf8",
);
const storageRules = readFileSync(
  new URL("../storage.chat-media-quarantine.rules", import.meta.url),
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
      }),
      setDoc(doc(firestore, "moderationAccounts", otherUID), {
        schemaVersion: 2,
        accountStatus: "active",
        moderationStatus: "active",
      }),
      setDoc(doc(firestore, "Rooms", roomID, "MediaUploads", uploadID), {
        contractVersion: 2,
        senderUID,
        kind: "images",
        processingStatus: "uploading",
        quarantineBucket: bucket,
        attachmentIDs: [attachmentID, "attachment-b", "attachment-c"],
        uploadExpiresAt: new Date(Date.now() + 60_000),
      }),
    ]);
  });
});

after(async () => testEnvironment.cleanup());

function sourceReference(context, id = attachmentID) {
  return context.storage().ref(
    `${roomID}/${senderUID}/${uploadID}/${id}/source`,
  );
}

describe("chat media quarantine storage boundary", () => {
  test("예약 발급자만 exact attachment source를 한 번 생성할 수 있다", async () => {
    const sender = testEnvironment.authenticatedContext(senderUID);
    const other = testEnvironment.authenticatedContext(otherUID);
    const bytes = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
    await assertFails(sourceReference(other).put(bytes, {contentType: "image/jpeg"}));
    await assertFails(sourceReference(sender, "not-reserved").put(
      bytes,
      {contentType: "image/jpeg"},
    ));
    await assertSucceeds(sourceReference(sender).put(
      bytes,
      {contentType: "image/jpeg"},
    ));
    await assertFails(sourceReference(sender).put(
      bytes,
      {contentType: "image/jpeg"},
    ));
  });

  test("클라이언트 read/delete와 잘못된 MIME을 거부한다", async () => {
    const sender = testEnvironment.authenticatedContext(senderUID);
    const reference = sourceReference(sender, "attachment-b");
    await assertFails(reference.put(
      new Uint8Array([1, 2, 3]),
      {contentType: "image/heic"},
    ));
    await assertSucceeds(reference.put(
      new Uint8Array([0xff, 0xd8, 0xff, 0xd9]),
      {contentType: "image/jpeg"},
    ));
    await assertFails(reference.getDownloadURL());
    await assertFails(reference.delete());
  });

  test("terminal 또는 만료 reservation은 source 생성을 거부한다", async () => {
    const sender = testEnvironment.authenticatedContext(senderUID);
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(
        context.firestore(),
        "Rooms", roomID, "MediaUploads", uploadID,
      ), {
        processingStatus: "queued",
      }, {merge: true});
    });
    await assertFails(sourceReference(sender, "attachment-c").put(
      new Uint8Array([0xff, 0xd8, 0xff, 0xd9]),
      {contentType: "image/jpeg"},
    ));
  });
});
