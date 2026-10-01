/* eslint-disable require-jsdoc, max-len */
import {onSchedule} from "firebase-functions/v2/scheduler";
import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {chatMediaServiceAccountEmailForEnvironment} from "./runtime.js";
import {
  CHAT_MEDIA_EXPIRY_FUNCTION_TIMEOUT_SECONDS,
  CHAT_MEDIA_EXPIRY_START_BUDGET_MILLIS,
} from "./retentionContracts.js";
import {drainDueChatMediaExpiryJobs} from "./retentionService.js";
import {firebaseChatMediaRetentionStorage} from "./retentionStorage.js";

function requiredReadyBucket(): string {
  const value = process.env.CHAT_MEDIA_READY_BUCKET?.trim();
  if (!value) throw new Error("chat_media_ready_bucket_missing");
  return value;
}

export const cleanupExpiredChatMedia = onSchedule(
  {
    schedule: "0 * * * *",
    region: FUNCTIONS_REGION,
    timeZone: "Asia/Seoul",
    timeoutSeconds: CHAT_MEDIA_EXPIRY_FUNCTION_TIMEOUT_SECONDS,
    memory: "512MiB",
    maxInstances: 1,
    serviceAccount: chatMediaServiceAccountEmailForEnvironment(process.env, "cleanup"),
  },
  async () => {
    const startedAt = Date.now();
    const deadline = startedAt + CHAT_MEDIA_EXPIRY_START_BUDGET_MILLIS;
    const result = await drainDueChatMediaExpiryJobs({
      firestore: db,
      storage: firebaseChatMediaRetentionStorage(),
      readyBucket: requiredReadyBucket(),
      clock: () => new Date(),
      startDeadlineMillis: deadline,
    });
    if (result.candidateCount > 0) {
      console.info("[chat-media-retention] run complete", {
        candidateCount: result.candidateCount,
        resultCounts: result.resultCounts,
        elapsedMillis: Date.now() - startedAt,
      });
    }
  },
);
