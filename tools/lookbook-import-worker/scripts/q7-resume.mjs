import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {mkdir, readFile, writeFile} from "node:fs/promises";
import {join} from "node:path";
import {assertBatchRunEvidence} from "./queue-development-contract.mjs";

// 접수가 확정된 A 생성·2시즌 import만 복원한다. 다른 중단 지점은 자동 재개하지 않는다.
export function validateQ7SmokeResume({runID, journal, report, manifest, discovery}, plan) {
  const fail = () => { throw new Error("Q7_RESUME_CONTRACT_MISMATCH"); };
  try {
    assert.equal(plan.stage, "smoke");
    for (const value of [journal, report, manifest]) assert.equal(value.runID, runID);
    assert.equal(journal.projectID, "outpick-test");
    assert.equal(manifest.projectID, "outpick-test");
    assert.equal(report.stage, "smoke");
    assert.equal(journal.stage, "smoke");
    assert.equal(manifest.stage, "smoke");
    assert.equal(journal.status, "stopped");
    assert.equal(report.status, "stopped");
    assert.equal(journal.stopReason, "Q7_IMPORT_ITEM_INCOMPLETE");
    assert.equal(report.reason, journal.stopReason);
    assert.notEqual(journal.finalized, true);
    assert.equal(journal.mutationCount, 2);
    assert.equal(report.mutationCount, 2);
    assert.equal(journal.planDigest, plan.planDigest);
    assert.equal(journal.sourceInputDigest, plan.sourceInputDigest);
    assert.deepEqual(manifest.plan, plan);
    assert.equal(journal.startedAt, manifest.createdAt);
    assert.match(manifest.identity.uidHash, /^[a-f0-9]{64}$/);
    assert.equal(journal.requests.length, 2);
    const [create, imports] = journal.requests;
    assert.equal(create.callable, "createBrand");
    assert.equal(imports.callable, "requestSeasonCandidateImportJobs");
    for (const request of journal.requests) {
      assert.equal(request.state, "accepted");
      assert.equal(request.requestID, request.payload.requestID);
      assert.equal(request.requestID, request.response.requestID);
      assert.equal(request.payloadDigest, sha(JSON.stringify(request.payload)));
    }
    assert.notEqual(create.requestID, imports.requestID);
    assert.equal(manifest.brands.length, 1);
    const brand = manifest.brands[0];
    assert.equal(brand.letter, "A");
    assert.equal(brand.brandID, create.response.brandID);
    assert.equal(brand.discoveryJobID, create.response.discoveryJobID);
    assert.equal(brand.discoveryBatchID, create.response.batchID);
    assert.equal(brand.createRequestID, create.requestID);
    assert.equal(brand.brandID, imports.payload.brandID);
    assert.equal(brand.discoveryJobID, imports.payload.discoveryJobID);
    assert.equal(imports.response.receiptState, "preparing");
    assert.equal(imports.response.kind, "importSeasons");
    assert.equal(imports.response.brandID, brand.brandID);
    assert.equal(imports.response.requestedCount, 2);
    assert.equal(imports.response.items.length, 2);
    assert.deepEqual(imports.response.items.map((item) => item.targetID), imports.payload.candidateIDs);
    assert.ok(imports.response.items.every((item) => item.jobID === null && item.admissionStatus === "pending"));
    assert.equal(discovery.brandID, brand.brandID);
    assert.equal(discovery.discoveryJobID, brand.discoveryJobID);
    assert.equal(discovery.status, "succeeded");
    assert.equal(discovery.generation, imports.payload.generation);
    assert.equal(discovery.candidateSnapshotHash, imports.payload.candidateSnapshotHash);
    assert.deepEqual(discovery.selectedSeasonIDs, plan.brands[0].seasons);
    assert.equal(manifest.batches.length, 0);
    assert.equal(manifest.jobs.length, 0);
    assert.deepEqual(journal.batchIDs, [create.response.batchID, imports.response.batchID]);
    assert.deepEqual(report.batchIDs, journal.batchIDs);
    return {brand: {...brand, generation: discovery.generation,
      candidateSnapshotHash: discovery.candidateSnapshotHash, status: discovery.status},
    imports, startedAt: journal.startedAt, uidHash: manifest.identity.uidHash};
  } catch { return fail(); }
}

