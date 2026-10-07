#!/usr/bin/env node
import {createHash, randomUUID} from "node:crypto";
import {mkdir, open, readFile, rename} from "node:fs/promises";
import {dirname, join} from "node:path";
import {fileURLToPath} from "node:url";
import {applicationDefault, deleteApp, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {queueBatchID, queueHash} from "../../../functions/lib/shared/lookbookQueue/model.js";
import {openQ7Journal} from "./q7-journal.mjs";

const projectID = "outpick-test";
const runID = process.argv.slice(2).find((value) => value.startsWith("--runID="))
  ?.slice("--runID=".length);
if (!/^[a-f0-9-]{36}$/.test(runID ?? "")) {
  throw new Error("사용법: node q7-reconcile-no-mutation.mjs --runID=<UUID>");
}
const outputRoot = fileURLToPath(new URL(
  "../../../output/lookbook-import-performance/product-queue-q7/",
  import.meta.url));
const runDirectory = join(outputRoot, runID);
const journalPath = join(runDirectory, runID + ".json");
const reportPath = join(runDirectory, "report.json");
const manifestPath = join(runDirectory, "manifest.json");
const [journal, report, manifest] = await Promise.all([
  readJSON(journalPath), readJSON(reportPath), readJSON(manifestPath),
]);
if (journal.runID !== runID || journal.status !== "stopped" ||
    report.runID !== runID || report.stage !== "smoke" ||
    report.status !== "stopped" || report.batchIDs?.length !== 0 ||
    manifest.runID !== runID || manifest.projectID !== projectID ||
    manifest.stage !== "smoke" || manifest.brands?.length !== 0 ||
    manifest.batches?.length !== 0 || manifest.jobs?.length !== 0 ||
    journal.requests?.length !== 1) {
  throw new Error("Q7_RECONCILE_RUN_NOT_ELIGIBLE");
}
const request = journal.requests[0];
if (request.state !== "uncertain" || request.callable !== "createBrand" ||
    request.errorCode !== "PERMISSION_DENIED" ||
    request.payload?.name !== "Q7 A " + runID.slice(0, 8) ||
    request.payload?.lookbookArchiveURL !==
      "https://unaffected.co.kr/collection.html?cate_no=88") {
  throw new Error("Q7_RECONCILE_REQUEST_NOT_ELIGIBLE");
}

const app = initializeApp({credential: applicationDefault(), projectId: projectID},
  "q7-reconcile-" + runID);
let store;
try {
  const auth = getAuth(app);
  const firestore = getFirestore(app);
  const identityHash = manifest.identity?.uidHash;
  if (typeof identityHash !== "string" || !/^[a-f0-9]{64}$/.test(identityHash)) {
    throw new Error("Q7_RECONCILE_IDENTITY_MISSING");
  }
  const users = await auth.listUsers(1000);
  const matchedUsers = users.users.filter((user) =>
    createHash("sha256").update(user.uid).digest("hex") === identityHash);
  if (matchedUsers.length !== 1 || !matchedUsers[0].providerData.some((provider) =>
    provider.providerId === "google.com")) {
    throw new Error("Q7_RECONCILE_IDENTITY_MISMATCH");
  }
  const uid = matchedUsers[0].uid;
  const adminSnapshot = await firestore.doc("platformAdmins/" + uid).get();
  const adminData = adminSnapshot.data() ?? {};
  const adminUpdatedAt = adminData.updatedAt instanceof Timestamp ?
    adminData.updatedAt.toMillis() : null;
  if (adminData.isActive !== true || adminData.revokedAt instanceof Timestamp ||
      adminUpdatedAt === null || adminUpdatedAt > request.requestCreatedAt) {
    throw new Error("Q7_RECONCILE_ADMIN_STATE_UNVERIFIED");
  }

  const requestKey = queueBatchID(uid, request.requestID);
  const brandID = queueHash(["brand", requestKey]);
  const [receipt, brand, batch, sameName, nameIndex, queue] = await Promise.all([
    firestore.doc("brandCreationRequests/" + requestKey).get(),
    firestore.doc("brands/" + brandID).get(),
    firestore.doc("lookbookImportBatches/" + requestKey).get(),
    firestore.collection("brands").where("name", "==", request.payload.name)
      .limit(2).get(),
    firestore.collection("brandNameIndex").where("name", "==", request.payload.name)
      .limit(2).get(),
    firestore.doc("lookbookImportQueue/main").get(),
  ]);
  if (receipt.exists || brand.exists || batch.exists || sameName.size !== 0 ||
      nameIndex.size !== 0) {
    throw new Error("Q7_RECONCILE_REMOTE_ARTIFACT_FOUND");
  }

  const evidenceFile = "evidence/no-mutation-reconciliation.json";
  const checkedAt = Date.now();
  const evidence = {
    schemaVersion: 1,
    runID,
    projectID,
    stage: "smoke",
    checkedAt,
    conclusion: "noMutationConfirmed",
    request: {
      requestID: request.requestID,
      callable: request.callable,
      errorCode: request.errorCode,
      payloadDigest: request.payloadDigest,
    },
    administrator: {
      isActive: true,
      revokedAtIsTimestamp: false,
      updatedAtMillis: adminUpdatedAt,
      activeBeforeRequest: adminUpdatedAt <= request.requestCreatedAt,
    },
    checks: {
      receiptExists: receipt.exists,
      deterministicBrandExists: brand.exists,
      deterministicBatchExists: batch.exists,
      matchingBrandCount: sameName.size,
      matchingNameIndexCount: nameIndex.size,
    },
    queueAtReconciliation: queue.exists ? {
      headBatchIDPresent: Boolean(queue.get("headBatchID")),
      recoveryRequired: queue.get("recoveryRequired") === true,
    } : {exists: false},
    note: "createBrand의 트랜잭션 결과 흔적을 Development에서 읽기 전용으로 확인함.",
  };
  const evidenceRaw = JSON.stringify(evidence, null, 2) + "\n";
  const evidenceDigest = createHash("sha256").update(evidenceRaw).digest("hex");
  await atomicWrite(join(runDirectory, evidenceFile), evidenceRaw);

  store = await openQ7Journal(runDirectory, runID, {});
  await store.updateRequest(request.requestID, {
    state: "reconciledNoMutation",
    noMutationConfirmed: true,
    reconciledAt: checkedAt,
    reconciliationEvidence: evidenceFile,
  });
  await store.save({...store.snapshot(), status: "reconciled",
    reconciledAt: checkedAt, reconciliation: {
      status: "noMutationConfirmed", evidenceFile, evidenceDigest,
    }});
  await atomicWrite(reportPath, JSON.stringify({...report, reconciliation: {
    status: "noMutationConfirmed", evidenceFile, evidenceDigest,
    reconciledAt: checkedAt,
  }}, null, 2) + "\n");
  process.stdout.write(JSON.stringify({runID, projectID,
    conclusion: "noMutationConfirmed", evidenceFile, evidenceDigest}, null, 2) + "\n");
} finally {
  await store?.close();
  await deleteApp(app);
}

async function readJSON(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

async function atomicWrite(path, contents) {
  await mkdir(dirname(path), {recursive: true, mode: 0o700});
  const temporary = path + "." + randomUUID() + ".tmp";
  const file = await open(temporary, "wx", 0o600);
  try {
    await file.writeFile(contents);
    await file.sync();
  } finally {
    await file.close();
  }
  await rename(temporary, path);
  const directory = await open(dirname(path), "r");
  try { await directory.sync(); } finally { await directory.close(); }
}
