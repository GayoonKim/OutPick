import test from "node:test";
import assert from "node:assert/strict";
import {makeRetryKLPlan, runRetryKL, predictRetryIdentity, assertRetryKEvidence} from "./q7-retry-contract.mjs";
import {assertRetryKLResume, retryReviewJob, readRetryExecutionWrites} from "./q7-retry-contract.mjs";
import {assertRetryKLContinuation, assertRetryContinuationRemote, assertRetryDeliveryBudget, redeliverRetryK} from "./q7-retry-contract.mjs";
import {createHash} from "node:crypto";

test("QV09 짧은 재시도 검증은 두 브랜드·여덟 접수·새 검토·수동 새 실행 범위를 지킨다", async () => {
  const plan = makeRetryKLPlan();
  assert.equal(plan.maxMutations, 8);
  assert.deepEqual(plan.brands, ["K", "L"]);
  assert.equal(plan.expectedFiles, 124);
  let mutations = 0;
  const reviews = new Map();
  const ports = {
    create: async (letter) => {mutations++; return {letter, executionID: letter + "-old"};},
    importSeason: async (brand, fail) => {mutations++; assert.equal(fail, brand.letter === "L"); return {brand};},
    waitReleased: async () => {},
    review: async (brand) => {const n = (reviews.get(brand.letter) ?? 0) + 1; reviews.set(brand.letter, n); return {reviewGeneration: n};},
    approve: async (brand, review, oom) => {mutations++; assert.equal(oom, brand.letter === "K" && review.reviewGeneration === 1); return {batchID: "approval"};},
    verifyK: async () => {},
    failures: async (brand) => brand.executionID.endsWith("old") ? [{state: "failed", attemptCount: 5, attemptLimit: 5, latestExecutionID: brand.executionID}] : [],
    retry: async (brand) => {mutations++; brand.executionID = "L-new"; return {executionID: "L-new", batchID: "manual"};},
    verifyFinal: async () => ({passed: true}),
  };
  assert.deepEqual(await runRetryKL(ports), {passed: true});
  assert.equal(mutations, 8);
  const identity = predictRetryIdentity("uid", "11111111-1111-4111-8111-111111111111");
  assert.match(identity.batchID, /^[a-f0-9]{64}$/);
  assert.notEqual(identity.executionID, identity.jobID);
});

test("QV10 고의 종료 코드나 HTTP 오류만으로 실제 종료·처음부터 재시도 통과를 선언하지 않는다", () => {
  const input = {batch: {state: "released"}, execution: {status: "succeeded", attemptCount: 2, attemptLimit: 5},
    fault: {consumedAttempts: {"1": {runID: "old"}}}, originalAttempt: {errorCode: "WORKER_TERMINATED"},
    expectedRevision: "revision", runs: [{runID: "old", epoch: 1, traceID: "trace", settlement: "restartFromParsing",
      terminationEvidence: {kind: "platformTermination", projectID: "outpick-test", serviceName: "lookbook-import-worker-development",
        revision: "revision", traceID: "trace", instanceID: "instance", insertID: "log", timestamp: new Date(1000).toISOString()}},
    {runID: "new", epoch: 2, terminalConfirmed: true, inFlight: 0}]};
  assert.equal(assertRetryKEvidence(input).attemptCount, 2);
  const missing = structuredClone(input); delete missing.runs[0].terminationEvidence;
  assert.throws(() => assertRetryKEvidence(missing));
  const wrong = structuredClone(input); wrong.runs[0].terminationEvidence.revision = "another";
  assert.throws(() => assertRetryKEvidence(wrong));
});

test("QV11 검토 대조는 문서 경로 jobID를 사용하고 다른 브랜드·작업은 거절한다", () => {
  assert.deepEqual(retryReviewJob({brandID: "brand", reviewGeneration: 1}, {brandID: "brand", jobID: "job"}),
    {brandID: "brand", reviewGeneration: 1, jobID: "job"});
  assert.throws(() => retryReviewJob({brandID: "wrong"}, {brandID: "brand", jobID: "job"}));
  assert.throws(() => retryReviewJob({brandID: "brand", jobID: "old"}, {brandID: "brand", jobID: "job"}));
});

