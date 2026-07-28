import {after, before, beforeEach, describe, test} from "node:test";
import {readFileSync} from "node:fs";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
} from "firebase/firestore";

const projectId = "outpick-rules-test";
const ownerUID = "profile-owner";
const otherUID = "profile-other";
const rules = readFileSync(
  new URL("../firestore.rules", import.meta.url),
  "utf8",
);

let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules,
    },
  });
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await Promise.all([
      setDoc(doc(firestore, "users", ownerUID), {
        accountStatus: "active",
        onboardingVersion: 1,
        selectedMoodIDs: ["minimal"],
      }),
      setDoc(doc(firestore, "userPublicProfiles", ownerUID), {
        nickname: "아웃픽",
        avatarThumbPath: null,
        avatarOriginalPath: null,
      }),
      setDoc(doc(firestore, "nicknameIndex", "nickname-hash"), {
        uid: ownerUID,
      }),
    ]);
  });
});

after(async () => {
  await testEnvironment.cleanup();
});

describe("profile document boundary", () => {
  test("비공개 users 문서는 본인만 읽고 클라이언트는 쓸 수 없다", async () => {
    const owner = testEnvironment.authenticatedContext(ownerUID).firestore();
    const other = testEnvironment.authenticatedContext(otherUID).firestore();

    await assertSucceeds(getDoc(doc(owner, "users", ownerUID)));
    await assertFails(getDoc(doc(other, "users", ownerUID)));
    await assertFails(updateDoc(doc(owner, "users", ownerUID), {
      selectedMoodIDs: ["street"],
    }));
    await assertFails(setDoc(doc(other, "users", otherUID), {
      accountStatus: "active",
    }));
  });

  test("공개 프로필은 인증 사용자만 읽고 클라이언트는 쓸 수 없다", async () => {
    const owner = testEnvironment.authenticatedContext(ownerUID).firestore();
    const other = testEnvironment.authenticatedContext(otherUID).firestore();
    const unauthenticated = testEnvironment.unauthenticatedContext().firestore();

    await assertSucceeds(
      getDoc(doc(other, "userPublicProfiles", ownerUID)),
    );
    await assertFails(
      getDoc(doc(unauthenticated, "userPublicProfiles", ownerUID)),
    );
    await assertFails(updateDoc(
      doc(owner, "userPublicProfiles", ownerUID),
      {nickname: "변경닉네임"},
    ));
  });

  test("닉네임 인덱스는 모든 클라이언트 접근을 거부한다", async () => {
    const owner = testEnvironment.authenticatedContext(ownerUID).firestore();

    await assertFails(getDoc(doc(owner, "nicknameIndex", "nickname-hash")));
    await assertFails(setDoc(doc(owner, "nicknameIndex", "other-hash"), {
      uid: ownerUID,
    }));
  });
});
