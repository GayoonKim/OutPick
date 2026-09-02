/* eslint-disable require-jsdoc, max-len */
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {getFunctions} from "firebase-admin/functions";
import {createHash} from "node:crypto";
import {DocumentReference, FieldPath, QueryDocumentSnapshot, Timestamp} from "firebase-admin/firestore";
import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {
  dueRoomOwnershipSuccessionJobIDs,
  processRoomOwnershipSuccessionJob,
  processRoomSuccessionAttempt,
  settleExpiredRoomSuccession,
} from "./roomSuccessionJobs.js";

type SuccessionTaskPayload = {jobID: string; roomID?: string; generation?: number; expireOnly?: boolean};

const TASK_FUNCTION_NAME = "runRoomOwnershipSuccessionTask";

function validJobID(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && !value.includes("/");
}

function taskID(payload: SuccessionTaskPayload, attempt: number, scheduledAtMillis: number): string {
  return createHash("sha256")
    .update(`${JSON.stringify(payload)}:${attempt}:${scheduledAtMillis}`)
    .digest("hex");
}

async function enqueue(payload: SuccessionTaskPayload, attempt: number, at: Timestamp): Promise<void> {
  const queue = getFunctions().taskQueue<SuccessionTaskPayload>(
    `locations/${FUNCTIONS_REGION}/functions/${TASK_FUNCTION_NAME}`,
  );
  try {
    await queue.enqueue(
      payload,
      {
        scheduleTime: at.toDate(),
        dispatchDeadlineSeconds: 60,
        id: taskID(payload, Number.isSafeInteger(attempt) ? attempt : 0, at.toMillis()),
      },
    );
  } catch (error) {
    if ((error as {code?: unknown})?.code === "functions/task-already-exists") return;
    throw error;
  }
}

async function enqueueNextAttemptIfNeeded(jobID: string): Promise<void> {
  const ref = db.collection("roomOwnershipSuccessionJobs").doc(jobID);
  const job = await ref.get();
  if (!job.exists || !["pending", "retryPending", "processing", "failed"].includes(job.get("status"))) return;
  if (job.get("status") === "failed" && !(Number(job.get("pendingRoomCount")) > 0)) return;
  // 방별 만료 정리도 예약한다. 실제 DB 장애 중에는 watchdog이 복구 후 실패 기록만 확정한다.
  for await (const room of activeRoomPages(ref)) {
    const deadline = room.get("deadlineAt");
    if (!(deadline instanceof Timestamp) || deadline.toMillis() <= Date.now()) {
      await settleExpiredRoomSuccession(jobID, room.id);
      continue;
    }
    const payload = {jobID, roomID: room.id, generation: Number(room.get("generation"))};
    await enqueue({...payload, expireOnly: true}, 0, deadline);
    const next = room.get("nextAttemptAt");
    if (room.get("status") !== "processing" && next instanceof Timestamp && next.toMillis() < deadline.toMillis()) {
      await enqueue(payload, Number(room.get("attempt")), next);
    }
  }
  // 방 처리로 counter/nextAttemptAt이 바뀔 수 있으므로 부모 예약은 최신 상태를 사용한다.
  const current = await ref.get();
  const next = current.get("nextAttemptAt");
  if ((current.get("status") === "retryPending" || current.get("status") === "failed") && next instanceof Timestamp) {
    await enqueue({jobID}, Number(current.get("attempt")), next);
  }
}

async function* activeRoomPages(ref: DocumentReference): AsyncGenerator<QueryDocumentSnapshot> {
  let cursor: QueryDocumentSnapshot | undefined;
  while (true) {
    let query = ref.collection("roomSuccessionAttempts").where("status", "in", ["pending", "retryPending", "processing"])
      .orderBy(FieldPath.documentId()).limit(25);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    for (const room of page.docs) yield room;
    if (page.size < 25) return;
    cursor = page.docs[page.size - 1];
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
    retry: false,
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
    if (request.data.roomID !== undefined) {
      if (!validJobID(request.data.roomID) || !Number.isSafeInteger(request.data.generation) || Number(request.data.generation) < 1) throw new Error("invalid_room_succession_task");
      if (request.data.expireOnly) {
        // 오래된 만료 task가 수동 재처리로 열린 새 세대에 영향을 주지 않도록 현재 기한만 확인한다.
        await settleExpiredRoomSuccession(request.data.jobID, request.data.roomID);
      } else {
        await processRoomSuccessionAttempt(request.data.jobID, request.data.roomID, Number(request.data.generation));
      }
      await enqueueNextAttemptIfNeeded(request.data.jobID);
      return;
    }
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
      try {
        await processRoomOwnershipSuccessionAndSchedule(jobID);
      } catch (error) {
        console.error("[roomSuccession] watchdog failure", {jobID, code: (error as {code?: unknown})?.code ?? "unknown"});
      }
    }
  },
);