test("QV11 K 두 확정 접수만 보존하고 남은 여섯 접수를 진행하며 미확정·만료·승인 이력은 차단한다", async () => {
  const hash = (value) => createHash("sha256").update(JSON.stringify(value)).digest("hex");
  const brand = {letter: "K", brandID: "brand", jobID: "job", executionID: "K-old", discoveryJobID: "discovery", candidateID: "candidate", importBatchID: "import"};
  const requests = [{requestID: "create", callable: "createBrand", state: "accepted", payload: {}, response: {brandID: "brand", discoveryJobID: "discovery", batchID: "discovery-batch"}},
    {requestID: "import", callable: "requestSeasonCandidateImportJobs", state: "accepted", payload: {brandID: "brand", candidateIDs: ["candidate"]}, response: {batchID: "import"}}];
  requests.forEach((item) => {item.payloadDigest = hash(item.payload);});
  const input = {runID: "run", now: 1000, report: {runID: "run", stage: "retryKL", status: "stopped", mutationCount: 2, startedAt: 0},
    journal: {runID: "run", status: "stopped", requests}, manifest: {runID: "run", stage: "retryKL", plan: makeRetryKLPlan(), mutationCount: 2, startedAt: 0,
      brands: [brand], files: [], requests: requests.map((item) => ({requestID: item.requestID, batchID: item.response.batchID})),
      batches: [{id: "import", requestID: "import", expected: "awaitingReview"}]}};
  assert.equal(assertRetryKLResume(input), brand);
  for (const change of [x => {x.journal.requests[1].state = "uncertain";}, x => {x.now = 1200000;},
    x => {x.journal.requests.push(x.journal.requests[0]);}, x => {x.manifest.files.push({});}]) {
    const wrong = structuredClone(input); change(wrong); assert.throws(() => assertRetryKLResume(wrong));
  }
  let mutations = 0; const reviews = new Map();
  const ports = {
    create: async (letter) => {assert.equal(letter, "L"); mutations++; return {letter, executionID: "L-old"};},
    importSeason: async (b, fail) => {assert.equal(b.letter, "L"); assert.equal(fail, true); mutations++; return {};},
    waitReleased: async () => {}, review: async (b) => {const n = (reviews.get(b.letter) ?? 0) + 1; reviews.set(b.letter, n); return {reviewGeneration: n};},
    approve: async () => {mutations++; return {};}, verifyK: async () => {},
    failures: async (b) => b.executionID === "L-old" ? [{state: "failed", attemptCount: 5, attemptLimit: 5, latestExecutionID: "L-old"}] : [],
    retry: async (b) => {mutations++; b.executionID = "L-new"; return {executionID: "L-new"};},
    verifyFinal: async () => ({passed: true}),
  };
  assert.deepEqual(await runRetryKL(ports, brand), {passed: true}); assert.equal(mutations, 6);
});

test("QV12 종료 쓰기는 부모 assets 문서 없이도 정확한 execution 하위 원장을 읽고 범위 밖 쓰기를 거절한다", async () => {
  const brand = {brandID: "brand", jobID: "job", executionID: "execution"};
  let wrong = false;
  const db = {doc: () => ({collection: () => ({listDocuments: async () => [{collection: () => ({get: async () => ({docs: [{
    ref: {path: wrong ? "brands/other/writes/write" : "brands/brand/importJobs/job/executions/execution/assets/missing-parent/writes/write"},
    data: () => ({executionID: "execution", epoch: 49, status: "uploading"}),
  }]})})}]})})};
  const result = await readRetryExecutionWrites(db, brand);
  assert.equal(result.length, 1); assert.equal(result[0].epoch, 49);
  wrong = true; await assert.rejects(readRetryExecutionWrites(db, brand));
});

