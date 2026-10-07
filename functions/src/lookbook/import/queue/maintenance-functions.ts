/* eslint-disable require-jsdoc */
import {CloudTasksClient} from "@google-cloud/tasks";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {db} from "../../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../../core/runtime.js";
import {lookbookImportTaskConfig} from "../functions.js";
import {prepareNextQueueBatch} from "./preparation-runner.js";
import {advanceReleasedQueueHead} from "./advance.js";
import {batchTaskSender} from "../taskService.js";
import {
  deliverQueueHead, reopenStaleQueueDispatch,
} from "./dispatch.js";

let cloudTasksClient: CloudTasksClient | null = null;

export async function deliverHeadIfReady(now = Date.now()): Promise<boolean> {
  const config = lookbookImportTaskConfig();
  cloudTasksClient ??= new CloudTasksClient();
  return deliverQueueHead(db, batchTaskSender(cloudTasksClient, {
    projectID: config.projectID, locationID: config.locationID,
    queueID: config.queueID, workerURL: config.workerURL,
    serviceAccountEmail: config.serviceAccountEmail,
    audience: config.audience,
  }), now);
}

export const onLookbookQueueHeadChanged = onDocumentWritten(
  {region: FUNCTIONS_REGION, document: "lookbookImportQueue/main",
    retry: true, timeoutSeconds: 120, memory: "256MiB", maxInstances: 1},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after || before?.headBatchID === after.headBatchID) return;
    await deliverHeadIfReady();
  }
);

export const onLookbookQueueBatchReady = onDocumentWritten(
  {region: FUNCTIONS_REGION, document: "lookbookImportBatches/{batchID}",
    retry: true, timeoutSeconds: 120, memory: "256MiB", maxInstances: 1},
  async (event) => {
    const batch = event.data?.after.data();
    if (batch?.state === "released") {
      await advanceReleasedQueueHead(db);
      return;
    }
    if (batch?.state === "queued" && batch.dispatchState === "pending") {
      await deliverHeadIfReady();
    }
  }
);

/**
 * 이벤트 전달 누락을 회수한다. 준비 owner나 실행 종료를 경과 시간만으로
 * 빼앗지 않고, 전달 전 head와 미선점 batch만 다시 시도한다.
 */
export const reconcileLookbookQueueDelivery = onSchedule(
  {schedule: "every 5 minutes", timeZone: "Asia/Seoul",
    region: FUNCTIONS_REGION, timeoutSeconds: 120, memory: "256MiB",
    maxInstances: 1},
  async () => {
    const now = Date.now();
    const prepared = await prepareNextQueueBatch(db);
    const advanced = await advanceReleasedQueueHead(db);
    const reopened = await reopenStaleQueueDispatch(db, now);
    const delivered = await deliverHeadIfReady(now);
    console.info("[lookbook-queue-reconcile] finished", {
      prepared: prepared !== null, advanced, reopened, delivered,
    });
  }
);
