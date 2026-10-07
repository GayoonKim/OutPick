import {createHash, randomUUID} from "node:crypto";
import {mkdir, open, readFile, readdir, rename, rm, stat} from "node:fs/promises";
import {closeSync, rmSync} from "node:fs";
import {dirname, join} from "node:path";
import {loadQ7SmokeResume, loadQ7Finalization} from "./q7-resume.mjs";
import {makePlan} from "./queue-development-contract.mjs";
import {loadRetryKLResume} from "./q7-retry-contract.mjs";

export async function openQ7Campaign(directory, stage, resumeRunID = null, verifyOnly = false, retryContinuation = false) {
  if (!/^(smoke|tenBrands|retryKL)$/.test(stage)) throw new Error("Q7_INVALID_STAGE");
  await mkdir(directory, {recursive: true, mode: 0o700});
  const lockPath = join(directory, ".campaign.lock");
  let lock;
  try {
    lock = await open(lockPath, "wx", 0o600);
    await lock.writeFile(JSON.stringify({pid: process.pid, stage, createdAt: Date.now()}));
    await lock.sync();
  } catch (error) {
    if (error?.code === "EEXIST" && await isStaleLock(lockPath)) {
      await rm(lockPath, {force: true});
      return openQ7Campaign(directory, stage, resumeRunID, verifyOnly, retryContinuation);
    }
    throw new Error("Q7_CAMPAIGN_ALREADY_LOCKED");
  }

  let closed = false;
  const releaseAtExit = () => {
    try { closeSync(lock.fd); } catch {}
    try { rmSync(lockPath, {force: true}); } catch {}
  };
  process.once("exit", releaseAtExit);
  const close = async () => {
    if (closed) return;
    closed = true;
    process.removeListener("exit", releaseAtExit);
    await lock.close();
    await rm(lockPath, {force: true});
  };

  try {
    if (resumeRunID) {
      if (stage === "retryKL" && !verifyOnly) await loadRetryKLResume(join(directory, resumeRunID), resumeRunID, retryContinuation);
      else if (stage !== "smoke") throw new Error("Q7_RESUME_STAGE_UNSUPPORTED");
      else if (verifyOnly) await loadQ7Finalization(join(directory, resumeRunID), resumeRunID, makePlan(stage));
      else await loadQ7SmokeResume(join(directory, resumeRunID), resumeRunID, makePlan(stage));
    }
    const names = await readdir(directory, {withFileTypes: true});
    for (const entry of names) {
      if (!entry.isDirectory()) continue;
      const runID = entry.name;
      const runDirectory = join(directory, runID);
      let report = null;
      let journal = null;
      try { report = JSON.parse(await readFile(join(runDirectory, "report.json"), "utf8")); }
      catch (error) { if (error?.code !== "ENOENT") report = {status: "invalid"}; }
      try { journal = JSON.parse(await readFile(join(runDirectory, runID + ".json"), "utf8")); }
      catch (error) { if (error?.code !== "ENOENT") journal = {status: "invalid"}; }
      if (report?.stage === stage && report?.status === "completed") {
        throw new Error("Q7_STAGE_ALREADY_COMPLETED:" + runID);
      }
      if (!journal) continue;
      const reconciledNoMutation = await hasReconciledNoMutation(runDirectory,
        runID, report, journal);
      const settledTerminalCorrection = await hasSettledTerminalCorrection(
        runDirectory, runID, report, journal);
      const unresolved = report?.status !== "completed" &&
        !reconciledNoMutation && !settledTerminalCorrection &&
        (journal.status === "invalid" || journal.status === "running" ||
          (journal.requests ?? []).some((request) => request.state !== "prepared"));
      if (unresolved && runID !== resumeRunID) throw new Error("Q7_UNRESOLVED_PRIOR_RUN:" + runID);
    }
    return {close};
  } catch (error) {
    await close();
    throw error;
  }
}

