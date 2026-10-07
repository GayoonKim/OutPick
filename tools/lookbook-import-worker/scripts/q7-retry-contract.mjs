import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {fixture} from "./queue-development-contract.mjs";
import {readFile} from "node:fs/promises";

const hash = (value) => createHash("sha256").update(JSON.stringify(value)).digest("hex");
export function predictRetryIdentity(uid, requestID) {
  assert.ok(typeof uid === "string" && uid.length > 0);
  assert.match(requestID, /^[a-f0-9-]{36}$/);
  const batchID = hash([uid, requestID]), itemID = hash([batchID, 0]);
  return {batchID, itemID, jobID: hash([batchID, itemID, "job"]),
    executionID: hash([batchID, itemID, "execution"])};
}

export function makeRetryKLPlan() {
  const season = fixture.seasons.find((item) => item.seasonID === "2026SS");
  const golden = fixture.golden.find((item) => item.seasonID === "2026SS");
  assert.equal(season.images.length, 30);
  assert.equal(golden.uploadFiles, 62);
  return {version: 1, stage: "retryKL", projectID: "outpick-test", maxMutations: 8,
    durationMs: 1200000, maxPolls: 400, maxTaskDeliveries: 20,
    archiveURL: "https://unaffected.co.kr/collection.html?cate_no=88",
    sourceURL: season.sourceURL, seasonID: "2026SS", brands: ["K", "L"],
    expectedFiles: 124, sourceInputDigest: fixture.sourceInputDigest,
    expectedSuccessUploadBytes: golden.uploadBytes * 2,
    limits: {newManagementUSD: 1, cumulativeManagementUSD: 10},
  };
}

export async function runRetryKL(ports, resumedK = null, interruptedApproval = null) {
  const k = resumedK ?? await ports.create("K");
  if (!resumedK) {
    const kImport = await ports.importSeason(k, false);
    await ports.waitReleased(kImport, {expected: "awaitingReview"});
  }
  const oldReview = interruptedApproval?.review ?? await ports.review(k);
  const firstApproval = interruptedApproval?.pending ?? await ports.approve(k, oldReview, true);
  if (interruptedApproval) await ports.redeliverK(firstApproval);
  await ports.waitReleased(firstApproval, {expected: "awaitingReview", allowTermination: true});
  const newReview = await ports.review(k);
  assert.ok(newReview.reviewGeneration > oldReview.reviewGeneration, "Q7_NEW_REVIEW_REQUIRED");
  const lastApproval = await ports.approve(k, newReview, false);
  await ports.waitReleased(lastApproval, {expected: "succeeded"});
  await ports.verifyK(k, firstApproval);
  const l = await ports.create("L");
  const lImport = await ports.importSeason(l, true);
  await ports.waitReleased(lImport, {expected: "failed"});
  const failures = await ports.failures(l);
  assert.equal(failures.length, 1);
  const failure = failures[0];
  assert.equal(failure.state, "failed");
  assert.equal(failure.attemptCount, 5);
  assert.equal(failure.attemptLimit, 5);
  assert.equal(failure.latestExecutionID, l.executionID);
  const manual = await ports.retry(l, failure);
  assert.notEqual(manual.executionID, failure.latestExecutionID);
  await ports.waitReleased(manual, {expected: "awaitingReview"});
  const finalReview = await ports.review(l);
  const lApproval = await ports.approve(l, finalReview, false);
  await ports.waitReleased(lApproval, {expected: "succeeded"});
  assert.equal((await ports.failures(l)).length, 0);
  return ports.verifyFinal(k, l, {originalLExecutionID: failure.latestExecutionID,
    manualBatchID: manual.batchID, kTerminatedBatchID: firstApproval.batchID});
}

export function retryReviewJob(raw, brand) {
  assert.equal(raw.brandID, brand.brandID);
  if (raw.jobID != null) assert.equal(raw.jobID, brand.jobID);
  return {...raw, jobID: brand.jobID};
}

