/* eslint-disable require-jsdoc, max-len */
import {createHash, randomUUID} from "node:crypto";
import type {DocumentReference, Firestore} from "firebase-admin/firestore";
import {QUEUE_POLICY} from "./contracts.js";

const QUEUE_PATH = "lookbookImportQueue/main";
const BATCH_COLLECTION = "lookbookImportBatches";
const MAX_ASSET_WRITES = QUEUE_POLICY.cleanupMaxOperations - 10;

export type RecoveryTarget = {
  projectID: string;
  serviceName: string;
  revision: string;
  batchID: string;
  expectedEpoch: number;
};

export type PlatformTerminationEvidence = {
  kind: "platformTermination";
  projectID: string;
  serviceName: string;
  revision: string;
  instanceID: string;
  traceID: string;
  timestamp: string;
  insertID: string;
};

export type RecoveryEvidenceProvider = {
  findTerminatedInstance(input: {
    projectID: string;
    serviceName: string;
    revision: string;
    traceID: string;
    startedAt: number;
  }): Promise<PlatformTerminationEvidence | null>;
};

export type QueueRecoveryReport = {
  target: RecoveryTarget;
  servingRevision: string;
  runID: string;
  bootID: string | null;
  traceID: string | null;
  stateRevision: number;
  queueState: string;
  batchState: string;
  evidence: Record<string, unknown> | null;
  uncertainAssetWriteCount: number;
  assetWriteScanComplete: boolean;
  blockers: string[];
  canResume: boolean;
  terminalOutcome: "correctionRequired" | null;
  correctionEvidence: Record<string, unknown> | null;
  settlementBlockers: string[];
  canSettleCorrection: boolean;
  reportDigest: string;
};

type AssetWrite = {ref: DocumentReference; data: FirebaseFirestore.DocumentData};

export function parseRecoveryTarget(value: unknown): RecoveryTarget {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("INVALID_RECOVERY_REQUEST");
  }
  const input = value as Record<string, unknown>;
  const allowed = ["projectID", "serviceName", "revision", "batchID", "expectedEpoch"];
  if (Object.keys(input).some((key) => !allowed.includes(key)) ||
      typeof input.projectID !== "string" || !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(input.projectID) ||
      typeof input.serviceName !== "string" || !/^[a-z][a-z0-9-]{0,62}[a-z0-9]$/.test(input.serviceName) ||
      typeof input.revision !== "string" || !/^[a-z][a-z0-9-]{0,62}[a-z0-9]$/.test(input.revision) ||
      typeof input.batchID !== "string" || !/^[a-f0-9]{64}$/.test(input.batchID) ||
      !Number.isSafeInteger(input.expectedEpoch) || Number(input.expectedEpoch) < 1) {
    throw new Error("INVALID_RECOVERY_REQUEST");
  }
  return {projectID: input.projectID, serviceName: input.serviceName,
    revision: input.revision, batchID: input.batchID,
    expectedEpoch: Number(input.expectedEpoch)};
}