async function hasSettledTerminalCorrection(directory, runID, report, journal) {
  if (report?.stage !== "smoke" || report.status !== "stopped" ||
      journal.status !== "stopped" || journal.requests?.length !== 1 ||
      report.mutationCount !== 1 || journal.mutationCount !== 1) return false;
  const request = journal.requests[0];
  const receipt = request.response;
  if (request.callable !== "createBrand" || request.state !== "accepted" ||
      !receipt?.brandID || !receipt.discoveryJobID || !receipt.batchID ||
      report.batchIDs?.length !== 1 || report.batchIDs[0] !== receipt.batchID ||
      journal.batchIDs?.length !== 1 ||
      journal.batchIDs[0] !== receipt.batchID) return false;
  try {
    const proof = JSON.parse(await readFile(join(directory,
      "evidence/terminal-correction-reconciliation.json"), "utf8"));
    const [reportRaw, journalRaw, readbackRaw] = await Promise.all([
      readFile(join(directory, "report.json"), "utf8"),
      readFile(join(directory, runID + ".json"), "utf8"),
      readFile(join(directory, "evidence/settlement-readback.json"), "utf8"),
    ]);
    const digest = (raw) => createHash("sha256").update(raw).digest("hex");
    if (proof.schemaVersion !== 1 || proof.runID !== runID ||
        proof.projectID !== "outpick-test" ||
        proof.conclusion !== "settledTerminalCorrection" ||
        proof.reportDigest !== digest(reportRaw) ||
        proof.journalDigest !== digest(journalRaw) ||
        proof.readbackDigest !== digest(readbackRaw)) return false;
    const {status, queue, batch, run, job, decision} = JSON.parse(readbackRaw);
    const expectedRunID = receipt.batchID + "-" + batch?.epoch;
    return status === "passed" && queue?.state === "idle" &&
      batch?.state === "released" && batch.kind === "discoverSeasons" &&
      batch.brandID === receipt.brandID && batch.items?.length === 1 &&
      batch.items[0].jobID === receipt.discoveryJobID &&
      batch.items[0].processingStatus === "correctionRequired" &&
      batch.items[0].activeRunID === null &&
      job?.status === "correctionRequired" &&
      run?.runID === expectedRunID && run.terminalConfirmed === true &&
      run.inFlight === 0 && decision?.projectID === "outpick-test" &&
      decision.serviceName === "lookbook-import-worker-development" &&
      decision.decision === "settleCorrectionRequired" &&
      decision.batchID === receipt.batchID &&
      decision.runID === expectedRunID &&
      decision.expectedEpoch === batch.epoch &&
      decision.stateRevisionAfter === batch.stateRevision &&
      decision.uncertainAssetWriteCount === 0 &&
      decision.correctionEvidence?.jobID === receipt.discoveryJobID &&
      decision.evidence?.kind === "durableDrain" &&
      decision.evidence.runID === expectedRunID &&
      decision.evidence.terminalConfirmed === true &&
      decision.evidence.inFlight === 0;
  } catch {
    return false;
  }
}

async function hasReconciledNoMutation(directory, runID, report, journal) {
  const reconciliation = report?.reconciliation;
  if (report?.stage !== "smoke" ||
      reconciliation?.status !== "noMutationConfirmed" ||
      journal.status !== "reconciled" ||
      journal.reconciliation?.status !== "noMutationConfirmed" ||
      reconciliation.evidenceFile !== "evidence/no-mutation-reconciliation.json" ||
      typeof reconciliation.evidenceDigest !== "string" ||
      reconciliation.evidenceDigest.length !== 64 ||
      typeof reconciliation.evidenceFile !== "string") return false;
  if (journal.requests?.length !== 1) return false;
  const request = journal.requests[0];
  if (request.state !== "reconciledNoMutation" ||
      request.callable !== "createBrand" ||
      request.errorCode !== "PERMISSION_DENIED" ||
      request.noMutationConfirmed !== true ||
      request.reconciliationEvidence !== reconciliation.evidenceFile) return false;
  try {
    const evidencePath = join(directory, reconciliation.evidenceFile);
    const raw = await readFile(evidencePath, "utf8");
    if (createHash("sha256").update(raw).digest("hex") !==
        reconciliation.evidenceDigest) return false;
    const evidence = JSON.parse(raw);
    return evidence.schemaVersion === 1 && evidence.runID === runID &&
      evidence.projectID === "outpick-test" && evidence.stage === "smoke" &&
      evidence.conclusion === "noMutationConfirmed" &&
      evidence.request?.requestID === request.requestID &&
      evidence.request?.callable === "createBrand" &&
      evidence.request?.errorCode === "PERMISSION_DENIED" &&
      evidence.request?.payloadDigest === request.payloadDigest &&
      evidence.checks?.receiptExists === false &&
      evidence.checks?.deterministicBrandExists === false &&
      evidence.checks?.deterministicBatchExists === false &&
      evidence.checks?.matchingBrandCount === 0 &&
      evidence.checks?.matchingNameIndexCount === 0;
  } catch {
    return false;
  }
}

