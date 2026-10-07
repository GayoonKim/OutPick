import assert from "node:assert/strict";
import {before, beforeEach, after, test} from "node:test";
import {createRequire} from "node:module";
import {randomUUID} from "node:crypto";
import {readFile} from "node:fs/promises";

assert.equal(process.env.FIRESTORE_EMULATOR_HOST, "127.0.0.1:8086");
assert.equal(process.env.GCLOUD_PROJECT, "demo-lookbook-queue");
const require = createRequire(new URL("../functions/package.json", import.meta.url));
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const app = initializeApp({projectId: "demo-lookbook-queue"});
const secondApp = initializeApp({projectId: "demo-lookbook-queue"}, "independent");
const db = getFirestore(app);
const otherDB = getFirestore(secondApp);
const rulesRequire = createRequire(new URL("./package.json", import.meta.url));
const {initializeTestEnvironment, assertFails} = rulesRequire("@firebase/rules-unit-testing");
let rules;
before(async () => {
  rules = await initializeTestEnvironment({projectId: "demo-lookbook-queue",
    firestore: {host: "127.0.0.1", port: 8086,
      rules: await readFile(new URL("../firestore.rules", import.meta.url), "utf8")}});
});
const {admitQueueRequest, getQueueReceipt, getQueueReceiptByBatchID} =
  require("../functions/lib/lookbook/import/queue/admission.js");
const {queueAuthorization} = require("../functions/lib/lookbook/import/queue/authorization.js");
const {seasonImportFailureID, admitSeasonImportFailureRetry,
  dismissSeasonImportFailure, listSeasonImportFailures} =
  require("../functions/lib/lookbook/import/queue/failure-service.js");
const {beginQueuePreparation, prepareQueueItem, finishQueuePreparation} =
  require("../functions/lib/lookbook/import/queue/preparation.js");
const {deliverQueueHead, reopenStaleQueueDispatch} = require("../functions/lib/lookbook/import/queue/dispatch.js");
const {advanceReleasedQueueHead} = require("../functions/lib/lookbook/import/queue/advance.js");
const {cleanupLookbookQueueRecords} = require("../functions/lib/lookbook/import/queue/record-retention.js");
const {cleanupLookbookAssetWrites} = require("../functions/lib/lookbook/import/queue/asset-retention.js");
const {getSeasonImportBatch} = require("../functions/lib/lookbook/import/queue/functions.js");
const {createBrand} = require("../functions/lib/brand/admin/functions.js");
const {assertNoActiveLookbookAssetWrites} = require("../functions/lib/lookbook/deletion/assetWriteFence.js");
const {onSeasonImportQueued, requestSeasonImport, requestSeasonAssetRetry,
  requestSeasonCandidateImportJobs, reviewLookbookExtraction, retryLookbookExtractionAfterFix,
  requestLookbookSeasonRepair, applyLookbookSeasonRepair, discoverSeasonCandidates} = require("../functions/lib/lookbook/import/functions.js");
const {onSeasonDiscoveryQueued, reconcileSeasonDiscoveryJobs} =
  require("../functions/lib/lookbook/import/seasonDiscoveryJobs.js");
const {requestSeasonDiscovery, retrySeasonDiscovery, retrySeasonDiscoveryAfterExtractionFix} =
  require("../functions/lib/lookbook/import/seasonDiscoveryJobs.js");
const {prepareNextQueueBatch} = require("../functions/lib/lookbook/import/queue/preparation-runner.js");
const {onLookbookBatchPreparationRequested, onLookbookPreparationSequenceChanged} =
  require("../functions/lib/lookbook/import/queue/preparation-functions.js");
const {claimBatch, readOwnedBatch, heartbeatBatch, beginBatchDrain,
  finishBatchRun, advanceReleasedHead, writeBatchProgress} = await import("../tools/lookbook-import-worker/lib/queue/coordinator.js");
const {inspectQueueRecovery, resumeQueueRecovery, settleCorrectionQueueRecovery} =
  await import("../tools/lookbook-import-worker/lib/queue/recovery.js");
const {beginBatchItemAttempt, finishBatchItemAttempt} =
  await import("../tools/lookbook-import-worker/lib/queue/checkpoint.js");
const {activateQueueItem} =
  await import("../tools/lookbook-import-worker/lib/queue/activation.js");
const {prepareSeasonRestart} =
  await import("../tools/lookbook-import-worker/lib/queue/restart.js");
const {settleTerminatedSeasonRun} =
  await import("../tools/lookbook-import-worker/lib/queue/termination-retry.js");
const {updateOwnedJob} =
  await import("../tools/lookbook-import-worker/lib/queue/job-write.js");
const {createDevelopmentRetryFault} =
  await import("../tools/lookbook-import-worker/lib/queue/development-retry-fault.js");
const {assetWritePaths} =
  await import("../tools/lookbook-import-worker/lib/queue/asset-paths.js");
const {beginAssetWrite, finishAssetWrite, publishAssetWrite} =
  await import("../tools/lookbook-import-worker/lib/queue/asset-publication.js");
const {createQueuePipelineRuntime} =
  await import("../tools/lookbook-import-worker/lib/queue/runtime.js");
const {runSyncTargets} =
  await import("../tools/lookbook-import-worker/lib/processor.js");
const sharp = createRequire(new URL("../tools/lookbook-import-worker/package.json",
  import.meta.url))("sharp");
const {processImportSeasonsBatch} =
  await import("../tools/lookbook-import-worker/lib/queue/batch-runner.js");
const {QueueSupervisor} =
  await import("../tools/lookbook-import-worker/lib/queue/supervisor.js");
const {browserImageGate} =
  await import("../tools/lookbook-import-worker/lib/queue/browser-gate.js");
const {RetryableImportError} =
  await import("../tools/lookbook-import-worker/lib/import-error.js");
const now = 1791158400000;
const uid = "queue-owner";
const request = (extra = {}) => ({queueContractVersion: 1, requestID: randomUUID(),
  requestCreatedAt: now, brandID: "brand-a", kind: "importSeasons",
  payload: {candidateIDs: ["one"], snapshot: "frozen-v1"}, ...extra});
const target = (key, extra = {}) => ({targetID: key, claimKey: `https://brand.example/${key}`,
  collection: "importJobs", jobData: {jobType: "importSeasonFromURL",
    sourceURL: `https://brand.example/${key}`}, ...extra});
const hooks = (database, targets) => ({authorize: queueAuthorization(database),
  freezeTargets: async () => targets});
const batchRef = (id) => db.doc(`lookbookImportBatches/${id}`);
async function prepared(input, targets) {
  const receipt = await admitQueueRequest(db, uid, input, hooks(db, targets), now);
  const owner = randomUUID();
  assert.equal(await beginQueuePreparation(db, receipt.batchID, owner, now), true);
  for (let i = 0; i < targets.length; i++) {
    await prepareQueueItem(db, receipt.batchID, i, owner, now);
  }
  return finishQueuePreparation(db, receipt.batchID, owner, now);
}

beforeEach(async () => {
  const response = await fetch("http://127.0.0.1:8086/emulator/v1/projects/" +
    "demo-lookbook-queue/databases/(default)/documents", {method: "DELETE"});
  assert.equal(response.ok, true);
  await db.doc("brands/brand-a").set({deletionStatus: "active"});
  await db.doc(`brands/brand-a/admins/${uid}`).set({role: "owner"});
  await db.doc(`platformAdmins/${uid}`).set({isActive: true});
});
after(async () => {
  await rules?.cleanup();
  await db.terminate(); await otherDB.terminate();
  await deleteApp(secondApp); await deleteApp(app);
});

test("PQ01 독립 클라이언트의 동일 요청은 한 영수증과 한 순번만 만든다", async () => {
  const input = request();
  const receipts = await Promise.all(Array.from({length: 6}, (_, i) => {
    const database = i % 2 ? db : otherDB;
    return admitQueueRequest(database, uid, input, hooks(database, [target("one")]), now);
  }));
  assert.equal(new Set(receipts.map((r) => r.batchID)).size, 1);
  assert.equal((await db.collection("lookbookImportBatches").get()).size, 1);
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().nextSequence, 2);
});

test("PQ01 영수증 조회는 snapshot 만료보다 먼저지만 권한과 payload는 재검사한다", async () => {
  const input = request();
  const first = await admitQueueRequest(db, uid, input, hooks(db, [target("one")]), now);
  const expiredHooks = {...hooks(db, []), freezeTargets: async () => {
    throw new Error("SNAPSHOT_STALE");
  }};
  const again = await admitQueueRequest(db, uid, input, expiredHooks, now + 31 * 86400000);
  assert.deepEqual(again, first);
  await assert.rejects(() => admitQueueRequest(db, uid, {...input,
    payload: {...input.payload, candidateIDs: ["other"]}}, expiredHooks, now),
  /REQUEST_ID_CONFLICT/);
  await assert.rejects(() => admitQueueRequest(db, uid, {...input,
    requestID: randomUUID()}, expiredHooks, now + 86400001), /REQUEST_EXPIRED/);
  await db.doc(`platformAdmins/${uid}`).update({isActive: false});
  await assert.rejects(() => admitQueueRequest(db, uid, input, expiredHooks, now),
    /PERMISSION_DENIED/);
  await assert.rejects(() => getQueueReceipt(db, uid, input.requestID,
    queueAuthorization(db)), /PERMISSION_DENIED/);
});

test("PQ02 준비 전 뒤 요청의 선점을 막고 동일 시즌을 중복 생성하지 않는다", async () => {
  const a = await admitQueueRequest(db, uid, request(), hooks(db, [target("one")]), now);
  const b = await admitQueueRequest(otherDB, uid, request(),
    hooks(otherDB, [target("one")]), now);
  assert.equal(await beginQueuePreparation(db, b.batchID, "b", now), false);
  assert.equal(await beginQueuePreparation(db, a.batchID, "a", now), true);
  await assert.rejects(() => beginQueuePreparation(otherDB, a.batchID, "other", now),
    /PREPARATION_BUSY/);
  const results = await Promise.all([prepareQueueItem(db, a.batchID, 0, "a", now),
    prepareQueueItem(otherDB, a.batchID, 0, "a", now)]);
  assert.equal(results[0].jobID, results[1].jobID);
  await finishQueuePreparation(db, a.batchID, "a", now);
  assert.equal(await beginQueuePreparation(db, b.batchID, "b", now), true);
  const duplicate = await prepareQueueItem(db, b.batchID, 0, "b", now);
  assert.equal(duplicate.admissionStatus, "duplicate");
  assert.equal(duplicate.jobID, results[0].jobID);
  const receipt = await finishQueuePreparation(db, b.batchID, "b", now);
  assert.equal(receipt.receiptState, "released");
  assert.equal(receipt.duplicateCount, 1);
  assert.equal((await db.collection("brands/brand-a/importJobs").get()).size, 1);
});

test("PQ02 팔십 항목의 부분 실패와 준비 재실행은 집계와 성공 job을 보존한다", async () => {
  const targets = Array.from({length: 80}, (_, i) => target(`item-${i}`,
    i >= 77 ? {errorCode: "SNAPSHOT_STALE"} : {}));
  const receipt = await admitQueueRequest(db, uid, request(), hooks(db, targets), now);
  await beginQueuePreparation(db, receipt.batchID, "first", now);
  const firstItem = await prepareQueueItem(db, receipt.batchID, 0, "first", now);
  const partial = await finishQueuePreparation(db, receipt.batchID, "first", now);
  assert.equal(partial.pendingCount, 76);
  assert.equal(partial.failedCount, 3);
  await beginQueuePreparation(db, receipt.batchID, "second", now);
  for (let i = 0; i < 80; i++) await prepareQueueItem(db, receipt.batchID, i, "second", now);
  const result = await finishQueuePreparation(db, receipt.batchID, "second", now);
  assert.equal(result.items[0].jobID, firstItem.jobID);
  assert.deepEqual([result.pendingCount, result.createdCount, result.failedCount], [0, 77, 3]);
  assert.equal(result.receiptState, "queued");
  assert.equal((await db.collection("brands/brand-a/importJobs").get()).size, 77);
});

test("PQ02 준비 총 다섯 회 소진은 미확정 항목만 실패로 남기고 이전 owner를 차단한다", async () => {
  const receipt = await admitQueueRequest(db, uid, request(),
    hooks(db, [target("one"), target("two")]), now);
  for (let attempt = 1; attempt <= 5; attempt++) {
    const owner = `owner-${attempt}`;
    await beginQueuePreparation(db, receipt.batchID, owner, now);
    if (attempt === 1) await prepareQueueItem(db, receipt.batchID, 0, owner, now);
    await finishQueuePreparation(db, receipt.batchID, owner, now);
    await assert.rejects(() => prepareQueueItem(db, receipt.batchID, 1, owner, now),
      /PREPARATION_OWNER/);
  }
  const batch = (await batchRef(receipt.batchID).get()).data();
  assert.equal(batch.preparationAttempts, 5);
  assert.equal(batch.state, "queued");
  assert.equal(batch.items[1].errorCode, "PREPARATION_EXHAUSTED");
  assert.equal((await db.doc(`brands/brand-a/importJobs/${batch.items[0].jobID}`).get())
    .data().attemptCount, 0);
});

test("PQ03 전달 실패는 intent를 보존하고 동일 task ID로 다시 전달한다", async () => {
  const receipt = await prepared(request(), [target("one")]);
  const sent = [];
  await assert.rejects(() => deliverQueueHead(db, async (intent) => {
    sent.push(intent); throw new Error("response-lost");
  }, now), /response-lost/);
  assert.equal((await batchRef(receipt.batchID).get()).data().dispatchState, "pending");
  await deliverQueueHead(db, async (intent) => { sent.push(intent); }, now);
  assert.deepEqual(sent[0], sent[1]);
  assert.equal(sent[1].dispatchDeadlineSeconds, 900);
  assert.equal(sent[1].payload.queueContractVersion, 1);
  assert.equal(sent[1].payload.contractVersion, undefined);
  assert.equal((await batchRef(receipt.batchID).get()).data().dispatchState, "delivered");
  assert.equal(await deliverQueueHead(db, async () => { assert.fail("중복 송신"); }), false);
});

test("PQ13 15분 동안 claim되지 않은 head는 같은 generation task로만 다시 전달한다", async () => {
  const receipt = await prepared(request(), [target("one")]);
  const first = [];
  await deliverQueueHead(db, async (intent) => { first.push(intent); }, now);
  assert.equal((await batchRef(receipt.batchID).get()).data().dispatchState,
    "delivered");
  assert.equal(await reopenStaleQueueDispatch(db, now + 899_999), false);
  assert.equal(await reopenStaleQueueDispatch(db, now + 900_000), true);
  const reopened = (await batchRef(receipt.batchID).get()).data();
  assert.equal(reopened.dispatchGeneration, first[0].payload.dispatchGeneration);
  assert.equal(reopened.dispatchState, "pending");
  const second = [];
  await deliverQueueHead(db, async (intent) => { second.push(intent); }, now + 900_000);
  assert.deepEqual(second, first);
  await db.doc("lookbookImportQueue/main").update({state: "active", owner: "owner"});
  assert.equal(await reopenStaleQueueDispatch(db, now + 1_800_000), false);
});

test("PQ13 준비에서 전부 종료된 released head는 다음 queued 요청으로 전진한다", async () => {
  const first = await prepared(request(), [target("first")]);
  const second = await prepared(request(), [target("second")]);
  await batchRef(first.batchID).update({state: "released", owner: null,
    preparationOwner: null});
  await batchRef(second.batchID).update({state: "queued", dispatchState: "pending"});
  await db.doc("lookbookImportQueue/main").update({
    state: "idle", owner: null, headBatchID: first.batchID,
    nextSequence: 3,
  });
  assert.equal(await advanceReleasedQueueHead(db), second.batchID);
  const sent = [];
  await deliverQueueHead(db, async (intent) => {
    sent.push(intent.payload.batchID);
  }, now);
  assert.deepEqual(sent, [second.batchID]);
});

test("PQ12 상세 정리는 성공 영수증을 유지하고 30일 뒤 참조가 끝난 receipt만 지운다", async () => {
  const receipt = await prepared(request(), [target("retention-success")]);
  const batch = batchRef(receipt.batchID);
  const item = receipt.items[0];
  const execution = db.doc(`brands/brand-a/importJobs/${item.jobID}`)
    .collection("executions").doc(item.executionID);
  await execution.update({status: "succeeded", activeRunID: null});
  const releaseTime = now - 29 * 24 * 60 * 60 * 1000;
  await batch.update({state: "released", releasedAt: releaseTime,
    detailCleanupAfter: releaseTime + 24 * 60 * 60 * 1000,
    receiptExpiresAt: releaseTime + 30 * 24 * 60 * 60 * 1000,
    retentionNextAt: releaseTime + 24 * 60 * 60 * 1000});
  await db.doc("lookbookImportQueue/main").update({headBatchID: null, state: "idle"});

  const atDetailExpiry = now;
  const details = await cleanupLookbookQueueRecords({firestore: db,
    now: () => atDetailExpiry});
  assert.ok(details.changed > 0);
  assert.equal((await batch.get()).data().detailsPruned, true);
  assert.equal((await batch.collection("inputs").get()).size, 0);
  assert.ok((await batch.get()).exists);

  const atReceiptExpiry = releaseTime + 31 * 24 * 60 * 60 * 1000;
  const receipts = await cleanupLookbookQueueRecords({firestore: db,
    now: () => atReceiptExpiry});
  assert.ok(receipts.changed > 0);
  assert.equal((await batch.get()).exists, false);
});

test("PQ12 검토 대기 execution은 만료 기간이 지나도 batch receipt와 상세를 보호한다", async () => {
  const receipt = await prepared(request(), [target("retention-review")]);
  const batch = batchRef(receipt.batchID);
  const item = receipt.items[0];
  const execution = db.doc(`brands/brand-a/importJobs/${item.jobID}`)
    .collection("executions").doc(item.executionID);
  await execution.update({status: "awaitingReview"});
  const releaseTime = now - 40 * 24 * 60 * 60 * 1000;
  await batch.update({state: "released", releasedAt: releaseTime,
    detailCleanupAfter: releaseTime + 24 * 60 * 60 * 1000,
    receiptExpiresAt: releaseTime + 30 * 24 * 60 * 60 * 1000,
    retentionNextAt: releaseTime + 24 * 60 * 60 * 1000});
  await db.doc("lookbookImportQueue/main").update({headBatchID: null, state: "idle"});
  await cleanupLookbookQueueRecords({firestore: db, now: () => now});
  assert.equal((await batch.get()).exists, true);
  assert.equal((await batch.collection("inputs").get()).size, 1);
  assert.equal((await batch.get()).data().retentionNextAt,
    now + 24 * 60 * 60 * 1000);
});