export function isRecoveryDecisionID(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

export async function inspectQueueRecovery(input: {
  firestore: Firestore;
  evidenceProvider: RecoveryEvidenceProvider;
  target: RecoveryTarget;
  projectID: string;
  serviceName: string;
  revision: string;
}): Promise<QueueRecoveryReport> {
  const target = parseRecoveryTarget(input.target);
  const blockers: string[] = [];
  if (target.projectID !== input.projectID ||
      target.serviceName !== input.serviceName) {
    blockers.push("TARGET_ENVIRONMENT_MISMATCH");
    const runID = `${target.batchID}-${target.expectedEpoch}`;
    const report = {
      target, servingRevision: input.revision,
      runID, bootID: null, traceID: null, stateRevision: -1,
      queueState: "notInspected", batchState: "notInspected",
      evidence: null, uncertainAssetWriteCount: 0,
      assetWriteScanComplete: false, blockers, canResume: false,
      terminalOutcome: null, correctionEvidence: null,
      settlementBlockers: blockers, canSettleCorrection: false,
    };
    return {...report, reportDigest: stableDigest(report)};
  }
  const queue = (await input.firestore.doc(QUEUE_PATH).get()).data();
  const batchRef = input.firestore.collection(BATCH_COLLECTION).doc(target.batchID);
  const batch = (await batchRef.get()).data();
  const epoch = target.expectedEpoch;
  const runID = `${target.batchID}-${epoch}`;
  const run = batch ? (await batchRef.collection("runs").doc(runID).get()).data() : undefined;
  const stateRevision = Number(batch?.stateRevision ?? -1);
  const queueState = String(queue?.state ?? "missing");
  const batchState = String(batch?.state ?? "missing");
  const bootID = typeof run?.bootID === "string" ? run.bootID : null;
  const traceID = typeof run?.traceID === "string" ? run.traceID : null;
  if (!queue || !batch || !run) blockers.push("RECOVERY_RECORD_MISSING");
  if (queue?.headBatchID !== target.batchID) blockers.push("BATCH_IS_NOT_QUEUE_HEAD");
  if (queueState !== "recoveryRequired" || batchState !== "recoveryRequired") {
    blockers.push("BATCH_NOT_BLOCKED_FOR_RECOVERY");
  }
  if (Number(queue?.epoch) !== epoch || Number(batch?.epoch) !== epoch ||
      batch?.runID !== runID || run?.epoch !== epoch || run?.runID !== runID) {
    blockers.push("EPOCH_OR_RUN_MISMATCH");
  }
  if (run && run.revision !== target.revision) {
    blockers.push("RUN_REVISION_MISMATCH");
  }
  if (!Number.isSafeInteger(stateRevision) || stateRevision < 0) {
    blockers.push("STATE_REVISION_INVALID");
  }

  let evidence: Record<string, unknown> | null = null;
  if (run?.terminalConfirmed === true && run?.inFlight === 0) {
    evidence = {kind: "durableDrain", runID, epoch,
      terminalConfirmed: true, inFlight: 0};
  } else if (run && traceID && Number.isSafeInteger(run.startedAt)) {
    try {
      const proof = await input.evidenceProvider.findTerminatedInstance({
        projectID: target.projectID, serviceName: target.serviceName,
        revision: target.revision, traceID, startedAt: Number(run.startedAt),
      });
      if (proof && proof.projectID === target.projectID &&
          proof.serviceName === target.serviceName &&
          proof.revision === target.revision && proof.traceID === traceID &&
          typeof proof.instanceID === "string" && proof.instanceID.length > 0 &&
          typeof proof.insertID === "string" && proof.insertID.length > 0) {
        evidence = proof;
      }
    } catch {
      blockers.push("CLOUD_LOGGING_EVIDENCE_UNAVAILABLE");
    }
  }
  if (!evidence && !blockers.includes("CLOUD_LOGGING_EVIDENCE_UNAVAILABLE")) {
    blockers.push("INSTANCE_TERMINATION_NOT_PROVEN");
  }

  const scan = batch ? await findUploadingAssetWrites(
    input.firestore, batch, epoch) : {writes: [], complete: false};
  if (!scan.complete) blockers.push("ASSET_WRITE_SCAN_INCOMPLETE");
  const correction = batch ? await inspectCorrectionSettlement({
    firestore: input.firestore, batch, target,
  }) : {evidence: null, blockers: ["RECOVERY_RECORD_MISSING"]};
  const terminalOutcome = correction.evidence?.jobStatus === "correctionRequired" ?
    "correctionRequired" as const : null;
  const resumeBlockers = [...blockers];
  if (["importSeasons", "manualRetry", "reviewApproval"].includes(String(batch?.kind))) {
    resumeBlockers.push("SEASON_RESTART_FROM_PARSING_REQUIRED");
  }
  if (terminalOutcome) resumeBlockers.push("TERMINAL_OUTCOME_REQUIRES_SETTLEMENT");
  const settlementBlockers = [...blockers, ...correction.blockers];
  if (run?.terminalConfirmed !== true || run?.inFlight !== 0) {
    settlementBlockers.push("RUN_DRAIN_NOT_CONFIRMED");
  }
  if (scan.writes.length > 0) settlementBlockers.push("UNCERTAIN_ASSET_WRITES_PRESENT");
  const evidenceDigest = stableDigest({
    target, servingRevision: input.revision, runID, bootID, traceID,
    stateRevision, queueState, batchState, evidence, terminalOutcome,
    correctionEvidence: correction.evidence,
    uncertainAssetWritePaths: scan.writes.map((write) => write.ref.path).sort(),
    assetWriteScanComplete: scan.complete,
  });
  const report: QueueRecoveryReport = {
    target, servingRevision: input.revision,
    runID, bootID, traceID, stateRevision, queueState, batchState,
    evidence, uncertainAssetWriteCount: scan.writes.length,
    assetWriteScanComplete: scan.complete, terminalOutcome,
    correctionEvidence: correction.evidence,
    blockers: [...new Set(resumeBlockers)].sort(),
    canResume: resumeBlockers.length === 0,
    settlementBlockers: [...new Set(settlementBlockers)].sort(),
    canSettleCorrection: settlementBlockers.length === 0 &&
      terminalOutcome === "correctionRequired",
    reportDigest: evidenceDigest,
  };
  report.canResume = report.blockers.length === 0;
  return report;
}

async function inspectCorrectionSettlement(input: {
  firestore: Firestore;
  batch: FirebaseFirestore.DocumentData;
  target: RecoveryTarget;
}): Promise<{evidence: Record<string, unknown> | null; blockers: string[]}> {
  const {firestore, batch, target} = input;
  const blockers: string[] = [];
  if (batch.kind !== "discoverSeasons") {
    return {evidence: null, blockers: ["SETTLEMENT_KIND_UNSUPPORTED"]};
  }
  if (!Array.isArray(batch.items) || batch.items.length !== 1) {
    return {evidence: null, blockers: ["SETTLEMENT_ITEM_COUNT_INVALID"]};
  }
  const item = batch.items[0] as Record<string, unknown>;
  if (item.admissionStatus !== "created" ||
      item.processingStatus !== "recoveryRequired" ||
      typeof item.jobID !== "string" || typeof item.executionID !== "string" ||
      (item.activeRunID != null && item.activeRunID !== "")) {
    return {evidence: null, blockers: ["SETTLEMENT_ITEM_NOT_RECOVERABLE"]};
  }
  const brandID = typeof batch.brandID === "string" ? batch.brandID : "";
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(brandID)) {
    return {evidence: null, blockers: ["SETTLEMENT_BRAND_INVALID"]};
  }
  const jobRef = firestore.doc(`brands/${brandID}/seasonDiscoveryJobs/${item.jobID}`);
  const executionRef = jobRef.collection("executions").doc(item.executionID);
  const [jobSnapshot, executionSnapshot] = await Promise.all([
    jobRef.get(), executionRef.get(),
  ]);
  const job = jobSnapshot.data();
  const execution = executionSnapshot.data();
  const attemptCount = Number(execution?.attemptCount ?? 0);
  const attemptID = Number.isSafeInteger(attemptCount) && attemptCount > 0 ?
    String(attemptCount).padStart(5, "0") : null;
  const attemptSnapshot = attemptID ?
    await executionRef.collection("attempts").doc(attemptID).get() : null;
  const attempt = attemptSnapshot?.data();
  const continuationSnapshot = await executionRef.collection("continuations")
    .doc(target.batchID).get();
  const continuation = continuationSnapshot.data();
  if (!job || job.status !== "correctionRequired" || job.phase !== "completed" ||
      job.queueBatchID !== target.batchID ||
      job.queueExecutionID !== item.executionID) {
    blockers.push("DOMAIN_OUTCOME_NOT_TERMINAL_CORRECTION");
  }
  if (!execution || execution.status !== "recoveryRequired" ||
      execution.batchID !== target.batchID || execution.itemID !== item.itemID ||
      execution.activeRunID != null || execution.activeAttemptID != null ||
      Number(item.attemptCount) !== attemptCount || !attemptID) {
    blockers.push("QUEUE_EXECUTION_NOT_SETTLEABLE");
  }
  if (!attempt || attempt.status !== "recoveryRequired" ||
      attempt.runID !== `${target.batchID}-${target.expectedEpoch}` ||
      Number(attempt.epoch) !== target.expectedEpoch ||
      attempt.batchID !== target.batchID) {
    blockers.push("QUEUE_ATTEMPT_NOT_SETTLEABLE");
  }
  if (continuationSnapshot.exists &&
      (continuation?.status !== "recoveryRequired" ||
       continuation?.batchID !== target.batchID)) {
    blockers.push("QUEUE_CONTINUATION_NOT_SETTLEABLE");
  }
  return {
    evidence: {
      kind: "seasonDiscoveryCorrection",
      itemID: typeof item.itemID === "string" ? item.itemID : null,
      jobID: item.jobID, executionID: item.executionID,
      jobStatus: typeof job?.status === "string" ? job.status : null,
      jobPhase: typeof job?.phase === "string" ? job.phase : null,
      queueExecutionStatus: typeof execution?.status === "string" ? execution.status : null,
      attemptID, attemptStatus: typeof attempt?.status === "string" ? attempt.status : null,
      continuationStatus: typeof continuation?.status === "string" ? continuation.status : null,
    },
    blockers,
  };
}

