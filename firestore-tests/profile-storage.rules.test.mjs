import {after, before, beforeEach, describe, test} from "node:test";
import {readFileSync} from "node:fs";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, setDoc, updateDoc} from "firebase/firestore";

const projectId = "outpick-rules-test";
const ownerUID = "storage-owner";
const otherUID = "storage-other";
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
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules: firestoreRules,
    },
    storage: {
      host: "127.0.0.1",
      port: 9199,
      rules: storageRules,
    },
  });
});

beforeEach(async () => {
  await Promise.all([
    testEnvironment.clearFirestore(),
    testEnvironment.clearStorage(),
  ]);
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await Promise.all([
      setDoc(doc(context.firestore(), "users", ownerUID), {
        accountStatus: "active",
      }),
      setDoc(doc(context.firestore(), "users", otherUID), {
        accountStatus: "active",
      }),
      setDoc(doc(context.firestore(), "moderationAccounts", ownerUID), {
        accountStatus: "active", moderationStatus: "active", stateVersion: 1,
      }),
      setDoc(doc(context.firestore(), "moderationAccounts", otherUID), {
        accountStatus: "active", moderationStatus: "active", stateVersion: 1,
      }),
    ]);
  });
});

after(async () => {
  await testEnvironment.cleanup();
});

function avatarReference(context, userID = ownerUID) {
  return context
    .storage()
    .ref(`profileImage/${userID}/thumb/avatar.jpg`);
}

function uploadAvatar(reference) {
  return reference.put(
    new Uint8Array([0xff, 0xd8, 0xff, 0xd9]),
    {contentType: "image/jpeg"},
  );
}

describe("profile storage boundary", () => {
  test("active 사용자는 자신의 프로필 이미지만 업로드할 수 있다", async () => {
    const owner = testEnvironment.authenticatedContext(ownerUID);
    const other = testEnvironment.authenticatedContext(otherUID);

    await assertSucceeds(uploadAvatar(avatarReference(owner)));
    await assertFails(uploadAvatar(avatarReference(other)));
    await assertFails(uploadAvatar(avatarReference(owner, otherUID)));
  });

  test("deletionPending 사용자의 업로드와 삭제를 거부한다", async () => {
    const owner = testEnvironment.authenticatedContext(ownerUID);
    const reference = avatarReference(owner);
    await assertSucceeds(uploadAvatar(reference));

    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), "moderationAccounts", ownerUID), {
        accountStatus: "deletionPending",
      });
    });

    await assertFails(reference.delete());
    await assertFails(uploadAvatar(
      owner.storage().ref(
        `profileImage/${ownerUID}/original/avatar.jpg`,
      ),
    ));
  });

  test("인증 사용자는 이미지를 읽고 비인증 사용자는 읽을 수 없다", async () => {
    const owner = testEnvironment.authenticatedContext(ownerUID);
    const other = testEnvironment.authenticatedContext(otherUID);
    const unauthenticated = testEnvironment.unauthenticatedContext();
    await assertSucceeds(uploadAvatar(avatarReference(owner)));

    await assertSucceeds(avatarReference(other).getDownloadURL());
    await assertFails(avatarReference(unauthenticated).getDownloadURL());
  });

  test("pending 사용자의 기존 프로필 이미지는 다른 사용자에게도 숨긴다", async () => {
    const owner = testEnvironment.authenticatedContext(ownerUID);
    const other = testEnvironment.authenticatedContext(otherUID);
    const reference = avatarReference(owner);
    await assertSucceeds(uploadAvatar(reference));
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), "moderationAccounts", ownerUID), {
        accountStatus: "deletionPending",
      });
    });

    await assertFails(avatarReference(other).getDownloadURL());
  });

  test("restricted는 기존 이미지를 읽되 새 이미지를 업로드하지 못한다", async () => {
    const owner = testEnvironment.authenticatedContext(ownerUID);
    const reference = avatarReference(owner);
    await assertSucceeds(uploadAvatar(reference));
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), "moderationAccounts", ownerUID), {
        moderationStatus: "restricted",
      });
    });

    await assertSucceeds(reference.getDownloadURL());
    await assertFails(uploadAvatar(owner.storage().ref(
      `profileImage/${ownerUID}/original/restricted.jpg`,
    )));
  });
});