test("PQ12 브랜드 영수증과 복구 감사는 진행 중 기록을 보호하고 500건 상한을 지킨다", async () => {
  const protectedBatchID = "f".repeat(64);
  const terminalBatchID = "e".repeat(64);
  const protectedBatch = batchRef(protectedBatchID);
  const terminalBatch = batchRef(terminalBatchID);
  await protectedBatch.set({state: "recoveryRequired", items: []});
  await terminalBatch.set({state: "released", items: []});
  await db.doc("lookbookImportQueue/main").set({headBatchID: protectedBatchID,
    state: "recoveryRequired"});
  const expiry = now - 1;
  const protectedReceipt = db.doc("brandCreationRequests/protected-receipt");
  const expiredReceipt = db.doc("brandCreationRequests/expired-receipt");
  await protectedReceipt.set({result: {batchID: protectedBatchID},
    receiptExpiresAt: expiry, retentionNextAt: expiry});
  await expiredReceipt.set({result: {batchID: null},
    receiptExpiresAt: expiry, retentionNextAt: expiry});
  const protectedAudit = protectedBatch.collection("recoveryDecisions")
    .doc("protected-decision");
  const expiredAudit = terminalBatch.collection("recoveryDecisions")
    .doc("expired-decision");
  await protectedAudit.set({expiresAt: expiry});
  await expiredAudit.set({expiresAt: expiry});

  const counts = await cleanupLookbookQueueRecords({firestore: db,
    now: () => now});
  assert.ok(counts.protected >= 2);
  assert.equal((await protectedReceipt.get()).exists, true);
  assert.equal((await protectedReceipt.get()).data().retentionNextAt,
    now + 24 * 60 * 60 * 1000);
  assert.equal((await expiredReceipt.get()).exists, false);
  assert.equal((await protectedAudit.get()).exists, true);
  assert.equal((await protectedAudit.get()).data().expiresAt,
    now + 24 * 60 * 60 * 1000);
  assert.equal((await expiredAudit.get()).exists, false);

  const bulkNow = now + 10;
  const writes = [];
  for (let index = 0; index < 350; index++) {
    writes.push({ref: db.collection("lookbookImportBatches").doc(
      `bulk-batch-${String(index).padStart(3, "0")}`),
    data: {state: "queued", items: [], retentionNextAt: bulkNow - 1}});
  }
  for (let index = 0; index < 100; index++) {
    writes.push({ref: db.collection("brandCreationRequests").doc(
      `bulk-brand-${String(index).padStart(3, "0")}`),
    data: {result: {batchID: null}, receiptExpiresAt: bulkNow - 1,
      retentionNextAt: bulkNow - 1}});
    const parent = db.collection("lookbookImportBatches").doc(
      `bulk-audit-${String(index).padStart(3, "0")}`);
    writes.push({ref: parent, data: {state: "released"}});
    writes.push({ref: parent.collection("recoveryDecisions").doc("decision"),
      data: {expiresAt: bulkNow - 1}});
  }
  for (let offset = 0; offset < writes.length; offset += 400) {
    const writeBatch = db.batch();
    writes.slice(offset, offset + 400).forEach(({ref, data}) =>
      writeBatch.set(ref, data));
    await writeBatch.commit();
  }
  const bounded = await cleanupLookbookQueueRecords({firestore: db,
    now: () => bulkNow});
  assert.equal(bounded.changed, 500);
  assert.equal((await db.collection("lookbookImportBatches")
    .where("retentionNextAt", "<=", bulkNow).get()).size, 50);
  assert.equal((await db.collection("brandCreationRequests")
    .where("retentionNextAt", "<=", bulkNow).get()).size, 0);
  assert.equal((await db.collectionGroup("recoveryDecisions")
    .where("expiresAt", "<=", bulkNow).get()).size, 0);
});

test("PQ12 file cleanup은 현재 참조를 보호하고 exact generation만 지운다", async () => {
  const thumbPath = "brands/brand-a/seasons/season-a/imports/e1/1/cover/w1/thumb.jpg";
  const detailPath = "brands/brand-a/seasons/season-a/imports/e1/1/cover/w1/detail.jpg";
  const targetPath = "brands/brand-a/seasons/season-a";
  await db.doc(targetPath).set({coverPath: detailPath});
  const ledgerRef = db.doc("brands/brand-a/importJobs/job/executions/execution/" +
    "assets/asset/writes/write");
  await ledgerRef.set({status: "replaced", cleanupState: "pending",
    cleanupAfter: now - 86_400_000, brandID: "brand-a", targetPath,
    thumbPath, detailPath,
    objects: {thumb: {generation: "101", size: 12},
      detail: {generation: "102", size: 20}}});
  const deleted = [];
  const bucket = {file: (path, options) => ({delete: async () => {
    deleted.push({path, options});
  }})};
  const first = await cleanupLookbookAssetWrites({firestore: db, bucket, now: () => now});
  assert.equal(first.protected, 1);
  assert.deepEqual(deleted, []);

  await db.doc(targetPath).update({coverPath: "brands/brand-a/other.jpg"});
  const nextNow = now + 3_600_001;
  const second = await cleanupLookbookAssetWrites({firestore: db, bucket,
    now: () => nextNow});
  assert.equal(second.deleted, 2);
  assert.equal(second.objectOperations, 2);
  assert.deepEqual(deleted.map((item) => item.options.preconditionOpts.ifGenerationMatch),
    ["101", "102"]);
  assert.equal((await ledgerRef.get()).data().cleanupState, "completed");
});

test("PQ05 목록 탐색도 같은 순번에 준비되며 head만 전달한다", async () => {
  const a = await prepared(request(), [target("one")]);
  const b = await prepared(request({kind: "discoverSeasons"}),
    [target("archive", {collection: "seasonDiscoveryJobs"})]);
  const aBatch = (await batchRef(a.batchID).get()).data();
  const bBatch = (await batchRef(b.batchID).get()).data();
  assert.equal(bBatch.sequence, aBatch.sequence + 1);
  const sent = [];
  await deliverQueueHead(db, async (intent) => { sent.push(intent.payload.batchID); }, now);
  assert.deepEqual(sent, [a.batchID]);
  await db.doc("lookbookImportQueue/main").update({state: "recoveryRequired"});
  assert.equal(await deliverQueueHead(db, async () => { assert.fail("차단 무시"); }), false);
  const job = (await db.doc(`brands/brand-a/seasonDiscoveryJobs/${b.items[0].jobID}`).get()).data();
  assert.equal(job.attemptCount, 0);
});

test("PQ01 영수증은 내부 입력과 다른 사용자를 노출하지 않는다", async () => {
  const input = request();
  const receipt = await admitQueueRequest(db, uid, input,
    hooks(db, [target("one", {jobData: {sourceURL: "https://private.example"}})]), now);
  const read = await getQueueReceipt(db, uid, input.requestID, queueAuthorization(db));
  assert.deepEqual(read, receipt);
  assert.equal("sequence" in read, false);
  assert.equal("payloadDigest" in read, false);
  assert.equal(JSON.stringify(read).includes("private.example"), false);
  await assert.rejects(() => getQueueReceiptByBatchID(db, "another-user", receipt.batchID,
    queueAuthorization(db)), /PERMISSION_DENIED/);
});

test("PQ03 기존 trigger와 discovery 감시는 큐 소유 job을 전달하거나 재시도하지 않는다", async () => {
  const receipt = await prepared(request({kind: "discoverSeasons"}),
    [target("archive", {collection: "seasonDiscoveryJobs"})]);
  const ref = db.doc(`brands/brand-a/seasonDiscoveryJobs/${receipt.items[0].jobID}`);
  const snap = await ref.get();
  const event = {params: {brandID: "brand-a", jobID: ref.id},
    data: {after: snap, before: {data: () => undefined}}};
  await onSeasonDiscoveryQueued.run(event);
  await onSeasonImportQueued.run(event);
  await reconcileSeasonDiscoveryJobs.run({});
  assert.deepEqual((await ref.get()).data(), snap.data());
});

test("PQ03 늦은 전달 응답은 변경된 head나 전달 세대를 확정하지 않는다", async () => {
  const receipt = await prepared(request(), [target("one")]);
  await deliverQueueHead(db, async () => {
    await batchRef(receipt.batchID).update({dispatchGeneration: 1});
    await db.doc("lookbookImportQueue/main").update({headBatchID: "new-head"});
  }, now);
  const batch = (await batchRef(receipt.batchID).get()).data();
  assert.equal(batch.dispatchState, "pending");
  assert.equal(batch.dispatchGeneration, 1);
});

test("PQ01 신규 입력 경계와 snapshot 실패는 순번이나 일부 입력을 남기지 않는다", async () => {
  const invalidTargets = [[], Array.from({length: 81}, (_, i) => target(`c-${i}`)),
    [target("one"), target("one")]];
  for (const targets of invalidTargets) {
    await assert.rejects(() => admitQueueRequest(db, uid, request(), hooks(db, targets), now),
      /INVALID_CONTRACT/);
  }
  await assert.rejects(() => admitQueueRequest(db, uid, request(), {
    ...hooks(db, []), freezeTargets: async (transaction) => {
      await transaction.get(db.doc("brands/brand-a"));
      throw new Error("SNAPSHOT_STALE");
    },
  }, now), /SNAPSHOT_STALE/);
  assert.equal((await db.collection("lookbookImportBatches").get()).size, 0);
  assert.equal((await db.doc("lookbookImportQueue/main").get()).exists, false);
});

test("PQ10 브랜드 관리자도 큐 입력 실행권 선점 원본을 직접 읽거나 쓸 수 없다", async () => {
  const receipt = await prepared(request(), [target("one")]);
  const client = rules.authenticatedContext(uid).firestore();
  for (const path of ["lookbookImportQueue/main",
    `lookbookImportBatches/${receipt.batchID}`,
    `lookbookImportBatches/${receipt.batchID}/inputs/0`,
    "brands/brand-a/queueSourceClaims/test",
    `brands/brand-a/importJobs/${receipt.items[0].jobID}/executions/${receipt.items[0].executionID}`]) {
    await assertFails(client.doc(path).get());
    await assertFails(client.doc(path).set({state: "released"}));
  }
});

test("PQ01 조회 callable은 자기 영수증만 반환하고 입력과 인증을 검사한다", async () => {
  const input = request();
  const receipt = await admitQueueRequest(db, uid, input, hooks(db, [target("one")]), now);
  assert.deepEqual(await getSeasonImportBatch.run({auth: {uid},
    data: {requestID: input.requestID}}), receipt);
  assert.deepEqual(await getSeasonImportBatch.run({auth: {uid},
    data: {batchID: receipt.batchID}}), receipt);
  await assert.rejects(() => getSeasonImportBatch.run({data: {requestID: input.requestID}}),
    (error) => error.code === "unauthenticated");
  await assert.rejects(() => getSeasonImportBatch.run({auth: {uid},
    data: {requestID: input.requestID, batchID: receipt.batchID}}),
    (error) => error.code === "invalid-argument");
  await assert.rejects(() => getSeasonImportBatch.run({auth: {uid: "other"},
    data: {batchID: receipt.batchID}}), (error) => error.code === "permission-denied");
});

test("PQ02 접수 후 권한 회수는 기존 준비를 막지 않지만 삭제 브랜드는 차단한다", async () => {
  const receipt = await admitQueueRequest(db, uid, request(), hooks(db, [target("one")]), now);
  await beginQueuePreparation(db, receipt.batchID, "owner", now);
  await db.doc(`platformAdmins/${uid}`).update({isActive: false});
  const preparedItem = await prepareQueueItem(db, receipt.batchID, 0, "owner", now);
  assert.equal(preparedItem.admissionStatus, "created");
  assert.equal((await db.collection("brands/brand-a/importJobs").get()).size, 1);
  await finishQueuePreparation(db, receipt.batchID, "owner", now);

  await db.doc(`platformAdmins/${uid}`).update({isActive: true});
  const deletedBrandReceipt = await admitQueueRequest(db, uid, request(),
    hooks(db, [target("two")]), now);
  await beginQueuePreparation(db, deletedBrandReceipt.batchID, "deleted-owner", now);
  await db.doc("brands/brand-a").update({deletionStatus: "deleting"});
  await assert.rejects(() => prepareQueueItem(db, deletedBrandReceipt.batchID, 0,
    "deleted-owner", now),
    /TARGET_DELETED/);
  assert.equal((await db.collection("brands/brand-a/importJobs").get()).size, 1);
});

test("PQ02 기존 job 참조는 이력과 실행권을 보존하고 새 실행을 만들지 않는다", async () => {
  const ref = db.doc("brands/brand-a/importJobs/legacy");
  const original = {jobType: "importSeasonFromURL", status: "partialFailed",
    sourceURL: "https://brand.example/one", attemptCount: 4,
    createdPostIDs: ["post-one"], targetSeasonID: "season-one"};
  await ref.set(original);
  const receipt = await prepared(request(), [target("one", {existingJobID: "legacy"})]);
  assert.equal(receipt.items[0].admissionStatus, "duplicate");
  assert.equal(receipt.items[0].jobID, "legacy");
  assert.equal(receipt.items[0].executionID, null);
  assert.deepEqual((await ref.get()).data(), original);
  assert.equal((await ref.collection("executions").get()).size, 0);
  assert.equal((await db.collection("brands/brand-a/importJobs").get()).size, 1);
  assert.equal((await db.collection("brands/brand-a/queueSourceClaims").get()).size, 0);
  assert.equal((await batchRef(receipt.batchID).get()).data().dispatchState, "none");
});

test("PQ02 삭제된 중복 대상은 새 job으로 대체하지 않고 준비 재실행도 중복을 보존한다", async () => {
  const ref = db.doc("brands/brand-a/importJobs/existing");
  await ref.set({status: "processing", queueExecutionID: "execution-old"});
  const receipt = await admitQueueRequest(db, uid, request(),
    hooks(db, [target("one", {existingJobID: "existing"})]), now);
  await beginQueuePreparation(db, receipt.batchID, "owner", now);
  await ref.delete();
  await assert.rejects(() => prepareQueueItem(db, receipt.batchID, 0, "owner", now),
    /QUEUE_REFERENCE_NOT_FOUND/);
  assert.equal((await db.collection("brands/brand-a/importJobs").get()).size, 0);
  await ref.set({status: "processing", queueExecutionID: "execution-old"});
  const first = await prepareQueueItem(db, receipt.batchID, 0, "owner", now);
  const second = await prepareQueueItem(db, receipt.batchID, 0, "owner", now);
  assert.deepEqual(second, first);
  assert.equal(first.executionID, "execution-old");
  assert.equal((await ref.collection("executions").get()).size, 0);
});

test("PQ02 잘못된 기존 job 참조는 접수 순번을 소비하지 않는다", async () => {
  for (const existingJobID of ["", "../other", 123, null]) {
    await assert.rejects(() => admitQueueRequest(db, uid, request(),
      hooks(db, [target("one", {existingJobID})]), now), /INVALID_CONTRACT/);
  }
  assert.equal((await db.doc("lookbookImportQueue/main").get()).exists, false);
});

test("PQ02 아직 연결하지 않은 승인 재시도는 일반 새 job으로 잘못 생성하지 않는다", async () => {
  const receipt = await admitQueueRequest(db, uid, request({kind: "reviewApproval"}),
    hooks(db, [target("one")]), now);
  await beginQueuePreparation(db, receipt.batchID, "owner", now);
  await assert.rejects(() => prepareQueueItem(db, receipt.batchID, 0, "owner", now),
    /PREPARATION_KIND_NOT_CONNECTED/);
  assert.equal((await db.collection("brands/brand-a/importJobs").get()).size, 0);
});

const call = (handler, data) => handler.run({auth: {uid}, data});
const apiRequest = (extra = {}) => ({queueContractVersion: 1,
  requestID: randomUUID(), requestCreatedAt: Date.now(), brandID: "brand-a", ...extra});
async function prepareReceipt(receipt) {
  const owner = randomUUID();
  assert.equal(await beginQueuePreparation(db, receipt.batchID, owner), true);
  for (let i = 0; i < receipt.items.length; i++) {
    await prepareQueueItem(db, receipt.batchID, i, owner);
  }
  return finishQueuePreparation(db, receipt.batchID, owner);
}
async function publishedCandidates() {
  const discovery = db.doc("brands/brand-a/seasonDiscoveryJobs/discovery");
  await discovery.set({generation: 1, candidateSnapshotHash: "hash", status: "succeeded"});
  await db.doc("brands/brand-a").update({publishedSeasonDiscoveryJobID: "discovery",
    publishedSeasonDiscoveryGeneration: 1, publishedSeasonDiscoverySnapshotHash: "hash"});
  for (const id of ["one", "same-url"]) {
    await discovery.collection("candidates").doc(id).set({generation: 1,
      snapshotHash: "hash", resolution: "newSeason", seasonURL: "https://brand.example/one",
      title: "2026 SS", coverImageURL: "https://brand.example/cover.jpg", sortIndex: 2});
  }
  return apiRequest({discoveryJobID: "discovery", generation: 1,
    candidateSnapshotHash: "hash", candidateIDs: ["one", "same-url", "missing"]});
}

test("PQ01 실제 URL 접수는 최신 계약을 요구하고 기존 job 중복과 재전송을 보존한다", async () => {
  await assert.rejects(() => call(requestSeasonImport, {brandID: "brand-a",
    seasonURL: "https://brand.example/one"}), (error) => error.code === "invalid-argument");
  const ref = db.doc("brands/brand-a/importJobs/legacy");
  const original = {jobType: "importSeasonFromURL", sourceURL: "https://brand.example/one",
    status: "succeeded", attemptCount: 3};
  await ref.set(original);
  const input = apiRequest({seasonURL: original.sourceURL});
  const first = await call(requestSeasonImport, input);
  assert.deepEqual(await call(requestSeasonImport, input), first);
  const result = await prepareReceipt(first);
  assert.equal(result.items[0].jobID, "legacy");
  assert.equal(result.items[0].admissionStatus, "duplicate");
  assert.deepEqual((await ref.get()).data(), original);
  await assert.rejects(() => call(requestSeasonImport, {...input,
    seasonURL: "https://brand.example/changed"}), (error) => error.code === "failed-precondition");
});

test("PQ01 실제 후보 접수는 snapshot을 고정하고 부분 실패와 URL 중복을 집계한다", async () => {
  const input = await publishedCandidates();
  const first = await call(requestSeasonCandidateImportJobs, input);
  await db.doc("brands/brand-a").update({publishedSeasonDiscoverySnapshotHash: "changed"});
  assert.deepEqual(await call(requestSeasonCandidateImportJobs, input), first);
  await assert.rejects(() => call(requestSeasonCandidateImportJobs,
    {...input, requestID: randomUUID()}), (error) => error.code === "failed-precondition");
  const result = await prepareReceipt(first);
  assert.deepEqual(result.items.map((item) => item.admissionStatus), ["created", "duplicate", "failed"]);
  const job = (await db.doc(`brands/brand-a/importJobs/${result.items[0].jobID}`).get()).data();
  assert.equal(job.sourceTitle, "2026 SS");
  assert.equal(job.coverRemoteURL, "https://brand.example/cover.jpg");
  assert.equal(job.sourceSortIndex, 2);
  assert.equal(job.dispatchMode, "batchQueue");
  assert.equal((await db.collection("brands/brand-a/importJobs").get()).size, 1);
});