export async function readRetryExecutionWrites(db, brand) {
  const prefix = `brands/${brand.brandID}/importJobs/${brand.jobID}/executions/${brand.executionID}/assets/`;
  const refs = await db.doc(`brands/${brand.brandID}/importJobs/${brand.jobID}/executions/${brand.executionID}`).collection("assets").listDocuments();
  assert.ok(refs.length <= 31, "Q7_RETRY_ASSET_SCOPE_LIMIT");
  const writes = [];
  for (const ref of refs) {
    const snapshot = await ref.collection("writes").get();
    assert.ok(snapshot.docs.length <= 5, "Q7_RETRY_WRITE_SCOPE_LIMIT");
    for (const doc of snapshot.docs) {
      assert.ok(doc.ref.path.startsWith(prefix));
      const data = doc.data(); assert.equal(data.executionID, brand.executionID);
      writes.push({path: doc.ref.path, ...data});
    }
  }
  return writes;
}

export function assertRetryKLResume({manifest, report, journal, runID, now = Date.now()}) {
  assert.equal(manifest.runID, runID); assert.equal(report.runID, runID); assert.equal(journal.runID, runID);
  assert.equal(report.status, "stopped"); assert.equal(journal.status, "stopped");
  assert.equal(manifest.stage, "retryKL"); assert.equal(report.stage, "retryKL");
  assert.deepEqual(manifest.plan, makeRetryKLPlan());
  assert.equal(manifest.mutationCount, 2); assert.equal(report.mutationCount, 2);
  assert.equal(report.startedAt, manifest.startedAt);
  assert.ok(now >= manifest.startedAt && now - manifest.startedAt < manifest.plan.durationMs);
  assert.equal(manifest.brands.length, 1); assert.equal(manifest.brands[0].letter, "K");
  assert.equal(manifest.files.length, 0); assert.equal(journal.requests.length, 2);
  assert.equal(manifest.requests.length, 2);
  assert.deepEqual(journal.requests.map((item) => item.callable), ["createBrand", "requestSeasonCandidateImportJobs"]);
  journal.requests.forEach((item, index) => {
    assert.equal(item.state, "accepted"); assert.equal(item.requestID, manifest.requests[index].requestID);
    assert.equal(item.response.batchID, manifest.requests[index].batchID);
    assert.equal(item.payloadDigest, hash(item.payload));
  });
  const brand = manifest.brands[0];
  assert.equal(journal.requests[0].response.brandID, brand.brandID);
  assert.equal(journal.requests[0].response.discoveryJobID, brand.discoveryJobID);
  assert.equal(journal.requests[1].payload.brandID, brand.brandID);
  assert.deepEqual(journal.requests[1].payload.candidateIDs, [brand.candidateID]);
  assert.equal(journal.requests[1].response.batchID, brand.importBatchID);
  assert.deepEqual(manifest.batches, [{id: brand.importBatchID,
    requestID: journal.requests[1].requestID, expected: "awaitingReview"}]);
  return brand;
}

export function assertRetryKLContinuation({manifest, report, journal, runID}) {
  assert.equal(report.clientInterrupted, true);
  assert.equal(report.newInputStopped, true);
  assert.equal(report.serverQueueModified, false);
  assert.equal(report.reason, "PLATFORM_TERMINATION_LOGNAME_FILTER_ZERO_MATCHES");
  assert.equal(report.mutationCount, 3); assert.equal(manifest.mutationCount, 3);
  assert.equal(journal.requests.length, 3); assert.equal(manifest.requests.length, 3);
  assert.ok(["running", "stopped"].includes(journal.status));
  assert.equal(manifest.continuation, undefined, "Q7_CONTINUATION_ALREADY_STARTED");
  // 중지 신호로 journal 종료 상태가 남지 않은 원본을 보존하고, 앞 두 영수증은 기존 계약으로 검사한다.
  const brand = assertRetryKLResume({manifest: {...manifest, mutationCount: 2, requests: manifest.requests.slice(0, 2)},
    report: {...report, mutationCount: 2}, journal: {...journal, status: "stopped", requests: journal.requests.slice(0, 2)},
    runID, now: manifest.startedAt + 1});
  const request = journal.requests[2], recorded = manifest.requests[2];
  assert.equal(request.callable, "reviewLookbookExtraction"); assert.equal(request.state, "accepted");
  assert.equal(request.requestID, recorded.requestID); assert.equal(request.response.batchID, recorded.batchID);
  assert.equal(request.payloadDigest, hash(request.payload));
  assert.equal(request.payload.brandID, brand.brandID); assert.equal(request.payload.jobID, brand.jobID);
  assert.equal(request.payload.decision, "approved"); assert.deepEqual(request.payload.excludedCandidateKeys, []);
  assert.equal(request.payload.expectedCandidateCount, 30);
  assert.ok(Number.isSafeInteger(request.payload.reviewGeneration) && request.payload.reviewGeneration > 0);
  assert.ok(request.payload.reviewSnapshotHash);
  return {brand, pending: {...request.response, requestID: request.requestID, brand}, review: request.payload};
}

