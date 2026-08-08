import {after, before, beforeEach, describe, test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc} from "firebase/firestore";

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
        moderationPrincipalID: `principal-${uid}`,
        moderationStatus: uid.split("-")[0],
        restrictedUntil: null,
        stateVersion: 1,
      }),
    ));
    await setDoc(doc(firestore, "Rooms", "room"), {
      creatorUID: "active", memberCount: 1, isClosed: false,
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
  });
});
