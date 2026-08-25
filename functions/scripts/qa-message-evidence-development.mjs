import {randomUUID} from "node:crypto";
import {applicationDefault, deleteApp, initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {messageIncidentID} from "../lib/moderation/messageEvidence/contracts.js";

const PROJECT_ID = "outpick-test";
const READY_BUCKET = "outpick-test-chat-media";
const EVIDENCE_BUCKET = "outpick-test-moderation-evidence";
const MEBIBYTE = 1024 * 1024;
const IMAGE_COUNT = 30;
const IMAGE_BYTES = 5 * MEBIBYTE;
const VIDEO_BYTES = 350 * MEBIBYTE;
const POLL_INTERVAL_MILLIS = 2_000;
const POLL_TIMEOUT_MILLIS = 12 * 60 * 1_000;

function runID(values) {
  const index = values.indexOf("--run-id");
  const value = index >= 0 ? values[index + 1] : null;
  if (!value || !/^[a-z0-9-]{1,40}$/.test(value)) {
    throw new Error("--run-id에는 1~40자의 소문자·숫자·하이픈만 사용할 수 있습니다.");
  }
  return value;
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitForDocument(reference, predicate, label) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < POLL_TIMEOUT_MILLIS) {
    const snapshot = await reference.get();
    if (predicate(snapshot)) {
      return {snapshot, elapsedMillis: Date.now() - startedAt};
    }
    await sleep(POLL_INTERVAL_MILLIS);
  }
  throw new Error(`${label}이 ${POLL_TIMEOUT_MILLIS}ms 안에 완료되지 않았습니다.`);
}

async function saveFiveMiBFixture(bucket, path) {
  const file = bucket.file(path);
  await file.save(Buffer.alloc(IMAGE_BYTES, 0x61), {
    resumable: false,
    validation: "crc32c",
    contentType: "application/octet-stream",
    metadata: {cacheControl: "private, no-store"},
  });
  return file;
}

async function copyWithContentType(source, destination, contentType) {
  const [copied] = await source.copy(destination, {preconditionOpts: {ifGenerationMatch: 0}});
  await copied.setMetadata({contentType, cacheControl: "private, no-store"});
  const [metadata] = await copied.getMetadata();
  return metadata;
}

async function createImageSources(bucket, base, roomID, messageID) {
  const sources = [];
  for (let index = 0; index < IMAGE_COUNT; index += 1) {
    const attachmentID = `image-${String(index + 1).padStart(2, "0")}`;
    const path = `rooms/${roomID}/messages/${messageID}/attachments/${attachmentID}/display`;
    const metadata = await copyWithContentType(base, bucket.file(path), "image/jpeg");
    sources.push({
      attachmentID,
      bucket: READY_BUCKET,
      path,
      generation: String(metadata.generation),
      bytes: Number(metadata.size),
      contentType: String(metadata.contentType),
    });
  }
  return sources;
}

async function createVideoSource(bucket, base, fixturePrefix, roomID, messageID) {
  const components = [];
  for (let index = 0; index < 70; index += 1) {
    const component = bucket.file(`${fixturePrefix}/video-component-${String(index + 1).padStart(2, "0")}`);
    await base.copy(component, {preconditionOpts: {ifGenerationMatch: 0}});
    components.push(component);
  }
  const intermediateA = bucket.file(`${fixturePrefix}/video-160m-a`);
  const intermediateB = bucket.file(`${fixturePrefix}/video-160m-b`);
  const intermediateC = bucket.file(`${fixturePrefix}/video-30m-c`);
  await bucket.combine(components.slice(0, 32), intermediateA, {ifGenerationMatch: 0});
  await bucket.combine(components.slice(32, 64), intermediateB, {ifGenerationMatch: 0});
  await bucket.combine(components.slice(64), intermediateC, {ifGenerationMatch: 0});

  const attachmentID = "video-01";
  const path = `rooms/${roomID}/messages/${messageID}/attachments/${attachmentID}/display`;
  const destination = bucket.file(path);
  await bucket.combine([intermediateA, intermediateB, intermediateC], destination, {ifGenerationMatch: 0});
  await destination.setMetadata({contentType: "video/mp4", cacheControl: "private, no-store"});
  const [metadata] = await destination.getMetadata();
  if (Number(metadata.size) !== VIDEO_BYTES) {
    throw new Error(`350 MiB 영상 fixture 크기가 일치하지 않습니다: ${metadata.size}`);
  }
  return {
    source: {
      attachmentID,
      bucket: READY_BUCKET,
      path,
      generation: String(metadata.generation),
      bytes: Number(metadata.size),
      contentType: String(metadata.contentType),
    },
    components: [...components, intermediateA, intermediateB, intermediateC],
  };
}

