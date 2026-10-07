#!/usr/bin/env node
import {randomUUID, createHash} from "node:crypto";
import {mkdir, writeFile, readFile, copyFile} from "node:fs/promises";
import {execFileSync, spawn} from "node:child_process";
import {fileURLToPath} from "node:url";
import {initializeApp, deleteApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {makePlan, fixture, assertReviewMatches, assertBatchRunEvidence}
  from "./queue-development-contract.mjs";
import {startQ7Session} from "./q7-session.mjs";
import {openQ7Campaign, openQ7Journal, atomicSave} from "./q7-journal.mjs";
import {runQ7Wave, assertQ7WaveEvidence} from "./q7-wave.mjs";
import {createQ7Callable} from "./q7-callable.mjs";
import {waitQ7Receipt} from "./q7-receipts.mjs";
import {loadQ7SmokeResume, loadQ7Finalization, preserveQ7ResumeOriginals, assertQ7RecoveredWorkflow,
  assertQ7ExtractedContinuation} from "./q7-resume.mjs";
import {readQ7StorageOutput, q7PublishedCoverReference} from "./q7-storage-evidence.mjs";
import {assertQ7DevelopmentSnapshot, Q7_FUNCTION, Q7_QUEUES,
  Q7_SERVICE, Q7_TAG} from "./q7-development-preflight.mjs";

const MAX_RUN_MS = 2 * 60 * 60 * 1000;
const ARCHIVE_URL = "https://unaffected.co.kr/collection.html?cate_no=88";
const outputRoot = new URL("../../../output/lookbook-import-performance/product-queue-q7/",
  import.meta.url);
const args = Object.fromEntries(process.argv.slice(2).map((arg) => {
  const match = /^--([^=]+)=(.*)$/.exec(arg);
  if (!match) throw new Error("옵션은 --이름=값 형식이어야 합니다.");
  return [match[1], match[2]];
}));
const stage = args.stage;
const verifyOnly = args["verify-only"] === "true";
if (args["verify-only"] != null && (!verifyOnly || !args.resume || stage !== "smoke")) throw new Error("Q7_VERIFY_ONLY_INVALID");
const afterExtraction = args["resume-after-extraction"] === "true";
if (args["resume-after-extraction"] != null && (!afterExtraction || !args.resume || stage !== "smoke")) {
  throw new Error("Q7_EXTRACTED_CONTINUATION_INVALID");
}
if (!["smoke", "tenBrands"].includes(stage)) {
  throw new Error("사용법: node scripts/q7-runner.mjs --stage=smoke|tenBrands --config=/path/firebase-web-config.json");
}
const configPath = args.config ?? process.env.OUTPICK_Q7_FIREBASE_CONFIG;
const storageBucket = process.env.OUTPICK_Q7_STORAGE_BUCKET;
const expectedWorkerVerificationDigest =
  process.env.OUTPICK_Q7_EXPECTED_WORKER_VERIFICATION_DIGEST;
if (!configPath) throw new Error("OUTPICK_Q7_FIREBASE_CONFIG으로 Web 설정 파일을 지정하세요.");
if (!storageBucket || !storageBucket.endsWith(".firebasestorage.app") &&
    !storageBucket.endsWith(".appspot.com")) throw new Error("검증된 Storage bucket을 OUTPICK_Q7_STORAGE_BUCKET에 지정하세요.");
if (!/^[a-f0-9]{64}$/.test(expectedWorkerVerificationDigest ?? "")) {
  throw new Error("OUTPICK_Q7_EXPECTED_WORKER_VERIFICATION_DIGEST가 필요합니다.");
}

const plan = makePlan(stage);
if (plan.archiveURL !== ARCHIVE_URL) throw new Error("Q7_INPUT_CHANGED");
const runID = args.resume ?? randomUUID();
const campaign = await openQ7Campaign(outputRoot.pathname, stage, args.resume ?? null, verifyOnly);
const runPath = new URL(runID + "/", outputRoot);
const finalization = verifyOnly ? await loadQ7Finalization(runPath.pathname, runID, plan) : null;
const resume = args.resume && !verifyOnly ? await loadQ7SmokeResume(runPath.pathname, runID, plan) : null;
const startedAt = finalization?.journal.startedAt ?? resume?.state.startedAt ?? Date.now();
if (Date.now() - startedAt >= MAX_RUN_MS) {
  await campaign.close();
  throw new Error("Q7_RUN_WINDOW_EXCEEDED");
}
await mkdir(runPath, {recursive: true});
const journal = await openQ7Journal(runPath.pathname, runID, {
  projectID: "outpick-test", stage, planDigest: plan.planDigest,
  sourceInputDigest: plan.sourceInputDigest, startedAt,
});
const firebaseApp = initializeApp({projectId: "outpick-test", storageBucket},
  "q7-run-" + runID);
const db = getFirestore(firebaseApp);
const auth = getAuth(firebaseApp);
const bucket = getStorage(firebaseApp).bucket(storageBucket);
let session;
let mutationCount = verifyOnly ? 7 : resume ? 2 : 0;
let stopReason = null;
const brands = new Map();
const importJobs = [];
const batchIDs = finalization ? [...finalization.journal.batchIDs] : resume ? [...resume.journal.batchIDs] : [];
const expectedSeasons = new Map(plan.brands.map((item) => [item.brand, item.seasons]));
let jsonWriteTail = Promise.resolve();

try {
  if (verifyOnly) {
    await verifyFinalEvidence();
  } else {
  const configStat = await import("node:fs/promises").then((fs) => fs.stat(configPath));
  if (!configStat.isFile()) throw new Error("Q7_FIREBASE_CONFIG_REQUIRED");
  const initial = await journal.snapshot();
  if (initial.finalized) throw new Error("Q7_RUN_ALREADY_FINALIZED");
  session = await startQ7Session({firebaseConfigPath: configPath});
  process.stdout.write("브라우저에서 Development 관리자 계정으로 로그인하세요: " + session.url + "\n");
  openBrowser(session.url);
  await waitForLogin(session);
  const user = session.identity();
  if (!user?.uid) throw new Error("Q7_LOGIN_REQUIRED");
  const runtimeEvidence = readQ7DevelopmentPreflight(expectedWorkerVerificationDigest);
  await mkdir(new URL("evidence/", runPath), {recursive: true});
  await saveJSON(new URL(resume ? "evidence/resume-development-preflight.json" :
    "evidence/development-preflight.json", runPath), runtimeEvidence);
  await assertCanStart(db, user.uid, stage, runPath, resume);
  const expectedUID = user.uid;
  const call = createQ7Callable({getToken: async () => {
    const current = await session.getToken();
    if (current.uid !== expectedUID) throw new Error("Q7_ACCOUNT_CHANGED");
    return current;
  }, onDispatch: async ({name, requestID, recordedAt}) => {
    if (["createBrand", "requestSeasonCandidateImportJobs", "reviewLookbookExtraction"].includes(name)) {
      await journal.updateRequest(requestID, {httpIntentRecordedAt: recordedAt});
    }
  }});
  const manifest = resume ? structuredClone(resume.manifest) : {schemaVersion: 1, runID, stage, projectID: "outpick-test",
    region: "asia-northeast3", createdAt: startedAt,
    identity: {uidHash: createHash("sha256").update(user.uid).digest("hex")},
    plan, brands: [], batches: [], jobs: [], status: "running"};
  manifest.jobs = importJobs;
  if (resume) {
    await preserveQ7ResumeOriginals(runPath.pathname, resume);
    manifest.resumption = {resumedAt: Date.now(), originalStartedAt: startedAt,
      initialAcceptedRequests: resume.journal.requests.map((item) => item.requestID),
      originalEvidenceDirectory: "evidence/resume-original",
      historicalEnvironmentFailure: "QUEUE_ENVIRONMENT_SAMPLE-GAP"};
    await journal.save({...journal.snapshot(), status: "running", resumedAt: Date.now(),
      originalStopReason: initial.stopReason});
  }
  manifest.workerRevision = runtimeEvidence.candidateRevision;
  manifest.validationScope = stage === "tenBrands" ? "tenBrands100msWave" :
    afterExtraction ? "functionalStorageSmoke" : "overlapSmoke";
  manifest.overlapDeferredTo = afterExtraction ? "tenBrands100msWave" : null;
  await saveJSON(new URL("manifest.json", runPath), manifest);

  if (stage === "smoke") {
    const a = resume ? resume.state.brand : await createBrand(call, "A", journal, manifest, runPath);
    brands.set("A", a);
    if (!resume) await waitDiscovery(db, a, call);
    const aCandidates = await selectCandidates(db, a, expectedSeasons.get("A"), manifest, runPath);
    let aImport;
    if (resume) {
      if (JSON.stringify(aCandidates.map((item) => item.candidateID)) !==
          JSON.stringify(resume.state.imports.payload.candidateIDs)) throw new Error("Q7_RESUME_CANDIDATES_CHANGED");
      const prior = resume.state.imports;
      aImport = {brand: a, selected: aCandidates, requestID: prior.requestID,
        batchID: prior.response.batchID};
      manifest.batches.push({requestID: prior.requestID, batchID: aImport.batchID,
        kind: "importSeasons", brandID: a.brandID});
      await saveJSON(new URL("manifest.json", runPath), manifest);
      process.stdout.write("Q7_RESUME_OBSERVER_READY: " + runID + "\n");
      await prepareImport(call, aImport, manifest);
    } else aImport = await requestImport(call, a, aCandidates, journal, manifest);
    const overlap = afterExtraction ? false : await waitForBatchState(call, aImport, "active", 120_000);
    if (!afterExtraction && !overlap) {
      stopReason = "A import가 완료되기 전에 B 접수를 관측하지 못했습니다.";
      throw new Error("Q7_OVERLAP_SCENARIO_NOT_OBSERVED");
    }
    const b = await createBrand(call, "B", journal, manifest, runPath);
    await waitDiscovery(db, b, call);
    const bCandidates = await selectCandidates(db, b, expectedSeasons.get("B"), manifest, runPath);
    await waitReleased(call, aImport);
    const aReviews = await loadAndValidateReviews(call, db, a, aCandidates, manifest, runPath);
    for (const entry of aReviews) await approve(call, entry, journal, manifest);
    const bImport = await requestImport(call, b, bCandidates, journal, manifest);
    await waitReleased(call, bImport);
    const bReviews = await loadAndValidateReviews(call, db, b, bCandidates, manifest, runPath);
    for (const entry of bReviews) await approve(call, entry, journal, manifest);
  } else {
    const discoveryWave = await runQ7Wave(plan.brands, (item, timing) =>
      createBrand(call, item.brand, journal, manifest, runPath, timing), {name: "discovery"});
    manifest.waves = [{name: "discovery", timings: discoveryWave.map((item) => item.timing)}];
    manifest.brands = plan.brands.map((item) => brands.get(item.brand));
    await saveJSON(new URL("manifest.json", runPath), manifest);
    for (const brand of brands.values()) await waitDiscovery(db, brand, call);
    const selections = new Map();
    for (const item of plan.brands) {
      selections.set(item.brand, await selectCandidates(db, brands.get(item.brand),
        item.seasons, manifest, runPath));
    }
    const importWave = await runQ7Wave(plan.brands, (item, timing) =>
      requestImport(call, brands.get(item.brand), selections.get(item.brand), journal, manifest, timing), {name: "imports"});
    manifest.waves.push({name: "imports", timings: importWave.map((item) => item.timing)});
    const pendingImports = importWave.map((item) => item.value);
    await saveJSON(new URL("manifest.json", runPath), manifest);
    for (const pending of pendingImports) await waitReleased(call, pending);
    for (const item of plan.brands) {
      const selected = selections.get(item.brand);
      const reviews = await loadAndValidateReviews(call, db, brands.get(item.brand),
        selected, manifest, runPath);
      for (const entry of reviews) await approve(call, entry, journal, manifest);
    }
  }

  const evidence = await collectEvidence({db, bucket, manifest, batchIDs,
    importJobs, stage, startedAt, runPath});
  await completeRun(manifest, evidence);
  }
} catch (error) {
  const message = error instanceof Error ? error.message : "Q7_UNKNOWN_FAILURE";
  await journal.save({...journal.snapshot(), stoppedAt: Date.now(),
    status: "stopped", stopReason: stopReason ?? message,
    mutationCount, batchIDs});
  await saveJSON(new URL("report.json", runPath), {runID, stage, status: "stopped",
    mutationCount, batchIDs, reason: stopReason ?? message,
    nextAction: "영수증과 서버 상태를 읽기 전용으로 대조한 뒤 같은 run의 복원 가능성을 확인하세요."});
  process.stderr.write("Q7 실행 중단: " + (stopReason ?? message) +
    "\n증거: " + runPath.pathname + "\n");
  process.exitCode = 1;
} finally {
  await session?.close();
  await journal.close();
  await campaign.close();
  await deleteApp(firebaseApp);
}

async function verifyFinalEvidence() {
  const snapshotDirectory = new URL("evidence/finalization-stop-" + Date.now() + "/", runPath);
  await mkdir(snapshotDirectory, {recursive: true});
  for (const name of [runID + ".json", "manifest.json", "report.json"]) {
    await copyFile(new URL(name, runPath), new URL(name, snapshotDirectory));
  }
  const queue = (await db.doc("lookbookImportQueue/main").get()).data();
  if (queue?.state !== "idle" || queue.headBatchID != null) throw new Error("Q7_SHARED_QUEUE_NOT_IDLE");
  const manifest = structuredClone(finalization.manifest);
  manifest.batches = [];
  for (const request of finalization.journal.requests) {
    const batch = (await db.doc("lookbookImportBatches/" + request.response.batchID).get()).data();
    const brandID = request.callable === "createBrand" ? request.response.brandID : request.payload.brandID;
    if (batch?.state !== "released" || batch.brandID !== brandID || batch.requestID !== request.requestID ||
        typeof batch.requestedBy !== "string" ||
        createHash("sha256").update(batch.requestedBy).digest("hex") !== manifest.identity.uidHash) {
      throw new Error("Q7_FINALIZATION_REMOTE_CHANGED");
    }
    if (request.callable !== "createBrand") manifest.batches.push({requestID: request.requestID,
      batchID: request.response.batchID, kind: batch.kind, brandID, jobID: request.payload.jobID ?? null});
    if (request.callable !== "requestSeasonCandidateImportJobs") continue;
    if (JSON.stringify(batch.items.map((item) => item.targetID)) !== JSON.stringify(request.payload.candidateIDs)) {
      throw new Error("Q7_FINALIZATION_REMOTE_CHANGED");
    }
    const brand = manifest.brands.find((item) => item.brandID === brandID);
    const expected = plan.brands.find((item) => item.brand === brand?.letter);
    if (!expected || batch.items.length !== expected.seasons.length) throw new Error("Q7_FINALIZATION_REMOTE_CHANGED");
    for (const item of batch.items) {
      const job = (await db.doc("brands/" + brandID + "/importJobs/" + item.jobID).get()).data();
      const season = fixture.seasons.find((entry) => entry.sourceURL === job?.sourceURL);
      if (!season || !expected.seasons.includes(season.seasonID) || job?.status !== "succeeded") {
        throw new Error("Q7_FINALIZATION_REMOTE_CHANGED");
      }
      importJobs.push({brandID, seasonID: season.seasonID, candidateID: item.targetID,
        jobID: item.jobID, batchID: request.response.batchID});
    }
  }
  if (importJobs.length !== 3 || new Set(importJobs.map((item) => item.brandID + ":" + item.seasonID)).size !== 3) {
    throw new Error("Q7_FINALIZATION_REMOTE_CHANGED");
  }
  manifest.jobs = importJobs;
  const evidence = await collectEvidence({db, bucket, manifest, batchIDs,
    importJobs, stage, startedAt, runPath});
  await completeRun(manifest, evidence);
}

async function completeRun(manifest, evidence) {
  Object.assign(manifest, {evidence, status: "completed", finishedAt: Date.now(), mutationCount});
  await saveJSON(new URL("manifest.json", runPath), manifest);
  await saveJSON(new URL("report.json", runPath), {runID, stage, status: "completed", mutationCount,
    expectedMutations: plan.totals.mutationRequestsIfAllReviewed, elapsedMs: Date.now() - startedAt,
    performanceStatus: manifest.resumption ? "historicalFailurePreserved" : "passed",
    resumption: manifest.resumption ?? null, validationScope: manifest.validationScope,
    overlapObserved: stage === "smoke" ? manifest.validationScope !== "functionalStorageSmoke" : null,
    overlapDeferredTo: manifest.overlapDeferredTo, readyForTenBrands: stage === "smoke", evidence,
    limitations: ["청구서 확정액은 별도 확인 전 미확정", "성능 개선의 통계적 우월성은 1회 결과로 판정하지 않음"]});
  await journal.save({...journal.snapshot(), finalized: true, finishedAt: Date.now(), status: "completed", mutationCount});
  process.stdout.write("Q7 " + stage + " 완료. 원본: " + runPath.pathname + "\n");
}

async function assertCanStart(firestore, uid, currentStage, directory, continuation) {
  const adminSnapshot = await firestore.collection("platformAdmins").doc(uid).get();
  const admin = adminSnapshot.data();
  if (admin?.isActive !== true || admin?.revokedAt instanceof Timestamp) {
    throw new Error("Q7_PLATFORM_ADMIN_INACTIVE");
  }
  const queue = (await firestore.doc("lookbookImportQueue/main").get()).data();
  if (continuation) {
    if (createHash("sha256").update(uid).digest("hex") !== continuation.state.uidHash) {
      throw new Error("Q7_RESUME_ACCOUNT_CHANGED");
    }
    const a = continuation.state.brand;
    const pending = continuation.state.imports;
    const [brand, job, imports, discovery] = await Promise.all([
      firestore.doc("brands/" + a.brandID).get(),
      firestore.doc("brands/" + a.brandID + "/seasonDiscoveryJobs/" + a.discoveryJobID).get(),
      firestore.doc("lookbookImportBatches/" + pending.response.batchID).get(),
      firestore.doc("lookbookImportBatches/" + a.discoveryBatchID).get(),
    ]);
    const b = brand.data(), j = job.data(), i = imports.data(), d = discovery.data();
    if (afterExtraction) {
      assertQ7ExtractedContinuation({queue, brand: b, discoveryJob: j,
        discoveryBatch: d, importBatch: i, expectedBrand: a, pending, uid});
      return;
    }
    if (queue?.state !== "recoveryRequired" || queue.headBatchID !== a.discoveryBatchID ||
        d?.state !== "recoveryRequired" || !["QUEUE_ENVIRONMENT_SAMPLE-GAP", "QUEUE_ITEM_NOTQUEUED"].includes(d.recoveryReason) ||
        d.items?.length !== 1 || d.items[0].processingStatus !== "succeeded" ||
        j?.status !== "succeeded" || j.generation !== a.generation ||
        j.candidateSnapshotHash !== a.candidateSnapshotHash ||
        b?.publishedSeasonDiscoveryJobID !== a.discoveryJobID ||
        b.publishedSeasonDiscoveryGeneration !== a.generation ||
        b.publishedSeasonDiscoverySnapshotHash !== a.candidateSnapshotHash ||
        i?.state !== "preparing" || i.requestID !== pending.requestID ||
        i.brandID !== a.brandID || i.requestedBy !== uid ||
        JSON.stringify(i.items?.map((item) => item.targetID)) !== JSON.stringify(pending.payload.candidateIDs) ||
        i.items.some((item) => item.jobID != null || item.admissionStatus !== "pending")) {
      throw new Error("Q7_RESUME_REMOTE_STATE_CHANGED");
    }
    return;
  }
  if (queue?.headBatchID || queue?.recoveryRequired === true) {
    throw new Error("Q7_SHARED_QUEUE_NOT_IDLE");
  }
  if (currentStage === "tenBrands") {
    const prior = await findPassedSmoke(directory);
    if (!prior) throw new Error("Q7_SMOKE_EVIDENCE_REQUIRED");
  }
}

async function findPassedSmoke(currentPath) {
  const root = new URL("../", currentPath);
  const {readdir, readFile} = await import("node:fs/promises");
  for (const name of await readdir(root)) {
    try {
      const value = JSON.parse(await readFile(new URL(name + "/report.json", root)));
      if (value.stage === "smoke" && value.status === "completed") return value;
    } catch {}
  }
  return null;
}

async function createBrand(call, letter, store, manifest, directory, wave) {
  const name = "Q7 " + letter + " " + manifest.runID.slice(0, 8);
  const request = envelope({name, isFeatured: false, moodIDs: [],
    websiteURL: "https://unaffected.co.kr", lookbookArchiveURL: ARCHIVE_URL});
  const result = await mutation(call, store, manifest, "createBrand", request, {
    name, isFeatured: false, moodIDs: [], websiteURL: "https://unaffected.co.kr",
    lookbookArchiveURL: ARCHIVE_URL, ...request}, wave);
  const value = {letter, name, brandID: result.brandID,
    discoveryJobID: result.discoveryJobID, createRequestID: request.requestID,
    discoveryBatchID: result.batchID};
  if (!value.brandID || !value.discoveryJobID || !value.discoveryBatchID) {
    throw new Error("Q7_BRAND_RECEIPT_INCOMPLETE");
  }
  brands.set(letter, value);
  batchIDs.push(value.discoveryBatchID);
  manifest.brands.push(value);
  await saveJSON(new URL("manifest.json", directory), manifest);
  return value;
}

async function waitDiscovery(firestore, brand, call) {
  await poll(async () => {
    const ref = firestore.doc("brands/" + brand.brandID +
      "/seasonDiscoveryJobs/" + brand.discoveryJobID);
    const snapshot = await ref.get();
    if (!snapshot.exists) return null;
    const job = snapshot.data();
    if (["failed", "correctionRequired", "cancelled"].includes(job.status)) {
      throw new Error("Q7_DISCOVERY_" + String(job.status).toUpperCase());
    }
    if (!["succeeded", "awaitingReview"].includes(job.status)) return null;
    const currentBrand = (await firestore.doc("brands/" + brand.brandID).get()).data();
    if (currentBrand?.publishedSeasonDiscoveryJobID !== brand.discoveryJobID ||
        currentBrand?.publishedSeasonDiscoveryGeneration !== job.generation ||
        currentBrand?.publishedSeasonDiscoverySnapshotHash !== job.candidateSnapshotHash) {
      throw new Error("Q7_DISCOVERY_SNAPSHOT_NOT_PUBLISHED");
    }
    return {...brand, generation: job.generation,
      candidateSnapshotHash: job.candidateSnapshotHash,
      status: job.status, sourceArchiveURL: job.sourceArchiveURL};
  }, 15 * 60 * 1000, "Q7_DISCOVERY_TIMEOUT").then(async (published) => {
    Object.assign(brand, published);
    await waitQ7Receipt(call, {requestID: brand.createRequestID,
      batchID: brand.discoveryBatchID}, {mode: "released"});
  });
}

async function selectCandidates(firestore, brand, seasonIDs, manifest, directory) {
  const snapshot = await firestore.collection("brands/" + brand.brandID +
    "/seasonDiscoveryJobs/" + brand.discoveryJobID + "/candidates").get();
  const candidates = snapshot.docs.map((doc) => ({candidateID: doc.id, ...doc.data()}));
  const selected = seasonIDs.map((seasonID) => {
    const expected = fixture.seasons.find((entry) => entry.seasonID === seasonID);
    const candidate = candidates.find((item) => item.seasonURL === expected.sourceURL);
    if (!candidate) throw new Error("Q7_DISCOVERY_CANDIDATE_MISMATCH_" + seasonID);
    if (candidate.resolution !== "newSeason") {
      throw new Error("Q7_CANDIDATE_REQUIRES_REVIEW_" + seasonID);
    }
    return {seasonID, candidateID: candidate.candidateID, candidate};
  });
  await mkdir(new URL("evidence/discovery/", directory), {recursive: true});
  await saveJSON(new URL("evidence/discovery/" + brand.letter + ".json", directory), {
    brandID: brand.brandID, discoveryJobID: brand.discoveryJobID,
    generation: brand.generation, candidateSnapshotHash: brand.candidateSnapshotHash,
    status: brand.status, selectedSeasonIDs: seasonIDs,
    candidates: candidates.map((item) => ({candidateID: item.candidateID, ...item})),
  });
  manifest.discovery = [...(manifest.discovery ?? []), {
    brand: brand.letter, generation: brand.generation,
    candidateSnapshotHash: brand.candidateSnapshotHash,
    selectedSeasonIDs: seasonIDs,
  }];
  return selected;
}

async function requestImport(call, brand, selected, store, manifest, wave) {
  const request = envelope({brandID: brand.brandID,
    discoveryJobID: brand.discoveryJobID, generation: brand.generation,
    candidateIDs: selected.map((item) => item.candidateID),
    candidateSnapshotHash: brand.candidateSnapshotHash});
  const result = await mutation(call, store, manifest,
    "requestSeasonCandidateImportJobs", request, {
      queueContractVersion: 1, requestID: request.requestID,
      requestCreatedAt: request.requestCreatedAt, brandID: brand.brandID,
      discoveryJobID: brand.discoveryJobID, generation: brand.generation,
      candidateIDs: request.candidateIDs,
      candidateSnapshotHash: brand.candidateSnapshotHash,
    }, wave);
  const pending = {brand, selected, requestID: request.requestID,
    batchID: result.batchID, receipt: result};
  if (!pending.batchID) throw new Error("Q7_IMPORT_RECEIPT_INCOMPLETE");
  batchIDs.push(pending.batchID);
  manifest.batches.push({requestID: request.requestID, batchID: pending.batchID,
    kind: "importSeasons", brandID: brand.brandID});
  await saveJSON(new URL("manifest.json", runPath), manifest);
  await prepareImport(call, pending, manifest);
  return pending;
}

async function prepareImport(call, pending, manifest) {
  const {brand, selected} = pending;
  const prepared = await waitQ7Receipt(call, pending,
    {mode: "prepared", expectedCount: selected.length});
  pending.receipt = prepared;
  importJobs.push(...prepared.items.map((item) => {
    const candidate = selected.find((entry) => entry.candidateID === item.targetID);
    if (!candidate || typeof item.jobID !== "string") {
      throw new Error("Q7_IMPORT_ITEM_INCOMPLETE");
    }
    candidate.jobID = item.jobID;
    return {brandID: brand.brandID, seasonID: candidate.seasonID,
      candidateID: item.targetID, jobID: item.jobID, batchID: pending.batchID};
  }));
  await saveJSON(new URL("manifest.json", runPath), manifest);
  return pending;
}

async function loadAndValidateReviews(call, firestore, brand, selected, manifest, directory) {
  const output = [];
  for (const item of selected) {
    if (typeof item.jobID !== "string") throw new Error("Q7_IMPORT_JOB_ID_MISSING");
    const jobSnapshot = await firestore.doc("brands/" + brand.brandID +
      "/importJobs/" + item.jobID).get();
    if (!jobSnapshot.exists) throw new Error("Q7_IMPORT_JOB_MISSING");
    const job = {jobID: jobSnapshot.id, brandID: brand.brandID, ...jobSnapshot.data()};
    const review = await call("getLookbookExtractionReview", {
      brandID: brand.brandID, jobID: job.jobID});
    assertReviewMatches(item.seasonID, review, job);
    await mkdir(new URL("evidence/reviews/", directory), {recursive: true});
    await saveJSON(new URL("evidence/reviews/" + brand.letter + "-" +
      item.seasonID + ".json", directory), {job, review});
    manifest.reviews = [...(manifest.reviews ?? []), {brand: brand.letter,
      seasonID: item.seasonID, jobID: job.jobID,
      reviewGeneration: review.reviewGeneration,
      reviewSnapshotHash: review.reviewSnapshotHash,
      candidateCount: review.candidates.length}];
    output.push({brand, seasonID: item.seasonID, candidateID: item.candidateID,
      job, review});
  }
  return output;
}

async function approve(call, entry, store, manifest) {
  const request = envelope({brandID: entry.brand.brandID,
    jobID: entry.job.jobID, reviewGeneration: entry.review.reviewGeneration,
    reviewSnapshotHash: entry.review.reviewSnapshotHash,
    decision: "approved", excludedCandidateKeys: [],
    expectedCandidateCount: entry.review.candidates.length});
  const payload = {...request, brandID: entry.brand.brandID, jobID: entry.job.jobID,
    reviewGeneration: entry.review.reviewGeneration,
    reviewSnapshotHash: entry.review.reviewSnapshotHash, decision: "approved",
    excludedCandidateKeys: [],
    expectedCandidateCount: entry.review.candidates.length};
  const receipt = await mutation(call, store, manifest, "reviewLookbookExtraction",
    request, payload);
  if (!receipt.batchID) throw new Error("Q7_APPROVAL_RECEIPT_INCOMPLETE");
  const pending = {requestID: request.requestID, batchID: receipt.batchID};
  batchIDs.push(receipt.batchID);
  manifest.batches.push({requestID: request.requestID, batchID: receipt.batchID,
    kind: "reviewApproval", brandID: entry.brand.brandID,
    jobID: entry.job.jobID});
  await waitReleased(call, pending);
}

async function mutation(call, store, manifest, name, request, payload, wave) {
  if (Date.now() - startedAt >= MAX_RUN_MS) throw new Error("Q7_RUN_WINDOW_EXCEEDED");
  if (mutationCount >= plan.totals.mutationRequestsIfAllReviewed) throw new Error("Q7_MUTATION_LIMIT_EXCEEDED");
  const saved = await store.appendRequest({requestID: request.requestID,
    requestCreatedAt: request.requestCreatedAt, callable: name, payload, ...(wave ? {wave} : {})});
  mutationCount++;
  await store.updateRequest(request.requestID, {state: "sent", sentAt: Date.now()});
  try {
    const response = await call(name, payload);
    await store.updateRequest(request.requestID, {state: "accepted",
      acceptedAt: Date.now(), response});
    return response;
  } catch (error) {
    await store.updateRequest(request.requestID, {state: "uncertain",
      uncertainAt: Date.now(), errorCode: error?.code ?? "NETWORK_OR_CALLABLE_ERROR"});
    manifest.lastUncertainRequestID = saved.requestID;
    throw error;
  }
}

function envelope(payload) {
  return {...payload, queueContractVersion: 1, requestID: randomUUID(),
    requestCreatedAt: Date.now()};
}

async function waitReleased(call, pending) {
  await waitQ7Receipt(call, pending, {mode: "released"}).then((receipt) => {
    pending.finalReceipt = receipt;
    return receipt;
  });
}

async function waitForBatchState(call, pending, desired, timeoutMs) {
  try {
    return await poll(async () => {
      const receipt = await call("getSeasonImportBatch", {requestID: pending.requestID});
      if (receipt.receiptState === desired) return receipt;
      if (receipt.receiptState === "released") return false;
      if (receipt.receiptState === "recoveryRequired") throw new Error("Q7_RECOVERY_REQUIRED");
      return null;
    }, timeoutMs, "Q7_BATCH_ACTIVE_NOT_OBSERVED");
  } catch (error) {
    if (error?.message === "Q7_BATCH_ACTIVE_NOT_OBSERVED") return false;
    throw error;
  }
}

async function collectEvidence({db: firestore, bucket: storageBucketRef,
  manifest: runManifest, batchIDs: ids, importJobs: jobs, stage: currentStage,
  startedAt: timeStarted, runPath: directory}) {
  const batches = [];
  const files = [];
  let verificationBytes = 0;
  for (const id of [...new Set(ids)]) {
    const ref = firestore.doc("lookbookImportBatches/" + id);
    const snapshot = await ref.get();
    if (!snapshot.exists) throw new Error("Q7_BATCH_EVIDENCE_MISSING");
    const data = snapshot.data();
    const runsSnapshot = await ref.collection("runs").get();
    const runs = runsSnapshot.docs.map((doc) => normalizeTimes({runID: doc.id, ...doc.data()}));
    const auditSnapshot = await ref.collection("recoveryDecisions").get();
    const recoveryDecisions = auditSnapshot.docs.map((doc) => normalizeTimes({decisionID: doc.id, ...doc.data()}));
    batches.push(normalizeTimes({id, ...data, runs, recoveryDecisions}));
    await mkdir(new URL("evidence/batches/", directory), {recursive: true});
    await saveJSON(new URL("evidence/batches/" + id + ".json", directory),
      normalizeTimes({id, ...data, runs, recoveryDecisions}));
  }
  const revision = runManifest.workerRevision;
  if (!revision) throw new Error("Q7_WORKER_REVISION_EVIDENCE_MISSING");
  const queueAssertion = runManifest.resumption ? assertQ7RecoveredWorkflow(batches,
    [...new Set(ids)], revision, runManifest.brands[0].discoveryBatchID) :
    assertBatchRunEvidence(batches, [...new Set(ids)], revision);
  const sequenceEvidence = batches.map((batch) => ({id: batch.id, sequence: batch.sequence,
    state: batch.state, releasedAt: batch.releasedAt, runID: batch.runID,
    epoch: batch.epoch, runs: batch.runs}));
  const waveEvidence = currentStage === "tenBrands" ?
    assertQ7WaveEvidence(journal.snapshot().requests, batches, runManifest.waves) : null;
  if (waveEvidence) await saveJSON(new URL("evidence/waves.json", directory), waveEvidence);

  for (const jobRef of jobs) {
    const ref = firestore.doc("brands/" + jobRef.brandID + "/importJobs/" + jobRef.jobID);
    const snapshot = await ref.get();
    if (!snapshot.exists) throw new Error("Q7_FINAL_JOB_MISSING");
    const job = snapshot.data();
    const seasonID = job.targetSeasonID;
    if (typeof seasonID !== "string") throw new Error("Q7_TARGET_SEASON_MISSING");
    const seasonRef = firestore.doc("brands/" + jobRef.brandID + "/seasons/" + seasonID);
    const seasonSnap = await seasonRef.get();
    if (!seasonSnap.exists) throw new Error("Q7_SEASON_NOT_SAVED");
    const season = seasonSnap.data();
    const postSnapshot = await seasonRef.collection("posts").get();
    const expectedSeason = fixture.seasons.find((item) => item.seasonID === jobRef.seasonID);
    const golden = fixture.golden.find((item) => item.seasonID === jobRef.seasonID);
    const expectedBySource = new Map(expectedSeason.images.map((image) => [image.sourceURL, image.sha256]));
    const expectedOutputs = new Map(golden.outputs.map((output) =>
      [output.sourceHash + ":" + output.maxPixel, output]));
    const ledgerPath = "brands/" + jobRef.brandID + "/importJobs/" + season.coverAssetJobID +
      "/executions/" + season.coverAssetExecutionID + "/assets/" + season.coverAssetKey +
      "/writes/" + season.coverAssetWriteID;
    const coverLedger = (await firestore.doc(ledgerPath).get()).data();
    const refs = [q7PublishedCoverReference(season, coverLedger)];
    for (const post of postSnapshot.docs) {
      for (const media of Array.isArray(post.data().media) ? post.data().media : []) {
        refs.push({kind: "post", sourceURL: media.remoteURL,
          thumbPath: media.thumbPath, detailPath: media.detailPath});
      }
    }
    if (refs.length !== golden.assetTargets) throw new Error("Q7_ASSET_TARGET_COUNT_MISMATCH");
    const observedOutputSizes = [];
    for (const ref of refs) {
      const sourceHash = ref.kind === "cover" ?
        fixture.covers.find((cover) => cover.seasonID === jobRef.seasonID)?.sha256 :
        expectedBySource.get(ref.sourceURL);
      if (!sourceHash || typeof ref.thumbPath !== "string" ||
          typeof ref.detailPath !== "string") throw new Error("Q7_ASSET_PATH_MISSING");
      for (const [maxPixel, path] of [[ref.kind === "cover" ? 512 : 768, ref.thumbPath],
        [ref.kind === "cover" ? 1600 : 1920, ref.detailPath]]) {
        const expected = expectedOutputs.get(sourceHash + ":" + maxPixel);
        if (!expected) throw new Error("Q7_GOLDEN_ASSET_MISSING");
        const generation = path === ref.thumbPath ? ref.thumbGeneration : ref.detailGeneration;
        const checked = await readQ7StorageOutput(storageBucketRef, path, {...expected, generation});
        verificationBytes += checked.bytes;
        const evidence = {brandID: jobRef.brandID, seasonID: jobRef.seasonID,
          path, generation: checked.generation, bytes: checked.bytes,
          contentType: checked.contentType, crc32c: checked.crc32c,
          md5Hash: checked.md5Hash, sha256: checked.sha256,
          width: checked.width, height: checked.height, sourceHash, maxPixel};
        files.push(evidence);
        observedOutputSizes.push(checked.bytes);
      }
    }
    if (observedOutputSizes.reduce((sum, bytes) => sum + bytes, 0) !== golden.uploadBytes) {
      throw new Error("Q7_JPEG_TOTAL_BYTES_MISMATCH");
    }
  }
  const expectedCount = currentStage === "smoke" ? 7 : 36;
  if (runManifest.batches.length + runManifest.brands.length !== expectedCount) {
    throw new Error("Q7_MUTATION_COUNT_MISMATCH");
  }
  if (Date.now() - timeStarted > MAX_RUN_MS) throw new Error("Q7_RUN_WINDOW_EXCEEDED");
  const measurements = collectMeasurementLogs(timeStarted, [...new Set(ids)]);
  await mkdir(new URL("metrics/", directory), {recursive: true});
  await saveJSON(new URL("metrics/worker-measurements.json", directory), measurements);
  if (measurements.length !== new Set(ids).size) {
    throw new Error("Q7_WORKER_MEASUREMENT_MISSING");
  }
  for (const entry of measurements) for (const report of entry.reports) {
    if (!report.measurement.complete) throw new Error("Q7_WORKER_MEASUREMENT_INCOMPLETE");
  }
  return {revision, batchRunEvidence: sequenceEvidence, batches: batches.length,
    queueAssertions: queueAssertion, waveEvidence, measurements, files, fileCount: files.length,
    storedBytes: files.reduce((sum, item) => sum + item.bytes, 0),
    verificationGets: files.length, verificationMetadataGets: files.length,
    verificationBytes};
}

function collectMeasurementLogs(timeStarted, ids) {
  const service = process.env.OUTPICK_Q7_SERVICE ?? "lookbook-import-worker-development";
  const filter = 'resource.type="cloud_run_revision" AND ' +
    'resource.labels.service_name="' + service + '" AND timestamp >= "' +
    new Date(timeStarted - 5000).toISOString() + '"';
  let entries;
  try {
    entries = JSON.parse(execFileSync("gcloud", ["logging", "read", filter,
      "--project=outpick-test", "--limit=20000", "--format=json"],
    {encoding: "utf8", maxBuffer: 32 * 1024 * 1024, timeout: 60_000}));
  } catch {
    throw new Error("Q7_CLOUD_LOGGING_READ_FAILED");
  }
  const wanted = new Set(ids);
  const found = new Map();
  for (const entry of entries) {
    const text = typeof entry.textPayload === "string" ? entry.textPayload :
      typeof entry.jsonPayload?.message === "string" ? entry.jsonPayload.message : "";
    const marker = "[lookbook-import-performance] ";
    const start = text.indexOf(marker);
    if (start < 0) continue;
    try {
      const report = JSON.parse(text.slice(start + marker.length));
      const measurement = report.measurement;
      if (wanted.has(measurement?.batchID)) {
        const rows = found.get(measurement.batchID) ?? [];
        rows.push({timestamp: entry.timestamp, revision:
          entry.resource?.labels?.revision_name ?? null, measurement,
          resources: report.resources});
        found.set(measurement.batchID, rows);
      }
    } catch {}
  }
  return [...wanted].map((batchID) => {
    const reports = found.get(batchID) ?? [];
    if (reports.length === 0) throw new Error("Q7_WORKER_MEASUREMENT_MISSING");
    return {batchID, reports};
  });
}

function readQ7DevelopmentPreflight(expectedVerificationDigest) {
  const service = gcloudJSON(["run", "services", "describe", Q7_SERVICE,
    "--project=outpick-test", "--region=asia-northeast3", "--format=json"]);
  const tagged = service.status?.traffic?.find((item) => item.tag === Q7_TAG);
  if (!tagged?.revisionName) throw new Error("Q7_CANDIDATE_TAG_MISSING");
  const revision = gcloudJSON(["run", "revisions", "describe", tagged.revisionName,
    "--project=outpick-test", "--region=asia-northeast3", "--format=json"]);
  const functionConfig = gcloudJSON(["functions", "describe", Q7_FUNCTION,
    "--gen2", "--region=asia-northeast3", "--project=outpick-test", "--format=json"]);
  const queues = {};
  for (const queueID of Q7_QUEUES) {
    const queue = gcloudJSON(["tasks", "queues", "describe", queueID,
      "--project=outpick-test", "--location=asia-northeast3", "--format=json"]);
    const tasks = gcloudJSON(["tasks", "list", "--queue=" + queueID,
      "--project=outpick-test", "--location=asia-northeast3", "--limit=1000", "--format=json"]);
    queues[queueID] = {state: queue.state, tasks: Array.isArray(tasks) ? tasks : []};
  }
  try {
    return assertQ7DevelopmentSnapshot({service, revision, functionConfig, queues},
      expectedVerificationDigest);
  }
  catch (error) {
    throw new Error(error instanceof Error ? error.message : "Q7_PREFLIGHT_FAILED");
  }
}

function gcloudJSON(args) {
  try {
    return JSON.parse(execFileSync("gcloud", args, {encoding: "utf8",
      maxBuffer: 16 * 1024 * 1024, timeout: 60_000}));
  } catch {
    throw new Error("Q7_DEVELOPMENT_PREFLIGHT_READ_FAILED");
  }
}

function normalizeTimes(value) {
  if (value instanceof Timestamp) return value.toMillis();
  if (Array.isArray(value)) return value.map(normalizeTimes);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, child]) =>
      [key, normalizeTimes(child)]));
  }
  return value;
}