function interruptedFixture() {
  const uid = "uid", runID = "11111111-1111-4111-8111-111111111111";
  const importID = "22222222-2222-4222-8222-222222222222", approvalID = "33333333-3333-4333-8333-333333333333";
  const predicted = predictRetryIdentity(uid, importID), approval = predictRetryIdentity(uid, approvalID);
  const brand = {letter: "K", brandID: "brand", discoveryJobID: "discovery", candidateID: "candidate",
    jobID: predicted.jobID, executionID: predicted.executionID, importBatchID: predicted.batchID};
  const requests = [{requestID: runID, callable: "createBrand", payload: {}, response: {brandID: brand.brandID, discoveryJobID: "discovery", batchID: "discovery-batch"}},
    {requestID: importID, callable: "requestSeasonCandidateImportJobs", payload: {brandID: "brand", candidateIDs: ["candidate"]}, response: {batchID: predicted.batchID}},
    {requestID: approvalID, callable: "reviewLookbookExtraction", payload: {brandID: "brand", jobID: brand.jobID, decision: "approved",
      excludedCandidateKeys: [], expectedCandidateCount: 30, reviewGeneration: 1, reviewSnapshotHash: "snapshot"}, response: {batchID: approval.batchID}}];
  for (const r of requests) {r.state = "accepted"; r.payloadDigest = createHash("sha256").update(JSON.stringify(r.payload)).digest("hex");}
  const manifest = {runID, stage: "retryKL", plan: makeRetryKLPlan(), startedAt: 0, mutationCount: 3,
    brands: [brand], files: [], workerRevision: "old", uidHash: createHash("sha256").update(uid).digest("hex"),
    requests: requests.map(r => ({requestID: r.requestID, batchID: r.response.batchID})),
    batches: [{id: predicted.batchID, requestID: importID, expected: "awaitingReview"}]};
  const report = {runID, stage: "retryKL", status: "stopped", startedAt: 0, mutationCount: 3, clientInterrupted: true,
    newInputStopped: true, serverQueueModified: false, reason: "PLATFORM_TERMINATION_LOGNAME_FILTER_ZERO_MATCHES"};
  return {uid, runID, manifest, report, journal: {runID, status: "running", mutationCount: 2, requests}};
}

test("QV13 K 세 확정 접수는 원본을 보존해 남은 다섯 접수만 수행하고 새 OOM·재접수를 하지 않는다", async () => {
  const input = interruptedFixture(), {brand, pending, review} = assertRetryKLContinuation(input);
  let mutations = 0, redeliveries = 0;
  const ports = {
    create: async (letter) => {assert.equal(letter, "L"); mutations++; return {letter, executionID: "L-old"};},
    importSeason: async (b, fail) => {assert.equal(b.letter, "L"); assert.equal(fail, true); mutations++; return {};},
    waitReleased: async () => {}, redeliverK: async p => {assert.equal(p.batchID, pending.batchID); redeliveries++;},
    review: async () => ({reviewGeneration: 2}), approve: async (b, r, oom) => {assert.equal(oom, false); mutations++; return {};},
    verifyK: async () => {}, failures: async b => b.executionID === "L-old" ? [{state: "failed", attemptCount: 5, attemptLimit: 5, latestExecutionID: "L-old"}] : [],
    retry: async b => {mutations++; b.executionID = "L-new"; return {executionID: "L-new"};}, verifyFinal: async () => ({passed: true}),
  };
  assert.deepEqual(await runRetryKL(ports, brand, {pending, review}), {passed: true});
  assert.equal(mutations, 5); assert.equal(redeliveries, 1);
  for (const change of [x => {x.journal.requests[2].state = "uncertain";}, x => {x.manifest.continuation = {};},
    x => {x.journal.requests.push(x.journal.requests[2]);}, x => {x.journal.requests[2].payload.jobID = "other";},
    x => {x.report.clientInterrupted = false;}, x => {x.manifest.files.push({});}]) {
    const wrong = structuredClone(input); change(wrong); assert.throws(() => assertRetryKLContinuation(wrong));
  }
});