function scenario(run, kind, sources) {
  const suffix = kind === "image" ? "images" : "video";
  const roomID = `qa-c3-${run}-${suffix}-room`;
  const messageID = `qa-c3-${run}-${suffix}-message`;
  const bundleID = `qa-c3-${run}-${suffix}-bundle`;
  const incidentID = messageIncidentID(roomID, messageID);
  return {kind, roomID, messageID, bundleID, incidentID, sources};
}

async function createCopyJob(firestore, input) {
  const now = Timestamp.now();
  const bundleRef = firestore.collection("moderationMessageEvidence").doc(input.bundleID);
  const guardRef = firestore.collection("moderationMessageGuards").doc(input.incidentID);
  const jobRef = firestore.collection("moderationEvidenceCopyJobs").doc(input.bundleID);
  await bundleRef.create({
    schemaVersion: 1,
    roomID: input.roomID,
    messageID: input.messageID,
    reviewRevision: 0,
    textSnapshot: null,
    replyContextSnapshot: null,
    sharedContentSnapshot: null,
    attachmentIDs: input.sources.map((source) => source.attachmentID),
    sourceObjects: input.sources,
    evidenceObjects: [],
    attemptGeneration: 0,
    acceptanceState: "notReady",
    pendingPreparationCount: 0,
    totalDisplayBytes: input.sources.reduce((sum, source) => sum + source.bytes, 0),
    objectPaths: [],
    state: "copyPending",
    retentionClass: "reviewOpen",
    createdAt: now,
    deleteAfter: null,
    updatedAt: now,
  });
  await guardRef.create({
    schemaVersion: 1,
    roomID: input.roomID,
    messageID: input.messageID,
    contentState: "active",
    guardWinner: "reportFirst",
    evidenceState: "copyPending",
    bundleID: input.bundleID,
    reviewRevision: 0,
    updatedAt: now,
  });
  await jobRef.create({
    schemaVersion: 1,
    roomID: input.roomID,
    messageID: input.messageID,
    bundleID: input.bundleID,
    incidentID: input.incidentID,
    reviewRevision: 0,
    messageType: input.kind,
    attemptGeneration: 0,
    sourceObjects: input.sources,
    evidenceObjects: [],
    status: "pending",
    phase: "copying",
    attempt: 0,
    finalizationAttempt: 0,
    nextAttemptAt: now,
    leaseToken: null,
    leaseExpiresAt: null,
    lastErrorCode: null,
    createdAt: now,
    updatedAt: now,
  });
  return {bundleRef, guardRef, jobRef};
}

async function verifyCopy(input, references) {
  const result = await waitForDocument(
    references.jobRef,
    (snapshot) => ["succeeded", "failed"].includes(snapshot.get("status")),
    `${input.kind} copy job`,
  );
  if (result.snapshot.get("status") !== "succeeded") {
    throw new Error(`${input.kind} copy가 실패했습니다: ${result.snapshot.get("lastErrorCode")}`);
  }
  const bundle = await references.bundleRef.get();
  const objects = bundle.get("evidenceObjects");
  if (bundle.get("state") !== "available" || bundle.get("acceptanceState") !== "reviewable" ||
      !Array.isArray(objects) || objects.length !== input.sources.length) {
    throw new Error(`${input.kind} evidence bundle 완료 계약이 일치하지 않습니다.`);
  }
  const totalBytes = objects.reduce((sum, object) => sum + Number(object.bytes), 0);
  const expectedBytes = input.kind === "image" ? IMAGE_COUNT * IMAGE_BYTES : VIDEO_BYTES;
  if (totalBytes !== expectedBytes) {
    throw new Error(`${input.kind} evidence bytes가 일치하지 않습니다: ${totalBytes}`);
  }
  const firstPath = objects[0].path;
  const publicResponse = await fetch(`https://storage.googleapis.com/${EVIDENCE_BUCKET}/${encodeURIComponent(firstPath).replaceAll("%2F", "/")}`);
  if (publicResponse.status !== 403) {
    throw new Error(`${input.kind} evidence 공개 요청이 403이 아닙니다: ${publicResponse.status}`);
  }
  return {elapsedMillis: result.elapsedMillis, objects, totalBytes, publicStatus: publicResponse.status};
}