export async function openQ7Journal(directory, runID, initial) {
  if (!/^[a-zA-Z0-9-]{8,80}$/.test(runID)) throw new Error("Q7_INVALID_RUN_ID");
  await mkdir(directory, {recursive: true, mode: 0o700});
  const path = join(directory, runID + ".json");
  const lockPath = path + ".lock";
  let lock;
  try {
    lock = await open(lockPath, "wx", 0o600);
    await lock.writeFile(JSON.stringify({pid: process.pid, createdAt: Date.now()}));
    await lock.sync();
  } catch (error) {
    if (error?.code === "EEXIST" && await isStaleLock(lockPath)) {
      await rm(lockPath, {force: true});
      return openQ7Journal(directory, runID, initial);
    }
    throw new Error("Q7_RUN_ALREADY_LOCKED");
  }
  let closed = false;
  let value;
  let writeTail = Promise.resolve();
  let writeFailure = null;
  const serial = (operation) => (...args) => {
    const running = writeTail.then(() => {
      if (writeFailure) throw writeFailure;
      return operation(...args);
    });
    writeTail = running.then(() => undefined, (error) => {
      // 저장소 오류 뒤에는 새 전송을 허용하지 않는다. 입력 검증 거절은 정상 재사용이 가능하다.
      if (error?.code) writeFailure ??= error;
    });
    return running;
  };
  try {
    value = JSON.parse(await readFile(path, "utf8"));
    if (value.runID !== runID) throw new Error("Q7_JOURNAL_ID_MISMATCH");
  } catch (error) {
    if (error?.code !== "ENOENT") {
      await lock.close();
      await rm(lockPath, {force: true});
      throw error;
    }
    value = {schemaVersion: 1, runID, createdAt: Date.now(), requests: [], ...initial};
    await atomicSave(path, value);
  }
  return {
    path,
    snapshot: () => structuredClone(value),
    save: serial(async (next) => {
      if (closed) throw new Error("Q7_JOURNAL_CLOSED");
      value = structuredClone(next);
      await atomicSave(path, value);
    }),
    appendRequest: serial(async (request) => {
      if (closed) throw new Error("Q7_JOURNAL_CLOSED");
      if (value.requests.some((item) => item.requestID === request.requestID)) {
        throw new Error("Q7_DUPLICATE_REQUEST_ID");
      }
      if (containsCredential(request)) throw new Error("Q7_JOURNAL_SECRET_REJECTED");
      const frozen = {...request, payloadDigest: digest(request.payload),
        state: "prepared", preparedAt: Date.now()};
      value.requests.push(frozen);
      await atomicSave(path, value);
      return structuredClone(frozen);
    }),
    updateRequest: serial(async (requestID, patch) => {
      if (closed) throw new Error("Q7_JOURNAL_CLOSED");
      const index = value.requests.findIndex((item) => item.requestID === requestID);
      if (index < 0) throw new Error("Q7_REQUEST_NOT_FOUND");
      value.requests[index] = {...value.requests[index], ...patch};
      await atomicSave(path, value);
      return structuredClone(value.requests[index]);
    }),
    close: async () => {
      if (closed) return;
      await writeTail;
      closed = true;
      await lock.close();
      await rm(lockPath, {force: true});
    },
  };
}

function digest(value) {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}
function containsCredential(value) {
  if (Array.isArray(value)) return value.some(containsCredential);
  if (!value || typeof value !== "object") return false;
  return Object.entries(value).some(([key, child]) =>
    /^(?:idToken|refreshToken|accessToken|authorization|cookie)$/i.test(key) ||
    containsCredential(child));
}
export async function atomicSave(path, value) {
  const temporary = path + "." + randomUUID() + ".tmp";
  const file = await open(temporary, "wx", 0o600);
  try {
    await file.writeFile(JSON.stringify(value, null, 2));
    await file.sync();
  } finally {
    await file.close();
  }
  await rename(temporary, path);
  const directory = await open(dirname(path), "r");
  try { await directory.sync(); } finally { await directory.close(); }
}
async function isStaleLock(path) {
  try {
    const data = JSON.parse(await readFile(path, "utf8"));
    if (!Number.isInteger(data.pid) || data.pid < 1) return false;
    try { process.kill(data.pid, 0); return false; } catch (error) {
      return error?.code === "ESRCH";
    }
  } catch (error) {
    if (error?.code === "ENOENT") return true;
    try { await stat(path); return false; } catch { return true; }
  }
}