test("QV13 이어 실행은 같은 계정·차례·첫 시도·이전 revision의 실제 종료 증거와 미공개 원장을 요구한다", () => {
  const input = interruptedFixture(), state = assertRetryKLContinuation(input), brand = state.brand;
  const oldRun = state.pending.batchID + "-49";
  const proof = {kind: "platformTermination", projectID: "outpick-test", serviceName: "lookbook-import-worker-development",
    revision: "old", traceID: "trace", instanceID: "instance", insertID: "insert", timestamp: new Date(100).toISOString()};
  const remote = {resume: {...input, ...state}, uid: input.uid, queue: {headBatchID: state.pending.batchID, state: "active", runID: oldRun, epoch: 49},
    batches: input.journal.requests.map((r, i) => ({brandID: "brand", requestedBy: input.uid, requestID: r.requestID,
      state: i < 2 ? "released" : "active", kind: "reviewApproval", runID: oldRun, epoch: 49, dispatchGeneration: 0,
      items: [{jobID: brand.jobID, executionID: brand.executionID, processingStatus: "active"}]})),
    job: {status: "processing", queueExecutionID: brand.executionID}, execution: {status: "active", attemptCount: 1, attemptLimit: 5, activeRunID: oldRun},
    fault: {scenario: "oomAfterUpload", batchID: state.pending.batchID, brandID: "brand", executionID: brand.executionID, consumedAttempts: {"1": {runID: oldRun}}},
    run: {runID: oldRun, epoch: 49, revision: "old", traceID: "trace", startedAt: 1}, proof,
    writes: [{executionID: brand.executionID, epoch: 49, status: "unpublished"}]};
  assert.equal(assertRetryContinuationRemote(remote).batchID, state.pending.batchID);
  for (const change of [x => {x.uid = "other";}, x => {x.queue.headBatchID = "other";}, x => {x.execution.attemptCount = 2;},
    x => {x.proof.revision = "new";}, x => {x.proof.instanceID = null;}, x => {x.fault.consumedAttempts["2"] = {};},
    x => {x.writes[0].status = "published";}, x => {x.run.resourceEvidence = {memoryStop: "85%"};}]) {
    const wrong = structuredClone(remote); change(wrong); assert.throws(() => assertRetryContinuationRemote(wrong));
  }
});

test("QV14 기존 task 실행 또는 같은 계약의 새 task 한 개만 전달하며 intent 실패·불확정 응답은 재전송하지 않는다", async () => {
  const {pending} = assertRetryKLContinuation(interruptedFixture());
  const input = {campaignID: "44444444-4444-4444-8444-444444444444", candidateURL: "https://q7-20261006---lookbook-import-worker-development-xyenspjiwa-du.a.run.app",
    delivery: {batchID: pending.batchID, dispatchGeneration: 0, queueContractVersion: 1}};
  let created = 0, ran = 0, intent = 0, task;
  const ports = {recordIntent: async () => {intent++;}, create: async (parent, value) => {assert.match(parent, /outpick-test/); created++; task = value;}, run: async () => {ran++;}};
  await redeliverRetryK({...input, ports}); assert.equal(created, 1); assert.equal(ran, 0); assert.equal(intent, 1);
  const existingTask = {...task, name: `projects/outpick-test/locations/asia-northeast3/queues/lookbook-import-jobs/tasks/batch-${pending.batchID}-0`};
  await redeliverRetryK({...input, existingTask, ports}); assert.equal(created, 1); assert.equal(ran, 1);
  await assert.rejects(redeliverRetryK({...input, ports: {...ports, recordIntent: async () => {throw new Error("EXISTS");}}}));
  assert.equal(created, 1);
  await assert.rejects(redeliverRetryK({...input, ports: {...ports, create: async () => {created++; throw new Error("UNCERTAIN");}}}));
  assert.equal(created, 2);
  const wrong = structuredClone(existingTask); wrong.httpRequest.oidcToken.audience = "other";
  await assert.rejects(redeliverRetryK({...input, existingTask: wrong, ports})); assert.equal(ran, 1);
});

test("QV14 전달 상한은 기존 이력과 새 전달을 합산하고 필요한 남은 전달 여유가 없으면 신규 투입을 차단한다", () => {
  assertRetryDeliveryBudget({historical: 18, reserve: 6});
  assertRetryDeliveryBudget({historical: 20, additional: 10});
  for (const input of [{historical: 25, reserve: 6}, {historical: 18, additional: 11},
    {historical: 20, additional: 10, reserve: 1}, {historical: -1}, {historical: 1.5}]) {
    assert.throws(() => assertRetryDeliveryBudget(input));
  }
});
