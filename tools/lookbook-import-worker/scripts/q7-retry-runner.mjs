#!/usr/bin/env node
import assert from "node:assert/strict";
import {randomUUID, createHash} from "node:crypto";
import {execFileSync} from "node:child_process";
import {mkdir, open} from "node:fs/promises";
import {initializeApp, deleteApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {startQ7Session} from "./q7-session.mjs";
import {openQ7Campaign, openQ7Journal, atomicSave} from "./q7-journal.mjs";
import {createQ7Callable} from "./q7-callable.mjs";
import {fixture, assertReviewMatches} from "./queue-development-contract.mjs";
import {readQ7StorageOutput, q7PublishedCoverReference} from "./q7-storage-evidence.mjs";
import {Q7_SERVICE, Q7_TAG, Q7_QUEUES, assertQ7DevelopmentSnapshot} from "./q7-development-preflight.mjs";
import {makeRetryKLPlan, predictRetryIdentity, runRetryKL, assertRetryKEvidence, retryReviewJob, loadRetryKLResume, readRetryExecutionWrites,
  assertRetryContinuationRemote, assertRetryDeliveryBudget, redeliverRetryK} from "./q7-retry-contract.mjs";

const options = Object.fromEntries(process.argv.slice(2).map((argument) => {
  const match = /^--(campaign|config|digest|resume|continue|fault-campaign)=(.+)$/.exec(argument);
  if (!match) throw new Error("Q7_RETRY_OPTION_INVALID");
  return [match[1], match[2]];
}));
assert.match(options.campaign ?? "", /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/);
assert.match(options.digest ?? "", /^[a-f0-9]{64}$/);
assert.ok(options.config);
const plan = makeRetryKLPlan(), runID = options.campaign;
const root = new URL("../../../output/lookbook-import-performance/product-queue-q7/", import.meta.url).pathname;
const directory = root + runID;
if (options.resume != null) assert.equal(options.resume, "true");
const continuation = options.continue != null;
if (continuation) {
  assert.equal(options.continue, "true"); assert.equal(options.resume, undefined);
  assert.match(options["fault-campaign"] ?? "", /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/);
  assert.notEqual(options["fault-campaign"], runID);
} else assert.equal(options["fault-campaign"], undefined);
const resume = options.resume || continuation ? await loadRetryKLResume(directory, runID, continuation) : null;
const lock = await openQ7Campaign(root, "retryKL", resume ? runID : null, false, continuation);
await mkdir(directory, {recursive: true, mode: 0o700});
const journal = await openQ7Journal(directory, runID, {projectID: "outpick-test", stage: "retryKL", startedAt: Date.now()});
const app = initializeApp({projectId: "outpick-test", storageBucket: "outpick-test.firebasestorage.app"}, "retry-" + runID);
const db = getFirestore(app), bucket = getStorage(app).bucket();
const faultCampaignID = options["fault-campaign"] ?? runID;
const faultRoot = db.doc(`lookbookImportQ7FaultCampaigns/${faultCampaignID}`);
const oldFaultRoot = db.doc(`lookbookImportQ7FaultCampaigns/${runID}`);
const originalStartedAt = resume?.manifest.startedAt;
const oldRevision = resume?.manifest.workerRevision;
let session, startedAt = continuation ? undefined : originalStartedAt, mutationCount = resume?.manifest.mutationCount ?? 0,
  pollCount = continuation ? 0 : resume?.manifest.pollCount ?? 0, identity, redelivery, historicalLogs;
const manifest = resume?.manifest ?? {runID, stage: "retryKL", projectID: "outpick-test", plan, brands: [], batches: [], requests: [], files: []};
const originalResume = continuation ? structuredClone(resume) : null;
const write = (name, value) => atomicSave(directory + "/" + name, value);
const normalize = (value) => value?.toMillis ? value.toMillis() : value instanceof Date ? value.getTime() :
  Array.isArray(value) ? value.map(normalize) : value && typeof value === "object" ?
    Object.fromEntries(Object.entries(value).map(([key, item]) => [key, normalize(item)])) : value;
const snapshot = async (ref) => normalize((await ref.get()).data());
const save = async () => write("manifest.json", {...manifest, mutationCount, pollCount});
const gcloud = (args) => JSON.parse(execFileSync("gcloud", [...args, "--project=outpick-test", "--format=json"],
  {encoding: "utf8", maxBuffer: 8 * 1024 * 1024, timeout: 60000}));
const clockGuard = () => {if (Date.now() - startedAt >= plan.durationMs) throw new Error("Q7_RETRY_WINDOW_EXCEEDED");};
async function tasksAPI(path, body) {
  const token = execFileSync("gcloud", ["auth", "print-access-token"], {encoding: "utf8", timeout: 30000}).trim();
  const response = await fetch("https://cloudtasks.googleapis.com/v2/" + path,
    {method: body ? "POST" : "GET", headers: {Authorization: "Bearer " + token, "Content-Type": "application/json"},
      ...(body ? {body: JSON.stringify(body)} : {}), signal: AbortSignal.timeout(30000)});
  if (!response.ok) throw new Error("Q7_TASK_API_HTTP_" + response.status);
  return response.json();
}

async function continuationReadback() {
  const brand = originalResume.brand;
  const queue = await snapshot(db.doc("lookbookImportQueue/main"));
  const batches = await Promise.all(originalResume.manifest.requests.map((request) => snapshot(db.doc(`lookbookImportBatches/${request.batchID}`))));
  const job = await snapshot(db.doc(`brands/${brand.brandID}/importJobs/${brand.jobID}`));
  const execution = await snapshot(db.doc(`brands/${brand.brandID}/importJobs/${brand.jobID}/executions/${brand.executionID}`));
  const fault = await snapshot(oldFaultRoot.collection("targets").doc(brand.executionID));
  const runID = batches[2].runID;
  const run = {runID, ...await snapshot(db.doc(`lookbookImportBatches/${originalResume.pending.batchID}/runs/${runID}`))};
  const {CloudLoggingRecoveryEvidenceProvider} = await import("../lib/queue/cloud-logging-evidence.js");
  const provider = new CloudLoggingRecoveryEvidenceProvider();
  // 로컬 조회는 기존 CLI 계정으로 수행하며 Worker의 인증·증거 판정은 변경하지 않는다.
  Reflect.set(provider, "auth", {getClient: async () => ({getAccessToken: async () => ({token:
    execFileSync("gcloud", ["auth", "print-access-token"], {encoding: "utf8", timeout: 30000}).trim()})})});
  const proof = await provider.findTerminatedInstance({projectID: "outpick-test", serviceName: Q7_SERVICE,
    revision: run.revision, traceID: run.traceID, startedAt: run.startedAt});
  const writes = await readRetryExecutionWrites(db, brand);
  const evidence = {resume: originalResume, uid: identity.uid, queue, batches, job, execution, fault, run, proof, writes};
  const delivery = assertRetryContinuationRemote(evidence);
  await write("continuation-remote-readback.json", {...evidence, uid: undefined, checkedAt: Date.now()});
  return delivery;
}
const envelope = (data) => ({...data, queueContractVersion: 1, requestID: randomUUID(), requestCreatedAt: Date.now()});
let call;
let lastDeliveryCheck = 0;
function readRunLogs() {
  const filter = `resource.type="cloud_run_revision" AND resource.labels.service_name="${Q7_SERVICE}" ` +
    `AND resource.labels.revision_name="${manifest.workerRevision}" AND timestamp >= "${new Date(startedAt).toISOString()}"`;
  const entries = gcloud(["logging", "read", filter, "--limit=3000"]);
  if (entries.length === 3000) throw new Error("Q7_RETRY_LOG_LIMIT");
  const deliveries = entries.filter((entry) => entry.httpRequest?.requestUrl?.includes("/tasks/import-batch"));
  if (continuation) assertRetryDeliveryBudget({historical: historicalLogs?.deliveries.length ?? 0, additional: deliveries.length});
  else if (deliveries.length > plan.maxTaskDeliveries) throw new Error("Q7_RETRY_TASK_DELIVERY_LIMIT");
  return {entries: [...(historicalLogs?.entries ?? []), ...entries],
    deliveries: [...(historicalLogs?.deliveries ?? []), ...deliveries], additionalDeliveries: deliveries.length};
}
async function mutate(name, data, beforeSend) {
  clockGuard();
  if (continuation) {
    const logs = readRunLogs();
    assertRetryDeliveryBudget({historical: historicalLogs.deliveries.length, additional: logs.additionalDeliveries, reserve: 1});
  }
  if (mutationCount >= 8) throw new Error("Q7_RETRY_MUTATION_LIMIT");
  await journal.appendRequest({requestID: data.requestID, requestCreatedAt: data.requestCreatedAt, callable: name, payload: data});
  if (beforeSend) await beforeSend();
  await journal.updateRequest(data.requestID, {state: "sent", sentAt: Date.now()});
  mutationCount++;
  try {
    const result = await call(name, data);
    await journal.updateRequest(data.requestID, {state: "accepted", acceptedAt: Date.now(), response: result});
    manifest.requests.push({name, requestID: data.requestID, batchID: result.batchID});
    await save();
    return {...result, requestID: data.requestID};
  } catch (error) {
    await journal.updateRequest(data.requestID, {state: "uncertain", uncertainAt: Date.now(), errorCode: error.code ?? "NETWORK_OR_CALLABLE_ERROR"});
    throw error;
  }
}
async function poll(operation, label, interval = 3000) {
  for (;;) {
    clockGuard();
    if (++pollCount > plan.maxPolls) throw new Error("Q7_RETRY_POLL_LIMIT");
    if (manifest.workerRevision && Date.now() - lastDeliveryCheck >= 30000) {
      const logs = readRunLogs();
      await write("runtime-logs-latest.json", logs);
      lastDeliveryCheck = Date.now();
    }
    const result = await operation();
    if (result) return result;
    await new Promise((resolve) => setTimeout(resolve, interval));
  }
}
async function prepared(pending) {
  return poll(async () => {
    const receipt = await call("getSeasonImportBatch", {requestID: pending.requestID});
    if (receipt.batchID !== pending.batchID || receipt.requestID !== pending.requestID) throw new Error("Q7_RETRY_RECEIPT_CHANGED");
    if (receipt.items.length !== 1 || receipt.items[0].admissionStatus !== "created") {
      if (receipt.receiptState === "preparing") return null;
      throw new Error("Q7_RETRY_ADMISSION_NOT_CREATED");
    }
    return receipt;
  }, "prepared");
}
async function arm(brand, pending, scenario, attempt = null) {
  if (continuation) {assert.equal(brand.letter, "L"); assert.equal(scenario, "retryableBeforeDownload");}
  const ref = faultRoot.collection("targets").doc(brand.executionID);
  const value = {campaignID: faultCampaignID, scenario, brandID: brand.brandID, jobID: brand.jobID,
    executionID: brand.executionID, batchID: pending.batchID, ordinal: 0,
    ...(attempt ? {attempt} : {attemptLimit: 5}), createdAt: Date.now()};
  await ref.create(value);
  await write(`fault-${brand.letter}.json`, {path: ref.path, ...value});
}
const ports = {
  async redeliverK() {
    clockGuard();
    const freshDelivery = await continuationReadback();
    assert.deepEqual(freshDelivery, redelivery.delivery);
    await redeliverRetryK({...redelivery, candidateURL: manifest.continuation.candidateURL, campaignID: faultCampaignID,
      ports: {
        recordIntent: async (intent) => {
          const file = await open(directory + "/continuation-task-intent.json", "wx", 0o600);
          try {await file.writeFile(JSON.stringify({...intent, recordedAt: Date.now()})); await file.sync();}
          finally {await file.close();}
        },
        run: (name) => tasksAPI(name + ":run", {responseView: "FULL"}),
        create: (parent, task) => tasksAPI(parent + "/tasks", {task, responseView: "FULL"}),
      }});
    await write("continuation-task-accepted.json", {acceptedAt: Date.now(), delivery: redelivery.delivery});
  },
  async create(letter) {
    const result = await mutate("createBrand", envelope({name: `Q7 Retry ${letter} ${runID.slice(0, 8)}`,
      isFeatured: false, moodIDs: [], websiteURL: "https://unaffected.co.kr", lookbookArchiveURL: plan.archiveURL}));
    const brand = {letter, brandID: result.brandID, discoveryJobID: result.discoveryJobID};
    assert.ok(brand.brandID && brand.discoveryJobID && result.batchID);
    manifest.brands.push(brand); await save();
    await poll(async () => {
      const job = await snapshot(db.doc(`brands/${brand.brandID}/seasonDiscoveryJobs/${brand.discoveryJobID}`));
      if (["failed", "correctionRequired"].includes(job?.status)) throw new Error("Q7_RETRY_DISCOVERY_FAILED");
      if (!["succeeded", "awaitingReview"].includes(job?.status)) return null;
      const batch = await snapshot(db.doc(`lookbookImportBatches/${result.batchID}`));
      if (batch?.state !== "released") return null;
      const pointer = await snapshot(db.doc(`brands/${brand.brandID}`));
      assert.equal(pointer.publishedSeasonDiscoveryJobID, brand.discoveryJobID);
      assert.equal(pointer.publishedSeasonDiscoverySnapshotHash, job.candidateSnapshotHash);
      Object.assign(brand, {generation: job.generation, candidateSnapshotHash: job.candidateSnapshotHash});
      const candidates = await db.collection(`brands/${brand.brandID}/seasonDiscoveryJobs/${brand.discoveryJobID}/candidates`).get();
      const selected = candidates.docs.find((doc) => doc.data().seasonURL === plan.sourceURL);
      assert.equal(selected?.data().resolution, "newSeason");
      brand.candidateID = selected.id;
      await write(`discovery-${letter}.json`, {job, candidates: candidates.docs.map((doc) => ({id: doc.id, ...normalize(doc.data())}))});
      return brand;
    }, "discovery", 10000);
    await save(); return brand;
  },
  async importSeason(brand, fail) {
    const request = envelope({brandID: brand.brandID, discoveryJobID: brand.discoveryJobID,
      generation: brand.generation, candidateIDs: [brand.candidateID], candidateSnapshotHash: brand.candidateSnapshotHash});
    const predicted = predictRetryIdentity(identity.uid, request.requestID);
    Object.assign(brand, {jobID: predicted.jobID, executionID: predicted.executionID, importBatchID: predicted.batchID});
    const pending = await mutate("requestSeasonCandidateImportJobs", request,
      fail ? () => arm(brand, predicted, "retryableBeforeDownload") : null);
    assert.equal(pending.batchID, predicted.batchID);
    pending.brand = brand;
    const receipt = await prepared(pending);
    assert.equal(receipt.items[0].jobID, predicted.jobID);
    assert.equal(receipt.items[0].executionID, predicted.executionID);
    await save(); return pending;
  },
  async waitReleased(pending, {expected, allowTermination = false}) {
    const receipt = await poll(async () => {
      const result = await call("getSeasonImportBatch", {requestID: pending.requestID});
      assert.equal(result.batchID, pending.batchID);
      if (result.receiptState === "recoveryRequired" && !allowTermination) throw new Error("Q7_RETRY_RECOVERY_REQUIRED");
      if (result.receiptState !== "released") return null;
      assert.equal(result.items.length, 1);
      assert.equal(result.items[0].processingStatus, expected);
      return result;
    }, "release");
    manifest.batches.push({id: pending.batchID, requestID: pending.requestID, expected});
    await write(`receipt-${pending.batchID}.json`, receipt); await save();
  },
  async review(brand) {
    const job = await snapshot(db.doc(`brands/${brand.brandID}/importJobs/${brand.jobID}`));
    assert.equal(job.status, "awaitingReview");
    const review = await call("getLookbookExtractionReview", {brandID: brand.brandID, jobID: brand.jobID});
    assertReviewMatches(plan.seasonID, review, retryReviewJob(job, brand));
    await write(`review-${brand.letter}-${review.reviewGeneration}.json`, {job, review});
    return review;
  },
  async approve(brand, review, oom) {
    const request = envelope({brandID: brand.brandID, jobID: brand.jobID,
      reviewGeneration: review.reviewGeneration, reviewSnapshotHash: review.reviewSnapshotHash,
      decision: "approved", excludedCandidateKeys: [], expectedCandidateCount: review.candidates.length});
    const predicted = predictRetryIdentity(identity.uid, request.requestID);
    const pending = await mutate("reviewLookbookExtraction", request,
      oom ? () => arm(brand, predicted, "oomAfterUpload", 1) : null);
    assert.equal(pending.batchID, predicted.batchID);
    pending.brand = brand; return pending;
  },
  async verifyK(brand, pending) {
    const job = db.doc(`brands/${brand.brandID}/importJobs/${brand.jobID}`);
    const batch = await snapshot(db.doc(`lookbookImportBatches/${pending.batchID}`));
    const runs = (await db.collection(`lookbookImportBatches/${pending.batchID}/runs`).get()).docs.map((doc) => ({runID: doc.id, ...normalize(doc.data())}));
    const execution = await snapshot(job.collection("executions").doc(brand.executionID));
    const fault = await snapshot(oldFaultRoot.collection("targets").doc(brand.executionID));
    const originalAttempt = await snapshot(job.collection("executions").doc(brand.executionID).collection("attempts").doc("00001"));
    const result = assertRetryKEvidence({batch, runs, execution, fault, originalAttempt, expectedRevision: continuation ? oldRevision : manifest.workerRevision});
    await write("K-termination-evidence.json", {result, batch, runs, execution, fault, originalAttempt});
    return result;
  },
  async failures(brand) {
    const result = await call("getSeasonImportFailures", {brandID: brand.brandID});
    assert.equal(result.nextCursor, null); return result.items;
  },
  async retry(brand, failure) {
    await write("L-original-failure.json", failure);
    brand.originalExecutionID = brand.executionID;
    const request = envelope({brandID: brand.brandID, failureID: failure.failureID,
      expectedVersion: failure.version, expectedExecutionID: failure.latestExecutionID});
    const pending = await mutate("requestSeasonImportFailureRetry", request);
    const receipt = await prepared(pending);
    assert.equal(receipt.items[0].jobID, brand.jobID);
    brand.executionID = receipt.items[0].executionID;
    pending.executionID = brand.executionID; pending.brand = brand;
    const original = await snapshot(db.doc(`lookbookImportBatches/${brand.importBatchID}`));
    const manual = await snapshot(db.doc(`lookbookImportBatches/${pending.batchID}`));
    assert.ok(manual.sequence > original.sequence); await save(); return pending;
  },
  async verifyFinal(k, l, summary) {
    const original = await snapshot(db.doc(`brands/${l.brandID}/importJobs/${l.jobID}/executions/${summary.originalLExecutionID}`));
    const current = await snapshot(db.doc(`brands/${l.brandID}/importJobs/${l.jobID}/executions/${l.executionID}`));
    assert.equal(original.status, "failed"); assert.equal(original.attemptCount, 5);
    assert.equal(current.status, "succeeded"); assert.equal(current.attemptCount, 1); assert.equal(current.attemptLimit, 5);
    const fault = await snapshot(faultRoot.collection("targets").doc(summary.originalLExecutionID));
    assert.equal(Object.keys(fault.consumedAttempts).length, 5);
    await write("L-retry-evidence.json", {original, current, fault, summary});
    for (const brand of [k, l]) await verifyOutputs(brand);
    assert.equal(manifest.files.length, plan.expectedFiles);
    assert.equal(manifest.files.reduce((sum, item) => sum + item.bytes, 0), plan.expectedSuccessUploadBytes);
    const queue = await snapshot(db.doc("lookbookImportQueue/main"));
    assert.equal(queue.state, "idle"); assert.equal(queue.headBatchID, null);
    await write("final-queue.json", queue);
    const rawBatches = [];
    for (const id of [...new Set(manifest.requests.map((item) => item.batchID))]) {
      const batch = await snapshot(db.doc(`lookbookImportBatches/${id}`));
      const runs = (await db.collection(`lookbookImportBatches/${id}/runs`).get()).docs.map((doc) => ({runID: doc.id, ...normalize(doc.data())}));
      assert.equal(batch.state, "released");
      for (const run of runs) {
        assert.ok([manifest.workerRevision, ...(continuation ? [oldRevision] : [])].includes(run.revision));
        if (run.revision === oldRevision && continuation) assert.ok(run.startedAt < startedAt);
      }
      rawBatches.push({id, ...batch, runs});
    }
    const targetK = await snapshot(oldFaultRoot.collection("targets").doc(k.executionID));
    const oldEpoch = targetK.consumedAttempts["1"].epoch;
    const relevant = (await readRetryExecutionWrites(db, k)).filter((ledger) => ledger.epoch === oldEpoch);
    assert.ok(relevant.length > 0);
    for (const ledger of relevant) {
      assert.equal(ledger.status, "unpublished"); assert.equal(ledger.cleanupState, "pending");
      assert.ok(ledger.cleanupAfter >= (originalStartedAt ?? startedAt) + 86400000);
      assert.ok(!manifest.files.some((file) => file.path === ledger.thumbPath || file.path === ledger.detailPath));
    }
    await write("K-unreferenced-writes.json", normalize(relevant));
    await write("batches.json", rawBatches);
    const logs = readRunLogs();
    await write("runtime-logs-final.json", logs);
    const measurements = logs.entries.flatMap((entry) => {
      const text = entry.textPayload ?? entry.jsonPayload?.message;
      const marker = "[lookbook-import-performance] ";
      if (typeof text !== "string" || !text.includes(marker)) return [];
      try {return [{timestamp: entry.timestamp, ...JSON.parse(text.slice(text.indexOf(marker) + marker.length))}];}
      catch {return [];}
    });
    await write("worker-measurements.json", measurements);
    for (const batch of rawBatches) {
      assert.ok(measurements.some((report) => report.measurement?.batchID === batch.id && report.measurement.complete),
        "Q7_RETRY_NORMAL_MEASUREMENT_MISSING");
    }
    return {passed: true, files: manifest.files.length, verificationBytes: plan.expectedSuccessUploadBytes,
      mutationCount, pollCount, observedTaskDeliveries: logs.deliveries.length,
      ...(continuation ? {originalPollCount: null, additionalTaskDeliveries: logs.additionalDeliveries,
        revisions: [oldRevision, manifest.workerRevision], singleRevisionExperiment: false} : {}),
      killedRequestMeasurement: "프로세스 종료로 마지막 계측 보고 미발행; 플랫폼 종료 증거와 분리", ...summary};
  },
};
async function verifyOutputs(brand) {
  const job = await snapshot(db.doc(`brands/${brand.brandID}/importJobs/${brand.jobID}`));
  assert.equal(job.status, "succeeded");
  const seasonRef = db.doc(`brands/${brand.brandID}/seasons/${job.targetSeasonID}`);
  const season = await snapshot(seasonRef), posts = await seasonRef.collection("posts").get();
  assert.equal(posts.size, 30);
  const executionPrefix = `brands/${brand.brandID}/importJobs/${brand.jobID}/executions/`;
  const coverLedger = await snapshot(db.doc(`${executionPrefix}${season.coverAssetExecutionID}/assets/${season.coverAssetKey}/writes/${season.coverAssetWriteID}`));
  const refs = [q7PublishedCoverReference(season, coverLedger)];
  for (const post of posts.docs) {
    const media = post.data().media[0];
    const ledger = await snapshot(db.doc(`${executionPrefix}${media._assetExecutionID}/assets/${media._assetKey}/writes/${media._assetWriteID}`));
    assert.equal(ledger.status, "published"); assert.equal(ledger.executionID, brand.executionID);
    assert.equal(ledger.thumbPath, media.thumbPath); assert.equal(ledger.detailPath, media.detailPath);
    refs.push({kind: "post", sourceURL: media.remoteURL, thumbPath: media.thumbPath, detailPath: media.detailPath,
      thumbGeneration: ledger.objects.thumb.generation, detailGeneration: ledger.objects.detail.generation});
  }
  const seasonFixture = fixture.seasons.find((item) => item.seasonID === plan.seasonID);
  const sourceHashes = new Map(seasonFixture.images.map((item) => [item.sourceURL, item.sha256]));
  const outputs = fixture.golden.find((item) => item.seasonID === plan.seasonID).outputs;
  for (const ref of refs) {
    const sourceHash = ref.kind === "cover" ? fixture.covers.find((item) => item.seasonID === plan.seasonID).sha256 : sourceHashes.get(ref.sourceURL);
    for (const [path, generation, maxPixel] of [[ref.thumbPath, ref.thumbGeneration, ref.kind === "cover" ? 512 : 768],
      [ref.detailPath, ref.detailGeneration, ref.kind === "cover" ? 1600 : 1920]]) {
      assert.ok(path.includes(`/imports/${brand.executionID}/`));
      const expected = outputs.find((item) => item.sourceHash === sourceHash && item.maxPixel === maxPixel);
      assert.ok(expected);
      const checked = await readQ7StorageOutput(bucket, path, {...expected, generation});
      manifest.files.push({brand: brand.letter, path, sourceHash, ...checked});
      await save();
    }
  }
  await write(`final-${brand.letter}.json`, {job, season, posts: posts.docs.map((doc) => ({id: doc.id, ...normalize(doc.data())}))});
}
try {
  if (continuation) {
    const file = await open(directory + "/continuation-original.json", "wx", 0o600);
    try {await file.writeFile(JSON.stringify(originalResume, null, 2)); await file.sync();}
    finally {await file.close();}
  }
  session = await startQ7Session({firebaseConfigPath: options.config});
  console.log("Development 관리자 로그인: " + session.url);
  execFileSync("open", ["-a", "Google Chrome", session.url]);
  identity = await Promise.race([session.login, new Promise((_, reject) => setTimeout(() => reject(new Error("Q7_LOGIN_TIMEOUT")), 300000).unref())]);
  const service = gcloud(["run", "services", "describe", Q7_SERVICE, "--region=asia-northeast3"]);
  const tagged = service.status.traffic.find((item) => item.tag === Q7_TAG);
  const revision = gcloud(["run", "revisions", "describe", tagged.revisionName, "--region=asia-northeast3"]);
  const functionConfig = gcloud(["functions", "describe", "requestSeasonImport", "--gen2", "--region=asia-northeast3"]);
  const queues = Object.fromEntries(Q7_QUEUES.map((id) => [id, {...gcloud(["tasks", "queues", "describe", id, "--location=asia-northeast3"]),
    tasks: gcloud(["tasks", "list", "--queue=" + id, "--location=asia-northeast3"])}]));
  const expectedOldTask = continuation ? `projects/outpick-test/locations/asia-northeast3/queues/lookbook-import-jobs/tasks/batch-${resume.pending.batchID}-0` : null;
  const preflightQueues = structuredClone(queues);
  if (continuation) {
    const tasks = preflightQueues["lookbook-import-jobs"].tasks;
    assert.ok(tasks.length <= 1);
    if (tasks.length) assert.equal(tasks[0].name, expectedOldTask);
    preflightQueues["lookbook-import-jobs"].tasks = [];
  }
  const preflight = assertQ7DevelopmentSnapshot({service, revision, functionConfig, queues: preflightQueues}, options.digest);
  const functions = [];
  for (const name of ["getSeasonImportBatch", "getSeasonImportFailures", "requestSeasonImportFailureRetry", "dismissSeasonImportFailure"]) {
    const data = gcloud(["functions", "describe", name, "--gen2", "--region=asia-northeast3"]);
    assert.equal(data.state, "ACTIVE"); functions.push({name, updateTime: data.updateTime, uri: data.serviceConfig.uri});
  }
  const env = Object.fromEntries(revision.spec.containers[0].env.map((item) => [item.name, item.value]));
  assert.equal(env.OUTPICK_Q7_RETRY_FAULT_CAMPAIGN, faultCampaignID);
  assert.equal((await snapshot(db.doc(`platformAdmins/${identity.uid}`)))?.isActive, true);
  const queue = await snapshot(db.doc("lookbookImportQueue/main"));
  if (!continuation) {assert.equal(queue.state, "idle"); assert.equal(queue.headBatchID, null);}
  if (continuation) {
    assert.notEqual(preflight.candidateRevision, oldRevision);
    const delivery = await continuationReadback();
    const oldTask = queues["lookbook-import-jobs"].tasks[0];
    const existingTask = oldTask ? await tasksAPI(oldTask.name + "?responseView=FULL") : null;
    redelivery = {delivery, existingTask};
    const filter = `resource.type="cloud_run_revision" AND resource.labels.service_name="${Q7_SERVICE}" ` +
      `AND resource.labels.revision_name="${oldRevision}" AND timestamp >= "${new Date(originalStartedAt).toISOString()}"`;
    const entries = gcloud(["logging", "read", filter, "--limit=3000"]);
    assert.ok(entries.length < 3000);
    historicalLogs = {entries, deliveries: entries.filter((entry) => entry.httpRequest?.requestUrl?.includes("/tasks/import-batch"))};
    assertRetryDeliveryBudget({historical: historicalLogs.deliveries.length, reserve: 6});
    await write("continuation-historical-logs.json", historicalLogs);
    await journal.save({...journal.snapshot(), status: "running", continuationStartedAt: Date.now()});
    manifest.continuation = {originalStartedAt, originalRevision: oldRevision, originalPollCount: null,
      candidateURL: preflight.candidateURL, sourceDigests: originalResume.sourceDigests,
      maxAdditionalTaskDeliveries: 10, maxCumulativeTaskDeliveries: 30, faultCampaignID};
  }
  if (resume && !continuation) {
    assert.equal(manifest.workerRevision, preflight.candidateRevision);
    assert.equal(manifest.uidHash, createHash("sha256").update(identity.uid).digest("hex"));
    clockGuard();
    const campaign = await snapshot(faultRoot);
    assert.equal(campaign.state, "running"); assert.equal(campaign.startedAt, startedAt);
    assert.equal(campaign.expiresAt, startedAt + plan.durationMs);
    assert.equal(campaign.revision, manifest.workerRevision); assert.equal(campaign.verificationDigest, options.digest);
    assert.equal((await faultRoot.collection("targets").get()).size, 0);
    for (const request of resume.journal.requests) {
      const batch = await snapshot(db.doc(`lookbookImportBatches/${request.response.batchID}`));
      assert.equal(batch.state, "released"); assert.equal(batch.brandID, resume.brand.brandID);
    }
    const execution = await snapshot(db.doc(`brands/${resume.brand.brandID}/importJobs/${resume.brand.jobID}/executions/${resume.brand.executionID}`));
    assert.equal(execution.status, "awaitingReview"); assert.equal(execution.attemptCount, 1);
    const predicted = predictRetryIdentity(identity.uid, resume.journal.requests[1].requestID);
    assert.equal(predicted.jobID, resume.brand.jobID); assert.equal(predicted.executionID, resume.brand.executionID);
    await write("resume-original.json", resume);
    await journal.save({...journal.snapshot(), status: "running", resumedAt: Date.now()});
  }
  manifest.workerRevision = preflight.candidateRevision;
  manifest.uidHash = createHash("sha256").update(identity.uid).digest("hex");
  startedAt ??= Date.now(); manifest.startedAt = startedAt;
  await write("preflight.json", {preflight, service, revision, functionConfig, functions, queues});
  if (!resume || continuation) await faultRoot.create({projectID: "outpick-test", mode: "q7RetryKL", maxMutations: 8,
    state: "running", startedAt, expiresAt: startedAt + plan.durationMs,
    revision: manifest.workerRevision, verificationDigest: options.digest, uidHash: manifest.uidHash});
  call = createQ7Callable({getToken: async () => {
    const token = await session.getToken(); assert.equal(token.uid, identity.uid); return token;
  }, onDispatch: async ({requestID, recordedAt}) => {
    if (requestID) await journal.updateRequest(requestID, {httpIntentRecordedAt: recordedAt});
  }});
  await save();
  const result = await runRetryKL(ports, resume?.brand, continuation ? {pending: resume.pending, review: resume.review} : null);
  await faultRoot.update({state: "completed", completedAt: Date.now()});
  await write("report.json", {runID, stage: "retryKL", status: "completed", startedAt, finishedAt: Date.now(),
    result, limitations: ["실제24시간 삭제는 미검증", "청구액은 미확정", "성능 우위의 통계 판정이 아님"]});
  await journal.save({...journal.snapshot(), status: "completed", finalized: true, mutationCount});
  console.log("Q7 재시도 검증 완료: " + directory);
} catch (error) {
  await write("report.json", {runID, stage: "retryKL", status: "stopped", startedAt: startedAt ?? null,
    stoppedAt: Date.now(), mutationCount, pollCount, reason: error.message});
  await journal.save({...journal.snapshot(), status: "stopped", mutationCount, stopReason: error.message});
  console.error("Q7 재시도 검증 중단: " + error.message + " / " + directory);
  process.exitCode = 1;
} finally {
  await session?.close(); await journal.close(); await lock.close(); await deleteApp(app);
}