export async function loadQ7SmokeResume(directory, runID, plan) {
  if (!/^[a-zA-Z0-9-]{8,80}$/.test(runID)) throw new Error("Q7_INVALID_RUN_ID");
  const names = [runID + ".json", "report.json", "manifest.json", "evidence/discovery/A.json"];
  const raw = await Promise.all(names.map((name) => readFile(join(directory, name), "utf8")));
  let originals = names.map((name, index) => ({name, raw: raw[index], sha256: sha(raw[index])}));
  let values = raw.map((value) => JSON.parse(value));
  if (values[2].resumption) {
    const proof = JSON.parse(await readFile(join(directory, "evidence/resume-original/digests.json"), "utf8"));
    assert.equal(proof.runID, runID);
    assert.equal(proof.priorMutationCount, 2);
    const saved = await Promise.all(names.map((name) => readFile(join(directory,
      "evidence/resume-original", name.replaceAll("/", "__")), "utf8")));
    originals = names.map((name, index) => ({name, raw: saved[index], sha256: sha(saved[index])}));
    for (const file of originals) assert.equal(proof.files.find((entry) => entry.name === file.name)?.sha256, file.sha256);
    const prior = saved.map((value) => JSON.parse(value));
    assert.deepEqual(values[0].requests, prior[0].requests);
    assert.notEqual(values[0].finalized, true);
    assert.equal(values[0].startedAt, prior[0].startedAt);
    assert.equal(values[0].runID, runID);
    assert.equal(values[2].runID, runID);
    assert.deepEqual(values[2].identity, prior[2].identity);
    assert.deepEqual(values[2].plan, prior[2].plan);
    assert.equal(values[2].brands.length, 1);
    assert.equal(values[2].brands[0].brandID, prior[2].brands[0].brandID);
    assert.equal(values[2].batches.length, 1);
    assert.equal(values[2].batches[0].batchID, prior[0].requests[1].response.batchID);
    assert.equal(values[2].jobs.length, 0);
    values = prior;
  }
  const [journal, report, manifest, discovery] = values;
  const state = validateQ7SmokeResume({runID, journal, report, manifest, discovery}, plan);
  return {state, manifest, journal, originals};
}

export async function preserveQ7ResumeOriginals(directory, resume) {
  const evidenceDirectory = join(directory, "evidence/resume-original");
  await mkdir(evidenceDirectory, {recursive: true, mode: 0o700});
  for (const file of resume.originals) {
    const target = join(evidenceDirectory, file.name.replaceAll("/", "__"));
    try { await writeFile(target, file.raw, {flag: "wx", mode: 0o600}); }
    catch (error) {
      if (error.code !== "EEXIST" || sha(await readFile(target, "utf8")) !== file.sha256) throw error;
    }
  }
  const proof = {schemaVersion: 1, runID: resume.journal.runID,
    priorMutationCount: 2, originalStartedAt: resume.state.startedAt,
    files: resume.originals.map(({name, sha256}) => ({name, sha256}))};
  await writeFile(join(evidenceDirectory, "digests.json"), JSON.stringify(proof, null, 2), {mode: 0o600});
  return proof;
}