test("PQ02 실제 asset 재시도는 기존 root를 보존하고 새 오회 실행 하나만 접수한다", async () => {
  const ref = db.doc("brands/brand-a/importJobs/partial");
  const original = {jobType: "importSeasonFromURL", status: "partialFailed",
    sourceURL: "https://brand.example/one", targetSeasonID: "season", createdPostIDs: ["post"],
    assetFailedCount: 1, attemptCount: 5, queueExecutionID: "previous"};
  await ref.set(original);
  await ref.collection("executions").doc("previous").set({status: "failed", attemptCount: 5});
  const first = await call(requestSeasonAssetRetry, apiRequest({sourceJobID: "partial"}));
  const second = await call(requestSeasonImport, apiRequest({seasonURL: original.sourceURL}));
  const a = await prepareReceipt(first);
  const b = await prepareReceipt(second);
  assert.equal(a.items[0].admissionStatus, "created");
  assert.equal(b.items[0].admissionStatus, "duplicate");
  assert.equal(a.items[0].executionID, b.items[0].executionID);
  assert.deepEqual((await ref.get()).data(), original);
  assert.equal((await ref.collection("executions").get()).size, 1);
  const retryRef = db.doc(`brands/brand-a/importJobs/${a.items[0].jobID}`);
  assert.equal((await retryRef.collection("executions").get()).size, 1);
  const execution = (await retryRef.collection("executions")
    .doc(a.items[0].executionID).get()).data();
  assert.equal(execution.attemptLimit, 5);
  assert.equal(execution.attemptCount, 0);
  assert.equal(execution.mode, "assetFailureRetry");
  assert.deepEqual(execution.input.createdPostIDs, ["post"]);
  const ownership = await claimBatch(db, delivery(a.batchID), "worker", "boot", now);
  const item = a.items[0];
  const attempt = await beginBatchItemAttempt(db, ownership, {
    ordinal: item.ordinal, jobID: item.jobID, executionID: item.executionID,
  }, now);
  await activateQueueItem({firestore: db, brandID: "brand-a", jobID: item.jobID,
    executionID: item.executionID, ordinal: item.ordinal, ownership,
    batchKind: "assetRetry", mode: attempt.mode, continuationInput: attempt.input,
    now});
  const activatedRetry = (await retryRef.get()).data();
  assert.equal(activatedRetry.queueActiveRunID, ownership.runID);
  assert.equal(activatedRetry.queueActivatedForBatchID, a.batchID);
  assert.equal((await ref.get()).data().assetRetryStatus, "processing");
});

test("PQ02 asset 재시도 입력이 준비 전에 바뀌면 이전 입력으로 실행하지 않는다", async () => {
  const ref = db.doc("brands/brand-a/importJobs/partial");
  await ref.set({jobType: "importSeasonFromURL", status: "failed",
    sourceURL: "https://brand.example/one", targetSeasonID: "season", createdPostIDs: ["post"]});
  const receipt = await call(requestSeasonAssetRetry, apiRequest({sourceJobID: "partial"}));
  await ref.update({createdPostIDs: ["different"]});
  await beginQueuePreparation(db, receipt.batchID, "owner");
  await assert.rejects(() => prepareQueueItem(db, receipt.batchID, 0, "owner"), /ASSET_RETRY_SOURCE_CHANGED/);
  assert.equal((await ref.collection("executions").get()).size, 0);
});

test("PQ01 직접 URL 후보 불일치와 재시도 불가 상태는 접수하지 않는다", async () => {
  await db.doc("brands/brand-a/seasonCandidates/candidate").set({seasonURL: "https://brand.example/a"});
  await assert.rejects(() => call(requestSeasonImport, apiRequest({sourceCandidateID: "candidate",
    seasonURL: "https://brand.example/b"})), (error) => error.code === "invalid-argument");
  await db.doc("brands/brand-a/importJobs/done").set({status: "succeeded"});
  await assert.rejects(() => call(requestSeasonAssetRetry, apiRequest({sourceJobID: "done"})),
    (error) => error.code === "failed-precondition");
  assert.equal((await db.doc("lookbookImportQueue/main").get()).exists, false);
});

async function brandCreationInput(extra = {}) {
  await db.doc(`platformAdmins/${uid}`).set({isActive: true});
  return apiRequest({name: "Atomic Brand", lookbookArchiveURL: "https://brand.example/collections", ...extra});
}

test("PQ01 브랜드 생성 동시 재전송은 브랜드와 최초 탐색 순번을 하나만 만든다", async () => {
  const input = await brandCreationInput();
  const results = await Promise.all(Array.from({length: 6}, () => call(createBrand, input)));
  results.forEach((result) => assert.deepEqual(result, results[0]));
  const result = results[0];
  assert.equal((await db.collection("brandCreationRequests").get()).size, 1);
  const brandReceipt = (await db.collection("brandCreationRequests").get()).docs[0].data();
  assert.equal(brandReceipt.receiptExpiresAt - brandReceipt.createdAt,
    30 * 86400000);
  assert.equal(brandReceipt.retentionNextAt, brandReceipt.receiptExpiresAt);
  assert.equal((await db.collection("lookbookImportBatches").get()).size, 1);
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().nextSequence, 2);
  const brandRef = db.doc(`brands/${result.brandID}`);
  assert.equal((await brandRef.get()).data().activeSeasonDiscoveryJobID, result.discoveryJobID);
  assert.equal((await brandRef.collection("seasonDiscoveryJobs").get()).size, 0);
  const receipt = await getQueueReceiptByBatchID(db, uid, result.batchID, queueAuthorization(db));
  const preparedResult = await prepareReceipt(receipt);
  assert.equal(preparedResult.items[0].jobID, result.discoveryJobID);
  const job = (await brandRef.collection("seasonDiscoveryJobs").doc(result.discoveryJobID).get()).data();
  assert.equal(job.requestReason, "brandCreated");
  assert.equal(job.dispatchMode, "batchQueue");
  assert.equal(job.generation, 1);
  assert.equal(job.sourceArchiveURL, input.lookbookArchiveURL);
  assert.equal(job.queueBatchID, result.batchID);
});

test("PQ01 목록 URL 없는 브랜드 생성은 영수증만 남기고 탐색 순번을 소비하지 않는다", async () => {
  const input = await brandCreationInput({lookbookArchiveURL: null});
  const result = await call(createBrand, input);
  assert.equal(result.discoveryJobID, null);
  assert.equal(result.batchID, null);
  assert.deepEqual(await call(createBrand, input), result);
  assert.equal((await db.doc("lookbookImportQueue/main").get()).exists, false);
  assert.equal((await db.doc(`brands/${result.brandID}`).get()).data().discoveryStatus, "idle");
});

test("PQ01 브랜드 생성은 이름 충돌과 입력 실패 때 접수나 일부 브랜드를 남기지 않는다", async () => {
  const first = await call(createBrand, await brandCreationInput());
  const beforeBrands = (await db.collection("brands").get()).size;
  await assert.rejects(() => call(createBrand, apiRequest({name: "Atomic Brand",
    lookbookArchiveURL: "https://brand.example/other"})), (error) => error.code === "already-exists");
  await assert.rejects(() => call(createBrand, apiRequest({name: "Invalid Mood",
    moodIDs: ["nonexistent"], lookbookArchiveURL: "https://brand.example/other"})));
  assert.equal((await db.collection("brands").get()).size, beforeBrands);
  assert.equal((await db.collection("brandCreationRequests").get()).size, 1);
  assert.equal((await db.collection("lookbookImportBatches").get()).size, 1);
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().headBatchID, first.batchID);
});

test("PQ01 브랜드 생성 영수증은 만료 전 재조회하고 payload 충돌과 권한 회수를 거절한다", async () => {
  const input = await brandCreationInput({requestCreatedAt: Date.now() - 86400000 + 60000});
  const result = await call(createBrand, input);
  assert.deepEqual(await call(createBrand, input), result);
  await assert.rejects(() => call(createBrand, {...input, name: "Changed Name"}),
    (error) => error.code === "failed-precondition");
  await db.doc(`platformAdmins/${uid}`).update({isActive: false});
  await assert.rejects(() => call(createBrand, input), (error) => error.code === "permission-denied");
  await db.doc(`platformAdmins/${uid}`).update({isActive: true});
  await assert.rejects(() => call(createBrand, {...input, requestID: randomUUID(),
    requestCreatedAt: Date.now() - 86400001, name: "Expired"}),
  (error) => error.code === "failed-precondition");
  assert.equal((await db.collection("brandCreationRequests").get()).size, 1);
});

test("PQ10 브랜드 생성 영수증은 앱 관리자가 직접 읽거나 쓸 수 없다", async () => {
  await call(createBrand, await brandCreationInput());
  const receipt = (await db.collection("brandCreationRequests").get()).docs[0];
  const client = rules.authenticatedContext(uid).firestore();
  await assertFails(client.doc(receipt.ref.path).get());
  await assertFails(client.doc(receipt.ref.path).set({result: {brandID: "forged"}}));
});

test("PQ02 준비 이벤트 중복과 순번 전진은 각 batch를 한 번만 준비한다", async () => {
  const a = await call(requestSeasonImport, apiRequest({seasonURL: "https://brand.example/a"}));
  const b = await call(requestSeasonImport, apiRequest({seasonURL: "https://brand.example/b"}));
  const event = {data: {after: await batchRef(a.batchID).get()}};
  await Promise.all([onLookbookBatchPreparationRequested.run(event),
    onLookbookBatchPreparationRequested.run(event)]);
  assert.equal((await batchRef(a.batchID).get()).data().preparationAttempts, 1);
  await onLookbookPreparationSequenceChanged.run({data: {
    before: {data: () => ({preparationSequence: 1})},
    after: await db.doc("lookbookImportQueue/main").get()}});
  assert.equal((await batchRef(b.batchID).get()).data().state, "queued");
  assert.equal((await db.collection("brands/brand-a/importJobs").get()).size, 2);
  assert.equal(await prepareNextQueueBatch(db), null);
});

test("PQ02 복구 해제는 같은 준비 순번을 즉시 재개하고 중복 이벤트는 한 번만 준비한다", async () => {
  const receipt = await call(requestSeasonImport, apiRequest({seasonURL: "https://brand.example/recovered"}));
  const queueRef = db.doc("lookbookImportQueue/main");
  await queueRef.update({state: "recoveryRequired"});
  const before = await queueRef.get();
  await onLookbookBatchPreparationRequested.run({data: {after: await batchRef(receipt.batchID).get()}});
  assert.equal((await batchRef(receipt.batchID).get()).data().preparationAttempts, 0);
  await queueRef.update({state: "idle"});
  const after = await queueRef.get();
  assert.equal(before.data().preparationSequence, after.data().preparationSequence);
  await Promise.all([onLookbookPreparationSequenceChanged.run({data: {before, after}}),
    onLookbookPreparationSequenceChanged.run({data: {before, after}})]);
  assert.equal((await batchRef(receipt.batchID).get()).data().state, "queued");
  assert.equal((await batchRef(receipt.batchID).get()).data().preparationAttempts, 1);
  assert.equal((await db.collection("brands/brand-a/importJobs").get()).size, 1);
});

test("PQ02 자동 준비는 오회 소진과 종료 불명확 owner를 구분한다", async () => {
  const receipt = await call(requestSeasonImport, apiRequest({seasonURL: "https://brand.example/a"}));
  await db.doc("brands/brand-a").update({deletionStatus: "deleting"});
  for (let i = 0; i < 5; i++) await prepareNextQueueBatch(db);
  const batch = (await batchRef(receipt.batchID).get()).data();
  assert.equal(batch.preparationAttempts, 5);
  assert.equal(batch.state, "released");
  assert.equal(batch.items[0].errorCode, "PREPARATION_EXHAUSTED");
  assert.equal((await batchRef(receipt.batchID).collection("preparationAttempts").get()).size, 5);
  await db.doc("brands/brand-a").update({deletionStatus: "active"});
  const next = await call(requestSeasonImport, apiRequest({seasonURL: "https://brand.example/b"}));
  await beginQueuePreparation(db, next.batchID, "unknown-owner");
  assert.equal(await prepareNextQueueBatch(db), null);
  assert.equal((await batchRef(next.batchID).get()).data().preparationOwner, "unknown-owner");
});

test("PQ04 검토 승인은 같은 실행과 시도 이력을 보존하며 snapshot 변경을 거절한다", async () => {
  const ref = db.doc("brands/brand-a/importJobs/review");
  const original = {jobType: "importSeasonFromURL", sourceURL: "https://brand.example/review",
    status: "awaitingReview", reviewGeneration: 2, reviewSnapshotHash: "review-hash",
    reviewCandidateKeys: ["a", "b"], attemptCount: 4, queueExecutionID: "original"};
  await ref.set(original);
  const history = {status: "awaitingReview", attemptCount: 4, attemptLimit: 5, batchID: "previous"};
  await ref.collection("executions").doc("original").set(history);
  const input = apiRequest({jobID: "review", reviewGeneration: 2, reviewSnapshotHash: "review-hash",
    decision: "approvedWithExclusions", excludedCandidateKeys: ["b"]});
  const receipt = await call(reviewLookbookExtraction, input);
  assert.deepEqual(await call(reviewLookbookExtraction, input), receipt);
  await prepareNextQueueBatch(db);
  assert.equal((await batchRef(receipt.batchID).get()).data().items[0].executionID, "original");
  assert.deepEqual((await ref.get()).data(), original);
  assert.deepEqual((await ref.collection("executions").doc("original").get()).data(), history);
  const continuation = (await ref.collection("executions").doc("original")
    .collection("continuations").doc(receipt.batchID).get()).data();
  assert.deepEqual(continuation.input.approvedCandidateKeys, ["a"]);
  assert.equal(continuation.input.resumeFrom, "materializing");
  const ownership = await claimBatch(db, delivery(receipt.batchID), "worker", "boot", now);
  const item = (await batchRef(receipt.batchID).get()).data().items[0];
  const attempt = await beginBatchItemAttempt(db, ownership, {
    ordinal: 0, jobID: item.jobID, executionID: item.executionID,
  }, now);
  await activateQueueItem({firestore: db, brandID: "brand-a", jobID: item.jobID,
    executionID: item.executionID, ordinal: 0, ownership, batchKind: "reviewApproval",
    mode: attempt.mode, continuationInput: attempt.input, now});
  const activatedRoot = (await ref.get()).data();
  assert.equal(activatedRoot.status, "queued");
  assert.equal(activatedRoot.reviewStatus, "approved");
  assert.equal(activatedRoot.queueActiveRunID, ownership.runID);
  assert.ok((await ref.collection("executions").doc(item.executionID)
    .collection("continuations").doc(receipt.batchID).get()).data().activatedAt);
  await assert.rejects(() => call(reviewLookbookExtraction, {...input, requestID: randomUUID(),
    excludedCandidateKeys: ["a"]}), (error) => error.code === "failed-precondition");
});

test("PQ04 수정 후 수동 재시도는 관리자와 runtime 조건을 지키고 새 오회 실행을 만든다", async () => {
  const ref = db.doc("brands/brand-a/importJobs/fix");
  const original = {jobType: "importSeasonFromURL", sourceURL: "https://brand.example/fix",
    status: "awaitingReview", reviewStatus: "correctionRequired", reviewGeneration: 1,
    extractionIssueStatus: "fixed", blockedRuntimeVersion: "extractor:1.0.0",
    retryAvailableRuntimeVersion: "extractor:1.1.0", queueExecutionID: "previous", attemptCount: 5};
  await ref.set(original);
  const input = apiRequest({jobID: "fix"});
  await db.doc(`platformAdmins/${uid}`).update({isActive: false});
  await assert.rejects(() => call(retryLookbookExtractionAfterFix, input), (error) => error.code === "permission-denied");
  await db.doc(`platformAdmins/${uid}`).update({isActive: true});
  const receipt = await call(retryLookbookExtractionAfterFix, input);
  await prepareNextQueueBatch(db);
  const item = (await batchRef(receipt.batchID).get()).data().items[0];
  const execution = (await ref.collection("executions").doc(item.executionID).get()).data();
  assert.notEqual(item.executionID, "previous");
  assert.equal(execution.attemptCount, 0);
  assert.equal(execution.attemptLimit, 5);
  assert.deepEqual((await ref.get()).data(), original);
});

test("PQ04 보수 분석과 적용 접수는 시즌이나 게시물을 즉시 변경하지 않는다", async () => {
  const ref = db.doc("brands/brand-a/importJobs/repair");
  const seasonRef = db.doc("brands/brand-a/seasons/season");
  await ref.set({jobType: "importSeasonFromURL", status: "succeeded",
    sourceURL: "https://brand.example/repair", targetSeasonID: "season"});
  await seasonRef.set({sourceImportJobID: "repair", postCount: 1});
  const analyze = await call(requestLookbookSeasonRepair, apiRequest({sourceImportJobID: "repair", seasonID: "season"}));
  assert.equal(analyze.kind, "repair");
  await prepareNextQueueBatch(db);
  const analyzeItem = (await batchRef(analyze.batchID).get()).data().items[0];
  assert.equal(analyzeItem.admissionStatus, "created");
  const analyzeExecution = ref.collection("executions").doc(analyzeItem.executionID);
  assert.equal((await analyzeExecution.get()).data().mode, "repairAnalyze");
  const analyzeOwnership = await claimBatch(db, delivery(analyze.batchID),
    "worker", "boot", now);
  const analyzeAttempt = await beginBatchItemAttempt(db, analyzeOwnership, {
    ordinal: 0, jobID: analyzeItem.jobID, executionID: analyzeItem.executionID,
  }, now);
  await activateQueueItem({firestore: db, brandID: "brand-a",
    jobID: analyzeItem.jobID, executionID: analyzeItem.executionID, ordinal: 0,
    ownership: analyzeOwnership, batchKind: "repair", mode: analyzeAttempt.mode,
    continuationInput: analyzeAttempt.input, now});
  assert.equal((await ref.get()).data().repairStatus, "analyzing");
  await ref.update({status: "awaitingReview", repairGeneration: 1,
    repairSnapshotHash: "repair-hash", repairStatus: "previewReady"});
  await finishBatchItemAttempt(db, analyzeOwnership, {ordinal: 0,
    jobID: analyzeItem.jobID, executionID: analyzeItem.executionID,
    outcome: "awaitingReview"}, now + 1);
  await beginBatchDrain(db, analyzeOwnership, now + 2);
  assert.equal(await finishBatchRun(db, analyzeOwnership, finish("complete"),
    now + 3), "released");
  await advanceReleasedHead(db);
  const plan = {seasonID: "season", status: "previewReady", repairSnapshotHash: "repair-hash",
    keep: [], reorder: [], add: [], removeCandidates: [], orderedPostIDs: [], allPostIDs: [], resultingPostCount: 0};
  await ref.collection("repairs").doc("1").set(plan);
  const apply = await call(applyLookbookSeasonRepair, apiRequest({jobID: "repair",
    repairGeneration: 1, repairSnapshotHash: "repair-hash"}));
  assert.equal(apply.kind, "repair");
  await prepareNextQueueBatch(db);
  const applyItem = (await batchRef(apply.batchID).get()).data().items[0];
  assert.equal(applyItem.admissionStatus, "created");
  const continuation = (await ref.collection("executions").doc(applyItem.executionID)
    .collection("continuations").doc(apply.batchID).get()).data();
  assert.equal(continuation.mode, "repairApply");
  assert.equal(continuation.input.plan.resultingPostCount, 0);
  assert.deepEqual((await seasonRef.get()).data(), {sourceImportJobID: "repair", postCount: 1});
  assert.deepEqual((await ref.collection("repairs").doc("1").get()).data(), plan);
  assert.equal((await seasonRef.collection("posts").get()).size, 0);
  const applyOwnership = await claimBatch(db, delivery(apply.batchID),
    "worker", "boot", now + 4);
  const applyAttempt = await beginBatchItemAttempt(db, applyOwnership, {
    ordinal: 0, jobID: applyItem.jobID, executionID: applyItem.executionID,
  }, now + 4);
  await activateQueueItem({firestore: db, brandID: "brand-a", jobID: applyItem.jobID,
    executionID: applyItem.executionID, ordinal: 0, ownership: applyOwnership,
    batchKind: "repair", mode: applyAttempt.mode,
    continuationInput: applyAttempt.input, now: now + 4});
  assert.equal((await ref.get()).data().repairStatus, "applied");
  assert.equal((await seasonRef.get()).data().postCount, 0);
  assert.equal((await ref.collection("repairs").doc("1").get()).data().status,
    "applied");
});