async function enqueueAndVerifyCleanup(firestore, input, references) {
  const now = Timestamp.now();
  const cleanupRef = firestore.collection("moderationEvidenceCleanupJobs").doc(input.bundleID);
  await references.bundleRef.set({state: "cleanupPending", updatedAt: now}, {merge: true});
  await cleanupRef.create({
    schemaVersion: 1,
    bundleID: input.bundleID,
    attemptGeneration: 0,
    reviewRevision: 0,
    status: "pending",
    phase: "deleting",
    attempt: 0,
    nextAttemptAt: now,
    leaseToken: null,
    leaseExpiresAt: null,
    lastErrorCode: null,
    createdAt: now,
    updatedAt: now,
  });
  const result = await waitForDocument(
    cleanupRef,
    (snapshot) => ["succeeded", "failed"].includes(snapshot.get("status")),
    `${input.kind} cleanup job`,
  );
  if (result.snapshot.get("status") !== "succeeded") {
    throw new Error(`${input.kind} cleanup이 실패했습니다: ${result.snapshot.get("lastErrorCode")}`);
  }
  if ((await references.bundleRef.get()).exists) {
    throw new Error(`${input.kind} cleanup 뒤 bundle 문서가 남아 있습니다.`);
  }
  return {cleanupRef, elapsedMillis: result.elapsedMillis};
}

async function deleteFiles(files) {
  await Promise.all(files.map((file) => file.delete({ignoreNotFound: true})));
}

const selectedRunID = runID(process.argv.slice(2));
const app = initializeApp({
  credential: applicationDefault(),
  projectId: PROJECT_ID,
  storageBucket: READY_BUCKET,
}, `message-evidence-c3-${selectedRunID}-${randomUUID()}`);

const firestore = getFirestore(app);
const readyBucket = getStorage(app).bucket(READY_BUCKET);
const evidenceBucket = getStorage(app).bucket(EVIDENCE_BUCKET);
const fixturePrefix = `qa/message-evidence-c3/${selectedRunID}`;
const base = await saveFiveMiBFixture(readyBucket, `${fixturePrefix}/five-mib-base`);
const createdSourceFiles = [];
const createdComponentFiles = [base];
const createdReferences = [];
const cleanupReferences = [];

try {
  const imageIdentity = scenario(selectedRunID, "image", []);
  const imageSources = await createImageSources(
    readyBucket,
    base,
    imageIdentity.roomID,
    imageIdentity.messageID,
  );
  createdSourceFiles.push(...imageSources.map((source) => readyBucket.file(source.path)));
  const imageScenario = {...imageIdentity, sources: imageSources};

  const videoIdentity = scenario(selectedRunID, "video", []);
  const videoFixture = await createVideoSource(
    readyBucket,
    base,
    fixturePrefix,
    videoIdentity.roomID,
    videoIdentity.messageID,
  );
  createdSourceFiles.push(readyBucket.file(videoFixture.source.path));
  createdComponentFiles.push(...videoFixture.components);
  const videoScenario = {...videoIdentity, sources: [videoFixture.source]};

  const results = [];
  for (const input of [imageScenario, videoScenario]) {
    const references = await createCopyJob(firestore, input);
    createdReferences.push({input, ...references});
    const copy = await verifyCopy(input, references);
    const cleanup = await enqueueAndVerifyCleanup(firestore, input, references);
    cleanupReferences.push(cleanup.cleanupRef);
    const [remaining] = await evidenceBucket.getFiles({prefix: `${input.bundleID}/`});
    if (remaining.length !== 0) {
      throw new Error(`${input.kind} cleanup 뒤 evidence 객체 ${remaining.length}개가 남아 있습니다.`);
    }
    results.push({
      kind: input.kind,
      sourceCount: input.sources.length,
      totalBytes: copy.totalBytes,
      copyElapsedMillis: copy.elapsedMillis,
      publicStatus: copy.publicStatus,
      cleanupElapsedMillis: cleanup.elapsedMillis,
      evidenceObjectsAfterCleanup: remaining.length,
    });
  }

  await deleteFiles([...createdSourceFiles, ...createdComponentFiles]);
  for (const reference of createdReferences) {
    await Promise.all([
      reference.jobRef.delete(),
      reference.guardRef.delete(),
    ]);
  }
  await Promise.all(cleanupReferences.map((reference) => reference.delete()));

  const [fixtureResidue] = await readyBucket.getFiles({prefix: fixturePrefix});
  const [evidenceResidue] = await evidenceBucket.getFiles({prefix: `qa-c3-${selectedRunID}-`});
  if (fixtureResidue.length !== 0 || evidenceResidue.length !== 0) {
    throw new Error(`QA cleanup residue가 남았습니다: ready=${fixtureResidue.length}, evidence=${evidenceResidue.length}`);
  }
  console.log(JSON.stringify({
    projectID: PROJECT_ID,
    runID: selectedRunID,
    results,
    readyFixtureResidue: fixtureResidue.length,
    evidenceResidue: evidenceResidue.length,
  }, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    projectID: PROJECT_ID,
    runID: selectedRunID,
    retainedForInvestigation: {
      readyFixturePrefix: fixturePrefix,
      bundleIDs: createdReferences.map((reference) => reference.input.bundleID),
    },
    error: error instanceof Error ? error.message : String(error),
  }, null, 2));
  process.exitCode = 1;
} finally {
  await deleteApp(app);
}
