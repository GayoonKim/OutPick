/* eslint-disable require-jsdoc, max-len */
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {getFunctions} from "firebase-admin/functions";
import {createHash} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";
import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {
  dueRoomOwnershipSuccessionJobIDs,
  processRoomOwnershipSuccessionJob,
} from "./roomMembershipSweep.js";

type SuccessionTaskPayload = {jobID: string};

const TASK_FUNCTION_NAME = "runRoomOwnershipSuccessionTask";

function validJobID(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && !value.includes("/");
}

function taskID(jobID: string, attempt: number, scheduledAtMillis: number): string {
  return createHash("sha256")
    .update(`${jobID}:${attempt}:${scheduledAtMillis}`)
    .digest("hex");
}

async function enqueueNextAttemptIfNeeded(jobID: string): Promise<void> {
  const job = await db.collection("roomOwnershipSuccessionJobs").doc(jobID).get();
  const nextAttemptAt = job.get("nextAttemptAt");
  if (!job.exists || job.get("status") !== "retryPending" || !(nextAttemptAt instanceof Timestamp)) return;
  const attempt = Number(job.get("attempt"));
  const scheduledAtMillis = nextAttemptAt.toMillis();
  const queue = getFunctions().taskQueue<SuccessionTaskPayload>(
    `locations/${FUNCTIONS_REGION}/functions/${TASK_FUNCTION_NAME}`,
  );
  try {
    await queue.enqueue(
      {jobID},
      {
        scheduleTime: nextAttemptAt.toDate(),
        dispatchDeadlineSeconds: 60,
        id: taskID(jobID, Number.isSafeInteger(attempt) ? attempt : 0, scheduledAtMillis),
      },
    );
  } catch (error) {
    if ((error as {code?: unknown})?.code === "functions/task-already-exists") return;
    throw error;
  }
}

export async function processRoomOwnershipSuccessionAndSchedule(jobID: string): Promise<void> {
  await processRoomOwnershipSuccessionJob(jobID, db);
  await enqueueNextAttemptIfNeeded(jobID);
}

export const onRoomOwnershipSuccessionQueued = onDocumentCreated(
  {
    document: "roomOwnershipSuccessionJobs/{jobID}",
    region: FUNCTIONS_REGION,
    retry: true,
  },
  async (event) => {
    await processRoomOwnershipSuccessionAndSchedule(event.params.jobID);
  },
);

export const runRoomOwnershipSuccessionTask = onTaskDispatched<SuccessionTaskPayload>(
  {
    region: FUNCTIONS_REGION,
    retryConfig: {
      maxAttempts: 2,
      maxRetrySeconds: 10,
      minBackoffSeconds: 1,
      maxBackoffSeconds: 5,
      maxDoublings: 0,
    },
    rateLimits: {maxConcurrentDispatches: 10, maxDispatchesPerSecond: 20},
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!validJobID(request.data?.jobID)) throw new Error("invalid_room_succession_task");
    await processRoomOwnershipSuccessionAndSchedule(request.data.jobID);
  },
);

export const drainRoomOwnershipSuccessionJobs = onSchedule(
  {
    schedule: "every 5 minutes",
    region: FUNCTIONS_REGION,
    timeZone: "Asia/Seoul",
  },
  async () => {
    const jobIDs = await dueRoomOwnershipSuccessionJobIDs(db);
    for (const jobID of jobIDs) {
      await processRoomOwnershipSuccessionAndSchedule(jobID);
    }
  },
);
