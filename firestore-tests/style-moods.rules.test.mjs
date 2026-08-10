import assert from "node:assert/strict";
import {after, before, beforeEach, describe, test} from "node:test";
import {readFileSync} from "node:fs";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  setDoc,
  updateDoc,
  where,
} from "firebase/firestore";

const projectId = "outpick-rules-test";
const userUID = "style-mood-user";
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
      setDoc(doc(firestore, "styleMoods", "minimal"), {
        displayName: "미니멀",
        status: "active",
        sortOrder: 20,
      }),
      setDoc(doc(firestore, "styleMoods", "legacy"), {
        displayName: "비활성",
        status: "inactive",
        sortOrder: 999,
      }),
      setDoc(doc(firestore, "styleMoodTermIndex", "term-hash"), {
        moodID: "minimal",
        termType: "canonical",
      }),
      setDoc(doc(firestore, "styleMoodSeedMetadata", "current"), {
        version: 1,
        count: 56,
      }),
      setDoc(doc(firestore, "brandAdmins", "total-admin"), {
        isActive: true,
      }),
      setDoc(doc(firestore, "users", "total-admin"), {
        accountStatus: "active",
      }),
      setDoc(doc(firestore, "users", "brand-admin"), {
        accountStatus: "active",
      }),
      setDoc(doc(firestore, "moderationAccounts", "total-admin"), {
        accountStatus: "active", moderationStatus: "active", stateVersion: 1,
      }),
      setDoc(doc(firestore, "moderationAccounts", "brand-admin"), {
        accountStatus: "active", moderationStatus: "active", stateVersion: 1,
      }),
      setDoc(doc(firestore, "brands", "brand-1"), {
        name: "Brand",
      }),
      setDoc(doc(firestore, "brands", "brand-1", "seasons", "season-1"), {
        displayTitle: "25 F/W",
        moodIDs: [],
      }),
      setDoc(doc(
        firestore,
        "brands", "brand-1", "seasonDiscoveryJobs", "job-1",
      ), {status: "succeeded", generation: 1}),
      setDoc(doc(
        firestore,
        "brands", "brand-1", "seasonDiscoveryJobs", "job-1",
        "candidates", "candidate-1",
      ), {title: "25 F/W", resolution: "newSeason"}),
    ]);
  });
});

after(async () => {
  await testEnvironment.cleanup();
});

describe("style mood rules", () => {
  test("인증 사용자는 active 무드만 조회할 수 있다", async () => {
    const firestore = testEnvironment
      .authenticatedContext(userUID)
      .firestore();

    await assertSucceeds(getDoc(doc(firestore, "styleMoods", "minimal")));
    await assertFails(getDoc(doc(firestore, "styleMoods", "legacy")));

    const snapshot = await assertSucceeds(getDocs(query(
      collection(firestore, "styleMoods"),
      where("status", "==", "active"),
      orderBy("sortOrder", "asc"),
    )));
    assert.deepEqual(
      snapshot.docs.map((document) => document.id),
      ["minimal"],
    );
  });

  test("비인증 사용자는 active 무드도 읽을 수 없다", async () => {
    const firestore = testEnvironment
      .unauthenticatedContext()
      .firestore();
    await assertFails(getDoc(doc(firestore, "styleMoods", "minimal")));
  });

  test("총 관리자는 inactive 무드도 읽을 수 있다", async () => {
    const firestore = testEnvironment
      .authenticatedContext("total-admin")
      .firestore();

    await assertSucceeds(getDoc(doc(firestore, "styleMoods", "legacy")));
    const snapshot = await assertSucceeds(getDocs(query(
      collection(firestore, "styleMoods"),
      orderBy("sortOrder", "asc"),
    )));
    assert.deepEqual(
      snapshot.docs.map((document) => document.id),
      ["minimal", "legacy"],
    );
  });

  test("인증 사용자와 총 관리자도 무드를 직접 쓸 수 없다", async () => {
    const userFirestore = testEnvironment
      .authenticatedContext(userUID)
      .firestore();
    const adminFirestore = testEnvironment
      .authenticatedContext("total-admin")
      .firestore();

    await assertFails(setDoc(
      doc(userFirestore, "styleMoods", "new-mood"),
      {displayName: "새 무드", status: "active", sortOrder: 1000},
    ));
    await assertFails(updateDoc(
      doc(adminFirestore, "styleMoods", "minimal"),
      {displayName: "변경"},
    ));
  });

  test("term index와 seed metadata는 클라이언트에서 접근할 수 없다", async () => {
    const firestore = testEnvironment
      .authenticatedContext(userUID)
      .firestore();

    await assertFails(getDoc(
      doc(firestore, "styleMoodTermIndex", "term-hash"),
    ));
    await assertFails(getDoc(
      doc(firestore, "styleMoodSeedMetadata", "current"),
    ));
    await assertFails(setDoc(
      doc(firestore, "styleMoodTermIndex", "new-term"),
      {moodID: "minimal"},
    ));
  });

  test("총 관리자와 브랜드 관리자도 시즌 문서를 직접 쓸 수 없다", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), "brands", "brand-1", "admins", "brand-admin"),
        {uid: "brand-admin", role: "owner"},
      );
    });
    const totalAdminFirestore = testEnvironment
      .authenticatedContext("total-admin")
      .firestore();
    const brandAdminFirestore = testEnvironment
      .authenticatedContext("brand-admin")
      .firestore();

    await assertFails(updateDoc(
      doc(totalAdminFirestore, "brands", "brand-1", "seasons", "season-1"),
      {moodIDs: ["minimal"]},
    ));
    await assertFails(setDoc(
      doc(brandAdminFirestore, "brands", "brand-1", "seasons", "season-2"),
      {displayTitle: "26 S/S", moodIDs: []},
    ));
  });

  test("discovery snapshot은 브랜드 관리자만 읽고 누구도 직접 쓰지 못한다", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), "brands", "brand-1", "admins", "brand-admin"),
        {uid: "brand-admin", role: "owner"},
      );
    });
    const admin = testEnvironment.authenticatedContext("brand-admin").firestore();
    const user = testEnvironment.authenticatedContext(userUID).firestore();
    const jobPath = ["brands", "brand-1", "seasonDiscoveryJobs", "job-1"];
    const candidatePath = [...jobPath, "candidates", "candidate-1"];

    await assertSucceeds(getDoc(doc(admin, ...jobPath)));
    await assertSucceeds(getDoc(doc(admin, ...candidatePath)));
    await assertFails(getDoc(doc(user, ...jobPath)));
    await assertFails(getDoc(doc(user, ...candidatePath)));
    await assertFails(updateDoc(doc(admin, ...jobPath), {status: "cancelled"}));
    await assertFails(setDoc(
      doc(admin, ...jobPath, "reviews", "review-1"),
      {decision: "keepAsNew"},
    ));
  });
});