export async function resumeQueueRecovery(input: {
  firestore: Firestore;
  evidenceProvider: RecoveryEvidenceProvider;
  target: RecoveryTarget;
  projectID: string;
  serviceName: string;
  revision: string;
  reportDigest: string;
  expectedStateRevision: number;
  decisionID: string;
  actorEmail: string;
  now?: number;
}): Promise<{accepted: true; batchID: string; decisionID: string;
  state: "queued"; alreadyApplied: boolean}> {
  const target = parseRecoveryTarget(input.target);
  if (!/^[a-f0-9]{64}$/.test(input.reportDigest) ||
      !Number.isSafeInteger(input.expectedStateRevision) || input.expectedStateRevision < 0 ||
      !isRecoveryDecisionID(input.decisionID) ||
      !/^[a-z0-9._%+-]+@[a-z0-9.-]+\.gserviceaccount\.com$/i.test(input.actorEmail)) {
    throw new Error("INVALID_RECOVERY_REQUEST");
  }
  const now = input.now ?? Date.now();
  if (!Number.isSafeInteger(now) || now < 0) throw new Error("INVALID_RECOVERY_REQUEST");
  const batchRef = input.firestore.collection(BATCH_COLLECTION).doc(target.batchID);
  const decisionRef = batchRef.collection("recoveryDecisions").doc(input.decisionID);
  const existingDecision = (await decisionRef.get()).data();
  if (existingDecision) {
    if (existingDecision.decision !== "resume" ||
        existingDecision.reportDigest !== input.reportDigest ||
        existingDecision.expectedEpoch !== target.expectedEpoch) {
      throw new Error("RECOVERY_DECISION_CONFLICT");
    }
    return {accepted: true, batchID: target.batchID,
      decisionID: input.decisionID, state: "queued", alreadyApplied: true};
  }

  const report = await inspectQueueRecovery({
    firestore: input.firestore, evidenceProvider: input.evidenceProvider,
    target, projectID: input.projectID, serviceName: input.serviceName,
    revision: input.revision,
  });
  if (!report.canResume || report.reportDigest !== input.reportDigest ||
      report.stateRevision !== input.expectedStateRevision) {
    throw new Error("RECOVERY_REPORT_STALE_OR_BLOCKED");
  }
  const freshBatch = (await batchRef.get()).data();
  if (!freshBatch) throw new Error("RECOVERY_REPORT_STALE_OR_BLOCKED");
  const scan = await findUploadingAssetWrites(
    input.firestore, freshBatch, target.expectedEpoch);
  if (!scan.complete || scan.writes.length !== report.uncertainAssetWriteCount) {
    throw new Error("RECOVERY_REPORT_STALE_OR_BLOCKED");
  }
  const queueRef = input.firestore.doc(QUEUE_PATH);
  const runRef = batchRef.collection("runs").doc(report.runID);
  const expectedRunRevision = target.revision;
  const state = await input.firestore.runTransaction(async (transaction) => {
    const existing = await transaction.get(decisionRef);
    if (existing.exists) {
      const decision = existing.data();
      if (decision?.decision !== "resume" ||
          decision?.reportDigest !== input.reportDigest ||
          decision?.expectedEpoch !== target.expectedEpoch) {
        throw new Error("RECOVERY_DECISION_CONFLICT");
      }
      return "alreadyApplied" as const;
    }
    const [queueSnapshot, batchSnapshot, runSnapshot] = await Promise.all([
      transaction.get(queueRef), transaction.get(batchRef), transaction.get(runRef),
    ]);
    const queue = queueSnapshot.data();
    const batch = batchSnapshot.data();
    const run = runSnapshot.data();
    const writeSnapshots = await Promise.all(scan.writes.map((write) =>
      transaction.get(write.ref)));
    if (!queue || !batch || !run || queue.headBatchID !== target.batchID ||
        queue.state !== "recoveryRequired" || batch.state !== "recoveryRequired" ||
        Number(queue.epoch) !== target.expectedEpoch ||
        Number(batch.epoch) !== target.expectedEpoch || batch.runID !== report.runID ||
        Number(batch.stateRevision) !== input.expectedStateRevision ||
        run.runID !== report.runID || run.revision !== expectedRunRevision) {
      throw new Error("RECOVERY_REPORT_STALE_OR_BLOCKED");
    }
    for (let index = 0; index < scan.writes.length; index++) {
      const snapshot = writeSnapshots[index];
      const write = snapshot.data();
      if (!snapshot.exists || write?.status !== "uploading" ||
          Number(write.epoch) !== target.expectedEpoch) {
        throw new Error("RECOVERY_REPORT_STALE_OR_BLOCKED");
      }
    }
    scan.writes.forEach((entry) => transaction.update(entry.ref, {
      status: "unpublished", cleanupState: "pending",
      cleanupAfter: now + QUEUE_POLICY.unreferencedFileRetentionMs,
      cleanupBlocker: "operator_recovery", recoveredAt: now, updatedAt: now,
    }));
    const stateRevision = Number(batch.stateRevision) + 1;
    transaction.create(decisionRef, {
      decisionID: input.decisionID, decision: "resume",
      projectID: target.projectID, serviceName: target.serviceName,
      revision: target.revision, servingRevision: input.revision,
      batchID: target.batchID,
      expectedEpoch: target.expectedEpoch, runID: report.runID,
      stateRevisionBefore: input.expectedStateRevision,
      stateRevisionAfter: stateRevision, reportDigest: report.reportDigest,
      actorEmail: input.actorEmail, evidence: report.evidence,
      uncertainAssetWriteCount: scan.writes.length,
      createdAt: now, expiresAt: now + QUEUE_POLICY.recoveryAuditRetentionMs,
    });
    transaction.update(batchRef, {state: "queued", stateRevision,
      owner: null, recoveryReason: null,
      dispatchGeneration: Number(batch.dispatchGeneration) + 1,
      dispatchState: "pending", recoveryResolvedAt: now, updatedAt: now});
    transaction.update(queueRef, {state: "idle", owner: null,
      recoveryResolvedAt: now, heartbeatAt: now});
    return "queued" as const;
  });
  return {accepted: true, batchID: target.batchID,
    decisionID: input.decisionID, state: "queued",
    alreadyApplied: state === "alreadyApplied"};
}