test("PQ05 실제 목록 탐색 두 진입점은 같은 순번과 claim을 사용한다", async () => {
  await db.doc("brands/brand-a").update({lookbookArchiveURL: "https://brand.example/collections",
    publishedSeasonDiscoveryJobID: "published", publishedSeasonDiscoverySnapshotHash: "keep"});
  const a = await call(requestSeasonDiscovery, apiRequest({requestReason: "manualRefresh"}));
  const b = await call(discoverSeasonCandidates, apiRequest());
  await prepareNextQueueBatch(db);
  await prepareNextQueueBatch(db);
  const first = (await batchRef(a.batchID).get()).data();
  const second = (await batchRef(b.batchID).get()).data();
  assert.equal(first.items[0].admissionStatus, "created");
  assert.equal(second.items[0].admissionStatus, "duplicate");
  assert.equal(first.items[0].jobID, second.items[0].jobID);
  assert.equal((await db.doc("brands/brand-a").get()).data().publishedSeasonDiscoverySnapshotHash, "keep");
});

test("PQ05 목록 수동 재시도는 기존 삼회 예산과 원본 상태를 보존한다", async () => {
  await db.doc("brands/brand-a").update({lookbookArchiveURL: "https://brand.example/collections",
    activeSeasonDiscoveryJobID: "failed"});
  const ref = db.doc("brands/brand-a/seasonDiscoveryJobs/failed");
  const original = {status: "failed", retryable: true, generation: 1,
    sourceArchiveURL: "https://brand.example/collections", attemptCount: 3};
  await ref.set(original);
  const receipt = await call(retrySeasonDiscovery, apiRequest({jobID: "failed"}));
  await prepareNextQueueBatch(db);
  const item = (await batchRef(receipt.batchID).get()).data().items[0];
  const execution = (await ref.collection("executions").doc(item.executionID).get()).data();
  assert.equal(execution.attemptLimit, 3);
  assert.equal(execution.attemptCount, 0);
  assert.deepEqual((await ref.get()).data(), original);
});

test("PQ05 검증된 목록 재분석은 이전 검토 자료를 접수 시점에 없애지 않는다", async () => {
  await db.doc(`platformAdmins/${uid}`).set({isActive: true});
  await db.doc("brands/brand-a").update({lookbookArchiveURL: "https://brand.example/collections",
    publishedSeasonDiscoveryJobID: "review", lastSeasonDiscoveryGeneration: 1});
  const ref = db.doc("brands/brand-a/seasonDiscoveryJobs/review");
  const original = {status: "correctionRequired", generation: 1, candidateSnapshotHash: "hash",
    sourceArchiveURL: "https://brand.example/collections", extractionIssueStatus: "fixed",
    extractionIssueFingerprint: "a".repeat(40), blockedRuntimeVersion: "contract:1",
    retryAvailableRuntimeVersion: "contract:2"};
  await ref.set(original);
  const receipt = await call(retrySeasonDiscoveryAfterExtractionFix, apiRequest({jobID: "review",
    generation: 1, candidateSnapshotHash: "hash"}));
  await prepareNextQueueBatch(db);
  assert.equal((await batchRef(receipt.batchID).get()).data().items[0].admissionStatus, "created");
  assert.deepEqual((await ref.get()).data(), original);
});

test("PQ04 승인 중복은 이후 root가 바뀌어도 원래 승인 실행을 참조한다", async () => {
  const ref = db.doc("brands/brand-a/importJobs/legacy-review");
  await ref.set({jobType: "importSeasonFromURL", sourceURL: "https://brand.example/review",
    status: "awaitingReview", reviewGeneration: 0, reviewSnapshotHash: "hash",
    reviewCandidateKeys: ["image"], attemptCount: 2});
  const input = apiRequest({jobID: "legacy-review", reviewGeneration: 0,
    reviewSnapshotHash: "hash", decision: "approved"});
  const first = await call(reviewLookbookExtraction, input);
  await prepareNextQueueBatch(db);
  const executionID = (await batchRef(first.batchID).get()).data().items[0].executionID;
  await ref.update({queueExecutionID: "later-execution", status: "succeeded"});
  const second = await call(reviewLookbookExtraction, {...input, requestID: randomUUID()});
  await prepareNextQueueBatch(db);
  const duplicate = (await batchRef(second.batchID).get()).data().items[0];
  assert.equal(duplicate.admissionStatus, "duplicate");
  assert.equal(duplicate.executionID, executionID);
});

test("PQ02 복구 차단 중에는 새 준비를 시작하거나 owner를 교체하지 않는다", async () => {
  const receipt = await call(requestSeasonImport, apiRequest({seasonURL: "https://brand.example/a"}));
  await db.doc("lookbookImportQueue/main").update({state: "recoveryRequired"});
  assert.equal(await prepareNextQueueBatch(db), null);
  assert.equal(await beginQueuePreparation(db, receipt.batchID, "new-owner"), false);
  const batch = (await batchRef(receipt.batchID).get()).data();
  assert.equal(batch.preparationAttempts, 0);
  assert.equal(batch.preparationOwner, null);
});

test("PQ04 접수 후 검토 snapshot이 바뀌면 승인 준비가 새 실행을 만들지 않는다", async () => {
  const ref = db.doc("brands/brand-a/importJobs/stale");
  await ref.set({jobType: "importSeasonFromURL", sourceURL: "https://brand.example/stale",
    status: "awaitingReview", reviewGeneration: 0, reviewSnapshotHash: "hash", reviewCandidateKeys: ["image"]});
  const receipt = await call(reviewLookbookExtraction, apiRequest({jobID: "stale",
    reviewGeneration: 0, reviewSnapshotHash: "hash", decision: "approved"}));
  await ref.update({reviewSnapshotHash: "changed"});
  await beginQueuePreparation(db, receipt.batchID, "owner");
  await assert.rejects(() => prepareQueueItem(db, receipt.batchID, 0, "owner"), /CONTINUATION_SOURCE_CHANGED/);
  assert.equal((await ref.collection("executions").get()).size, 0);
});

test("PQ04 승인 접수 준비가 소진돼도 같은 검토의 새 요청으로 준비를 복구한다", async () => {
  const ref = db.doc("brands/brand-a/importJobs/recover-review");
  await ref.set({jobType: "importSeasonFromURL", sourceURL: "https://brand.example/recover",
    status: "awaitingReview", reviewGeneration: 0, reviewSnapshotHash: "hash", reviewCandidateKeys: ["image"]});
  const input = apiRequest({jobID: "recover-review", reviewGeneration: 0,
    reviewSnapshotHash: "hash", decision: "approved"});
  const first = await call(reviewLookbookExtraction, input);
  await db.doc("brands/brand-a").update({deletionStatus: "deleting"});
  for (let i = 0; i < 5; i++) await prepareNextQueueBatch(db);
  assert.equal((await batchRef(first.batchID).get()).data().items[0].admissionStatus, "failed");
  await db.doc("brands/brand-a").update({deletionStatus: "active"});
  const second = await call(reviewLookbookExtraction, {...input, requestID: randomUUID()});
  await prepareNextQueueBatch(db);
  assert.equal((await batchRef(second.batchID).get()).data().items[0].admissionStatus, "created");
  assert.equal((await ref.collection("reviews").get()).size, 1);
  assert.equal((await ref.collection("executions").get()).size, 1);
});

const delivery = (batchID, dispatchGeneration = 0) => ({batchID, dispatchGeneration, queueContractVersion: 1});
const finish = (disposition, extra = {}) => ({disposition, drained: true, inFlight: 0, ...extra});

test("PQ03 독립 Worker의 묶음 선점은 하나만 성공하고 시간만으로 실행권을 뺏지 않는다", async () => {
  const receipt = await prepared(request(), [target("one")]);
  const claims = await Promise.all([claimBatch(db, delivery(receipt.batchID), "worker-a", "boot-a", now),
    claimBatch(otherDB, delivery(receipt.batchID), "worker-b", "boot-b", now)]);
  assert.equal(claims.filter(Boolean).length, 1);
  assert.equal(await claimBatch(otherDB, delivery(receipt.batchID), "worker-c", "boot-c", now + 86400000), null);
  assert.equal((await batchRef(receipt.batchID).collection("runs").get()).size, 1);
});

test("PQ03 정상 재개는 같은 head와 새 epoch를 쓰며 이전 실행의 쓰기를 거절한다", async () => {
  const receipt = await prepared(request(), [target("one")]);
  const token = await claimBatch(db, delivery(receipt.batchID), "worker", "boot", now);
  await writeBatchProgress(db, token, "one", "parsed");
  await beginBatchDrain(db, token, now + 1);
  assert.equal(await finishBatchRun(db, token, finish("continue"), now + 2), "queued");
  assert.equal(await claimBatch(db, delivery(receipt.batchID), "worker", "boot", now + 3), null);
  const next = await claimBatch(otherDB, delivery(receipt.batchID, 1), "worker", "boot", now + 3);
  assert.equal(next.epoch, token.epoch + 1);
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().headBatchID, receipt.batchID);
  await assert.rejects(() => heartbeatBatch(db, token, now + 4), /QUEUE_OWNERSHIP_LOST/);
  await assert.rejects(() => db.runTransaction(async (tx) => {
    await readOwnedBatch(db, tx, token);
    tx.set(db.doc("brands/brand-a/staleWrites/forbidden"), {written: true});
  }), /QUEUE_OWNERSHIP_LOST/);
  assert.equal((await db.doc("brands/brand-a/staleWrites/forbidden").get()).exists, false);
});

test("PQ06 종료 미확인과 남은 작업은 다음 브랜드를 차단한다", async () => {
  const a = await prepared(request(), [target("one")]);
  const b = await prepared(request(), [target("two")]);
  const token = await claimBatch(db, delivery(a.batchID), "worker", "boot", now);
  await assert.rejects(() => finishBatchRun(db, token, finish("complete"), now), /QUEUE_NOT_DRAINING/);
  await beginBatchDrain(db, token, now);
  assert.equal(await finishBatchRun(db, token, finish("complete", {drained: false, inFlight: 1}), now), "recoveryRequired");
  assert.equal(await advanceReleasedHead(db), null);
  assert.equal(await claimBatch(otherDB, delivery(b.batchID), "next", "next-boot", now + 86400000), null);
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().owner, "worker");
});

test("PQ07 무진행 두 구간은 복구 확인으로 멈추고 heartbeat를 진행으로 세지 않는다", async () => {
  const receipt = await prepared(request(), [target("one")]);
  for (let generation = 0; generation < 2; generation++) {
    const token = await claimBatch(db, delivery(receipt.batchID, generation), "worker", "boot", now + generation);
    await heartbeatBatch(db, token, now + 10);
    await beginBatchDrain(db, token, now + 11);
    const state = await finishBatchRun(db, token, finish("continue"), now + 12);
    assert.equal(state, generation === 0 ? "queued" : "recoveryRequired");
  }
  assert.equal((await batchRef(receipt.batchID).get()).data().noProgressSegments, 2);
});

test("PQ03 완료는 시즌 종료와 drain 증거를 모두 확인한 뒤 다음 순번으로 간다", async () => {
  const a = await prepared(request(), [target("one")]);
  const b = await prepared(request(), [target("two")]);
  const token = await claimBatch(db, delivery(a.batchID), "worker", "boot", now);
  await beginBatchDrain(db, token, now);
  await assert.rejects(() => finishBatchRun(db, token, finish("complete"), now), /QUEUE_EXECUTION_NOT_TERMINAL/);
  const item = a.items[0];
  // Worker가 저장까지 완료한 영속 상태를 fixture로 설정한다.
  await db.doc(`brands/brand-a/importJobs/${item.jobID}/executions/${item.executionID}`).update({status: "succeeded"});
  await writeBatchProgress(db, token, "one", "stored");
  assert.equal(await finishBatchRun(db, token, finish("complete"), now), "released");
  assert.equal(await advanceReleasedHead(db), b.batchID);
  assert.ok(await claimBatch(otherDB, delivery(b.batchID), "next", "next-boot", now + 1));
});

test("PQ03 추출 교정 필요는 종료를 보존하고 정리 뒤 다음 묶음으로 진행한다", async () => {
  const a = await prepared(request({kind: "discoverSeasons"}),
    [target("archive", {collection: "seasonDiscoveryJobs", jobData: {
      status: "queued", generation: 1, dispatchGeneration: 0,
      extractorVersion: "season-discovery-v1",
      extractionContractRevision: 3,
      sourceArchiveURL: "https://brand.example/archive",
    }})]);
  const b = await prepared(request(), [target("later")]);
  const item = a.items[0];
  const token = await claimBatch(db, delivery(a.batchID), "worker", "boot", now);
  const attempt = await beginBatchItemAttempt(db, token, {
    ordinal: item.ordinal, jobID: item.jobID, executionID: item.executionID,
  }, now);
  assert.equal(attempt.started, true);
  await db.doc(`brands/brand-a/seasonDiscoveryJobs/${item.jobID}`)
    .update({status: "correctionRequired", phase: "completed"});
  await finishBatchItemAttempt(db, token, {
    ordinal: item.ordinal, jobID: item.jobID,
    executionID: item.executionID, outcome: "correctionRequired",
  }, now + 1);
  await beginBatchDrain(db, token, now + 2);
  assert.equal(await finishBatchRun(db, token, finish("complete"), now + 3),
    "released");
  const storedBatch = (await batchRef(a.batchID).get()).data();
  assert.equal(storedBatch.items[0].processingStatus, "correctionRequired");
  assert.equal((await db.doc(`brands/brand-a/seasonDiscoveryJobs/${item.jobID}`)
    .collection("executions").doc(item.executionID).get()).data().status,
  "correctionRequired");
  assert.equal(await advanceReleasedHead(db), b.batchID);
  assert.ok(await claimBatch(otherDB, delivery(b.batchID), "next", "next-boot",
    now + 4));
});

test("PQ06 continuation이 끝나도 원본 execution이 미종료면 차례를 넘기지 않는다", async () => {
  const receipt = await prepared(request(), [target("unfinished-continuation")]);
  const item = receipt.items[0];
  const token = await claimBatch(db, delivery(receipt.batchID), "worker", "boot", now);
  const execution = db.doc(`brands/brand-a/importJobs/${item.jobID}`)
    .collection("executions").doc(item.executionID);
  await execution.update({status: "processing"});
  await execution.collection("continuations").doc(receipt.batchID)
    .set({status: "succeeded"});
  await beginBatchDrain(db, token, now);
  await assert.rejects(() => finishBatchRun(db, token, finish("complete"), now),
    /QUEUE_EXECUTION_NOT_TERMINAL/);
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().owner,
    token.owner);
});

test("PQ06 시즌 attempt ledger는 재시도 시도 수와 due 시각을 실행권 transaction에 기록한다", async () => {
  const receipt = await prepared(request(), [target("ledger")]);
  const item = receipt.items[0];
  const token = await claimBatch(db, delivery(receipt.batchID), "worker", "boot", now);
  const first = await beginBatchItemAttempt(db, token, {
    ordinal: 0, jobID: item.jobID, executionID: item.executionID,
  }, now);
  assert.deepEqual(first, {started: true, attempt: 1, attemptID: "00001",
    attemptLimit: 5, mode: null, approval: false,
    batchKind: "importSeasons", input: null});
  assert.deepEqual(await beginBatchItemAttempt(db, token, {
    ordinal: 0, jobID: item.jobID, executionID: item.executionID,
  }, now + 1), {started: false, reason: "alreadyActive"});
  await finishBatchItemAttempt(db, token, {ordinal: 0, jobID: item.jobID,
    executionID: item.executionID, outcome: "retryWaiting", retryAt: now + 5000,
    errorCode: "NETWORK"}, now + 2);
  const execution = db.doc(`brands/brand-a/importJobs/${item.jobID}`)
    .collection("executions").doc(item.executionID);
  assert.equal((await execution.get()).data().attemptCount, 1);
  const firstAttempt = (await execution.collection("attempts").doc("00001").get()).data();
  assert.equal(firstAttempt.status, "retryWaiting");
  assert.equal(firstAttempt.batchID, receipt.batchID);
  assert.deepEqual(await beginBatchItemAttempt(db, token, {
    ordinal: 0, jobID: item.jobID, executionID: item.executionID,
  }, now + 4999), {started: false, reason: "retryNotDue"});
  await beginBatchDrain(db, token, now + 5000);
  assert.equal(await finishBatchRun(db, token, finish("retry", {retryAt: now + 5000}), now + 5000),
    "retryWaiting");
  const resumed = await claimBatch(db, delivery(receipt.batchID, 1), "worker", "boot", now + 5000);
  const second = await beginBatchItemAttempt(db, resumed, {
    ordinal: 0, jobID: item.jobID, executionID: item.executionID,
  }, now + 5000);
  assert.equal(second.attempt, 2);
  await finishBatchItemAttempt(db, resumed, {ordinal: 0, jobID: item.jobID,
    executionID: item.executionID, outcome: "succeeded"}, now + 5001);
  assert.equal((await execution.get()).data().attemptCount, 2);
  assert.equal((await execution.collection("attempts").get()).size, 2);
});

test("PQ08 두 객체 원장이 준비되기 전에는 기존 cover를 유지하고 소유 실행만 공개한다", async () => {
  const receipt = await prepared(request(), [target("asset-publish")]);
  const item = receipt.items[0];
  const token = await claimBatch(db, delivery(receipt.batchID), "asset-worker", "asset-boot", now);
  await beginBatchItemAttempt(db, token, {ordinal: 0, jobID: item.jobID,
    executionID: item.executionID}, now);
  const season = db.doc("brands/brand-a/seasons/asset-season");
  const sourceURL = "https://brand.example/cover.jpg";
  await season.set({coverRemoteURL: sourceURL, coverPath: "legacy/cover.jpg"});
  const identity = {brandID: "brand-a", seasonID: "asset-season", jobID: item.jobID,
    executionID: item.executionID, epoch: token.epoch, writeID: "asset-write-a",
    kind: "seasonCover", sourceURL, transformPolicyVersion: "512-75-1600-88"};
  const paths = assetWritePaths(identity);
  const write = {...identity, ordinal: 0, paths};
  await beginAssetWrite(db, token, write, now);
  await assert.rejects(() => assertNoActiveLookbookAssetWrites(db, {
    brandID: "brand-a", seasonID: "asset-season",
  }), /LOOKBOOK_ASSET_WRITE_STILL_ACTIVE/);
  assert.equal((await season.get()).data().coverPath, "legacy/cover.jpg");
  const thumb = {generation: "1001", size: 128};
  const detail = {generation: "1002", size: 512};
  await assert.rejects(() => publishAssetWrite(db, token, write, {thumb}, now + 2),
    /ASSET_VARIANTS_INCOMPLETE/);
  assert.equal((await season.get()).data().coverPath, "legacy/cover.jpg");
  await publishAssetWrite(db, token, write, {thumb, detail}, now + 4);
  await assert.doesNotReject(() => assertNoActiveLookbookAssetWrites(db, {
    brandID: "brand-a", seasonID: "asset-season",
  }));
  const saved = (await season.get()).data();
  assert.equal(saved.coverPath, paths.detailPath);
  assert.equal(saved.coverAssetWriteID, write.writeID);
  const ledger = db.doc(`brands/brand-a/importJobs/${item.jobID}/executions/${item.executionID}` +
    `/assets/${paths.assetKey}/writes/${write.writeID}`);
  assert.equal((await ledger.get()).data().status, "published");
  assert.deepEqual((await ledger.get()).data().objects,
    {thumb: {generation: "1001", size: 128}, detail: {generation: "1002", size: 512}});
});

