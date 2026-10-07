import assert from "node:assert/strict";
import {before, beforeEach, after, test} from "node:test";
import {createRequire} from "node:module";
import {readFile} from "node:fs/promises";
import {initializeApp, deleteApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {RemoteRunStore, REMOTE_CONTROL} from "../lib/performance/remote-store.js";
import {remotePlans, outputRoot} from "../lib/performance/remote-contract.js";
import {testCampaign} from "../lib/performance/remote-fixture.js";

assert.equal(process.env.FIRESTORE_EMULATOR_HOST, "127.0.0.1:8085");
assert.equal(process.env.FIREBASE_STORAGE_EMULATOR_HOST, "127.0.0.1:9195");
const projectId = "demo-lookbook-performance";
const app = initializeApp({projectId}, "remote-emulator");
const db = getFirestore(app);
const store = new RemoteRunStore(db);
const require = createRequire(new URL("../../../firestore-tests/package.json", import.meta.url));
const {initializeTestEnvironment, assertFails} = require("@firebase/rules-unit-testing");
let rules;
before(async () => {
  rules = await initializeTestEnvironment({projectId,
    firestore: {host: "127.0.0.1", port: 8085,
      rules: await readFile(new URL("../../../firestore.rules", import.meta.url), "utf8")},
    storage: {host: "127.0.0.1", port: 9195,
      rules: await readFile(new URL("../../../storage.rules", import.meta.url), "utf8")}});
});
beforeEach(async () => { await rules.clearFirestore(); });
after(async () => {
  await rules?.cleanup(); await db.terminate(); await deleteApp(app);
});
const evidence = (campaign, plan, continueAllowed = true) => ({status: "succeeded",
  evidencePath: `${outputRoot(campaign, plan)}result.json`, continueAllowed});

test("RD01 독립 요청 경합은 한 실행권만 허용하고 중복과 타 owner 종료를 거부한다", async () => {
  const campaign = testCampaign(); const plan = remotePlans()[0];
  const results = await Promise.allSettled([store.claim(campaign, plan, "one"),
    store.claim(campaign, plan, "two")]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  const owner = (await db.doc(REMOTE_CONTROL).get()).data().owner;
  await assert.rejects(() => store.claim(campaign, plan, "again"));
  await assert.rejects(() => store.finish(campaign, plan, "wrong", evidence(campaign, plan)));
  await store.finish(campaign, plan, owner, evidence(campaign, plan));
  await assert.rejects(() => store.claim(campaign, plan, "again"));
  await store.claim(campaign, remotePlans()[1], "next");
});

test("RD02 종료 미확인과 중단 회차는 시간 경과에도 자동 인계하지 않는다", async () => {
  const campaign = testCampaign(); const plan = remotePlans()[0];
  await store.claim(campaign, plan, "lost");
  await assert.rejects(() => store.claim(campaign, remotePlans()[1], "next", Date.now() + 600000));
  await store.finish(campaign, plan, "lost", evidence(campaign, plan, false));
  await assert.rejects(() => store.claim(campaign, remotePlans()[1], "next"));
  const another = {...campaign, campaignID: "another-test-campaign"};
  await assert.rejects(() => store.claim(another, plan, "another"));
});

test("RD03 고정 순서 입력 변경과 만료 캠페인은 접수하지 않는다", async () => {
  const campaign = testCampaign(); const [first, second] = remotePlans();
  await assert.rejects(() => store.claim(campaign, second, "wrong-order"));
  await assert.rejects(() => store.claim({...campaign, expiresAtMs: 1}, first, "expired"));
  await store.claim(campaign, first, "one");
  await store.finish(campaign, first, "one", evidence(campaign, first));
  await assert.rejects(() => store.claim({...campaign, runTimeoutMs: 2000}, second, "changed"));
});

test("RD04 실험 문서와 객체는 인증 클라이언트도 직접 접근할 수 없다", async () => {
  const client = rules.authenticatedContext("not-an-experiment-server");
  for (const path of [REMOTE_CONTROL, "lookbookImportPerformanceRuns/test",
    "lookbookImportPerformanceCampaigns/test"]) {
    await assertFails(client.firestore().doc(path).get());
    await assertFails(client.firestore().doc(path).set({status: "running"}));
  }
  const file = client.storage().ref("lookbook-import-performance/test/secret.jpg");
  await assertFails(file.putString("test"));
  await assertFails(file.getDownloadURL());
});

test("RD05 8회 계약은 고정 순서를 지키며 추가 회차와 변경된 종료 계약을 거부한다", async () => {
  const campaign = testCampaign();
  const plans = remotePlans();
  assert.equal(plans.length, 8);
  assert.deepEqual(plans.map((p) => p.variant),
    ["smoke", "S6", "Sall", "P6", "Pall", "D8", "T2", "U8"]);
  await assert.rejects(() => store.claim({...campaign, version: 4},
    plans[0], "old-reverse"));
  await assert.rejects(() => store.claim(campaign, plans[1], "skip-smoke"));
  for (const [index, plan] of plans.entries()) {
    if (index === 1) {
      await assert.rejects(() => store.claim(campaign, plans[2], "skip-SP"));
    }
    await store.claim(campaign, plan, "owner");
    await assert.rejects(() => store.finish({...campaign, runTimeoutMs: 1000},
      plan, "owner", evidence(campaign, plan)));
    await store.finish(campaign, plan, "owner", evidence(campaign, plan));
    const state = (await db.doc(
      `lookbookImportPerformanceCampaigns/${campaign.campaignID}`).get()).data();
    assert.equal(state.next, index + 1);
  }
  await assert.rejects(() => store.claim(campaign, plans[0], "replay"));
  await assert.rejects(() => store.claim(campaign,
    {...plans[1], id: "PP-synthetic-three-2", repeat: 2}, "extra"));
  await assert.rejects(() => store.claim({...campaign, version: 2},
    plans[0], "old-contract"));
  await assert.rejects(() => store.claim({...campaign, version: 3},
    plans[0], "old-screening"));
});