// 이전 실패를 성능 통과로 바꾸지 않는다. 종료·복구 audit가 확인된 이력만 기능 재개의 앞부분으로 분리한다.
export function assertQ7RecoveredWorkflow(batches, ids, revision, discoveryBatchID) {
  const batch = batches.find((item) => item.id === discoveryBatchID);
  assert.ok(batch && batch.kind === "discoverSeasons");
  assert.equal([...batches].sort((a, b) => a.sequence - b.sequence)[0].id, discoveryBatchID);
  const historical = batch.runs.filter((run) => run.revision !== revision);
  assert.ok(historical.length > 0);
  let previousFinish = 0;
  const failures = [];
  for (const run of [...historical].sort((a, b) => a.startedAt - b.startedAt)) {
  assert.equal(run.state, "recoveryRequired");
  assert.equal(run.batchID, batch.id);
  assert.equal(run.projectID, "outpick-test");
  assert.equal(run.runID, `${batch.id}-${run.epoch}`);
  assert.equal(run.terminalConfirmed, true);
  assert.equal(run.inFlight, 0);
  assert.ok(Number.isSafeInteger(run.startedAt) && Number.isSafeInteger(run.finishedAt) && run.finishedAt >= run.startedAt);
  assert.ok(run.startedAt >= previousFinish);
  const audit = batch.recoveryDecisions?.find((item) => item.runID === run.runID);
  assert.equal(audit?.decision, "resume");
  assert.equal(audit.projectID, "outpick-test");
  assert.equal(audit.serviceName, "lookbook-import-worker-development");
  assert.equal(audit.batchID, batch.id);
  assert.equal(audit.revision, run.revision);
  assert.equal(audit.expectedEpoch, run.epoch);
  assert.equal(audit.uncertainAssetWriteCount, 0);
  assert.equal(audit.evidence?.kind, "durableDrain");
  assert.equal(audit.evidence.runID, run.runID);
  assert.equal(audit.evidence.terminalConfirmed, true);
  assert.equal(audit.evidence.inFlight, 0);
  const next = batch.runs.filter((item) => item.startedAt >= run.finishedAt && item.runID !== run.runID)
    .sort((a, b) => a.startedAt - b.startedAt)[0];
  assert.ok(next && next.startedAt >= audit.createdAt);
  assert.equal(audit.servingRevision, next.revision);
  failures.push({runID: run.runID, revision: run.revision,
    memoryStop: run.resourceEvidence?.memoryStop ?? null, recoveryDecisionID: audit.decisionID});
  previousFinish = run.finishedAt;
  }
  const following = batch.runs.filter((item) => item.revision === revision);
  assert.ok(following.length && following.every((item) => item.startedAt >= previousFinish));
  const current = batches.map((item) => item.id === batch.id ? {...item, runs: following} : item);
  return {...assertBatchRunEvidence(current, ids, revision),
    performanceStatus: "historicalFailurePreserved", historicalFailureRunID: failures[0].runID,
    historicalFailures: failures};
}

function sha(raw) { return createHash("sha256").update(raw).digest("hex"); }

