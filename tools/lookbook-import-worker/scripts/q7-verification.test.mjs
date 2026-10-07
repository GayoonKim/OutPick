import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {mkdir, mkdtemp, readFile, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";
import sharp from "sharp";
import {openQ7Campaign, openQ7Journal} from "./q7-journal.mjs";
import {readQ7StorageOutput, q7PublishedCoverReference} from "./q7-storage-evidence.mjs";
import {assertQ7DevelopmentSnapshot} from "./q7-development-preflight.mjs";
import {waitQ7Receipt} from "./q7-receipts.mjs";
import {createQ7Callable} from "./q7-callable.mjs";
import {makePlan, fixture} from "./queue-development-contract.mjs";
import {startQ7Session} from "./q7-session.mjs";

test("QV01 Firebase config은 Development project와 필수 public 필드만 허용한다", async () => {
  await assert.rejects(startQ7Session({}),
    /Q7_FIREBASE_CONFIG_REQUIRED/);
});

test("QV01 로그인 화면은 메모리 인증과 고정 SDK를 사용하고 토큰을 저장하지 않는다", async () => {
  const html = await readFile(new URL("./q7-login.html", import.meta.url), "utf8");
  const js = await readFile(new URL("./q7-login.js", import.meta.url), "utf8");
  assert.match(html, /__Q7_CONFIG__/);
  assert.match(js, /firebasejs\/12\.19\.0/);
  assert.match(js, /inMemoryPersistence/);
  assert.doesNotMatch(js, /localStorage|sessionStorage|indexedDB/);
});

test("QV02 journal은 요청을 전송 전에 원자 기록하고 재사용 ID를 거부한다", async () => {
  const directory = await mkdtemp(join(tmpdir(), "outpick-q7-journal-"));
  const store = await openQ7Journal(directory, "run-12345678", {projectID: "outpick-test"});
  try {
    await assert.rejects(store.appendRequest({requestID: "secret-request",
      payload: {name: "test", idToken: "never-store-this"}}),
    /Q7_JOURNAL_SECRET_REJECTED/);
    const request = await store.appendRequest({requestID: "request-1",
      requestCreatedAt: 123, callable: "createBrand", payload: {name: "test"}});
    assert.equal(request.state, "prepared");
    assert.equal(request.payloadDigest.length, 64);
    await assert.rejects(store.appendRequest({requestID: "request-1",
      payload: {}}), /Q7_DUPLICATE_REQUEST_ID/);
    await store.updateRequest("request-1", {state: "uncertain"});
    const onDisk = await readFile(store.path, "utf8");
    assert.doesNotMatch(onDisk, /never-store-this/);
    assert.equal(JSON.parse(onDisk).requests[0].state, "uncertain");
    await assert.rejects(openQ7Journal(directory, "run-12345678", {}),
      /Q7_RUN_ALREADY_LOCKED/);
  } finally {
    await store.close();
    await rm(directory, {recursive: true, force: true});
  }
});

test("QV02 campaign은 동시 실행·같은 단계 재실행·미해결 원격 쓰기를 차단한다", async () => {
  const directory = await mkdtemp(join(tmpdir(), "outpick-q7-campaign-"));
  try {
    const active = await openQ7Campaign(directory, "smoke");
    await assert.rejects(openQ7Campaign(directory, "smoke"), /Q7_CAMPAIGN_ALREADY_LOCKED/);
    await active.close();

    const runID = "run-12345678";
    const runDirectory = join(directory, runID);
    await mkdir(runDirectory);
    await writeFile(join(runDirectory, runID + ".json"), JSON.stringify({
      runID, status: "stopped", requests: [{requestID: "r1", state: "uncertain"}],
    }));
    await writeFile(join(runDirectory, "report.json"), JSON.stringify({stage: "smoke", status: "stopped"}));
    await assert.rejects(openQ7Campaign(directory, "smoke"),
      /Q7_UNRESOLVED_PRIOR_RUN:run-12345678/);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test("QV02 campaign은 원격 부작용 없음이 증거 digest와 함께 조정된 거절만 종결한다", async () => {
  const directory = await mkdtemp(join(tmpdir(), "outpick-q7-reconcile-"));
  const runID = "run-12345678";
  const runDirectory = join(directory, runID);
  const evidenceFile = "evidence/no-mutation-reconciliation.json";
  const evidencePath = join(runDirectory, evidenceFile);
  const request = {requestID: "request-1", callable: "createBrand",
    state: "reconciledNoMutation", errorCode: "PERMISSION_DENIED",
    noMutationConfirmed: true, payloadDigest: "a".repeat(64),
    reconciliationEvidence: evidenceFile};
  const evidence = {schemaVersion: 1, runID, projectID: "outpick-test",
    stage: "smoke", conclusion: "noMutationConfirmed",
    request: {requestID: request.requestID, callable: request.callable,
      errorCode: request.errorCode, payloadDigest: request.payloadDigest},
    checks: {receiptExists: false, deterministicBrandExists: false,
      deterministicBatchExists: false, matchingBrandCount: 0,
      matchingNameIndexCount: 0}};
  const evidenceRaw = JSON.stringify(evidence, null, 2) + "\n";
  const evidenceDigest = createHash("sha256").update(evidenceRaw).digest("hex");
  const reconciliation = {status: "noMutationConfirmed", evidenceFile, evidenceDigest};
  try {
    await mkdir(join(runDirectory, "evidence"), {recursive: true});
    await writeFile(evidencePath, evidenceRaw);
    await writeFile(join(runDirectory, runID + ".json"), JSON.stringify({
      runID, status: "reconciled", requests: [request], reconciliation,
    }));
    await writeFile(join(runDirectory, "report.json"), JSON.stringify({
      runID, stage: "smoke", status: "stopped", reconciliation,
    }));
    const resumed = await openQ7Campaign(directory, "smoke");
    await resumed.close();

    await writeFile(evidencePath, evidenceRaw.replace('"matchingBrandCount": 0',
      '"matchingBrandCount": 1'));
    await assert.rejects(openQ7Campaign(directory, "smoke"),
      /Q7_UNRESOLVED_PRIOR_RUN:run-12345678/);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test("QV02 완료된 smoke 후에는 tenBrands를 허용하고 완료 단계 반복은 거부한다", async () => {
  const directory = await mkdtemp(join(tmpdir(), "outpick-q7-stage-"));
  try {
    const runID = "run-87654321";
    const runDirectory = join(directory, runID);
    await mkdir(runDirectory);
    await writeFile(join(runDirectory, runID + ".json"), JSON.stringify({
      runID, status: "completed", requests: [{requestID: "r1", state: "accepted"}],
    }));
    await writeFile(join(runDirectory, "report.json"), JSON.stringify({stage: "smoke", status: "completed"}));
    const tenBrands = await openQ7Campaign(directory, "tenBrands");
    await tenBrands.close();
    await assert.rejects(openQ7Campaign(directory, "smoke"), /Q7_STAGE_ALREADY_COMPLETED/);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test("QV05 Storage 산출물을 고정 generation·SHA-256·JPEG 크기로 검증한다", async () => {
  const bytes = await sharp({create: {width: 3, height: 2, channels: 3, background: "#123456"}})
    .jpeg({quality: 82}).toBuffer();
  const expected = {bytes: bytes.length,
    sha256: (await import("node:crypto")).createHash("sha256").update(bytes).digest("hex"),
    width: 3, height: 2};
  let selectedGeneration;
  let validation;
  const bucket = {file: (path, options = {}) => {
    assert.equal(path, "brands/test/asset.jpg");
    if (options.generation) {
      selectedGeneration = options.generation;
      return {download: async (value) => { validation = value.validation; return [bytes]; }};
    }
    return {getMetadata: async () => [{generation: "42", size: String(bytes.length),
      contentType: "image/jpeg", crc32c: "crc", md5Hash: "md5"}]};
  }};
  assert.deepEqual(await readQ7StorageOutput(bucket, "brands/test/asset.jpg", expected), {
    bytes: bytes.length, sha256: expected.sha256, width: 3, height: 2,
    format: "jpeg", generation: "42", contentType: "image/jpeg", crc32c: "crc", md5Hash: "md5",
  });
  assert.equal(selectedGeneration, "42");
  assert.equal(validation, "crc32c");
  await assert.rejects(readQ7StorageOutput(bucket, "brands/test/asset.jpg", {
    ...expected, generation: "41"}), /Q7_STORAGE_OBJECT_VERSION_MISMATCH/);
  await assert.rejects(readQ7StorageOutput(bucket, "brands/test/asset.jpg", {
    ...expected, sha256: "0".repeat(64)}), /Q7_STORAGE_GOLDEN_MISMATCH/);
});

test("QV05 커버 썸네일은 현재 공개 원장의 경로와 generation으로 확인한다", () => {
  const season = {coverPath: "imports/write/cover.jpg", coverRemoteURL: "https://example.test/cover.jpg",
    coverAssetEpoch: 3, coverAssetExecutionID: "execution", coverAssetKey: "asset", coverAssetWriteID: "write"};
  const ledger = {status: "published", kind: "seasonCover", epoch: 3, executionID: "execution",
    assetKey: "asset", writeID: "write", thumbPath: "imports/write/cover_thumb.jpg",
    detailPath: season.coverPath, objects: {thumb: {generation: "101"}, detail: {generation: "102"}}};
  assert.equal(q7PublishedCoverReference(season, ledger).thumbPath, ledger.thumbPath);
  assert.equal(q7PublishedCoverReference(season, ledger).thumbGeneration, "101");
  const changes = [(l) => {l.status = "unpublished";}, (l) => {l.epoch++;},
    (l) => {l.detailPath = "other";}, (l) => {l.objects.thumb = {};}, (l) => {l.writeID = "old";}];
  for (const change of changes) {
    const changed = structuredClone(ledger); change(changed);
    assert.throws(() => q7PublishedCoverReference(season, changed), /Q7_PUBLISHED_COVER_LEDGER_MISMATCH/);
  }
});

test("QV06 live preflight는 후보·기본 트래픽·Worker 설정·Function URL·공유 큐를 함께 고정한다", () => {
  const verificationDigest = "f".repeat(64);
  const snapshot = {service: {metadata: {name: "lookbook-import-worker-development",
    namespace: "86635107099", annotations: {"run.googleapis.com/maxScale": "5"}},
  status: {latestReadyRevisionName: "lookbook-import-worker-development-00018-abc",
    traffic: [{percent: 100, revisionName: "lookbook-import-worker-development-00012-fih"},
      {tag: "q7-20261006", revisionName: "lookbook-import-worker-development-00018-abc",
        url: "https://q7-20261006---lookbook-import-worker-development-xyenspjiwa-du.a.run.app"}]}},
  revision: {metadata: {name: "lookbook-import-worker-development-00018-abc",
    annotations: {"autoscaling.knative.dev/maxScale": "1"}},
  status: {conditions: [{type: "Ready", status: "True"}]},
  spec: {serviceAccountName: "outpick-lookbook-worker-dev@outpick-test.iam.gserviceaccount.com",
    containerConcurrency: 2, timeoutSeconds: 900,
    containers: [{image: "candidate@sha256:digest",
      resources: {limits: {cpu: "1", memory: "2Gi"}}, env: [
        {name: "OUTPICK_FIREBASE_PROJECT_ID", value: "outpick-test"},
        {name: "OUTPICK_FIREBASE_STORAGE_BUCKET", value: "outpick-test.firebasestorage.app"},
        {name: "OUTPICK_IMPORT_PERFORMANCE_ENABLED", value: "true"},
        {name: "OUTPICK_IMPORT_RECOVERY_SERVICE_ACCOUNT_EMAIL", value:
          "lookbook-import-recovery@outpick-test.iam.gserviceaccount.com"},
        {name: "OUTPICK_WORKER_VERIFICATION_DIGEST", value: verificationDigest},
      ]}] }},
  functionConfig: {state: "ACTIVE", serviceConfig: {environmentVariables: {
    OUTPICK_LOOKBOOK_IMPORT_WORKER_URL: "https://q7-20261006---lookbook-import-worker-xyenspjiwa-du.a.run.app"}}},
  queues: {"lookbook-import-jobs": {state: "RUNNING", tasks: []},
    "lookbook-discovery-jobs": {state: "RUNNING", tasks: []}}};
  // tag URL은 실제 service endpoint와 동일하게 고정한다.
  const url = snapshot.service.status.traffic[1].url;
  snapshot.functionConfig.serviceConfig.environmentVariables.OUTPICK_LOOKBOOK_IMPORT_WORKER_URL = url;
  const checked = assertQ7DevelopmentSnapshot(snapshot, verificationDigest);
  assert.equal(checked.baseTrafficPercent, 100);
  assert.equal(checked.performanceEnabled, true);
  assert.equal(checked.workerVerificationDigest, verificationDigest);
  assert.equal(checked.taskQueues["lookbook-import-jobs"].pendingTasks, 0);
  assert.throws(() => assertQ7DevelopmentSnapshot(snapshot),
    /Q7_EXPECTED_WORKER_VERIFICATION_DIGEST_REQUIRED/);
  for (const mutate of [
    (value) => {value.queues["lookbook-import-jobs"].tasks.push({name: "pending"});},
    (value) => {value.revision.spec.containers[0].env[2].value = "false";},
    (value) => {value.revision.spec.containers[0].env.find((env) =>
      env.name === "OUTPICK_WORKER_VERIFICATION_DIGEST").value = "0".repeat(64);},
    (value) => {value.revision.spec.containers[0].env =
      value.revision.spec.containers[0].env.filter((env) =>
        env.name !== "OUTPICK_IMPORT_RECOVERY_SERVICE_ACCOUNT_EMAIL");},
    (value) => {value.service.status.traffic[0].percent = 50;},
    (value) => {value.revision.spec.containerConcurrency = 6;},
    (value) => {value.functionConfig.state = "FAILED";},
  ]) {
    const changed = structuredClone(snapshot);
    mutate(changed);
    assert.throws(() => assertQ7DevelopmentSnapshot(changed, verificationDigest));
  }
});

test("QV03 callable 대상과 method allowlist를 검증하고 사용자 토큰을 헤더에만 보낸다", async () => {
  let sent;
  const call = createQ7Callable({getToken: async () => ({uid: "uid", idToken: "private-token"}),
    fetchImpl: async (url, options) => {
      sent = {url, options};
      return new Response(JSON.stringify({result: {ok: true}}), {status: 200});
    }});
  assert.deepEqual(await call("createBrand", {name: "test"}), {ok: true});
  assert.match(sent.url, /^https:\/\/asia-northeast3-outpick-test\.cloudfunctions\.net\//);
  assert.equal(sent.options.headers.authorization, "Bearer private-token");
  assert.doesNotMatch(sent.options.body, /private-token/);
  await assert.rejects(call("deleteBrand", {}), /Q7_CALLABLE_NOT_ALLOWED/);
  assert.throws(() => createQ7Callable({getToken: async () => ({}),
    projectID: "outpick-664ae"}), /Q7_TARGET_NOT_ALLOWED/);
});

test("QV02 정산된 단일 탐색 이력만 원본 digest와 종료 증거로 새 검증을 허용한다", async () => {
  const directory = await mkdtemp(join(tmpdir(), "outpick-q7-settlement-"));
  const runID = "run-12345678";
  const runDirectory = join(directory, runID);
  const report = {runID, stage: "smoke", status: "stopped",
    mutationCount: 1, batchIDs: ["batch-1"]};
  const journal = {runID, status: "stopped", mutationCount: 1,
    batchIDs: ["batch-1"], requests: [{callable: "createBrand", state: "accepted",
      response: {brandID: "brand-1", discoveryJobID: "job-1", batchID: "batch-1"}}]};
  const readback = {status: "passed", queue: {state: "idle"},
    batch: {state: "released", kind: "discoverSeasons", brandID: "brand-1",
      epoch: 1, stateRevision: 11, items: [{jobID: "job-1",
        processingStatus: "correctionRequired", activeRunID: null}]},
    job: {status: "correctionRequired"},
    run: {runID: "batch-1-1", terminalConfirmed: true, inFlight: 0},
    decision: {projectID: "outpick-test", serviceName: "lookbook-import-worker-development",
      decision: "settleCorrectionRequired", batchID: "batch-1", runID: "batch-1-1",
      expectedEpoch: 1, stateRevisionAfter: 11, uncertainAssetWriteCount: 0,
      correctionEvidence: {jobID: "job-1"}, evidence: {kind: "durableDrain",
        runID: "batch-1-1", terminalConfirmed: true, inFlight: 0}}};
  const raw = (value) => JSON.stringify(value, null, 2) + "\n";
  const digest = (text) => createHash("sha256").update(text).digest("hex");
  const reportRaw = raw(report);
  const journalRaw = raw(journal);
  const writeProof = async (value) => {
    const readbackRaw = raw(value);
    await writeFile(join(runDirectory, "evidence/settlement-readback.json"), readbackRaw);
    await writeFile(join(runDirectory, "evidence/terminal-correction-reconciliation.json"),
      raw({schemaVersion: 1, runID, projectID: "outpick-test",
        conclusion: "settledTerminalCorrection", reportDigest: digest(reportRaw),
        journalDigest: digest(journalRaw), readbackDigest: digest(readbackRaw)}));
  };
  try {
    await mkdir(join(runDirectory, "evidence"), {recursive: true});
    await writeFile(join(runDirectory, "report.json"), reportRaw);
    await writeFile(join(runDirectory, runID + ".json"), journalRaw);
    await assert.rejects(openQ7Campaign(directory, "smoke"), /Q7_UNRESOLVED_PRIOR_RUN/);
    await writeProof(readback);
    const campaign = await openQ7Campaign(directory, "smoke");
    await campaign.close();
    assert.equal(await readFile(join(runDirectory, "report.json"), "utf8"), reportRaw);
    assert.equal(await readFile(join(runDirectory, runID + ".json"), "utf8"), journalRaw);
    for (const mutate of [
      (value) => {value.queue.state = "active";},
      (value) => {value.batch.brandID = "other-brand";},
      (value) => {value.run.terminalConfirmed = false;},
      (value) => {value.run.inFlight = 1;},
      (value) => {value.decision.uncertainAssetWriteCount = 1;},
      (value) => {value.decision.expectedEpoch = 2;},
      (value) => {value.decision.correctionEvidence.jobID = "other-job";},
    ]) {
      const changed = structuredClone(readback);
      mutate(changed);
      await writeProof(changed);
      await assert.rejects(openQ7Campaign(directory, "smoke"), /Q7_UNRESOLVED_PRIOR_RUN/);
    }
    await writeProof(readback);
    await writeFile(join(runDirectory, "report.json"), reportRaw + " ");
    await assert.rejects(openQ7Campaign(directory, "smoke"), /Q7_UNRESOLVED_PRIOR_RUN/);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test("QV03 callable protocol recognizes Firebase errors returned with HTTP 200", async () => {
  const call = createQ7Callable({getToken: async () => ({uid: "u", idToken: "t"}),
    fetchImpl: async () => new Response(JSON.stringify({error: {
      status: "PERMISSION_DENIED", message: "no"}}), {status: 200})});
  await assert.rejects(call("createBrand", {}), /Q7_CALLABLE_PERMISSION_DENIED/);
});

test("QV04 existing input plan keeps the 3-season and 16-season verified scopes", () => {
  const smoke = makePlan("smoke");
  const tenBrands = makePlan("tenBrands");
  assert.equal(smoke.totals.seasons, 3);
  assert.equal(smoke.totals.mutationRequestsIfAllReviewed, 7);
  assert.equal(tenBrands.totals.seasons, 16);
  assert.equal(tenBrands.totals.mutationRequestsIfAllReviewed, 36);
  assert.equal(tenBrands.totals.jpegWrites, 710);
  assert.equal(fixture.sourceInputDigest, smoke.sourceInputDigest);
});

test("QV06 preparing 영수증은 동일 요청 조회로 job 준비와 최종 release를 기다린다", async () => {
  let time = 0;
  const calls = [];
  const pending = {requestID: "request-1", batchID: "batch-1", receipt: {
    requestID: "request-1", batchID: "batch-1", receiptState: "preparing",
    items: [{jobID: null}, {jobID: null}], failedCount: 0, skippedCount: 0}};
  const ready = {...pending.receipt, receiptState: "active",
    items: [{jobID: "job-1"}, {jobID: "job-2"}]};
  const released = {...ready, receiptState: "released"};
  const call = async (name, data) => {
    calls.push({name, data});
    return calls.length === 1 ? ready : released;
  };
  const options = {now: () => time, sleep: async (ms) => {time += ms;},
    intervalMs: 1, timeoutMs: 10};
  const prepared = await waitQ7Receipt(call, pending,
    {...options, mode: "prepared", expectedCount: 2});
  assert.deepEqual(prepared, ready);
  const final = await waitQ7Receipt(call, {...pending, receipt: prepared},
    {...options, mode: "released"});
  assert.deepEqual(final, released);
  assert.deepEqual(calls, [{name: "getSeasonImportBatch", data: {requestID: "request-1"}},
    {name: "getSeasonImportBatch", data: {requestID: "request-1"}}]);
});

test("QV06 대기 영수증은 복구 실패 대상 변경과 timeout에서 재접수 없이 중단한다", async () => {
  for (const mode of ["recovery", "failed", "target", "timeout", "incomplete"]) {
    let time = 0;
    let reads = 0;
    const receipt = {requestID: "request-1", batchID: "batch-1",
      receiptState: "preparing", items: [{jobID: null}], failedCount: 0};
    if (mode === "recovery") receipt.receiptState = "recoveryRequired";
    if (mode === "failed") receipt.failedCount = 1;
    if (mode === "target") receipt.batchID = "other-batch";
    if (mode === "incomplete") receipt.receiptState = "released";
    const expected = {recovery: /Q7_RECOVERY_REQUIRED/,
      failed: /Q7_BATCH_HAS_FAILED_ITEMS/, target: /Q7_RECEIPT_TARGET_CHANGED/,
      timeout: /Q7_PREPARATION_TIMEOUT/, incomplete: /Q7_IMPORT_ITEM_INCOMPLETE/};
    await assert.rejects(waitQ7Receipt(async (name, data) => {
      reads++;
      assert.equal(name, "getSeasonImportBatch");
      assert.deepEqual(data, {requestID: "request-1"});
      return receipt;
    }, {requestID: "request-1", batchID: "batch-1"}, {
      mode: "prepared", expectedCount: 1, intervalMs: 1, timeoutMs: 3,
      now: () => time, sleep: async (ms) => {time += ms;},
    }), expected[mode]);
    assert.equal(reads, mode === "timeout" ? 3 : 1);
  }
});