export function assertRetryContinuationRemote({resume, uid, queue, batches, job, execution, fault, run, proof, writes}) {
  const {brand, pending} = resume;
  assert.equal(resume.manifest.uidHash, createHash("sha256").update(uid).digest("hex"));
  const predicted = predictRetryIdentity(uid, resume.journal.requests[1].requestID);
  assert.equal(predicted.jobID, brand.jobID); assert.equal(predicted.executionID, brand.executionID);
  assert.equal(queue.headBatchID, pending.batchID); assert.equal(queue.state, "active");
  assert.equal(batches.length, 3);
  for (const [index, batch] of batches.entries()) {
    assert.equal(batch.brandID, brand.brandID); assert.equal(batch.requestedBy, uid);
    assert.equal(batch.requestID, resume.journal.requests[index].requestID);
    assert.equal(batch.state, index < 2 ? "released" : "active");
  }
  const batch = batches[2];
  assert.equal(batch.runID, queue.runID); assert.equal(batch.epoch, queue.epoch);
  assert.equal(batch.kind, "reviewApproval"); assert.equal(batch.items.length, 1);
  assert.equal(batch.items[0].jobID, brand.jobID); assert.equal(batch.items[0].executionID, brand.executionID);
  assert.equal(batch.items[0].processingStatus, "active");
  assert.equal(execution.status, "active"); assert.equal(execution.attemptCount, 1); assert.equal(execution.attemptLimit, 5);
  assert.equal(execution.activeRunID, batch.runID);
  assert.equal(job.status, "processing"); assert.equal(job.queueExecutionID, brand.executionID);
  assert.equal(fault.scenario, "oomAfterUpload"); assert.equal(fault.batchID, pending.batchID);
  assert.equal(fault.executionID, brand.executionID); assert.equal(fault.brandID, brand.brandID);
  assert.deepEqual(Object.keys(fault.consumedAttempts), ["1"]);
  assert.equal(fault.consumedAttempts["1"].runID, batch.runID);
  assert.equal(run.runID, batch.runID); assert.equal(run.epoch, batch.epoch);
  assert.equal(run.revision, resume.manifest.workerRevision);
  assert.equal(proof.kind, "platformTermination"); assert.equal(proof.projectID, "outpick-test");
  assert.equal(proof.serviceName, "lookbook-import-worker-development"); assert.equal(proof.revision, run.revision);
  assert.equal(proof.traceID, run.traceID); assert.ok(proof.instanceID && proof.insertID);
  assert.ok(Number.isFinite(Date.parse(proof.timestamp)) && Date.parse(proof.timestamp) >= run.startedAt);
  assert.ok(!run.resourceEvidence?.memoryStop && !run.resourceEvidence?.admissionStop);
  assert.equal(run.settlement, undefined);
  assert.ok(writes.length > 0);
  for (const write of writes) {
    assert.equal(write.executionID, brand.executionID); assert.equal(write.epoch, batch.epoch);
    assert.ok(["uploading", "unpublished"].includes(write.status));
  }
  return {batchID: pending.batchID, dispatchGeneration: batch.dispatchGeneration, queueContractVersion: 1};
}

export function assertRetryDeliveryBudget({historical, additional = 0, reserve = 0}) {
  for (const value of [historical, additional, reserve]) assert.ok(Number.isSafeInteger(value) && value >= 0);
  assert.ok(additional + reserve <= 10 && historical + additional + reserve <= 30,
    "Q7_RETRY_TASK_DELIVERY_LIMIT");
}