test("PQ08 deletion fence는 post·season·brand 활성 원장을 차단하고 완료 후 해제한다", async () => {
  const receipt = await prepared(request(), [target("asset-delete-fence")]);
  const item = receipt.items[0];
  const token = await claimBatch(db, delivery(receipt.batchID), "asset-worker", "asset-boot", now);
  await beginBatchItemAttempt(db, token, {ordinal: 0, jobID: item.jobID,
    executionID: item.executionID}, now);
  const seasonID = "fenced-season";
  const postID = "fenced-post";
  const season = db.doc(`brands/brand-a/seasons/${seasonID}`);
  const post = season.collection("posts").doc(postID);
  const sourceURL = "https://brand.example/fenced-image.jpg";
  await season.set({deletionStatus: "active"});
  await post.set({deletionStatus: "active", media: [{remoteURL: sourceURL}]});
  const identity = {brandID: "brand-a", seasonID, postID, mediaIndex: 0,
    jobID: item.jobID, executionID: item.executionID, epoch: token.epoch,
    writeID: "asset-write-fenced", kind: "postImage", sourceURL,
    transformPolicyVersion: "512-75-1600-88"};
  const paths = assetWritePaths(identity);
  const write = {...identity, ordinal: 0, paths};
  await beginAssetWrite(db, token, write, now);
  await assert.rejects(() => assertNoActiveLookbookAssetWrites(db, {
    brandID: "brand-a", seasonID, postID,
  }), /LOOKBOOK_ASSET_WRITE_STILL_ACTIVE/);
  await assert.rejects(() => assertNoActiveLookbookAssetWrites(db, {
    brandID: "brand-a", seasonID,
  }), /LOOKBOOK_ASSET_WRITE_STILL_ACTIVE/);
  await assert.rejects(() => assertNoActiveLookbookAssetWrites(db, {
    brandID: "brand-a",
  }), /LOOKBOOK_ASSET_WRITE_STILL_ACTIVE/);
  await assert.doesNotReject(() => assertNoActiveLookbookAssetWrites(db, {
    brandID: "brand-a", seasonID, postID: "unrelated-post",
  }));
  await finishAssetWrite(db, write, "unpublished", "TEST_UPLOAD_FINISHED", {
    thumb: {generation: "3501", size: 128},
  }, now + 1);
  await assert.doesNotReject(() => assertNoActiveLookbookAssetWrites(db, {
    brandID: "brand-a", seasonID, postID,
  }));
});

test("PQ08 새 epoch는 이전 이미지 write의 늦은 공개를 거절한다", async () => {
  const receipt = await prepared(request(), [target("stale-asset")]);
  const item = receipt.items[0];
  const token = await claimBatch(db, delivery(receipt.batchID), "asset-worker", "asset-boot", now);
  await beginBatchItemAttempt(db, token, {ordinal: 0, jobID: item.jobID,
    executionID: item.executionID}, now);
  const season = db.doc("brands/brand-a/seasons/stale-season");
  const sourceURL = "https://brand.example/stale-cover.jpg";
  await season.set({coverRemoteURL: sourceURL, coverPath: "legacy/stale.jpg"});
  const identity = {brandID: "brand-a", seasonID: "stale-season", jobID: item.jobID,
    executionID: item.executionID, epoch: token.epoch, writeID: "asset-write-stale",
    kind: "seasonCover", sourceURL, transformPolicyVersion: "512-75-1600-88"};
  const paths = assetWritePaths(identity);
  const write = {...identity, ordinal: 0, paths};
  await beginAssetWrite(db, token, write, now);
  const objects = {thumb: {generation: "2001", size: 128},
    detail: {generation: "2002", size: 512}};
  const nextRunID = `${receipt.batchID}-${token.epoch + 1}`;
  await db.doc("lookbookImportQueue/main").update({owner: "next-owner", bootID: "next-boot",
    epoch: token.epoch + 1, runID: nextRunID, state: "active"});
  await batchRef(receipt.batchID).update({owner: "next-owner", bootID: "next-boot",
    epoch: token.epoch + 1, runID: nextRunID, state: "active"});
  await assert.rejects(() => publishAssetWrite(db, token, write, objects, now + 3),
    /QUEUE_OWNERSHIP_LOST/);
  assert.equal((await season.get()).data().coverPath, "legacy/stale.jpg");
  assert.equal((await db.doc(`brands/brand-a/importJobs/${item.jobID}/executions/${item.executionID}` +
    `/assets/${paths.assetKey}/writes/${write.writeID}`).get()).data().status, "uploading");
});

test("PQ08 삭제 표식이 생긴 뒤에는 늦은 cover 공개를 거절한다", async () => {
  const receipt = await prepared(request(), [target("deleted-asset")]);
  const item = receipt.items[0];
  const token = await claimBatch(db, delivery(receipt.batchID), "asset-worker", "asset-boot", now);
  await beginBatchItemAttempt(db, token, {ordinal: 0, jobID: item.jobID,
    executionID: item.executionID}, now);
  const season = db.doc("brands/brand-a/seasons/deleted-season");
  const sourceURL = "https://brand.example/deleted-cover.jpg";
  await season.set({deletionStatus: "active", coverRemoteURL: sourceURL,
    coverPath: "legacy/deleted.jpg"});
  const identity = {brandID: "brand-a", seasonID: "deleted-season", jobID: item.jobID,
    executionID: item.executionID, epoch: token.epoch, writeID: "deleted-write",
    kind: "seasonCover", sourceURL, transformPolicyVersion: "512-75-1600-88"};
  const paths = assetWritePaths(identity);
  const write = {...identity, ordinal: 0, paths};
  await beginAssetWrite(db, token, write, now);
  await season.update({deletionStatus: "deleted"});
  await assert.rejects(() => publishAssetWrite(db, token, write, {
    thumb: {generation: "3001", size: 128},
    detail: {generation: "3002", size: 512},
  }, now + 1), /ASSET_TARGET_DELETING/);
  assert.equal((await season.get()).data().coverPath, "legacy/deleted.jpg");
});

test("PQ08 실제 processor는 고유 경로와 두 generation을 기록한 뒤 공개한다", async () => {
  const receipt = await prepared(request(), [target("asset-processor")]);
  const item = receipt.items[0];
  const token = await claimBatch(db, delivery(receipt.batchID), "asset-worker", "asset-boot", now);
  await beginBatchItemAttempt(db, token, {ordinal: 0, jobID: item.jobID,
    executionID: item.executionID}, now);
  const season = db.doc("brands/brand-a/seasons/processor-season");
  const post = season.collection("posts").doc("processor-post");
  const remoteURL = "https://brand.example/processor-image.png";
  const sourcePageURL = "https://brand.example/collection";
  await season.set({deletionStatus: "active"});
  await post.set({media: [{remoteURL, thumbPath: "legacy/thumb.jpg", caption: "유지"}]});
  const pipeline = createQueuePipelineRuntime();
  const scope = pipeline.sourceBuffers.openScope();
  scope.retain(remoteURL, sourcePageURL, await sharp({create: {width: 24,
    height: 32, channels: 3, background: "#7e4a43"}}).png().toBuffer());
  let generation = 3000;
  const uploaded = [];
  const storage = {bucket: () => ({file: (path) => {
    const file = {metadata: undefined, save: async (bytes, options) => {
      assert.equal(options.preconditionOpts.ifGenerationMatch, 0);
      assert.equal((await sharp(bytes).metadata()).format, "jpeg");
      assert.equal((await post.get()).data().media[0].thumbPath,
        "legacy/thumb.jpg");
      file.metadata = {generation: String(++generation)};
      uploaded.push(path);
    }};
    return file;
  }})};
  try {
    const [result] = await runSyncTargets({firestore: db, storage,
      assetSyncConcurrency: 1, pipeline, sourceBuffers: scope}, [{kind: "postImage",
      brandID: "brand-a", seasonID: "processor-season", postID: "processor-post",
      mediaIndex: 0, remoteURL, sourcePageURL}], {jobID: item.jobID,
      queueExecution: {ownership: token, ordinal: 0, executionID: item.executionID}});
    assert.equal(result.succeeded, true);
    assert.equal(uploaded.length, 2);
    const media = (await post.get()).data().media[0];
    assert.match(media.thumbPath,
      /\/imports\/[\w-]+\/1\/[a-f0-9]{64}\/[\w-]+\/thumb\.jpg$/);
    assert.match(media.detailPath, /\/detail\.jpg$/);
    assert.equal(media.caption, "유지");
    const pathParts = uploaded[0].split("/");
    const ledger = db.doc(`brands/brand-a/importJobs/${item.jobID}/executions/${item.executionID}` +
      `/assets/${pathParts[9]}/writes/${pathParts[10]}`);
    const saved = (await ledger.get()).data();
    assert.equal(saved.status, "published");
    assert.deepEqual(Object.keys(saved.objects).sort(), ["detail", "thumb"]);
  } finally {
    scope.close();
  }
  assert.equal(pipeline.sourceBuffers.snapshot().retainedBytes, 0);
});

test("PQ08 실제 processor의 부분 업로드 실패는 이전 경로를 유지하고 공개하지 않는다", async () => {
  const receipt = await prepared(request(), [target("asset-partial")]);
  const item = receipt.items[0];
  const token = await claimBatch(db, delivery(receipt.batchID), "asset-worker", "asset-boot", now);
  await beginBatchItemAttempt(db, token, {ordinal: 0, jobID: item.jobID,
    executionID: item.executionID}, now);
  const season = db.doc("brands/brand-a/seasons/partial-season");
  const post = season.collection("posts").doc("partial-post");
  const remoteURL = "https://brand.example/partial-image.png";
  const sourcePageURL = "https://brand.example/collection";
  await season.set({deletionStatus: "active"});
  await post.set({media: [{remoteURL, thumbPath: "legacy/partial-thumb.jpg",
    caption: "보존"}]});
  const pipeline = createQueuePipelineRuntime();
  const scope = pipeline.sourceBuffers.openScope();
  scope.retain(remoteURL, sourcePageURL, await sharp({create: {width: 24,
    height: 32, channels: 3, background: "#7e4a43"}}).png().toBuffer());
  const uploaded = [];
  const storage = {bucket: () => ({file: (path) => {
    const file = {metadata: undefined, save: async (_bytes, options) => {
      assert.equal(options.preconditionOpts.ifGenerationMatch, 0);
      uploaded.push(path);
      if (path.endsWith("/thumb.jpg")) throw new Error("thumb upload failed");
      file.metadata = {generation: "4001"};
    }};
    return file;
  }})};
  try {
    const [result] = await runSyncTargets({firestore: db, storage,
      assetSyncConcurrency: 1, pipeline, sourceBuffers: scope}, [{kind: "postImage",
      brandID: "brand-a", seasonID: "partial-season", postID: "partial-post",
      mediaIndex: 0, remoteURL, sourcePageURL}], {jobID: item.jobID,
      queueExecution: {ownership: token, ordinal: 0, executionID: item.executionID}});
    assert.equal(result.succeeded, false);
    const media = (await post.get()).data().media[0];
    assert.equal(media.thumbPath, "legacy/partial-thumb.jpg");
    assert.equal(media.detailPath, undefined);
    const pathParts = uploaded[0].split("/");
    const ledger = db.doc(`brands/brand-a/importJobs/${item.jobID}/executions/${item.executionID}` +
      `/assets/${pathParts[9]}/writes/${pathParts[10]}`);
    assert.equal((await ledger.get()).data().status, "unpublished");
  } finally {
    scope.close();
  }
  assert.equal(pipeline.sourceBuffers.snapshot().retainedBytes, 0);
});

test("PQ06 묶음 runner는 실행권·공유 runtime을 연결하고 재시도는 즉시 총 다섯 회로 제한한다", async () => {
  const receipt = await prepared(request(), [target("runner")]);
  let calls = 0;
  const result = await processImportSeasonsBatch(db, delivery(receipt.batchID),
    "runner-worker", "runner-boot", new AbortController().signal,
    async (context) => {
      calls++;
      assert.equal(context.brandID, "brand-a");
      assert.equal(context.attempt, calls);
      assert.equal(context.attemptLimit, 5);
      assert.equal(context.pipeline.snapshot().transform.limit, 1);
      if (calls < 5) throw new RetryableImportError("transient");
      return {status: "succeeded"};
    }, () => now + calls, () => new QueueSupervisor({
      readMemory: () => ({source: "cgroup-v2", usedBytes: 500,
        limitBytes: 1000}),
    }));
  assert.equal(result.status, "released");
  assert.equal(calls, 5);
  const item = receipt.items[0];
  const execution = db.doc(`brands/brand-a/importJobs/${item.jobID}`)
    .collection("executions").doc(item.executionID);
  assert.equal((await execution.get()).data().status, "succeeded");
  const attempts = await execution.collection("attempts").get();
  assert.equal(attempts.size, 5);
  assert.deepEqual(attempts.docs.map((doc) => doc.data().status),
    ["retryWaiting", "retryWaiting", "retryWaiting", "retryWaiting", "succeeded"]);
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().headBatchID,
    null);
});

test("PQ06 복구 재개는 종료한 항목을 재시도하지 않고 원본 execution 종료를 확인한다", async () => {
  const receipt = await prepared(request({kind: "discoverSeasons"}),
    [target("finished-discovery", {collection: "seasonDiscoveryJobs"})]);
  const token = await claimBatch(db, delivery(receipt.batchID), "old-worker", "old-boot", now);
  const item = receipt.items[0];
  await beginBatchItemAttempt(db, token, {ordinal: 0, jobID: item.jobID, executionID: item.executionID}, now);
  await finishBatchItemAttempt(db, token, {ordinal: 0, jobID: item.jobID,
    executionID: item.executionID, outcome: "succeeded"}, now + 1);
  await beginBatchDrain(db, token, now + 2);
  await finishBatchRun(db, token, {disposition: "recovery", drained: true, inFlight: 0,
    reason: "QUEUE_ENVIRONMENT_SAMPLE-GAP"}, now + 3);
  const ref = batchRef(receipt.batchID);
  const prior = (await ref.get()).data();
  // 운영 복구가 확인한 같은 head를 queued로 되돌린 상태를 재현한다.
  await ref.update({state: "queued", owner: null, dispatchGeneration: prior.dispatchGeneration + 1});
  await db.doc("lookbookImportQueue/main").update({state: "idle", owner: null});
  const result = await processImportSeasonsBatch(db,
    {...delivery(receipt.batchID), dispatchGeneration: prior.dispatchGeneration + 1},
    "new-worker", "new-boot", new AbortController().signal,
    async () => assert.fail("종료한 탐색을 재실행하면 안 됩니다."), () => now + 10,
    () => new QueueSupervisor({readMemory: () => ({source: "cgroup-v2", usedBytes: 500, limitBytes: 1000})}));
  assert.equal(result.status, "released");
  const execution = db.doc(`brands/brand-a/seasonDiscoveryJobs/${item.jobID}/executions/${item.executionID}`);
  assert.equal((await execution.get()).data().attemptCount, 1);
  assert.equal((await execution.get()).data().status, "succeeded");
  assert.equal((await execution.collection("attempts").get()).size, 1);
  assert.equal((await ref.get()).data().items[0].processingStatus, "succeeded");
});

test("PQ06 종료 checkpoint와 실제 execution이 불일치하면 재개 후 차례 반환을 차단한다", async () => {
  const receipt = await prepared(request(), [target("terminal-mismatch")]);
  const ref = batchRef(receipt.batchID), data = (await ref.get()).data();
  await ref.update({items: data.items.map((item) => ({...item, processingStatus: "succeeded"}))});
  const result = await processImportSeasonsBatch(db, delivery(receipt.batchID),
    "worker", "boot", new AbortController().signal,
    async () => assert.fail("종료 checkpoint 항목을 다시 시작하면 안 됩니다."), () => now,
    () => new QueueSupervisor({readMemory: () => ({source: "cgroup-v2", usedBytes: 500, limitBytes: 1000})}));
  assert.equal(result.status, "recoveryRequired");
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().state, "recoveryRequired");
});

test("PQ06 browser 전환은 공유 batch의 원본 재사용 cache를 먼저 비운다", async () => {
  const receipt = await prepared(request(), [target("browser-cache-clear")]);
  const source = Buffer.from("cached-image-original");
  let retainedAfterBrowser = -1;
  let sourceStore;
  const result = await processImportSeasonsBatch(db, delivery(receipt.batchID),
    "browser-cache-worker", "browser-cache-boot", new AbortController().signal,
    async ({pipeline}) => {
      const store = pipeline.sourceBuffers;
      assert.ok(store);
      sourceStore = store;
      const scope = store.openScope();
      scope.retain("https://brand.example/image.jpg",
        "https://brand.example/collection", source);
      assert.equal(store.snapshot().retainedBytes, source.length);
      await browserImageGate.withBrowserWork(async () => {
        retainedAfterBrowser = store.snapshot().retainedBytes;
      });
      scope.close();
      return {status: "succeeded"};
    }, () => now, () => new QueueSupervisor({
      readMemory: () => ({source: "cgroup-v2", usedBytes: 500, limitBytes: 1000}),
    }));
  assert.equal(result.status, "released");
  assert.equal(retainedAfterBrowser, 0);
  assert.equal(sourceStore.snapshot().openScopes, 0);
  assert.equal(sourceStore.snapshot().retainedBytes, 0);
});

test("PQ06 high-memory 시작 표본은 시즌 시도 전에 실행권을 복구 확인으로 멈춘다", async () => {
  const receipt = await prepared(request(), [target("memory-stop")]);
  let calls = 0;
  const result = await processImportSeasonsBatch(db, delivery(receipt.batchID),
    "runner-worker", "runner-boot", new AbortController().signal,
    async () => { calls++; return {status: "succeeded"}; }, () => now,
    () => new QueueSupervisor({readMemory: () => ({source: "cgroup-v2",
      usedBytes: 850, limitBytes: 1000})}));
  assert.equal(result.status, "recoveryRequired");
  assert.equal(calls, 0);
  const item = receipt.items[0];
  const execution = await db.doc(`brands/brand-a/importJobs/${item.jobID}`)
    .collection("executions").doc(item.executionID).get();
  assert.equal(execution.data().attemptCount, 0);
  assert.equal(execution.data().status, "queued");
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().state,
    "recoveryRequired");
});

test("PQ06 목록 탐색 묶음은 실행권을 얻고 공통 runner에서 처리한다", async () => {
  const receipt = await prepared(request({kind: "discoverSeasons"}),
    [target("archive", {collection: "seasonDiscoveryJobs"})]);
  let observedKind = null;
  const result = await processImportSeasonsBatch(db, delivery(receipt.batchID),
    "runner-worker", "runner-boot", new AbortController().signal,
    async ({batchKind}) => {
      observedKind = batchKind;
      return {status: "succeeded"};
    }, () => now, () => new QueueSupervisor({readMemory: () =>
      ({source: "cgroup-v2", usedBytes: 500, limitBytes: 1000})}));
  assert.equal(result.status, "released");
  assert.equal(observedKind, "discoverSeasons");
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().owner ?? null,
    null);
  assert.equal((await batchRef(receipt.batchID).get()).data().state, "released");
});

