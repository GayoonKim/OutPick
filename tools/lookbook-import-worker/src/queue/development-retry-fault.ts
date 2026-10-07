/* eslint-disable require-jsdoc, max-len */
import type {Firestore} from "firebase-admin/firestore";
import {readOwnedBatch, type BatchOwnership} from "./coordinator.js";
import {RetryableImportError} from "../import-error.js";

export type RetryFaultContext = {
  ownership: BatchOwnership; brandID: string; jobID: string;
  executionID: string; ordinal: number; attempt: number;
};
export type RetryFaultUpload = {path: string; generation: string; size: number};
export type DevelopmentRetryFault = {
  beforeDownload(context: RetryFaultContext): Promise<void>;
  afterUpload(context: RetryFaultContext, object: RetryFaultUpload): Promise<void>;
};

export function retryFaultCampaign(env: NodeJS.ProcessEnv): string | null {
  const value = env.OUTPICK_Q7_RETRY_FAULT_CAMPAIGN;
  if (!value) return null;
  if (env.OUTPICK_FIREBASE_PROJECT_ID !== "outpick-test" ||
      env.K_SERVICE !== "lookbook-import-worker-development" ||
      !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(value) ||
      !String(env.K_REVISION).startsWith("lookbook-import-worker-development-") ||
      !/^[a-f0-9]{64}$/.test(env.OUTPICK_WORKER_VERIFICATION_DIGEST ?? "")) {
    throw new Error("Q7_RETRY_FAULT_ENVIRONMENT_INVALID");
  }
  return value;
}

export function forceQ7OOM(): never {
  const blocks: Buffer[] = [];
  // 승인된 2GiB 컨테이너가 실제 종료되도록 유한한 메모리 압박을 준다.
  for (let index = 0; index < 512; index++) {
    const block = Buffer.allocUnsafe(8 * 1024 * 1024);
    block.fill(0xa5);
    blocks.push(block);
  }
  throw new Error(`Q7_OOM_NOT_OBSERVED:${blocks.length}`);
}

export function createDevelopmentRetryFault(input: {
  firestore: Firestore; campaignID: string; revision: string;
  verificationDigest: string; projectID: string; serviceName: string;
  now?: () => number; oom?: () => never;
}): DevelopmentRetryFault {
  retryFaultCampaign({OUTPICK_Q7_RETRY_FAULT_CAMPAIGN: input.campaignID,
    OUTPICK_FIREBASE_PROJECT_ID: input.projectID, K_SERVICE: input.serviceName,
    K_REVISION: input.revision, OUTPICK_WORKER_VERIFICATION_DIGEST: input.verificationDigest});
  const db = input.firestore;
  const clock = input.now ?? Date.now;
  const root = db.doc(`lookbookImportQ7FaultCampaigns/${input.campaignID}`);
  async function consume(context: RetryFaultContext, stage: string,
    object?: RetryFaultUpload): Promise<boolean> {
    return db.runTransaction(async (tx) => {
      const batch = await readOwnedBatch(db, tx, context.ownership);
      const item = (batch.items as Array<Record<string, unknown>>)[context.ordinal];
      const [campaignSnapshot, targetSnapshot, executionSnapshot] = await Promise.all([
        tx.get(root), tx.get(root.collection("targets").doc(context.executionID)),
        tx.get(db.doc(`brands/${context.brandID}/importJobs/${context.jobID}/executions/${context.executionID}`)),
      ]);
      const campaign = campaignSnapshot.data(); const target = targetSnapshot.data();
      if (!target) return false;
      const now = clock();
      const execution = executionSnapshot.data();
      if (!campaign || campaign.projectID !== "outpick-test" || campaign.state !== "running" ||
          campaign.mode !== "q7RetryKL" || campaign.maxMutations !== 8 ||
          campaign.revision !== input.revision || campaign.verificationDigest !== input.verificationDigest ||
          !Number.isSafeInteger(campaign.startedAt) || !Number.isSafeInteger(campaign.expiresAt) ||
          campaign.startedAt > now || campaign.expiresAt <= now ||
          campaign.expiresAt - campaign.startedAt > 1200000 ||
          batch.brandID !== context.brandID || !item || item.jobID !== context.jobID ||
          item.executionID !== context.executionID || item.processingStatus !== "active" ||
          execution?.activeRunID !== context.ownership.runID || execution?.attemptCount !== context.attempt ||
          target.brandID !== context.brandID || target.jobID !== context.jobID ||
          target.executionID !== context.executionID ||
          target.ordinal !== context.ordinal || target.campaignID !== input.campaignID) {
        throw new Error("Q7_RETRY_FAULT_TARGET_CHANGED");
      }
      // 같은 execution의 새 검토 승인은 다른 batch이므로 장치를 적용하지 않는다.
      if (target.batchID !== context.ownership.batchID) return false;
      const consumed = target.consumedAttempts && typeof target.consumedAttempts === "object" ?
        target.consumedAttempts as Record<string, unknown> : {};
      const key = String(context.attempt);
      if (stage === "beforeDownload") {
        if (target.scenario !== "retryableBeforeDownload") return false;
        if (context.attempt < 1 || context.attempt > 5 || target.attemptLimit !== 5 || consumed[key]) return false;
      } else {
        if (target.scenario !== "oomAfterUpload") return false;
        if (target.consumedAt != null || context.attempt !== target.attempt) return false;
        const prefix = `brands/${context.brandID}/seasons/import_${context.jobID}/imports/${context.executionID}/${context.ownership.epoch}/`;
        if (!object || !object.path.startsWith(prefix) || !/^\d+$/.test(object.generation) ||
            !Number.isSafeInteger(object.size) || object.size < 0) throw new Error("Q7_RETRY_FAULT_OBJECT_INVALID");
      }
      tx.update(targetSnapshot.ref, {consumedAt: now,
        consumedAttempts: {...consumed, [key]: {stage, runID: context.ownership.runID,
          epoch: context.ownership.epoch, at: now}},
        ...(object ? {consumedObject: object} : {}), updatedAt: now});
      return true;
    });
  }
  return {
    async beforeDownload(context) {
      if (await consume(context, "beforeDownload")) throw new RetryableImportError("Q7_CONTROLLED_RETRYABLE_FAILURE");
    },
    async afterUpload(context, object) {
      if (await consume(context, "afterUpload", object)) {
        (input.oom ?? forceQ7OOM)();
      }
    },
  };
}