export async function settleCorrectionQueueRecovery(input: {
  firestore: Firestore;
  evidenceProvider: RecoveryEvidenceProvider;
  target: RecoveryTarget;
  projectID: string;
  serviceName: string;
  revision: string;
  reportDigest: string;
  expectedStateRevision: number;
  decisionID: string;
  actorEmail: string;
  now?: number;
}): Promise<{accepted: true; batchID: string; decisionID: string;
  state: "released"; outcome: "correctionRequired"; alreadyApplied: boolean}> {
  const target = parseRecoveryTarget(input.target);
  if (!/^[a-f0-9]{64}$/.test(input.reportDigest) ||
      !Number.isSafeInteger(input.expectedStateRevision) || input.expectedStateRevision < 0 ||
      !isRecoveryDecisionID(input.decisionID) ||
      !/^[a-z0-9._%+-]+@[a-z0-9.-]+\.iam\.gserviceaccount\.com$/i.test(input.actorEmail)) {
    throw new Error("INVALID_RECOVERY_REQUEST");
  }
  const now = input.now ?? Date.now();
  if (!Number.isSafeInteger(now) || now < 0) throw new Error("INVALID_RECOVERY_REQUEST");
  const batchRef = input.firestore.collection(BATCH_COLLECTION).doc(target.batchID);
  const decisionRef = batchRef.collection("recoveryDecisions").doc(input.decisionID);
  const existingDecision = (await decisionRef.get()).data();
  if (existingDecision) {
    if (existingDecision.decision !== "settleCorrectionRequired" ||
        existingDecision.reportDigest !== input.reportDigest ||
        existingDecision.expectedEpoch !== target.expectedEpoch) {
      throw new Error("RECOVERY_DECISION_CONFLICT");
    }
    return {accepted: true, batchID: target.batchID,
      decisionID: input.decisionID, state: "released",
      outcome: "correctionRequired", alreadyApplied: true};
  }

  const report = await inspectQueueRecovery({
    firestore: input.firestore, evidenceProvider: input.evidenceProvider,
    target, projectID: input.projectID, serviceName: input.serviceName,
    revision: input.revision,
  });
  if (!report.canSettleCorrection || report.reportDigest !== input.reportDigest ||
      report.stateRevision !== input.expectedStateRevision) {
    throw new Error("RECOVERY_REPORT_STALE_OR_BLOCKED");
  }
  const freshBatch = (await batchRef.get()).data();
  if (!freshBatch) throw new Error("RECOVERY_REPORT_STALE_OR_BLOCKED");
  const scan = await findUploadingAssetWrites(
    input.firestore, freshBatch, target.expectedEpoch);
  if (!scan.complete || scan.writes.length !== 0) {
    throw new Error("RECOVERY_REPORT_STALE_OR_BLOCKED");
  }

  const queueRef = input.firestore.doc(QUEUE_PATH);
  const runRef = batchRef.collection("runs").doc(report.runID);
  const result = await input.firestore.runTransaction(async (transaction) => {
    const priorDecision = await transaction.get(decisionRef);
    if (priorDecision.exists) {
      const decision = priorDecision.data();
      if (decision?.decision !== "settleCorrectionRequired" ||
          decision?.reportDigest !== input.reportDigest ||
          decision?.expectedEpoch !== target.expectedEpoch) {
        throw new Error("RECOVERY_DECISION_CONFLICT");
      }
      return "alreadyApplied" as const;
    }
    const [queueSnapshot, batchSnapshot, runSnapshot] = await Promise.all([
      transaction.get(queueRef), transaction.get(batchRef), transaction.get(runRef),
    ]);
    const queue = queueSnapshot.data();
    const batch = batchSnapshot.data();
    const run = runSnapshot.data();
    const items = Array.isArray(batch?.items) ?
      batch.items as Array<Record<string, unknown>> : [];
    const item = items[0];
    if (!queue || !batch || !run || batch.kind !== "discoverSeasons" ||
        items.length !== 1 || !item || item.admissionStatus !== "created" ||
        item.processingStatus !== "recoveryRequired" ||
        typeof item.jobID !== "string" || typeof item.executionID !== "string" ||
        item.activeRunID != null || queue.headBatchID !== target.batchID ||
        queue.state !== "recoveryRequired" || batch.state !== "recoveryRequired" ||
        Number(queue.epoch) !== target.expectedEpoch ||
        Number(batch.epoch) !== target.expectedEpoch || batch.runID !== report.runID ||
        queue.runID !== report.runID || Number(batch.stateRevision) !== input.expectedStateRevision ||
        run.runID !== report.runID || Number(run.epoch) !== target.expectedEpoch ||
        run.revision !== target.revision || run.state !== "recoveryRequired" ||
        run.terminalConfirmed !== true || run.inFlight !== 0) {
      throw new Error("RECOVERY_REPORT_STALE_OR_BLOCKED");
    }
    const brandID = typeof batch.brandID === "string" ? batch.brandID : "";
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(brandID)) {
      throw new Error("RECOVERY_REPORT_STALE_OR_BLOCKED");
    }
    const jobRef = input.firestore.doc(
      `brands/${brandID}/seasonDiscoveryJobs/${item.jobID}`);
    const executionRef = jobRef.collection("executions").doc(item.executionID);
    const continuationRef = executionRef.collection("continuations").doc(target.batchID);
    const jobSnapshot = await transaction.get(jobRef);
    const executionSnapshot = await transaction.get(executionRef);
    const execution = executionSnapshot.data();
    const attemptCount = Number(execution?.attemptCount ?? 0);
    const attemptID = Number.isSafeInteger(attemptCount) && attemptCount > 0 ?
      String(attemptCount).padStart(5, "0") : null;
    if (!attemptID) throw new Error("RECOVERY_REPORT_STALE_OR_BLOCKED");
    const attemptRef = executionRef.collection("attempts").doc(attemptID);
    const attemptSnapshot = await transaction.get(attemptRef);
    const continuationSnapshot = await transaction.get(continuationRef);
    const job = jobSnapshot.data();
    const attempt = attemptSnapshot.data();
    const continuation = continuationSnapshot.data();
    if (!job || job.status !== "correctionRequired" || job.phase !== "completed" ||
        job.queueBatchID !== target.batchID || job.queueExecutionID !== item.executionID ||
        !execution || execution.status !== "recoveryRequired" ||
        execution.batchID !== target.batchID || execution.itemID !== item.itemID ||
        execution.activeRunID != null || execution.activeAttemptID != null ||
        attemptCount !== Number(item.attemptCount) || !attempt ||
        attempt.status !== "recoveryRequired" || attempt.runID !== report.runID ||
        Number(attempt.epoch) !== target.expectedEpoch || attempt.batchID !== target.batchID ||
        (continuationSnapshot.exists &&
          (continuation?.status !== "recoveryRequired" ||
           continuation?.batchID !== target.batchID))) {
      throw new Error("RECOVERY_REPORT_STALE_OR_BLOCKED");
    }
    const updatedItems = items.slice();
    updatedItems[0] = {...item, processingStatus: "correctionRequired",
      activeRunID: null, retryAt: null, updatedAt: now};
    const stateRevision = Number(batch.stateRevision) + 1;
    transaction.update(executionRef, {status: "correctionRequired",
      activeRunID: null, activeAttemptID: null,
      finishedAt: execution.finishedAt ?? now, recoveryResolvedAt: now, updatedAt: now});
    transaction.update(attemptRef, {status: "correctionRequired",
      endedAt: attempt.endedAt ?? now, recoveryResolvedAt: now, updatedAt: now});
    if (continuationSnapshot.exists) {
      transaction.update(continuationRef, {status: "correctionRequired",
        finishedAt: continuation?.finishedAt ?? now,
        recoveryResolvedAt: now, updatedAt: now});
    }
    transaction.create(decisionRef, {
      decisionID: input.decisionID, decision: "settleCorrectionRequired",
      projectID: target.projectID, serviceName: target.serviceName,
      revision: target.revision, servingRevision: input.revision,
      batchID: target.batchID, expectedEpoch: target.expectedEpoch,
      runID: report.runID, stateRevisionBefore: input.expectedStateRevision,
      stateRevisionAfter: stateRevision, reportDigest: report.reportDigest,
      actorEmail: input.actorEmail, evidence: report.evidence,
      correctionEvidence: report.correctionEvidence,
      uncertainAssetWriteCount: 0, createdAt: now,
      expiresAt: now + QUEUE_POLICY.recoveryAuditRetentionMs,
    });
    transaction.update(batchRef, {items: updatedItems, state: "released",
      owner: null, stateRevision, releasedAt: now,
      detailCleanupAfter: now + QUEUE_POLICY.resolvedFailureRetentionMs,
      receiptExpiresAt: now + QUEUE_POLICY.receiptRetentionMs,
      retentionNextAt: now + QUEUE_POLICY.resolvedFailureRetentionMs,
      recoveryResolvedAt: now, recoveryOutcome: "correctionRequired",
      recoveryReason: null, updatedAt: now});
    transaction.update(queueRef, {state: "idle", owner: null,
      recoveryResolvedAt: now, heartbeatAt: now});
    return "released" as const;
  });
  return {accepted: true, batchID: target.batchID,
    decisionID: input.decisionID, state: "released",
    outcome: "correctionRequired",
    alreadyApplied: result === "alreadyApplied"};
}