test("PQ06 시즌 목록 탐색은 batch 차례에서만 활성화하고 brand 실행 포인터를 고정한다", async () => {
  const receipt = await prepared(request({kind: "discoverSeasons"}),
    [target("archive", {collection: "seasonDiscoveryJobs", jobData: {
      status: "queued", generation: 3, dispatchGeneration: 0,
      extractorVersion: "season-discovery-v1",
      extractionContractRevision: 1,
      sourceArchiveURL: "https://brand.example/archive",
    }})]);
  const item = receipt.items[0];
  const ownership = await claimBatch(db, delivery(receipt.batchID),
    "worker", "boot", now);
  const attempt = await beginBatchItemAttempt(db, ownership, {
    ordinal: 0, jobID: item.jobID, executionID: item.executionID,
  }, now);
  await activateQueueItem({firestore: db, brandID: "brand-a", jobID: item.jobID,
    executionID: item.executionID, ordinal: 0, ownership,
    batchKind: "discoverSeasons", mode: attempt.mode,
    continuationInput: attempt.input, now});
  const job = (await db.doc(`brands/brand-a/seasonDiscoveryJobs/${item.jobID}`).get()).data();
  const brand = (await db.doc("brands/brand-a").get()).data();
  assert.equal(job.queueActiveRunID, ownership.runID);
  assert.equal(job.status, "queued");
  assert.equal(brand.activeSeasonDiscoveryJobID, item.jobID);
  assert.equal(brand.activeSeasonDiscoveryGeneration, 3);
});

test("PQ06 알 수 없는 항목 준비 상태는 완료로 건너뛰지 않고 복구 확인으로 남긴다", async () => {
  const receipt = await prepared(request(), [target("bad-admission-status")]);
  const ref = batchRef(receipt.batchID);
  const batch = (await ref.get()).data();
  await ref.update({items: batch.items.map((item, index) => index === 0 ?
    {...item, admissionStatus: "unknown"} : item)});
  const result = await processImportSeasonsBatch(db, delivery(receipt.batchID),
    "runner-worker", "runner-boot", new AbortController().signal,
    async () => { assert.fail("손상된 항목을 실행하면 안 됩니다."); }, () => now,
    () => new QueueSupervisor({readMemory: () => ({source: "cgroup-v2",
      usedBytes: 500, limitBytes: 1000})}));
  assert.equal(result.status, "recoveryRequired");
  assert.equal(result.reason, "QUEUE_ITEM_CORRUPT");
  assert.equal((await batchRef(receipt.batchID).get()).data().state,
    "recoveryRequired");
});

test("PQ06 승인 continuation은 기존 실행 attempt 수를 유지하고 stale epoch checkpoint를 거절한다", async () => {
  const ref = db.doc("brands/brand-a/importJobs/approval-checkpoint");
  await ref.set({jobType: "importSeasonFromURL", sourceURL: "https://brand.example/approval-checkpoint",
    status: "awaitingReview", attemptCount: 2, reviewGeneration: 0,
    reviewSnapshotHash: "hash", reviewCandidateKeys: ["image"]});
  const input = apiRequest({jobID: "approval-checkpoint", reviewGeneration: 0,
    reviewSnapshotHash: "hash", decision: "approved"});
  const receipt = await call(reviewLookbookExtraction, input);
  await prepareNextQueueBatch(db);
  const batch = (await batchRef(receipt.batchID).get()).data();
  const item = batch.items[0];
  const token = await claimBatch(db, delivery(receipt.batchID), "worker", "boot", now);
  const result = await beginBatchItemAttempt(db, token, {
    ordinal: 0, jobID: item.jobID, executionID: item.executionID,
  }, now);
  assert.equal(result.approval, true);
  const execution = ref.collection("executions").doc(item.executionID);
  assert.equal((await execution.get()).data().attemptCount, 2);
  await finishBatchItemAttempt(db, token, {ordinal: 0, jobID: item.jobID,
    executionID: item.executionID, outcome: "succeeded"}, now + 1);
  await beginBatchDrain(db, token, now + 2);
  assert.equal(await finishBatchRun(db, token, finish("complete"), now + 3), "released");
  await advanceReleasedHead(db);
  await assert.rejects(() => beginBatchItemAttempt(db, token, {
    ordinal: 0, jobID: item.jobID, executionID: item.executionID,
  }, now + 4), /QUEUE_OWNERSHIP_LOST/);
  assert.equal((await execution.get()).data().attemptCount, 2);
});

test("KR16 고의 종료 장치는 지정 실행·업로드에 한 번만 소비되고 재전달과 다른 실행을 차단한다", async () => {
  const receipt = await prepared(request(), [target("fault-oom")]);
  const item = receipt.items[0], campaignID = randomUUID();
  const ownership = await claimBatch(db, delivery(receipt.batchID), "worker", "boot", now);
  await beginBatchItemAttempt(db, ownership, {ordinal: 0, jobID: item.jobID, executionID: item.executionID}, now);
  const campaign = db.doc(`lookbookImportQ7FaultCampaigns/${campaignID}`);
  const revision = "lookbook-import-worker-development-00025-test", verificationDigest = "b".repeat(64);
  await campaign.set({projectID: "outpick-test", mode: "q7RetryKL", maxMutations: 8,
    state: "running", startedAt: now, expiresAt: now + 1200000, revision, verificationDigest});
  await campaign.collection("targets").doc(item.executionID).set({campaignID,
    scenario: "oomAfterUpload", batchID: receipt.batchID, ordinal: 0,
    brandID: "brand-a", jobID: item.jobID, executionID: item.executionID, attempt: 1});
  let oomCalls = 0;
  const fault = createDevelopmentRetryFault({firestore: db, projectID: "outpick-test",
    serviceName: "lookbook-import-worker-development", campaignID, revision, verificationDigest,
    now: () => now, oom: () => {oomCalls++; throw new Error("fake-oom");}});
  const context = {ownership, brandID: "brand-a", jobID: item.jobID, executionID: item.executionID, ordinal: 0, attempt: 1};
  await assert.rejects(() => fault.afterUpload(context, {path: "brands/foreign.jpg", generation: "1", size: 3}), /OBJECT_INVALID/);
  const object = {path: `brands/brand-a/seasons/import_${item.jobID}/imports/${item.executionID}/${ownership.epoch}/cover/write/thumb.jpg`, generation: "123", size: 10};
  const outcomes = await Promise.allSettled([fault.afterUpload(context, object), fault.afterUpload(context, object)]);
  assert.equal(outcomes.filter((result) => result.status === "rejected").length, 1);
  assert.equal(oomCalls, 1);
  await fault.afterUpload(context, object);
  assert.equal(oomCalls, 1);
  await assert.rejects(() => fault.afterUpload({...context, jobID: "another-job"}, object), /TARGET_CHANGED/);
  assert.equal((await campaign.collection("targets").doc(item.executionID).get()).data().consumedObject.generation, "123");
});

test("KR17 다운로드 전 제어 실패는 원래 실행의 다섯 시도만 소비하며 만료·다른 revision은 거절한다", async () => {
  const receipt = await prepared(request(), [target("fault-limit")]);
  const item = receipt.items[0], campaignID = randomUUID();
  const ownership = await claimBatch(db, delivery(receipt.batchID), "worker", "boot", now);
  const campaign = db.doc(`lookbookImportQ7FaultCampaigns/${campaignID}`);
  const revision = "lookbook-import-worker-development-00025-test", verificationDigest = "c".repeat(64);
  await campaign.set({projectID: "outpick-test", mode: "q7RetryKL", maxMutations: 8,
    state: "running", startedAt: now, expiresAt: now + 1200000, revision, verificationDigest});
  await campaign.collection("targets").doc(item.executionID).set({campaignID,
    scenario: "retryableBeforeDownload", batchID: receipt.batchID, ordinal: 0,
    brandID: "brand-a", jobID: item.jobID, executionID: item.executionID, attemptLimit: 5});
  const fault = createDevelopmentRetryFault({firestore: db, projectID: "outpick-test",
    serviceName: "lookbook-import-worker-development", campaignID, revision, verificationDigest, now: () => now});
  for (let attempt = 1; attempt <= 5; attempt++) {
    const args = {ordinal: 0, jobID: item.jobID, executionID: item.executionID};
    await beginBatchItemAttempt(db, ownership, args, now);
    const context = {ownership, brandID: "brand-a", ...args, attempt};
    if (attempt === 1) {
      await campaign.update({expiresAt: now});
      await assert.rejects(() => fault.beforeDownload(context), /TARGET_CHANGED/);
      await campaign.update({expiresAt: now + 1200000, revision: "other-revision"});
      await assert.rejects(() => fault.beforeDownload(context), /TARGET_CHANGED/);
      await campaign.update({revision});
      const client = rules.authenticatedContext(uid).firestore();
      await assertFails(client.doc(campaign.path).get());
      await assertFails(client.doc(campaign.path).set({state: "running"}));
    }
    await assert.rejects(() => fault.beforeDownload(context), /CONTROLLED_RETRYABLE_FAILURE/);
    await fault.beforeDownload(context);
    await finishBatchItemAttempt(db, ownership, {...args,
      outcome: attempt < 5 ? "retryWaiting" : "failed", retryAt: now}, now);
  }
  assert.equal(Object.keys((await campaign.collection("targets").doc(item.executionID).get()).data().consumedAttempts).length, 5);
});

test("KR10 종료 증거가 있는 시도만 처음부터 정산하고 완료 시즌과 오회 예산을 유지한다", async () => {
  const receipt = await prepared(request(), [target("terminated"), target("already-finished")]);
  const context = {projectID: "outpick-test", revision: "worker-development-00002-test", traceID: "e".repeat(32)};
  const token = await claimBatch(db, delivery(receipt.batchID), "old-worker", "old-boot", now, undefined, context);
  for (const item of receipt.items) {
    const args = {ordinal: item.ordinal, jobID: item.jobID, executionID: item.executionID};
    const begun = await beginBatchItemAttempt(db, token, args, now);
    await activateQueueItem({firestore: db, brandID: "brand-a", ...args, ownership: token,
      batchKind: "importSeasons", mode: begun.mode, continuationInput: begun.input, now});
  }
  const first = receipt.items[0], second = receipt.items[1];
  await finishBatchItemAttempt(db, token, {ordinal: 1, jobID: second.jobID,
    executionID: second.executionID, outcome: "succeeded"}, now + 1);
  const args = {firestore: db, delivery: delivery(receipt.batchID), projectID: "outpick-test",
    serviceName: "worker-development", now: now + 2};
  await assert.rejects(() => settleTerminatedSeasonRun({...args,
    evidenceProvider: {async findTerminatedInstance() { return null; }}}), /TERMINATION_UNCONFIRMED/);
  assert.equal((await batchRef(receipt.batchID).get()).data().state, "active");
  const proof = {kind: "platformTermination", projectID: "outpick-test", serviceName: "worker-development",
    revision: context.revision, traceID: context.traceID, instanceID: "old-instance",
    timestamp: new Date(now + 1).toISOString(), insertID: "termination-log"};
  await assert.rejects(() => settleTerminatedSeasonRun({...args,
    evidenceProvider: {async findTerminatedInstance() { return {...proof, revision: "wrong-revision"}; }}}), /TERMINATION_UNCONFIRMED/);
  const nextDelivery = await settleTerminatedSeasonRun({...args,
    evidenceProvider: {async findTerminatedInstance() { return proof; }}});
  assert.equal(nextDelivery.dispatchGeneration, 1);
  const root = db.doc(`brands/brand-a/importJobs/${first.jobID}`);
  await assert.rejects(() => updateOwnedJob(root, {ownership: token, ordinal: 0,
    executionID: first.executionID}, {imageCandidates: ["stale"]}), /OWNERSHIP_LOST/);
  assert.equal((await root.collection("executions").doc(first.executionID).get()).data().attemptCount, 1);
  assert.equal((await root.collection("executions").doc(first.executionID).get()).data().restartFromParsing, true);
  assert.equal((await batchRef(receipt.batchID).get()).data().items[1].processingStatus, "succeeded");
  assert.equal((await batchRef(receipt.batchID).collection("runs").doc(token.runID).get()).data().terminalConfirmed, false,
    "플랫폼 종료 증거를 정상 drain 확인으로 바꾸지 않는다");
  const newToken = await claimBatch(db, nextDelivery, "new-worker", "new-boot", now + 3);
  const begun = await beginBatchItemAttempt(db, newToken, {ordinal: 0,
    jobID: first.jobID, executionID: first.executionID}, now + 3);
  assert.equal(begun.attempt, 2);
  assert.equal(begun.attemptLimit, 5);
  assert.equal(begun.input.restartFromParsing, true);
});

test("KR11 종료된 이전 run의 미확정 업로드만 세대 확인 후 정리하고 현재 run 쓰기는 차단한다", async () => {
  const receipt = await prepared(request(), [target("terminated-upload")]);
  const item = receipt.items[0];
  const token = await claimBatch(db, delivery(receipt.batchID), "worker", "boot", now);
  const args = {ordinal: 0, jobID: item.jobID, executionID: item.executionID};
  await beginBatchItemAttempt(db, token, args, now);
  const job = db.doc(`brands/brand-a/importJobs/${item.jobID}`);
  const season = db.doc(`brands/brand-a/seasons/import_${item.jobID}`);
  await season.set({sourceImportJobID: item.jobID});
  await job.update({targetSeasonID: season.id, queueActiveRunID: token.runID});
  const ledger = job.collection("executions").doc(item.executionID).collection("assets").doc("cover").collection("writes").doc("write");
  const priorRun = `${receipt.batchID}-0`;
  await ledger.set({status: "uploading", batchID: receipt.batchID, runID: priorRun,
    targetSeasonPath: season.path, executionID: item.executionID, epoch: 0,
    thumbPath: `${season.path}/imports/${item.executionID}/0/cover/write/cover_thumb.jpg`,
    detailPath: `${season.path}/imports/${item.executionID}/0/cover/write/cover.jpg`, objects: {}});
  let metadataCalls = 0;
  const input = {firestore: db, ownership: token, ...args, now,
    readMetadata: async () => {metadataCalls++; return {generation: "45", size: 10};}};
  await assert.rejects(() => prepareSeasonRestart(input), /UNCONFIRMED_WRITE/);
  assert.equal(metadataCalls, 0);
  await batchRef(receipt.batchID).collection("runs").doc(priorRun).set({
    terminationEvidence: {insertID: "confirmed"}, terminationVerifiedAt: now, settlement: "restartFromParsing"});
  await prepareSeasonRestart(input);
  assert.equal(metadataCalls, 2);
  assert.equal((await ledger.get()).data().status, "unpublished");
  assert.equal((await ledger.get()).data().objects.thumb.generation, "45");
  assert.equal((await season.get()).exists, false);
});

test("KR12 지연 정리는 종료 증거가 있는 고유 경로의 누락 generation을 조회하고 정확한 객체만 지운다", async () => {
  const batchID = "7".repeat(64), runID = `${batchID}-1`;
  const seasonPath = "brands/brand-a/seasons/partial-cleanup";
  const base = `${seasonPath}/imports/execution/1/cover/write`;
  const ledger = db.doc("brands/brand-a/importJobs/job/executions/execution/assets/cover/writes/write");
  await ledger.set({status: "unpublished", cleanupState: "pending", cleanupAfter: now,
    targetPath: seasonPath, targetSeasonPath: seasonPath, batchID, runID, epoch: 1,
    executionID: "execution", thumbPath: `${base}/thumb.jpg`, detailPath: `${base}/detail.jpg`,
    objects: {}, updatedAt: now});
  const metadata = [], deleted = [];
  const bucket = {file: (path, options) => ({getMetadata: async () => {
    metadata.push(path);
    if (path.endsWith("detail.jpg")) throw Object.assign(new Error("missing"), {code: 404});
    return [{generation: "66", size: "12"}];
  }, delete: async () => {deleted.push({path, options});}})};
  const first = await cleanupLookbookAssetWrites({firestore: db, bucket, now: () => now});
  assert.equal(first.protected, 1);
  assert.equal(metadata.length, 0);
  await batchRef(batchID).collection("runs").doc(runID).set({terminationEvidence: {insertID: "log"}, terminationVerifiedAt: now});
  const second = await cleanupLookbookAssetWrites({firestore: db, bucket, now: () => now + 3600001});
  assert.equal(second.deleted, 1);
  assert.equal(second.objectOperations, 3);
  assert.equal(metadata.length, 2);
  assert.equal(deleted[0].options.preconditionOpts.ifGenerationMatch, "66");
  assert.equal((await ledger.get()).data().cleanupState, "completed");
  assert.equal((await ledger.get()).data().objects.detail.absentAtCleanup, true);
});

test("KR19 상세 run이 정리돼도 정확한 종료 감사가 남으면 누락 generation 파일을 정리한다", async () => {
  const batchID = "4".repeat(64), runID = `${batchID}-1`, seasonPath = "brands/brand-a/seasons/audit-cleanup";
  const ledger = db.doc("brands/brand-a/importJobs/job/executions/execution/assets/cover/writes/write");
  await ledger.set({status: "unpublished", cleanupState: "pending", cleanupAfter: now,
    targetPath: seasonPath, targetSeasonPath: seasonPath, batchID, runID, epoch: 1,
    executionID: "execution", thumbPath: `${seasonPath}/imports/execution/1/cover/write/thumb.jpg`,
    detailPath: `${seasonPath}/imports/execution/1/cover/write/detail.jpg`, objects: {}, updatedAt: now});
  const audit = db.doc(`lookbookImportRecoveryAudits/termination-${runID}`);
  await audit.set({action: "automaticTerminationRetry", batchID, runID: "wrong-run",
    evidence: {kind: "platformTermination", projectID: process.env.GCLOUD_PROJECT}, expiresAt: now + 90 * 86400000});
  const deleted = [];
  const bucket = {file: (path, options) => ({getMetadata: async () => [{generation: "70", size: "2"}],
    delete: async () => deleted.push({path, options})})};
  assert.equal((await cleanupLookbookAssetWrites({firestore: db, bucket, now: () => now})).protected, 1);
  assert.equal(deleted.length, 0);
  await audit.update({runID});
  assert.equal((await cleanupLookbookAssetWrites({firestore: db, bucket, now: () => now + 3600001})).deleted, 2);
  assert.deepEqual(deleted.map((value) => value.options.preconditionOpts.ifGenerationMatch), ["70", "70"]);
});