export function validateQ7Finalization({runID, journal, report, manifest}, plan) {
  try {
    assert.equal(plan.stage, "smoke");
    assert.equal(journal.runID, runID);
    assert.equal(report.runID, runID);
    assert.equal(manifest.runID, runID);
    assert.equal(journal.projectID, "outpick-test");
    assert.equal(manifest.projectID, "outpick-test");
    assert.equal(journal.stage, "smoke");
    assert.equal(report.stage, "smoke");
    assert.equal(manifest.stage, "smoke");
    assert.equal(journal.status, "stopped");
    assert.equal(report.status, "stopped");
    assert.notEqual(journal.finalized, true);
    assert.equal(journal.mutationCount, 7);
    assert.equal(report.mutationCount, 7);
    assert.equal(journal.requests.length, 7);
    assert.equal(journal.startedAt, manifest.createdAt);
    assert.equal(journal.planDigest, plan.planDigest);
    assert.equal(journal.sourceInputDigest, plan.sourceInputDigest);
    assert.deepEqual(manifest.plan, plan);
    assert.equal(manifest.validationScope, "functionalStorageSmoke");
    assert.equal(manifest.overlapDeferredTo, "tenBrands100msWave");
    assert.equal(manifest.brands.length, 2);
    assert.match(manifest.identity.uidHash, /^[a-f0-9]{64}$/);
    assert.deepEqual(journal.requests.map((item) => item.callable), ["createBrand",
      "requestSeasonCandidateImportJobs", "createBrand", "reviewLookbookExtraction",
      "reviewLookbookExtraction", "requestSeasonCandidateImportJobs", "reviewLookbookExtraction"]);
    for (const request of journal.requests) {
      assert.equal(request.state, "accepted");
      assert.equal(request.requestID, request.payload.requestID);
      assert.equal(request.requestID, request.response.requestID);
      assert.equal(request.payloadDigest, sha(JSON.stringify(request.payload)));
      assert.match(request.response.batchID, /^[a-f0-9]{64}$/);
    }
    const ids = journal.requests.map((item) => item.response.batchID);
    assert.equal(new Set(ids).size, 7);
    assert.equal(new Set(journal.requests.map((item) => item.requestID)).size, 7);
    assert.deepEqual(journal.batchIDs, ids);
    assert.deepEqual(report.batchIDs, ids);
    for (const [index, ordinal] of [[0, 0], [1, 2]]) {
      const brand = manifest.brands[index], request = journal.requests[ordinal];
      assert.equal(brand.letter, index ? "B" : "A");
      assert.equal(brand.brandID, request.response.brandID);
      assert.equal(brand.discoveryJobID, request.response.discoveryJobID);
      assert.equal(brand.discoveryBatchID, request.response.batchID);
    }
  } catch { throw new Error("Q7_FINALIZATION_CONTRACT_MISMATCH"); }
}

export async function loadQ7Finalization(directory, runID, plan) {
  if (!/^[a-zA-Z0-9-]{8,80}$/.test(runID)) throw new Error("Q7_INVALID_RUN_ID");
  const raw = await Promise.all([runID + ".json", "report.json", "manifest.json"].map((name) =>
    readFile(join(directory, name), "utf8")));
  const [journal, report, manifest] = raw.map((value) => JSON.parse(value));
  validateQ7Finalization({runID, journal, report, manifest}, plan);
  return {journal, report, manifest};
}

export function assertQ7ExtractedContinuation({queue, brand, discoveryJob, discoveryBatch,
  importBatch, expectedBrand, pending, uid}) {
  try {
    assert.equal(queue?.state, "idle");
    assert.equal(queue.headBatchID ?? null, null);
    assert.equal(discoveryBatch?.state, "released");
    assert.equal(discoveryBatch.brandID, expectedBrand.brandID);
    assert.equal(discoveryBatch.items.length, 1);
    assert.equal(discoveryBatch.items[0].jobID, expectedBrand.discoveryJobID);
    assert.equal(discoveryBatch.items[0].processingStatus, "succeeded");
    assert.equal(discoveryJob?.status, "succeeded");
    assert.equal(discoveryJob.generation, expectedBrand.generation);
    assert.equal(discoveryJob.candidateSnapshotHash, expectedBrand.candidateSnapshotHash);
    assert.equal(brand?.publishedSeasonDiscoveryJobID, expectedBrand.discoveryJobID);
    assert.equal(brand.publishedSeasonDiscoveryGeneration, expectedBrand.generation);
    assert.equal(brand.publishedSeasonDiscoverySnapshotHash, expectedBrand.candidateSnapshotHash);
    assert.equal(importBatch?.state, "released");
    assert.equal(importBatch.requestID, pending.requestID);
    assert.equal(importBatch.brandID, expectedBrand.brandID);
    assert.equal(importBatch.requestedBy, uid);
    assert.deepEqual(importBatch.items.map((item) => item.targetID), pending.payload.candidateIDs);
    assert.ok(importBatch.items.length === 2 && importBatch.items.every((item) =>
      item.admissionStatus === "created" && item.processingStatus === "awaitingReview" &&
      typeof item.jobID === "string" && item.jobID && item.activeRunID == null));
    assert.equal(new Set(importBatch.items.map((item) => item.jobID)).size, 2);
  } catch { throw new Error("Q7_EXTRACTED_CONTINUATION_CHANGED"); }
}
