/* eslint-disable max-len, require-jsdoc */
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {getStorage} from "firebase-admin/storage";
import {db, defaultStorageBucket} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {
  dueCleanupJobIDs,
  processMessageCleanupJob,
  processRoomCleanupJob,
} from "./moderationCleanup.js";

function cleanupBuckets() {
  const defaultBucket = defaultStorageBucket();
  const readyBucketName = process.env.CHAT_MEDIA_READY_BUCKET?.trim();
  const readyBucket = readyBucketName ? getStorage().bucket(readyBucketName) : null;
  return {
    defaultBucket,
    bucket: (name: string) => {
      if (!readyBucket || name !== readyBucketName) {
        throw new Error("unsupported_chat_media_bucket");
      }
      return readyBucket;
    },
    roomBuckets: readyBucket ? [defaultBucket, readyBucket] : [defaultBucket],
  };
}

export const onChatMessageCleanupQueued = onDocumentCreated(
  {document: "chatMessageCleanupJobs/{jobID}", region: FUNCTIONS_REGION},
  async (event) => {
    await processMessageCleanupJob(event.params.jobID, db, cleanupBuckets());
  },
);

export const onModerationRoomCleanupQueued = onDocumentCreated(
  {document: "moderationRoomCleanupJobs/{roomID}", region: FUNCTIONS_REGION},
  async (event) => {
    await processRoomCleanupJob(event.params.roomID, db, cleanupBuckets());
  },
);

export const drainChatModerationCleanupJobs = onSchedule(
  {
    schedule: "every 5 minutes",
    region: FUNCTIONS_REGION,
    timeZone: "Asia/Seoul",
  },
  async () => {
    const buckets = cleanupBuckets();
    const [messageIDs, roomIDs] = await Promise.all([
      dueCleanupJobIDs(db, "chatMessageCleanupJobs", "message"),
      dueCleanupJobIDs(db, "moderationRoomCleanupJobs", "room"),
    ]);
    for (const jobID of messageIDs) {
      await processMessageCleanupJob(jobID, db, buckets);
    }
    for (const roomID of roomIDs) {
      await processRoomCleanupJob(roomID, db, buckets);
    }
  },
);