test("KR13 종료된 다섯 번째 시도는 새 시도를 만들지 않고 실패 목록 정산 후 FIFO를 넘긴다", async () => {
  const receipt = await prepared(request(), [target("terminated-final")]);
  const item = receipt.items[0], context = {projectID: "outpick-test", revision: "worker-development-00002-test", traceID: "a".repeat(32)};
  const token = await claimBatch(db, delivery(receipt.batchID), "old-worker", "old-boot", now, undefined, context);
  await beginBatchItemAttempt(db, token, {ordinal: 0, jobID: item.jobID, executionID: item.executionID}, now);
  const job = db.doc(`brands/brand-a/importJobs/${item.jobID}`);
  await job.update({queueActiveRunID: token.runID});
  await job.collection("executions").doc(item.executionID).update({attemptCount: 5});
  const args = {firestore: db, delivery: delivery(receipt.batchID), projectID: "outpick-test", serviceName: "worker-development", now: now + 1,
    evidenceProvider: {async findTerminatedInstance() {return {kind: "platformTermination", ...context,
      serviceName: "worker-development", instanceID: "old", timestamp: new Date(now + 1).toISOString(), insertID: "log"};}}};
  const next = await settleTerminatedSeasonRun(args);
  const result = await processImportSeasonsBatch(db, next, "new", "new-boot", new AbortController().signal,
    async () => assert.fail("여섯 번째 시도를 시작하면 안 됩니다."), () => now + 2,
    () => new QueueSupervisor({readMemory: () => ({source: "cgroup-v2", usedBytes: 500, limitBytes: 1000})}));
  assert.equal(result.status, "released");
  const failure = (await db.doc(`brands/brand-a/seasonImportFailures/${seasonImportFailureID("https://brand.example/terminated-final")}`).get()).data();
  assert.equal(failure.attemptCount, 5);
  assert.equal(failure.state, "failed");
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().headBatchID, null);
});

test("KR14 시즌 등록은 종료 증거가 있어도 이전 중간 재개 API로 저장 상태를 복원하지 않는다", async () => {
  const batchID = "6".repeat(64), epoch = 1, runID = `${batchID}-${epoch}`;
  const revision = "worker-development-00001-test", traceID = "f".repeat(32);
  const target = {projectID: "outpick-test", serviceName: "worker-development", revision, batchID, expectedEpoch: epoch};
  await db.doc("lookbookImportQueue/main").set({headBatchID: batchID, state: "recoveryRequired", owner: "old", epoch, runID});
  await batchRef(batchID).set({kind: "importSeasons", brandID: "brand-a", state: "recoveryRequired", stateRevision: 2, epoch, runID, items: []});
  await batchRef(batchID).collection("runs").doc(runID).set({runID, epoch, revision, traceID, startedAt: now});
  const provider = {async findTerminatedInstance(input) {return {kind: "platformTermination", ...input,
    instanceID: "old", timestamp: new Date(now + 1).toISOString(), insertID: "log"};}};
  const report = await inspectQueueRecovery({firestore: db, evidenceProvider: provider, target,
    projectID: "outpick-test", serviceName: target.serviceName, revision});
  assert.equal(report.canResume, false);
  assert.ok(report.blockers.includes("SEASON_RESTART_FROM_PARSING_REQUIRED"));
});

test("KR07 처음부터 재시도는 이번 부분 시즌만 정리하고 참조 해제 파일의 지연 정리를 남긴다", async () => {
  const receipt = await prepared(request(), [target("restart")]);
  const item = receipt.items[0];
  const token = await claimBatch(db, delivery(receipt.batchID), "worker", "boot", now);
  const attemptInput = {ordinal: 0, jobID: item.jobID, executionID: item.executionID};
  await beginBatchItemAttempt(db, token, attemptInput, now);
  const jobRef = db.doc(`brands/brand-a/importJobs/${item.jobID}`);
  const season = db.doc(`brands/brand-a/seasons/import_${item.jobID}`);
  await season.set({sourceImportJobID: item.jobID, likeCount: 0});
  await season.collection("posts").doc("post_0000").set({sourceImportJobID: item.jobID, metrics: {commentCount: 0}});
  await jobRef.update({targetSeasonID: season.id, createdPostIDs: ["post_0000"],
    queueActiveRunID: token.runID, imageCandidates: ["old"], approvedCandidateKeys: ["old"], reviewGeneration: 2});
  const ledger = jobRef.collection("executions").doc(item.executionID)
    .collection("assets").doc("asset").collection("writes").doc("write");
  await ledger.set({status: "published", targetSeasonPath: season.path,
    executionID: item.executionID, epoch: token.epoch,
    thumbPath: `${season.path}/imports/${item.executionID}/${token.epoch}/cover/write/cover_thumb.jpg`,
    detailPath: `${season.path}/imports/${item.executionID}/${token.epoch}/cover/write/cover.jpg`,
    objects: {thumb: {generation: "123", size: 10}, detail: {generation: "124", size: 20}}});
  await db.doc("brands/brand-a/seasons/completed").set({status: "published", sourceImportJobID: "completed-job"});
  await finishBatchItemAttempt(db, token, {...attemptInput, outcome: "retryWaiting", retryAt: now + 1}, now + 1);
  await prepareSeasonRestart({firestore: db, ownership: token, ...attemptInput, forNextAttempt: true, now: now + 1});
  assert.equal((await season.get()).exists, false);
  assert.equal((await season.collection("posts").get()).size, 0);
  assert.equal((await db.doc("brands/brand-a/seasons/completed").get()).exists, true);
  assert.equal((await ledger.get()).data().status, "unpublished");
  assert.equal((await ledger.get()).data().cleanupAfter, now + 1 + 86400000);
  const job = (await jobRef.get()).data();
  assert.equal(job.resumeFrom, "parsing");
  assert.deepEqual(job.approvedCandidateKeys, []);
  assert.deepEqual(job.createdPostIDs, []);
  const next = await beginBatchItemAttempt(db, token, attemptInput, now + 2);
  assert.equal(next.attempt, 2);
  assert.equal(next.input.restartFromParsing, true);
});

test("KR07 다른 등록이나 사용자 변경이 있는 부분 결과는 삭제하지 않고 재시도를 차단한다", async () => {
  const receipt = await prepared(request(), [target("protected-restart")]);
  const item = receipt.items[0];
  const token = await claimBatch(db, delivery(receipt.batchID), "worker", "boot", now);
  const attemptInput = {ordinal: 0, jobID: item.jobID, executionID: item.executionID};
  await beginBatchItemAttempt(db, token, attemptInput, now);
  const jobRef = db.doc(`brands/brand-a/importJobs/${item.jobID}`);
  const season = db.doc(`brands/brand-a/seasons/import_${item.jobID}`);
  await season.set({sourceImportJobID: item.jobID});
  await season.collection("posts").doc("post_0000").set({sourceImportJobID: item.jobID, metrics: {commentCount: 1}});
  await jobRef.update({targetSeasonID: season.id, queueActiveRunID: token.runID});
  await assert.rejects(() => prepareSeasonRestart({firestore: db, ownership: token,
    ...attemptInput, now}), /QUEUE_RESTART_TARGET_CHANGED/);
  assert.equal((await season.get()).exists, true);
  await season.update({sourceImportJobID: "other-job"});
  await assert.rejects(() => prepareSeasonRestart({firestore: db, ownership: token,
    ...attemptInput, now}), /QUEUE_RESTART_FOREIGN_SEASON/);
});

test("KR09 승인 저장 실패의 새 추출은 기존 예산에서 다음 시도로 시작하고 이전 승인을 지운다", async () => {
  const ref = db.doc("brands/brand-a/importJobs/approval-restart");
  await ref.set({jobType: "importSeasonFromURL", sourceURL: "https://brand.example/approval-restart",
    status: "awaitingReview", attemptCount: 2, reviewGeneration: 0,
    reviewSnapshotHash: "old-hash", reviewCandidateKeys: ["old-image"]});
  const receipt = await call(reviewLookbookExtraction, apiRequest({jobID: ref.id,
    reviewGeneration: 0, reviewSnapshotHash: "old-hash", decision: "approved"}));
  await prepareNextQueueBatch(db);
  const item = (await batchRef(receipt.batchID).get()).data().items[0];
  const executionRef = ref.collection("executions").doc(item.executionID);
  await executionRef.collection("attempts").doc("00002").set({status: "awaitingReview", attempt: 2});
  const token = await claimBatch(db, delivery(receipt.batchID), "worker", "boot", now);
  const attemptInput = {ordinal: 0, jobID: item.jobID, executionID: item.executionID};
  const first = await beginBatchItemAttempt(db, token, attemptInput, now);
  await activateQueueItem({firestore: db, brandID: "brand-a", ...attemptInput,
    ownership: token, batchKind: "reviewApproval", mode: first.mode, continuationInput: first.input, now});
  await finishBatchItemAttempt(db, token, {...attemptInput, outcome: "retryWaiting",
    retryAt: now + 1, errorCode: "STORAGE_ERROR"}, now + 1);
  assert.equal((await executionRef.collection("attempts").doc("00002").get()).data().status, "retryWaiting");
  await prepareSeasonRestart({firestore: db, ownership: token, ...attemptInput,
    forNextAttempt: true, now: now + 1});
  const next = await beginBatchItemAttempt(db, token, attemptInput, now + 2);
  assert.equal(next.attempt, 3);
  assert.equal(next.approval, false);
  assert.equal(next.input.restartFromParsing, true);
  await activateQueueItem({firestore: db, brandID: "brand-a", ...attemptInput,
    ownership: token, batchKind: "reviewApproval", mode: next.mode, continuationInput: next.input, now: now + 2});
  const root = (await ref.get()).data();
  assert.deepEqual(root.approvedCandidateKeys, []);
  assert.equal(root.resumeFrom, "parsing");
  assert.equal(root.reviewSnapshotHash, null);
  assert.equal((await executionRef.get()).data().attemptLimit, 5);
});

test("KR08 다섯 회 모두 실패하면 실패 목록을 남기고 다른 시즌과 다음 순번을 진행한다", async () => {
  const receipt = await prepared(request(), [target("fail-five"), target("succeed")]);
  let calls = 0;
  const result = await processImportSeasonsBatch(db, delivery(receipt.batchID),
    "worker", "boot", new AbortController().signal,
    async (context) => {
      if (context.item.ordinal === 0) {
        calls++;
        throw new RetryableImportError("transient");
      }
      return {status: "succeeded"};
    }, () => now, () => new QueueSupervisor({readMemory: () =>
      ({source: "cgroup-v2", usedBytes: 500, limitBytes: 1000})}));
  assert.equal(result.status, "released");
  assert.equal(calls, 5);
  const batch = (await batchRef(receipt.batchID).get()).data();
  assert.equal(batch.items[0].processingStatus, "failed");
  assert.equal(batch.items[1].processingStatus, "succeeded");
  const failureID = seasonImportFailureID("https://brand.example/fail-five");
  const failure = (await db.doc(`brands/brand-a/seasonImportFailures/${failureID}`).get()).data();
  assert.equal(failure.attemptCount, 5);
  assert.equal(failure.state, "failed");
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().headBatchID, null);
});

async function failedSeasonFixture(executionID = "failed-execution", version = 1) {
  const sourceURL = "https://brand.example/failed-season?season=2026ss";
  const failureID = seasonImportFailureID(sourceURL);
  const originalBatchID = "9".repeat(64);
  const jobID = "failed-job";
  const job = db.doc(`brands/brand-a/importJobs/${jobID}`);
  const failure = db.doc(`brands/brand-a/seasonImportFailures/${failureID}`);
  await job.set({jobType: "importSeasonFromURL", sourceURL, status: "failed",
    reviewGeneration: 2, queueExecutionID: executionID, queueBatchID: originalBatchID});
  await job.collection("executions").doc(executionID).set({status: "failed",
    attemptCount: 5, attemptLimit: 5, activeRunID: null, activeAttemptID: null});
  await batchRef(originalBatchID).set({state: "released"});
  await db.doc(`brands/brand-a/queueSourceClaims/${failureID}`).set({
    jobID, executionID, batchID: originalBatchID});
  await failure.set({sourceURL, state: "failed", version, displayTitle: "2026 SS",
    latestRequestID: "original-request", latestBatchID: originalBatchID,
    latestJobID: jobID, latestExecutionID: executionID, attemptCount: 5,
    attemptLimit: 5, errorCode: "ATTEMPTS_EXHAUSTED", updatedAt: now,
    expiresAt: now + 30 * 86400000, privateEvidence: "must-not-be-returned"});
  return {job, failure, sourceURL, failureID, originalBatchID,
    input: {queueContractVersion: 1, requestID: randomUUID(), requestCreatedAt: now,
      brandID: "brand-a", failureID, expectedVersion: version, expectedExecutionID: executionID}};
}

test("KR05 Worker 재실패는 같은 목록을 최신화하고 새 실행 성공만 제거한다", async () => {
  const receipt = await prepared(request(), [target("failure-record")]);
  const item = receipt.items[0];
  const token = await claimBatch(db, delivery(receipt.batchID), "worker", "boot", now);
  const attemptInput = {ordinal: 0, jobID: item.jobID, executionID: item.executionID};
  await beginBatchItemAttempt(db, token, attemptInput, now);
  await finishBatchItemAttempt(db, token, {...attemptInput, outcome: "failed", errorCode: "FIRST"}, now + 1);
  const failureID = seasonImportFailureID("https://brand.example/failure-record");
  const ref = db.doc(`brands/brand-a/seasonImportFailures/${failureID}`);
  assert.equal((await ref.get()).data().errorCode, "FIRST");
  const executionRef = db.doc(`brands/brand-a/importJobs/${item.jobID}/executions/${item.executionID}`);
  // 같은 실행의 다음 시도를 checkpoint로 재현한다. 실제 재시도 연결은 별도 gate다.
  await executionRef.update({status: "retryWaiting", retryAt: now + 2});
  await beginBatchItemAttempt(db, token, attemptInput, now + 2);
  await finishBatchItemAttempt(db, token, {...attemptInput, outcome: "failed", errorCode: "SECOND"}, now + 3);
  const latest = (await ref.get()).data();
  assert.equal(latest.errorCode, "SECOND");
  assert.equal(latest.attemptCount, 2);
  assert.equal(latest.version, 3);
  assert.equal(latest.latestBatchID, receipt.batchID);
  assert.equal((await db.collection("brands/brand-a/seasonImportFailures").get()).size, 1);
  await executionRef.update({status: "retryWaiting", retryAt: now + 4});
  await beginBatchItemAttempt(db, token, attemptInput, now + 4);
  await finishBatchItemAttempt(db, token, {...attemptInput, outcome: "succeeded"}, now + 5);
  assert.equal((await ref.get()).exists, false);
  await beginBatchDrain(db, token, now + 6);
  await finishBatchRun(db, token, finish("complete"), now + 7);
  const newer = await prepared(request(), [target("newer")]);
  await ref.set({state: "failed", version: 1, latestExecutionID: newer.items[0].executionID});
  await assert.rejects(() => finishBatchItemAttempt(db, token,
    {...attemptInput, outcome: "succeeded"}, now + 8), /QUEUE_OWNERSHIP_LOST/);
  assert.equal((await ref.get()).data().latestExecutionID, newer.items[0].executionID);
});

test("KR05 명시적 안 함 이후 같은 실행의 늦은 실패가 목록을 되살리지 않는다", async () => {
  const receipt = await prepared(request(), [target("dismissed-failure")]);
  const item = receipt.items[0];
  const token = await claimBatch(db, delivery(receipt.batchID), "worker", "boot", now);
  const attemptInput = {ordinal: 0, jobID: item.jobID, executionID: item.executionID};
  await beginBatchItemAttempt(db, token, attemptInput, now);
  const failureID = seasonImportFailureID("https://brand.example/dismissed-failure");
  await db.doc(`brands/brand-a/importJobs/${item.jobID}/executions/${item.executionID}`)
    .update({dismissedFailureID: failureID});
  await finishBatchItemAttempt(db, token, {...attemptInput, outcome: "failed"}, now + 1);
  assert.equal((await db.doc(`brands/brand-a/seasonImportFailures/${failureID}`).get()).exists, false);
});

test("KR02 실패 시즌 수동 접수는 맨뒤 새 오회 실행 하나와 같은 실패 문서를 원자적으로 갱신한다", async () => {
  const fixture = await failedSeasonFixture();
  await db.doc("lookbookImportQueue/main").set({nextSequence: 8,
    preparationSequence: 8, state: "idle", headBatchID: "older-head"});
  const results = await Promise.all([
    admitSeasonImportFailureRetry(db, uid, fixture.input, now),
    admitSeasonImportFailureRetry(otherDB, uid, fixture.input, now),
  ]);
  assert.equal(results[0].batchID, results[1].batchID);
  const batch = (await batchRef(results[0].batchID).get()).data();
  assert.equal(batch.sequence, 8);
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().nextSequence, 9);
  assert.equal((await db.collection("brands/brand-a/seasonImportFailures").get()).size, 1);
  const failure = (await fixture.failure.get()).data();
  assert.equal(failure.state, "retryQueued");
  assert.equal(failure.version, 2);
  assert.equal(failure.attemptCount, 0);
  assert.equal((await fixture.job.collection("executions").doc("failed-execution").get()).data().attemptCount, 5);
  const owner = "preparation-owner";
  assert.equal(await beginQueuePreparation(db, results[0].batchID, owner, now), true);
  const item = await prepareQueueItem(db, results[0].batchID, 0, owner, now);
  await finishQueuePreparation(db, results[0].batchID, owner, now);
  assert.equal(item.executionID, failure.latestExecutionID);
  const execution = (await fixture.job.collection("executions").doc(item.executionID).get()).data();
  assert.equal(execution.attemptCount, 0);
  assert.equal(execution.attemptLimit, 5);
  const continuation = (await fixture.job.collection("executions").doc(item.executionID)
    .collection("continuations").doc(results[0].batchID).get()).data();
  assert.equal(continuation.input.resumeFrom, "parsing");
  assert.equal(continuation.input.failureRetry, true);
});

test("KR02 다른 요청의 동시 수동 재시도는 한 번만 접수하고 권한 회수 후 재전송도 거절한다", async () => {
  const fixture = await failedSeasonFixture();
  const results = await Promise.allSettled([
    admitSeasonImportFailureRetry(db, uid, fixture.input, now),
    admitSeasonImportFailureRetry(otherDB, uid, {...fixture.input, requestID: randomUUID()}, now),
  ]);
  assert.equal(results.filter((value) => value.status === "fulfilled").length, 1);
  assert.equal((await db.collection("lookbookImportBatches").get()).size, 2);
  await db.doc(`platformAdmins/${uid}`).update({isActive: false});
  await assert.rejects(() => admitSeasonImportFailureRetry(db, uid, fixture.input, now), /PERMISSION_DENIED/);
});

test("KR03 재시도 안 함은 목록만 제거하고 같은 요청 재전송이 새 실패 문서를 지우지 않는다", async () => {
  const fixture = await failedSeasonFixture();
  await dismissSeasonImportFailure(db, uid, fixture.input, now);
  assert.equal((await fixture.failure.get()).exists, false);
  assert.equal((await fixture.job.get()).exists, true);
  assert.equal((await fixture.job.collection("executions").doc("failed-execution").get()).exists, true);
  await fixture.failure.set({state: "failed", version: 1, latestExecutionID: "new-execution"});
  await dismissSeasonImportFailure(otherDB, uid, fixture.input, now + 1);
  assert.equal((await fixture.failure.get()).data().latestExecutionID, "new-execution");
  await assert.rejects(() => dismissSeasonImportFailure(db, uid,
    {...fixture.input, requestID: randomUUID()}, now), /SNAPSHOT_STALE/);
});

