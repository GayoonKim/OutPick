/* eslint-disable max-len */
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {db, defaultStorageBucket} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {
  dueCleanupJobIDs,
  processMessageCleanupJob,
  processRoomCleanupJob,
} from "./moderationCleanup.js";

export const onChatMessageCleanupQueued = onDocumentCreated(
  {document: "chatMessageCleanupJobs/{jobID}", region: FUNCTIONS_REGION},
  async (event) => {
    await processMessageCleanupJob(event.params.jobID, db, defaultStorageBucket());
  },
);

export const onModerationRoomCleanupQueued = onDocumentCreated(
  {document: "moderationRoomCleanupJobs/{roomID}", region: FUNCTIONS_REGION},
  async (event) => {
    await processRoomCleanupJob(event.params.roomID, db, defaultStorageBucket());
  },
);

export const drainChatModerationCleanupJobs = onSchedule(
  {
    schedule: "every 5 minutes",
    region: FUNCTIONS_REGION,
    timeZone: "Asia/Seoul",
  },
  async () => {
    const bucket = defaultStorageBucket();
    const [messageIDs, roomIDs] = await Promise.all([
      dueCleanupJobIDs(db, "chatMessageCleanupJobs", "message"),
      dueCleanupJobIDs(db, "moderationRoomCleanupJobs", "room"),
    ]);
    for (const jobID of messageIDs) {
      await processMessageCleanupJob(jobID, db, bucket);
    }
    for (const roomID of roomIDs) {
      await processRoomCleanupJob(roomID, db, bucket);
    }
  },
);