async function findUploadingAssetWrites(
  firestore: Firestore, batch: FirebaseFirestore.DocumentData, epoch: number,
): Promise<{writes: AssetWrite[]; complete: boolean}> {
  if (batch.kind === "discoverSeasons") return {writes: [], complete: true};
  if (!Array.isArray(batch.items) || batch.items.length > QUEUE_POLICY.maxSelectedSeasons) {
    return {writes: [], complete: false};
  }
  const writes: AssetWrite[] = [];
  const startedAt = Date.now();
  for (const item of batch.items as Array<Record<string, unknown>>) {
    if (item.admissionStatus !== "created" || typeof item.jobID !== "string" ||
        typeof item.executionID !== "string") continue;
    if (Date.now() - startedAt > QUEUE_POLICY.cleanupAdmissionMs) {
      return {writes, complete: false};
    }
    const prefix = `brands/${String(batch.brandID)}/importJobs/${item.jobID}` +
      `/executions/${item.executionID}/assets/`;
    const remaining = MAX_ASSET_WRITES - writes.length;
    const writePage = await firestore.collectionGroup("writes")
      .where("executionID", "==", item.executionID)
      .where("epoch", "==", epoch)
      .where("status", "==", "uploading")
      .limit(remaining + 1).get();
    if (writePage.size > remaining || Date.now() - startedAt > QUEUE_POLICY.cleanupAdmissionMs) {
      return {writes, complete: false};
    }
    writePage.docs.forEach((write) => {
      if (write.ref.path.startsWith(prefix)) {
        writes.push({ref: write.ref, data: write.data()});
      }
    });
  }
  return {writes, complete: true};
}

function stableDigest(value: unknown): string {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

export function newRecoveryDecisionID(): string {
  return randomUUID();
}