test("KR03 진행 중 최신 실행 불일치와 오래된 version은 목록 제거를 거절한다", async () => {
  const fixture = await failedSeasonFixture();
  await assert.rejects(() => dismissSeasonImportFailure(db, uid,
    {...fixture.input, expectedVersion: 2}, now), /SNAPSHOT_STALE/);
  await fixture.failure.update({state: "retrying"});
  await assert.rejects(() => dismissSeasonImportFailure(db, uid, fixture.input, now), /SNAPSHOT_STALE/);
  await fixture.failure.update({state: "failed"});
  await fixture.job.collection("executions").doc("failed-execution").update({activeRunID: "still-running"});
  await assert.rejects(() => dismissSeasonImportFailure(db, uid, fixture.input, now), /SNAPSHOT_STALE/);
  assert.equal((await fixture.failure.get()).exists, true);
});

test("KR03 목록 제거와 수동 접수 경합은 하나만 적용하고 실패 문서를 잃지 않는다", async () => {
  const fixture = await failedSeasonFixture();
  const results = await Promise.allSettled([
    dismissSeasonImportFailure(db, uid, fixture.input, now),
    admitSeasonImportFailureRetry(otherDB, uid, {...fixture.input, requestID: randomUUID()}, now),
  ]);
  assert.equal(results.filter((value) => value.status === "fulfilled").length, 1);
  const failure = (await fixture.failure.get()).data();
  if (failure) assert.equal(failure.state, "retryQueued");
  assert.equal((await fixture.job.collection("executions").doc("failed-execution").get()).exists, true);
});

test("KR06 만료 목록과 안 함 영수증만 정리하고 진행 실행과 원본 실패 기록은 보호한다", async () => {
  const fixture = await failedSeasonFixture();
  await fixture.failure.update({expiresAt: now - 1});
  const actions = db.collection("brands/brand-a/seasonImportFailureActions");
  await actions.doc("expired").set({expiresAt: now - 1});
  await actions.doc("live").set({expiresAt: now + 1});
  const activeJob = db.doc("brands/brand-a/importJobs/active-job");
  await activeJob.collection("executions").doc("active-execution").set({status: "active", activeRunID: "run"});
  const protectedRef = db.doc("brands/brand-a/seasonImportFailures/active");
  await protectedRef.set({state: "failed", expiresAt: now - 1,
    latestJobID: "active-job", latestExecutionID: "active-execution"});
  const counts = await cleanupLookbookQueueRecords({firestore: db, now: () => now});
  assert.equal(counts.failed, 0);
  assert.equal((await fixture.failure.get()).exists, false);
  assert.equal((await actions.doc("expired").get()).exists, false);
  assert.equal((await actions.doc("live").get()).exists, true);
  assert.equal((await protectedRef.get()).exists, true);
  assert.equal((await fixture.job.collection("executions").doc("failed-execution").get()).exists, true);
  assert.ok(counts.changed <= 500);
});

test("KR04 실패 목록은 관리자만 조회하고 동률 페이지 중복과 내부 증거 노출이 없다", async () => {
  const fixture = await failedSeasonFixture();
  const batch = db.batch();
  for (let i = 0; i < 104; i++) {
    const sourceURL = `https://brand.example/paging-${i}`;
    batch.set(db.doc(`brands/brand-a/seasonImportFailures/${seasonImportFailureID(sourceURL)}`), {
      sourceURL, state: "failed", version: 1, updatedAt: now,
      expiresAt: now + 86400000, privateEvidence: "never-expose"});
  }
  await batch.commit();
  const first = await listSeasonImportFailures(db, uid, {brandID: "brand-a"}, now);
  assert.equal(first.items.length, 100);
  assert.ok(first.nextCursor);
  const second = await listSeasonImportFailures(db, uid, {brandID: "brand-a", cursor: first.nextCursor}, now);
  assert.equal(second.items.length, 5);
  assert.equal(new Set([...first.items, ...second.items].map((item) => item.failureID)).size, 105);
  assert.ok([...first.items, ...second.items].every((item) => !("privateEvidence" in item)));
  await assert.rejects(() => listSeasonImportFailures(db, "outsider", {brandID: "brand-a"}, now), /PERMISSION_DENIED/);
  const client = rules.authenticatedContext(uid).firestore();
  await assertFails(client.doc(fixture.failure.path).get());
  await assertFails(client.doc(fixture.failure.path).delete());
});

test("PQ14 복구는 정확한 종료 증거·보고서·epoch를 확인하고 한 번만 재개한다", async () => {
  const recoveryBatchID = "a".repeat(64);
  const epoch = 4;
  const runID = `${recoveryBatchID}-${epoch}`;
  const revision = "lookbook-import-worker-development-00002-test";
  const traceID = "b".repeat(32);
  const stateRevision = 7;
  const batch = db.doc(`lookbookImportBatches/${recoveryBatchID}`);
  const run = batch.collection("runs").doc(runID);
  const write = db.doc("brands/brand-a/importJobs/recovery-job/executions/" +
    "recovery-execution/assets/asset-one/writes/write-one");
  const target = {projectID: "outpick-test",
    serviceName: "lookbook-import-worker-development", revision,
    batchID: recoveryBatchID, expectedEpoch: epoch};
  await db.doc("lookbookImportQueue/main").set({headBatchID: recoveryBatchID,
    state: "recoveryRequired", owner: "old-owner", epoch, runID});
  // 기존 보수용 재개는 유지하되 시즌 등록은 새 계약의 처음부터 재시도만 허용한다.
  await batch.set({kind: "assetRetry", brandID: "brand-a",
    state: "recoveryRequired", stateRevision, epoch, runID,
    dispatchGeneration: 2, items: [{admissionStatus: "created",
      jobID: "recovery-job", executionID: "recovery-execution"}]});
  await run.set({runID, epoch, bootID: "old-boot", revision,
    traceID, startedAt: now, state: "recoveryRequired",
    terminalConfirmed: false, inFlight: 1});
  await write.set({status: "uploading", epoch, executionID: "recovery-execution",
    thumbPath: "brands/brand-a/thumb.jpg", detailPath: "brands/brand-a/detail.jpg"});
  const evidenceProvider = {async findTerminatedInstance(input) {
    return {kind: "platformTermination", ...input,
      instanceID: "platform-instance-123", timestamp: new Date(now + 1).toISOString(),
      insertID: "system-log-1"};
  }};
  const report = await inspectQueueRecovery({firestore: db,
    evidenceProvider, target, projectID: "outpick-test",
    serviceName: target.serviceName, revision});
  assert.equal(report.canResume, true);
  assert.equal(report.uncertainAssetWriteCount, 1);
  assert.equal(report.assetWriteScanComplete, true);
  const decisionID = "11111111-1111-4111-8111-111111111111";
  const resumedAt = now + 2000;
  const result = await resumeQueueRecovery({firestore: db, evidenceProvider,
    target, projectID: "outpick-test", serviceName: target.serviceName,
    revision, reportDigest: report.reportDigest,
    expectedStateRevision: stateRevision, decisionID,
    actorEmail: "lookbook-import-recovery@outpick-test.iam.gserviceaccount.com",
    now: resumedAt});
  assert.deepEqual(result, {accepted: true, batchID: recoveryBatchID,
    decisionID, state: "queued", alreadyApplied: false});
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().state,
    "idle");
  assert.equal((await batch.get()).data().state, "queued");
  assert.equal((await run.get()).data().terminalConfirmed, false,
    "복구 결정을 종료 증거로 덮어쓰지 않는다");
  const recoveredWrite = (await write.get()).data();
  assert.equal(recoveredWrite.status, "unpublished");
  assert.equal(recoveredWrite.cleanupAfter, resumedAt + 86400000);
  const audit = (await batch.collection("recoveryDecisions").doc(decisionID).get()).data();
  assert.equal(audit.reportDigest, report.reportDigest);
  assert.equal(audit.expiresAt, resumedAt + 90 * 86400000);
  assert.equal((await resumeQueueRecovery({firestore: db, evidenceProvider,
    target, projectID: "outpick-test", serviceName: target.serviceName,
    revision, reportDigest: report.reportDigest,
    expectedStateRevision: stateRevision, decisionID,
    actorEmail: "lookbook-import-recovery@outpick-test.iam.gserviceaccount.com",
    now: resumedAt + 1})).alreadyApplied, true);
  await assert.rejects(() => resumeQueueRecovery({firestore: db, evidenceProvider,
    target, projectID: "outpick-test", serviceName: target.serviceName,
    revision, reportDigest: "c".repeat(64),
    expectedStateRevision: stateRevision, decisionID,
    actorEmail: "lookbook-import-recovery@outpick-test.iam.gserviceaccount.com",
    now: resumedAt + 2}), /RECOVERY_DECISION_CONFLICT/);
});

test("PQ14 종료된 correctionRequired 탐색만 원자적으로 정산하고 FIFO를 넘긴다", async () => {
  const batchID = "f".repeat(64);
  const nextBatchID = "e".repeat(64);
  const epoch = 3;
  const runID = `${batchID}-${epoch}`;
  const runRevision = "lookbook-import-worker-development-00018-zon";
  const servingRevision = "lookbook-import-worker-development-00019-new";
  const executionID = "discovery-execution";
  const jobID = "discovery-job";
  const itemID = "discovery-item";
  const stateRevision = 9;
  const batch = db.doc(`lookbookImportBatches/${batchID}`);
  const run = batch.collection("runs").doc(runID);
  const job = db.doc(`brands/brand-a/seasonDiscoveryJobs/${jobID}`);
  const execution = job.collection("executions").doc(executionID);
  const attempt = execution.collection("attempts").doc("00001");
  const continuation = execution.collection("continuations").doc(batchID);
  const target = {projectID: "outpick-test",
    serviceName: "lookbook-import-worker-development",
    revision: runRevision, batchID, expectedEpoch: epoch};
  await db.doc("lookbookImportQueue/main").set({headBatchID: batchID,
    nextSequence: 3, state: "recoveryRequired", owner: "stale-owner",
    epoch, runID});
  await batch.set({kind: "discoverSeasons", brandID: "brand-a", sequence: 1,
    state: "recoveryRequired", stateRevision, epoch, runID,
    dispatchGeneration: 1, items: [{itemID, admissionStatus: "created",
      processingStatus: "recoveryRequired", attemptCount: 1,
      jobID, executionID, activeRunID: null}]});
  await run.set({runID, epoch, revision: runRevision, state: "recoveryRequired",
    terminalConfirmed: true, inFlight: 0});
  await job.set({status: "correctionRequired", phase: "completed",
    queueBatchID: batchID, queueExecutionID: executionID,
    completedAt: new Date(now)});
  await execution.set({batchID, itemID, status: "recoveryRequired",
    attemptCount: 1, attemptLimit: 3, activeRunID: null, activeAttemptID: null});
  await attempt.set({batchID, runID, epoch, attempt: 1,
    status: "recoveryRequired", endedAt: now});
  await continuation.set({batchID, status: "recoveryRequired"});
  await batchRef(nextBatchID).set({sequence: 2, state: "queued",
    preparationOwner: null});
  const evidenceProvider = {async findTerminatedInstance() { return null; }};
  const report = await inspectQueueRecovery({firestore: db, evidenceProvider,
    target, projectID: "outpick-test", serviceName: target.serviceName,
    revision: servingRevision});
  assert.equal(report.canResume, false,
    "이미 끝난 correctionRequired job을 재실행하지 않는다");
  assert.ok(report.blockers.includes("TERMINAL_OUTCOME_REQUIRES_SETTLEMENT"));
  assert.equal(report.terminalOutcome, "correctionRequired");
  assert.equal(report.canSettleCorrection, true,
    "새 revision은 이전 run의 기록된 revision을 정확히 대조할 수 있다");
  assert.deepEqual(report.settlementBlockers, []);
  const decisionID = "33333333-3333-4333-8333-333333333333";
  await assert.rejects(() => resumeQueueRecovery({firestore: db, evidenceProvider,
    target, projectID: "outpick-test", serviceName: target.serviceName,
    revision: servingRevision, reportDigest: report.reportDigest,
    expectedStateRevision: stateRevision, decisionID,
    actorEmail: "lookbook-import-recovery@outpick-test.iam.gserviceaccount.com",
    now: now + 10}), /RECOVERY_REPORT_STALE_OR_BLOCKED/);
  const result = await settleCorrectionQueueRecovery({firestore: db,
    evidenceProvider, target, projectID: "outpick-test",
    serviceName: target.serviceName, revision: servingRevision,
    reportDigest: report.reportDigest, expectedStateRevision: stateRevision,
    decisionID, actorEmail:
      "lookbook-import-recovery@outpick-test.iam.gserviceaccount.com", now: now + 20});
  assert.deepEqual(result, {accepted: true, batchID, decisionID,
    state: "released", outcome: "correctionRequired", alreadyApplied: false});
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().state,
    "idle");
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().headBatchID,
    batchID, "head는 정상 release trigger가 전진시키도록 보존한다");
  assert.equal((await batch.get()).data().state, "released");
  assert.equal((await batch.get()).data().items[0].processingStatus,
    "correctionRequired");
  assert.equal((await execution.get()).data().status, "correctionRequired");
  assert.equal((await attempt.get()).data().status, "correctionRequired");
  assert.equal((await continuation.get()).data().status, "correctionRequired");
  assert.equal((await job.get()).data().status, "correctionRequired",
    "원본 결과를 성공이나 다른 도메인 상태로 바꾸지 않는다");
  assert.equal((await run.get()).data().terminalConfirmed, true,
    "실제 종료 증거는 변경하지 않는다");
  const audit = (await batch.collection("recoveryDecisions").doc(decisionID).get()).data();
  assert.equal(audit.decision, "settleCorrectionRequired");
  assert.equal(audit.servingRevision, servingRevision);
  assert.equal(audit.revision, runRevision);
  assert.equal(audit.expiresAt, now + 20 + 90 * 86400000);
  assert.equal(await advanceReleasedHead(db), nextBatchID);
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().headBatchID,
    nextBatchID);
  assert.equal((await settleCorrectionQueueRecovery({firestore: db,
    evidenceProvider, target, projectID: "outpick-test",
    serviceName: target.serviceName, revision: servingRevision,
    reportDigest: report.reportDigest, expectedStateRevision: stateRevision,
    decisionID, actorEmail:
      "lookbook-import-recovery@outpick-test.iam.gserviceaccount.com", now: now + 21,
  })).alreadyApplied, true);
});

test("PQ14 실행 미종료나 다른 도메인 상태에서는 correction 정산을 거부한다", async () => {
  const batchID = "c".repeat(64);
  const epoch = 2;
  const runID = `${batchID}-${epoch}`;
  const revision = "lookbook-import-worker-development-00002-test";
  const target = {projectID: "outpick-test",
    serviceName: "lookbook-import-worker-development", revision,
    batchID, expectedEpoch: epoch};
  const batch = db.doc(`lookbookImportBatches/${batchID}`);
  const jobID = "not-terminal-job";
  const executionID = "not-terminal-execution";
  await db.doc("lookbookImportQueue/main").set({headBatchID: batchID,
    state: "recoveryRequired", owner: "old-owner", epoch, runID});
  await batch.set({kind: "discoverSeasons", brandID: "brand-a",
    state: "recoveryRequired", stateRevision: 2, epoch, runID,
    items: [{itemID: "item", admissionStatus: "created",
      processingStatus: "recoveryRequired", attemptCount: 1,
      jobID, executionID, activeRunID: null}]});
  await batch.collection("runs").doc(runID).set({runID, epoch, revision,
    state: "recoveryRequired", terminalConfirmed: false, inFlight: 1});
  const job = db.doc(`brands/brand-a/seasonDiscoveryJobs/${jobID}`);
  await job.set({status: "awaitingReview", phase: "completed",
    queueBatchID: batchID, queueExecutionID: executionID});
  const execution = job.collection("executions").doc(executionID);
  await execution.set({batchID, itemID: "item", status: "recoveryRequired",
    attemptCount: 1, activeRunID: null, activeAttemptID: null});
  await execution.collection("attempts").doc("00001").set({batchID, runID,
    epoch, status: "recoveryRequired"});
  const evidenceProvider = {async findTerminatedInstance() { return null; }};
  const report = await inspectQueueRecovery({firestore: db, evidenceProvider,
    target, projectID: "outpick-test", serviceName: target.serviceName, revision});
  assert.equal(report.canSettleCorrection, false);
  assert.ok(report.settlementBlockers.includes("INSTANCE_TERMINATION_NOT_PROVEN"));
  assert.ok(report.settlementBlockers.includes("DOMAIN_OUTCOME_NOT_TERMINAL_CORRECTION"));
  await assert.rejects(() => settleCorrectionQueueRecovery({firestore: db,
    evidenceProvider, target, projectID: "outpick-test",
    serviceName: target.serviceName, revision,
    reportDigest: report.reportDigest, expectedStateRevision: report.stateRevision,
    decisionID: "44444444-4444-4444-8444-444444444444",
    actorEmail: "lookbook-import-recovery@outpick-test.iam.gserviceaccount.com",
    now: now + 1}), /RECOVERY_REPORT_STALE_OR_BLOCKED/);
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().state,
    "recoveryRequired");
  assert.equal((await batch.get()).data().state, "recoveryRequired");
});

test("PQ14 종료 증거가 없거나 다른 revision이면 recoveryRequired를 유지한다", async () => {
  const batchID = "d".repeat(64);
  const epoch = 2;
  const runID = `${batchID}-${epoch}`;
  const batch = db.doc(`lookbookImportBatches/${batchID}`);
  const target = {projectID: "outpick-test",
    serviceName: "lookbook-import-worker-development",
    revision: "lookbook-import-worker-development-00002-test",
    batchID, expectedEpoch: epoch};
  await db.doc("lookbookImportQueue/main").set({headBatchID: batchID,
    state: "recoveryRequired", owner: "old-owner", epoch, runID});
  await batch.set({kind: "importSeasons", brandID: "brand-a",
    state: "recoveryRequired", stateRevision: 3, epoch, runID,
    items: []});
  await batch.collection("runs").doc(runID).set({runID, epoch,
    bootID: "old-boot", revision: target.revision,
    traceID: "e".repeat(32), startedAt: now,
    terminalConfirmed: false, inFlight: 1});
  const report = await inspectQueueRecovery({firestore: db,
    evidenceProvider: {async findTerminatedInstance(input) {
      return {kind: "platformTermination", ...input,
        revision: "other-revision", instanceID: "wrong-instance",
        timestamp: new Date(now + 1).toISOString(), insertID: "log"};
    }}, target, projectID: "outpick-test",
    serviceName: target.serviceName, revision: target.revision});
  assert.equal(report.canResume, false);
  assert.ok(report.blockers.includes("INSTANCE_TERMINATION_NOT_PROVEN"));
  assert.equal((await db.doc("lookbookImportQueue/main").get()).data().state,
    "recoveryRequired");
});

test("PQ14 환경이 다른 inspect는 queue와 Cloud Logging을 조회하지 않는다", async () => {
  let evidenceCalls = 0;
  const target = {projectID: "another-project",
    serviceName: "lookbook-import-worker-development",
    revision: "lookbook-import-worker-development-00002-test",
    batchID: "a".repeat(64), expectedEpoch: 1};
  const report = await inspectQueueRecovery({firestore: db, target,
    projectID: "outpick-test", serviceName: target.serviceName,
    revision: target.revision, evidenceProvider: {async findTerminatedInstance() {
      evidenceCalls++;
      return null;
    }}});
  assert.equal(report.canResume, false);
  assert.deepEqual(report.blockers, ["TARGET_ENVIRONMENT_MISMATCH"]);
  assert.equal(report.queueState, "notInspected");
  assert.equal(evidenceCalls, 0);
});
