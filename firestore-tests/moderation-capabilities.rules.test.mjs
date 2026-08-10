import {after, before, beforeEach, describe, test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {deleteDoc, doc, getDoc, setDoc, updateDoc} from "firebase/firestore";

const projectId = "outpick-rules-test";
const rules = readFileSync(new URL("../firestore.rules", import.meta.url), "utf8");
let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {host: "127.0.0.1", port: 8080, rules},
  });
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await Promise.all(["active", "restricted", "suspended", "missing"].map(
      (uid) => setDoc(doc(firestore, "users", uid), {accountStatus: "active"}),
    ));
    await Promise.all([
      "active", "restricted", "suspended", "active-new", "restricted-new",
      "suspended-new",
    ].map(
      (uid) => setDoc(doc(firestore, "moderationAccounts", uid), {
        accountStatus: "active",
        moderationPrincipalID: `principal-${uid}`,
        moderationStatus: uid.split("-")[0],
        restrictedUntil: null,
        stateVersion: 1,
      }),
    ));
    await setDoc(doc(firestore, "Rooms", "room"), {
      creatorUID: "active", memberCount: 1, isClosed: false,
      lifecycleStatus: "active", lifecycleVersion: 1,
    });
    await setDoc(doc(firestore, "Rooms", "room", "members", "active"), {
      joinedAt: new Date(),
    });
  });
});

after(async () => testEnvironment.cleanup());

describe("moderation capability rules", () => {
  test("restricted는 읽을 수 있지만 UGC 생성은 거부한다", async () => {
    const firestore = testEnvironment.authenticatedContext("restricted").firestore();
    await assertSucceeds(getDoc(doc(firestore, "users", "restricted")));
    await assertSucceeds(getDoc(doc(firestore, "Rooms", "room")));
    await assertFails(setDoc(doc(firestore, "tags", "new"), {name: "tag"}));
  });

  test("suspended와 projection 누락은 app content를 읽지 못한다", async () => {
    const suspended = testEnvironment.authenticatedContext("suspended").firestore();
    const missing = testEnvironment.authenticatedContext("missing").firestore();
    await assertFails(getDoc(doc(suspended, "Rooms", "room")));
    await assertFails(getDoc(doc(missing, "users", "missing")));
  });

  test("active와 restricted 재가입자는 없는 본인 account 문서를 단일 get할 수 있다", async () => {
    for (const uid of ["active-new", "restricted-new"]) {
      const firestore = testEnvironment.authenticatedContext(uid).firestore();
      const snapshot = await assertSucceeds(
        getDoc(doc(firestore, "users", uid)),
      );
      assert.equal(snapshot.exists(), false);
      await assertFails(getDoc(doc(firestore, "users", "other-missing")));
    }

    const suspended = testEnvironment
      .authenticatedContext("suspended-new").firestore();
    await assertFails(getDoc(doc(suspended, "users", "suspended-new")));
  });

  test("moderation 내부 문서는 본인 projection도 직접 읽거나 쓰지 못한다", async () => {
    const firestore = testEnvironment.authenticatedContext("active").firestore();
    const reference = doc(firestore, "moderationAccounts", "active");
    await assertFails(getDoc(reference));
    await assertFails(setDoc(reference, {moderationStatus: "active"}));
    await assertFails(getDoc(doc(
      firestore, "moderationPrincipals", "principal-active",
    )));
    await assertFails(getDoc(doc(
      firestore, "moderationUserReports", "principal-target",
    )));
    await assertFails(setDoc(doc(
      firestore, "moderationRoomReports", "room",
    ), {reviewState: "open"}));
    await assertFails(getDoc(doc(
      firestore,
      "moderationReportRateLimitBuckets",
      "principal-active_1",
    )));
    await assertFails(getDoc(doc(
      firestore,
      "moderationAdminRateLimitBuckets",
      "active_read_1",
    )));
  });

  test("메시지 tombstone과 방 lifecycle은 클라이언트가 직접 변경할 수 없다", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "Rooms", "room", "Messages", "message"), {
        ID: "message", roomID: "room", senderUID: "active", seq: 1,
        msg: "원문", isDeleted: false,
      });
    });
    const firestore = testEnvironment.authenticatedContext("active").firestore();
    await assertSucceeds(getDoc(doc(firestore, "Rooms", "room", "Messages", "message")));
    await assertFails(updateDoc(
      doc(firestore, "Rooms", "room", "Messages", "message"),
      {isDeleted: true},
    ));
    await assertFails(updateDoc(doc(firestore, "Rooms", "room"), {
      isClosed: true,
      lifecycleStatus: "closedByOwner",
      lifecycleVersion: 2,
    }));
  });

  test("폐쇄 방은 즉시 읽을 수 없고 사용자 안내는 본인만 읽고 삭제한다", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const firestore = context.firestore();
      await updateDoc(doc(firestore, "Rooms", "room"), {
        isClosed: true,
        lifecycleStatus: "closedByModeration",
        lifecycleVersion: 2,
      });
      await setDoc(doc(firestore, "users", "active", "roomClosureNotices", "room"), {
        roomID: "room",
        closureType: "closedByModeration",
        closureNoticeCode: "communityGuidelineViolation",
        closedAt: new Date(),
        expiresAt: new Date(),
      });
    });
    const owner = testEnvironment.authenticatedContext("active").firestore();
    const other = testEnvironment.authenticatedContext("restricted").firestore();
    const notice = doc(owner, "users", "active", "roomClosureNotices", "room");
    await assertFails(getDoc(doc(owner, "Rooms", "room")));
    await assertSucceeds(getDoc(notice));
    await assertFails(getDoc(doc(other, "users", "active", "roomClosureNotices", "room")));
    await assertFails(setDoc(notice, {closureType: "closedByOwner"}));
    await assertSucceeds(deleteDoc(notice));
  });
});