async function poll(operation, timeoutMs, timeoutCode) {
  const deadline = Date.now() + Math.min(timeoutMs, MAX_RUN_MS);
  let delay = 3_000;
  while (Date.now() < deadline) {
    const result = await operation();
    if (result !== null && result !== undefined) return result;
    await sleep(delay);
    delay = Math.min(delay, 10_000);
  }
  throw new Error(timeoutCode);
}

async function waitForLogin(activeSession) {
  let timer;
  try {
    await Promise.race([activeSession.login, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error("Q7_LOGIN_TIMEOUT")), 5 * 60 * 1000);
    })]);
  } finally { clearTimeout(timer); }
}
function openBrowser(url) {
  if (process.env.OUTPICK_Q7_OPEN_BROWSER === "0") return;
  const command = process.platform === "darwin" ? "open" :
    process.platform === "win32" ? "cmd" : "xdg-open";
  const commandArgs = process.platform === "win32" ? ["/c", "start", "", url] : [url];
  const child = spawn(command, commandArgs, {stdio: "ignore", detached: true});
  child.on("error", () => process.stdout.write("위 URL을 브라우저에서 여세요.\n"));
  child.unref();
}
async function saveJSON(url, value) {
  const snapshot = normalizeTimes(value);
  const write = jsonWriteTail.then(() => atomicSave(fileURLToPath(url), snapshot));
  jsonWriteTail = write.catch(() => undefined);
  await write;
}
function sleep(ms) { return new Promise((resolve) => setTimeout(resolve, ms)); }
