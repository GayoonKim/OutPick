/* eslint-disable require-jsdoc, max-len */
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {
  dueMessageEvidenceCleanupJobIDs,
  processMessageEvidenceCleanupJob,
} from "./evidenceCleanup.js";
import {
  dueMessageEvidenceCopyJobIDs,
  processMessageEvidenceCopyJob,
} from "./evidenceCopy.js";
import {firebaseMessageEvidenceStorage} from "./evidenceStorage.js";
import {messageEvidenceRuntimeForEnvironment} from "./evidenceRuntime.js";

function requiredEnvironment(name: "CHAT_MEDIA_READY_BUCKET" | "MODERATION_EVIDENCE_BUCKET"): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name.toLowerCase()}_missing`);
  return value;
}

function configuredMaxInstances(): number {
  return messageEvidenceRuntimeForEnvironment().maxInstances;
}

const runtime = messageEvidenceRuntimeForEnvironment();

async function processCopy(jobID: string): Promise<void> {
  const succeeded = await processMessageEvidenceCopyJob({
    jobID,
    firestore: db,
    storage: firebaseMessageEvidenceStorage(),
    readyBucket: requiredEnvironment("CHAT_MEDIA_READY_BUCKET"),
    evidenceBucket: requiredEnvironment("MODERATION_EVIDENCE_BUCKET"),
  });
  if (!succeeded) console.warn("[message-evidence-copy] job deferred", {jobID});
}

async function processCleanup(jobID: string): Promise<void> {
  const succeeded = await processMessageEvidenceCleanupJob({
    jobID,
    firestore: db,
    storage: firebaseMessageEvidenceStorage(),
    evidenceBucket: requiredEnvironment("MODERATION_EVIDENCE_BUCKET"),
  });
  if (!succeeded) console.warn("[message-evidence-cleanup] job deferred", {jobID});
}

export const onMessageEvidenceCopyQueued = onDocumentCreated(
  {
    document: "moderationEvidenceCopyJobs/{jobID}",
    region: FUNCTIONS_REGION,
    timeoutSeconds: 540,
    memory: "512MiB",
    maxInstances: configuredMaxInstances(),
    serviceAccount: runtime.serviceAccountEmail,
  },
  async (event) => processCopy(event.params.jobID),
);

export const onMessageEvidenceCleanupQueued = onDocumentCreated(
  {
    document: "moderationEvidenceCleanupJobs/{jobID}",
    region: FUNCTIONS_REGION,
    timeoutSeconds: 540,
    memory: "512MiB",
    maxInstances: configuredMaxInstances(),
    serviceAccount: runtime.serviceAccountEmail,
  },
  async (event) => processCleanup(event.params.jobID),
);

export const drainMessageEvidenceJobs = onSchedule(
  {
    schedule: "every 5 minutes",
    region: FUNCTIONS_REGION,
    timeZone: "Asia/Seoul",
    timeoutSeconds: 540,
    memory: "512MiB",
    maxInstances: 1,
    serviceAccount: runtime.serviceAccountEmail,
  },
  async () => {
    const [copyJobIDs, cleanupJobIDs] = await Promise.all([
      dueMessageEvidenceCopyJobIDs(db),
      dueMessageEvidenceCleanupJobIDs(db),
    ]);
    for (const jobID of copyJobIDs) await processCopy(jobID);
    for (const jobID of cleanupJobIDs) await processCleanup(jobID);
  },
);
