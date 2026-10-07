import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {mkdtemp, mkdir, writeFile, readFile, rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";
import {makePlan} from "./queue-development-contract.mjs";
import {openQ7Campaign} from "./q7-journal.mjs";
import {validateQ7SmokeResume, loadQ7SmokeResume, preserveQ7ResumeOriginals,
  assertQ7RecoveredWorkflow, assertQ7ExtractedContinuation, validateQ7Finalization} from "./q7-resume.mjs";

function savedFixture() {
  const plan = makePlan("smoke"), runID = "run-resume-12345678";
  const brand = {letter: "A", brandID: "brand-a", discoveryJobID: "discovery-a",
    createRequestID: "request-create", discoveryBatchID: "batch-discovery"};
  const payloads = [{requestID: "request-create"}, {requestID: "request-import",
    brandID: brand.brandID, discoveryJobID: brand.discoveryJobID, generation: 1,
    candidateSnapshotHash: "snapshot", candidateIDs: ["ss", "fw"]}];
  const responses = [{requestID: "request-create", brandID: brand.brandID,
    discoveryJobID: brand.discoveryJobID, batchID: brand.discoveryBatchID},
  {requestID: "request-import", brandID: brand.brandID, batchID: "batch-import",
    receiptState: "preparing", kind: "importSeasons", requestedCount: 2,
    items: ["ss", "fw"].map((targetID) => ({targetID, jobID: null, admissionStatus: "pending"}))}];
  const requests = payloads.map((payload, index) => ({requestID: payload.requestID,
    callable: index ? "requestSeasonCandidateImportJobs" : "createBrand", state: "accepted",
    payload, response: responses[index], payloadDigest: createHash("sha256").update(JSON.stringify(payload)).digest("hex")}));
  const ids = [brand.discoveryBatchID, "batch-import"];
  return {runID, plan,
    journal: {runID, projectID: "outpick-test", stage: "smoke", status: "stopped",
      stopReason: "Q7_IMPORT_ITEM_INCOMPLETE", mutationCount: 2, requests,
      planDigest: plan.planDigest, sourceInputDigest: plan.sourceInputDigest, startedAt: 100, batchIDs: ids},
    report: {runID, stage: "smoke", status: "stopped", reason: "Q7_IMPORT_ITEM_INCOMPLETE",
      mutationCount: 2, batchIDs: ids},
    manifest: {runID, projectID: "outpick-test", stage: "smoke", createdAt: 100,
      identity: {uidHash: "a".repeat(64)}, plan, brands: [brand], batches: [], jobs: []},
    discovery: {brandID: brand.brandID, discoveryJobID: brand.discoveryJobID,
      status: "succeeded", generation: 1, candidateSnapshotHash: "snapshot",
      selectedSeasonIDs: ["2026SS", "2025FW"]}};
}

test("QV07 결과 재검증은 확정된 일곱 접수만 허용하고 추가 접수와 미확정 기록을 차단한다", () => {
  const f = savedFixture();
  const names = ["createBrand", "requestSeasonCandidateImportJobs", "createBrand",
    "reviewLookbookExtraction", "reviewLookbookExtraction", "requestSeasonCandidateImportJobs", "reviewLookbookExtraction"];
  f.journal.requests = names.map((callable, index) => {
    const requestID = "request-" + index, payload = {requestID};
    return {requestID, callable, payload, payloadDigest: createHash("sha256").update(JSON.stringify(payload)).digest("hex"),
      state: "accepted", response: {requestID, batchID: String(index + 1).repeat(64),
        brandID: index === 2 ? "brand-b" : "brand-a", discoveryJobID: index === 2 ? "discovery-b" : "discovery-a"}};
  });
  const ids = f.journal.requests.map((item) => item.response.batchID);
  f.journal.mutationCount = 7; f.report.mutationCount = 7;
  f.journal.batchIDs = ids; f.report.batchIDs = ids;
  f.manifest.validationScope = "functionalStorageSmoke";
  f.manifest.overlapDeferredTo = "tenBrands100msWave";
  f.manifest.brands[0].discoveryBatchID = ids[0];
  f.manifest.brands.push({letter: "B", brandID: "brand-b", discoveryJobID: "discovery-b", discoveryBatchID: ids[2]});
  validateQ7Finalization(f, f.plan);
  for (const change of [(v) => {v.journal.requests[6].state = "uncertain";},
    (v) => {v.journal.requests.push(v.journal.requests[6]);},
    (v) => {v.journal.requests[6].payload.requestID = "changed";},
    (v) => {v.manifest.overlapDeferredTo = null;}, (v) => {v.journal.finalized = true;}]) {
    const candidate = structuredClone(f); change(candidate);
    assert.throws(() => validateQ7Finalization(candidate, candidate.plan), /Q7_FINALIZATION_CONTRACT_MISMATCH/);
  }
});

test("QV07 추출 후 이어 실행은 동일 종료 batch와 검토 대기 두 항목만 허용한다", () => {
  const f = savedFixture();
  const expectedBrand = {...f.manifest.brands[0], generation: 1, candidateSnapshotHash: "snapshot"};
  const value = {queue: {state: "idle", headBatchID: null},
    brand: {publishedSeasonDiscoveryJobID: "discovery-a", publishedSeasonDiscoveryGeneration: 1,
      publishedSeasonDiscoverySnapshotHash: "snapshot"},
    discoveryJob: {status: "succeeded", generation: 1, candidateSnapshotHash: "snapshot"},
    discoveryBatch: {state: "released", brandID: "brand-a", items: [{jobID: "discovery-a", processingStatus: "succeeded"}]},
    importBatch: {state: "released", requestID: "request-import", brandID: "brand-a", requestedBy: "uid",
      items: ["ss", "fw"].map((targetID, index) => ({targetID, jobID: "job-" + index,
        admissionStatus: "created", processingStatus: "awaitingReview", activeRunID: null}))},
    expectedBrand, pending: f.journal.requests[1], uid: "uid"};
  assertQ7ExtractedContinuation(value);
  const changes = [(v) => {v.queue.state = "recoveryRequired";},
    (v) => {v.queue.headBatchID = "another";}, (v) => {v.importBatch.items[0].processingStatus = "failed";},
    (v) => {v.importBatch.items[0].activeRunID = "still-running";},
    (v) => {v.importBatch.requestedBy = "another";},
    (v) => {v.importBatch.items.reverse();}, (v) => {v.discoveryJob.generation++;}];
  for (const change of changes) {
    const changed = structuredClone(value); change(changed);
    assert.throws(() => assertQ7ExtractedContinuation(changed), /Q7_EXTRACTED_CONTINUATION_CHANGED/);
  }
});

test("QV07 이어 실행은 확정된 A와 동일 두 시즌만 허용하고 미확정 변경을 차단한다", () => {
  const value = savedFixture();
  assert.equal(validateQ7SmokeResume(value, value.plan).imports.requestID, "request-import");
  const changes = [
    (v) => {v.journal.requests[1].state = "uncertain";},
    (v) => {v.journal.requests[1].payload.candidateIDs.reverse();},
    (v) => {v.manifest.identity.uidHash = "token";},
    (v) => {v.discovery.generation++;},
    (v) => {v.discovery.selectedSeasonIDs.reverse();},
    (v) => {v.report.mutationCount = 3;},
    (v) => {v.manifest.brands.push(v.manifest.brands[0]);},
    (v) => {v.journal.finalized = true;},
  ];
  for (const change of changes) {
    const candidate = savedFixture(); change(candidate);
    assert.throws(() => validateQ7SmokeResume(candidate, candidate.plan), /Q7_RESUME_CONTRACT_MISMATCH/);
  }
});

test("QV07 campaign은 지정 run만 복원하고 원본 중단 기록을 digest로 보존한다", async () => {
  const root = await mkdtemp(join(tmpdir(), "q7-resume-"));
  const value = savedFixture(), directory = join(root, value.runID);
  try {
    await mkdir(join(directory, "evidence/discovery"), {recursive: true});
    for (const [name, data] of [[value.runID + ".json", value.journal], ["report.json", value.report],
      ["manifest.json", value.manifest], ["evidence/discovery/A.json", value.discovery]]) {
      await writeFile(join(directory, name), JSON.stringify(data));
    }
    await assert.rejects(openQ7Campaign(root, "smoke"), /Q7_UNRESOLVED_PRIOR_RUN/);
    const campaign = await openQ7Campaign(root, "smoke", value.runID);
    await campaign.close();
    const loaded = await loadQ7SmokeResume(directory, value.runID, value.plan);
    await preserveQ7ResumeOriginals(directory, loaded);
    await writeFile(join(directory, value.runID + ".json"), JSON.stringify({...value.journal, status: "running"}));
    await writeFile(join(directory, "manifest.json"), JSON.stringify({...value.manifest,
      resumption: {resumedAt: 200}, batches: [{batchID: "batch-import"}]}));
    assert.equal((await loadQ7SmokeResume(directory, value.runID, value.plan)).state.imports.requestID, "request-import");
    assert.equal(await readFile(join(directory, "report.json"), "utf8"),
      await readFile(join(directory, "evidence/resume-original/report.json"), "utf8"));
    await preserveQ7ResumeOriginals(directory, loaded);
    await writeFile(join(directory, "evidence/resume-original/report.json"), "changed");
    await assert.rejects(preserveQ7ResumeOriginals(directory, loaded));
    await writeFile(join(directory, "evidence/resume-original/report.json"),
      loaded.originals.find((file) => file.name === "report.json").raw);
    await mkdir(join(root, "other-run"));
    await writeFile(join(root, "other-run/other-run.json"), JSON.stringify({status: "stopped", requests: [{state: "uncertain"}]}));
    await assert.rejects(openQ7Campaign(root, "smoke", value.runID), /Q7_UNRESOLVED_PRIOR_RUN:other-run/);
  } finally { await rm(root, {recursive: true, force: true}); }
});

test("QV07 복구 기능 완료는 종료 audit와 새 실행 검증을 요구하며 기존 실패를 성능 통과로 바꾸지 않는다", () => {
  const old = "lookbook-import-worker-development-old", current = "lookbook-import-worker-development-new";
  const run = {batchID: "batch", projectID: "outpick-test", revision: old, runID: "batch-1",
    epoch: 1, bootID: "boot", startedAt: 100, finishedAt: 200, state: "recoveryRequired",
    terminalConfirmed: true, inFlight: 0, resourceEvidence: {memoryStop: "sample-gap:922ms"}};
  const audit = {decisionID: "decision", decision: "resume", projectID: "outpick-test",
    serviceName: "lookbook-import-worker-development", batchID: "batch", revision: old,
    servingRevision: current, runID: run.runID, expectedEpoch: 1, uncertainAssetWriteCount: 0,
    createdAt: 250, evidence: {kind: "durableDrain", runID: run.runID, terminalConfirmed: true, inFlight: 0}};
  const batch = {id: "batch", kind: "discoverSeasons", sequence: 1, state: "released",
    releasedAt: 400, runID: "batch-2", epoch: 2, recoveryDecisions: [audit],
    runs: [run, {...run, revision: current, epoch: 2, runID: "batch-2", state: "released",
      startedAt: 300, finishedAt: 400, resourceEvidence: {sampleCount: 1, memoryLimitBytes: 2 * 1024 ** 3,
        memorySource: "cgroup-v2", maxMemoryRatio: 0.2, memoryStop: null, drainTargetExceeded: false}}]};
  const result = assertQ7RecoveredWorkflow([batch], ["batch"], current, "batch");
  assert.equal(result.performanceStatus, "historicalFailurePreserved");
  assert.equal(result.historicalFailureRunID, "batch-1");
  const changes = [(b) => {b.recoveryDecisions = [];}, (b) => {b.runs[0].inFlight = 1;},
    (b) => {b.runs[1].startedAt = 190;}, (b) => {b.runs[1].resourceEvidence.memoryStop = "sample-gap";},
    (b) => {b.recoveryDecisions[0].uncertainAssetWriteCount = 1;}];
  for (const change of changes) {
    const changed = structuredClone(batch); change(changed);
    assert.throws(() => assertQ7RecoveredWorkflow([changed], ["batch"], current, "batch"));
  }
});