export async function redeliverRetryK({delivery, candidateURL, campaignID, existingTask, ports}) {
  assert.match(delivery.batchID, /^[a-f0-9]{64}$/);
  assert.ok(Number.isSafeInteger(delivery.dispatchGeneration) && delivery.dispatchGeneration >= 0);
  assert.equal(delivery.queueContractVersion, 1);
  assert.match(campaignID, /^[a-f0-9-]{36}$/);
  assert.match(candidateURL, /^https:\/\/q7-20261006---lookbook-import-worker-development-[a-z0-9-]+\.a\.run\.app$/);
  const parent = "projects/outpick-test/locations/asia-northeast3/queues/lookbook-import-jobs";
  const oldName = `${parent}/tasks/batch-${delivery.batchID}-${delivery.dispatchGeneration}`;
  const task = {name: `${parent}/tasks/q7-retry-${campaignID}-${delivery.dispatchGeneration}`,
    dispatchDeadline: "900s", httpRequest: {httpMethod: "POST", url: candidateURL + "/tasks/import-batch",
      headers: {"Content-Type": "application/json"}, body: Buffer.from(JSON.stringify(delivery)).toString("base64"),
      oidcToken: {serviceAccountEmail: "outpick-lookbook-task-dev@outpick-test.iam.gserviceaccount.com",
        audience: "https://lookbook-import-worker-development-xyenspjiwa-du.a.run.app"}}};
  if (existingTask) {
    assert.equal(existingTask.name, oldName);
    assert.equal(existingTask.httpRequest.url, task.httpRequest.url);
    assert.equal(existingTask.httpRequest.httpMethod, "POST");
    assert.deepEqual(existingTask.httpRequest.oidcToken, task.httpRequest.oidcToken);
    assert.deepEqual(JSON.parse(Buffer.from(existingTask.httpRequest.body, "base64").toString()), delivery);
  }
  // 전송 의도를 배타적으로 저장하지 못하면 Cloud Tasks를 호출하지 않는다.
  await ports.recordIntent({operation: existingTask ? "runExisting" : "createReplacement", delivery, taskName: existingTask?.name ?? task.name});
  return existingTask ? ports.run(existingTask.name) : ports.create(parent, task);
}

export async function loadRetryKLResume(directory, runID, continuation = false) {
  const raws = await Promise.all(["manifest.json", "report.json", runID + ".json"].map((name) => readFile(directory + "/" + name, "utf8")));
  const [manifest, report, journal] = raws.map(JSON.parse);
  const state = continuation ? assertRetryKLContinuation({manifest, report, journal, runID}) :
    {brand: assertRetryKLResume({manifest, report, journal, runID})};
  return {manifest, report, journal, ...state, sourceDigests: raws.map((raw) => createHash("sha256").update(raw).digest("hex"))};
}

export function assertRetryKEvidence({batch, runs, execution, fault, originalAttempt, expectedRevision}) {
  assert.equal(batch.state, "released");
  assert.equal(execution.status, "succeeded");
  assert.equal(execution.attemptCount, 2);
  assert.equal(execution.attemptLimit, 5);
  assert.equal(Object.keys(fault.consumedAttempts ?? {}).length, 1);
  const interrupted = runs.find((run) => run.runID === fault.consumedAttempts["1"]?.runID);
  assert.ok(interrupted);
  const proof = interrupted.terminationEvidence;
  assert.equal(proof?.kind, "platformTermination");
  assert.equal(proof.projectID, "outpick-test");
  assert.equal(proof.serviceName, "lookbook-import-worker-development");
  assert.equal(proof.revision, expectedRevision);
  assert.equal(proof.traceID, interrupted.traceID);
  assert.ok(proof.instanceID && proof.insertID && Number.isFinite(Date.parse(proof.timestamp)));
  assert.equal(interrupted.settlement, "restartFromParsing");
  assert.equal(originalAttempt.errorCode, "WORKER_TERMINATED");
  assert.ok(runs.some((run) => run.epoch > interrupted.epoch && run.terminalConfirmed === true && run.inFlight === 0));
  return {terminatedRunID: interrupted.runID, instanceID: proof.instanceID,
    terminationInsertID: proof.insertID, attemptCount: execution.attemptCount};
}
