/* eslint-disable require-jsdoc, max-len */
import * as admin from "firebase-admin";
import {CloudTasksClient} from "@google-cloud/tasks";
import {FieldValue} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  recordData,
  requiredAuthUID,
  requiredDocumentID,
  requiredString,
} from "../../core/callable.js";
import {isAlreadyExistsError} from "../../core/errors.js";
import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {hasActivePlatformAdminData} from "../../shared/platformAuthorization.js";
import {
  SEASON_DISCOVERY_CONTRACT_REVISION,
} from "../../shared/seasonDiscoveryCreation.js";
import {
  canRecordSeasonDiscoveryDispatch,
  deterministicSeasonDiscoveryTaskID,
  isActiveSeasonDiscoveryStatus,
  isSeasonAvailableForDiscoveryReview,
  seasonDiscoveryExpiresAt,
  type SeasonDiscoveryStatus,
} from "./seasonDiscoveryContract.js";
import {isBatchQueueJob} from "./queue/authorization.js";
import {admitDiscoveryRequest} from "./queue/discovery-admission.js";
import {seasonAdmissionError} from "./queue/season-admission.js";

const LOCATION = "asia-northeast3";
const DEFAULT_QUEUE = "lookbook-discovery-jobs";
const ENDPOINT = "/tasks/discover-seasons";
const MAX_ATTEMPTS = 3;
const STALE_MILLIS = 15 * 60 * 1000;


let client: CloudTasksClient | null = null;

export const requestSeasonDiscovery = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    try {
      return await admitDiscoveryRequest(db, uid, recordData(request.data), "request");
    } catch (error) {
      return seasonAdmissionError(error);
    }
  }
);

export const cancelSeasonDiscovery = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(requiredString(data, "brandID", 128), "brandID");
    const jobID = requiredDocumentID(requiredString(data, "jobID", 128), "jobID");
    const brandRef = db.collection("brands").doc(brandID);
    const jobRef = brandRef
      .collection("seasonDiscoveryJobs").doc(jobID);
    await db.runTransaction(async (transaction) => {
      const [brandSnap, snap, platformAdmin] = await Promise.all([
        transaction.get(brandRef), transaction.get(jobRef),
        transaction.get(db.collection("platformAdmins").doc(uid)),
      ]);
      if (!hasActivePlatformAdminData(platformAdmin.data())) {
        throw new HttpsError("permission-denied", "플랫폼 관리자 권한이 필요합니다.");
      }
      if (!brandSnap.exists) throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      if (!snap.exists) throw new HttpsError("not-found", "탐색 작업을 찾을 수 없습니다.");
      const status = snap.data()?.status as SeasonDiscoveryStatus;
      if (status === "running") {
        transaction.update(jobRef, {
          cancelRequestedAt: FieldValue.serverTimestamp(),
          recommendedAction: "cancel",
          updatedAt: FieldValue.serverTimestamp(),
        });
      } else if (!isTerminal(status)) {
        terminalize(transaction, jobRef, "cancelled", "cancelled_by_admin", null);
        if (brandSnap.data()?.activeSeasonDiscoveryJobID === jobID) {
          transaction.update(brandRef, {
            activeSeasonDiscoveryJobID: null,
            discoveryStatus: "cancelled",
            lastDiscoveryCompletedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
      }
    });
    return {brandID, jobID, accepted: true};
  }
);

export const retrySeasonDiscovery = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    try {
      return await admitDiscoveryRequest(db, uid, recordData(request.data), "retry");
    } catch (error) {
      return seasonAdmissionError(error);
    }
  }
);

export const resolveSeasonDiscoveryCandidate = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(requiredString(data, "brandID", 128), "brandID");
    const jobID = requiredDocumentID(requiredString(data, "jobID", 128), "jobID");
    const candidateID = requiredDocumentID(requiredString(data, "candidateID", 128), "candidateID");
    const generation = integerInput(data.generation, "generation");
    const snapshotHash = requiredString(data, "candidateSnapshotHash", 128);
    const decision = reviewDecision(data.decision);
    const targetSeasonID = decision === "connectExistingSeason" ?
      requiredDocumentID(requiredString(data, "targetSeasonID", 128), "targetSeasonID") : null;
    const brandRef = db.collection("brands").doc(brandID);
    const jobRef = brandRef.collection("seasonDiscoveryJobs").doc(jobID);
    const candidateRef = jobRef.collection("candidates").doc(candidateID);
    const reviewRef = jobRef.collection("reviews").doc();
    const outcome = await db.runTransaction(async (transaction) => {
      const [brandSnap, jobSnap, candidateSnap, candidatesSnap, platformAdmin] = await Promise.all([
        transaction.get(brandRef),
        transaction.get(jobRef),
        transaction.get(candidateRef),
        transaction.get(jobRef.collection("candidates")),
        transaction.get(db.collection("platformAdmins").doc(uid)),
      ]);
      if (!hasActivePlatformAdminData(platformAdmin.data())) {
        throw new HttpsError("permission-denied", "플랫폼 관리자 권한이 필요합니다.");
      }
      const brand = brandSnap.data();
      const job = jobSnap.data();
      const candidate = candidateSnap.data();
      if (!brandSnap.exists || !jobSnap.exists || !candidateSnap.exists ||
          brand?.publishedSeasonDiscoveryJobID !== jobID ||
          job?.generation !== generation || candidate?.generation !== generation ||
          job?.candidateSnapshotHash !== snapshotHash || candidate?.snapshotHash !== snapshotHash) {
        throw new HttpsError("failed-precondition", "stale discovery snapshot입니다.");
      }
      if (!String(candidate?.resolution ?? "").startsWith("awaitingReview")) {
        const previousTargetSeasonID = typeof candidate?.matchedSeasonID === "string" ?
          candidate.matchedSeasonID : null;
        if (candidate?.reviewDecision === decision &&
            previousTargetSeasonID === targetSeasonID) {
          return {
            resolution: String(candidate.resolution),
            allReviewsCompleted: job?.status === "succeeded",
            duplicate: true,
          };
        }
        throw new HttpsError("failed-precondition", "검토 대기 후보가 아닙니다.");
      }
      let targetSeasonRef: FirebaseFirestore.DocumentReference | null = null;
      let targetSeasonSnap: FirebaseFirestore.DocumentSnapshot | null = null;
      if (targetSeasonID) {
        targetSeasonRef = brandRef.collection("seasons").doc(targetSeasonID);
        targetSeasonSnap = await transaction.get(targetSeasonRef);
        if (!targetSeasonSnap.exists ||
            !isSeasonAvailableForDiscoveryReview(targetSeasonSnap.data())) {
          throw new HttpsError("failed-precondition", "연결할 시즌이 유효하지 않습니다.");
        }
      }
      const resolution = decision === "keepAsNew" ? "newSeason" :
        decision === "reject" ? "rejected" : "matchedByAdminReview";
      transaction.update(candidateRef, {
        resolution,
        reviewDecision: decision,
        matchedSeasonID: targetSeasonID,
        reviewedBy: uid,
        reviewedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (targetSeasonRef && candidate && typeof candidate.seasonURL === "string") {
        transaction.update(targetSeasonRef, {
          sourceURL: candidate.seasonURL,
          sourceURLMatchMethod: "adminReview",
          sourceURLUpdatedAt: FieldValue.serverTimestamp(),
          sourceDiscoveryJobID: jobID,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      transaction.set(reviewRef, {
        brandID, jobID, candidateID, generation, snapshotHash,
        previousResolution: candidate?.resolution,
        decision, targetSeasonID, reviewerUID: uid,
        completedAt: FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromMillis(
          Date.now() + 60 * 24 * 60 * 60 * 1000
        ),
      });
      const unresolvedOthers = candidatesSnap.docs.filter((doc) =>
        doc.id !== candidateID &&
        String(doc.data().resolution ?? "").startsWith("awaitingReview")
      );
      if (unresolvedOthers.length === 0 && job?.status === "awaitingReview") {
        const expiresAt = admin.firestore.Timestamp.fromMillis(
          Date.now() + 30 * 24 * 60 * 60 * 1000
        );
        transaction.update(jobRef, {
          status: "succeeded", recommendedAction: "none", expiresAt,
          updatedAt: FieldValue.serverTimestamp(),
        });
        transaction.update(brandRef, {
          discoveryStatus: "succeeded",
          publishedSeasonDiscoveryExpiresAt: expiresAt,
          updatedAt: FieldValue.serverTimestamp(),
        });
        candidatesSnap.docs.forEach((doc) => transaction.update(doc.ref, {expiresAt}));
      }
      return {
        resolution,
        allReviewsCompleted: unresolvedOthers.length === 0,
        duplicate: false,
      };
    });
    return {brandID, jobID, candidateID, ...outcome};
  }
);

export const retrySeasonDiscoveryAfterExtractionFix = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    try {
      return await admitDiscoveryRequest(db, uid, recordData(request.data), "afterFix");
    } catch (error) {
      return seasonAdmissionError(error);
    }
  }
);

export const onSeasonDiscoveryQueued = onDocumentWritten(
  {
    document: "brands/{brandID}/seasonDiscoveryJobs/{jobID}",
    region: FUNCTIONS_REGION,
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (event) => {
    const before = event.data?.before.data();
    const afterSnap = event.data?.after;
    const after = afterSnap?.data();
    if (!afterSnap?.exists || after?.status !== "queued" ||
        isBatchQueueJob(after)) return;
    if (before?.status === "queued" &&
        integer(before.dispatchGeneration, 0) === integer(after.dispatchGeneration, 0)) return;
    const brandID = String(event.params.brandID ?? "");
    const jobID = String(event.params.jobID ?? "");
    const generation = integer(after.generation, -1);
    const dispatchGeneration = integer(after.dispatchGeneration, 0);
    const extractionContractRevision = integer(
      after.extractionContractRevision,
      SEASON_DISCOVERY_CONTRACT_REVISION
    );
    const receipt = await enqueueTask(
      brandID,
      jobID,
      generation,
      dispatchGeneration,
      String(after.extractorVersion ?? ""),
      extractionContractRevision
    );
    await db.runTransaction(async (transaction) => {
      const freshSnap = await transaction.get(afterSnap.ref);
      const fresh = freshSnap.data();
      if (!freshSnap.exists || !canRecordSeasonDiscoveryDispatch({
        status: fresh?.status,
        generation: integer(fresh?.generation, -1),
        dispatchGeneration: integer(fresh?.dispatchGeneration, 0),
        expectedGeneration: generation,
        expectedDispatchGeneration: dispatchGeneration,
      })) return;
      transaction.update(afterSnap.ref, {
        status: "dispatching",
        phase: "dispatching",
        taskName: receipt.taskName,
        dispatchStatus: receipt.alreadyExists ? "alreadyEnqueued" : "enqueued",
        taskEnqueuedAt: FieldValue.serverTimestamp(),
        extractionContractRevision,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
  }
);

export const reconcileSeasonDiscoveryJobs = onSchedule(
  {schedule: "every 10 minutes", region: FUNCTIONS_REGION, timeZone: "Asia/Seoul"},
  async () => {
    const snapshot = await db.collectionGroup("seasonDiscoveryJobs")
      .where("status", "in", ["queued", "dispatching", "running"])
      .limit(100)
      .get();
    const cutoff = Date.now() - STALE_MILLIS;
    for (const document of snapshot.docs) {
      const data = document.data();
      if (isBatchQueueJob(data) || !isActiveStatus(data.status) ||
          timestampMillis(data.updatedAt) > cutoff) continue;
      await db.runTransaction(async (transaction) => {
        const fresh = await transaction.get(document.ref);
        const job = fresh.data();
        if (!fresh.exists || !job || isBatchQueueJob(job) ||
            !isActiveStatus(job?.status) ||
            timestampMillis(job?.updatedAt) > cutoff) return;
        const brandRef = document.ref.parent.parent;
        if (!brandRef) return;
        const brandSnap = await transaction.get(brandRef);
        const brand = brandSnap.data();
        if (!brandSnap.exists ||
            (brand?.deletionStatus && brand.deletionStatus !== "active")) {
          terminalize(transaction, document.ref, "cancelled", "brand_inactive", null);
          return;
        }
        if (brand?.activeSeasonDiscoveryJobID !== document.id ||
            integer(brand?.lastSeasonDiscoveryGeneration, -1) !== integer(job?.generation, -2)) {
          terminalize(transaction, document.ref, "superseded", "stale_generation", null);
          return;
        }
        const attempts = integer(job?.attemptCount, 0);
        if (attempts >= MAX_ATTEMPTS) {
          terminalize(transaction, document.ref, "failed", "retry_exhausted", "retry");
          transaction.update(brandRef, {
            activeSeasonDiscoveryJobID: null,
            discoveryStatus: "failed",
            lastDiscoveryCompletedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
          return;
        }
        transaction.update(document.ref, {
          status: "queued",
          phase: "dispatching",
          dispatchGeneration: integer(job?.dispatchGeneration, 0) + 1,
          leaseOwner: null,
          leaseExpiresAt: null,
          errorCode: "watchdog_redispatch",
          updatedAt: FieldValue.serverTimestamp(),
        });
      });
    }
  }
);


async function enqueueTask(
  brandID: string,
  jobID: string,
  generation: number,
  dispatchGeneration: number,
  extractorVersion: string,
  extractionContractRevision: number
): Promise<{taskName: string; alreadyExists: boolean}> {
  if (!extractorVersion || extractionContractRevision < 0) {
    throw new Error("season discovery extraction contract가 필요합니다.");
  }
  const config = taskConfig();
  client ??= new CloudTasksClient();
  const parent = client.queuePath(config.projectID, config.location, config.queue);
  const taskName = client.taskPath(
    config.projectID, config.location, config.queue,
    deterministicSeasonDiscoveryTaskID(brandID, jobID, dispatchGeneration)
  );
  try {
    const [task] = await client.createTask({
      parent,
      task: {
        name: taskName,
        httpRequest: {
          httpMethod: "POST",
          url: `${config.workerURL}${ENDPOINT}`,
          headers: {"Content-Type": "application/json"},
          body: Buffer.from(JSON.stringify({
            brandID, jobID, generation, dispatchGeneration,
            extractorVersion,
            extractionContractRevision,
            maxAttempts: MAX_ATTEMPTS,
          })),
          oidcToken: {serviceAccountEmail: config.serviceAccount, audience: config.audience},
        },
      },
    });
    return {taskName: task.name ?? taskName, alreadyExists: false};
  } catch (error) {
    if (isAlreadyExistsError(error)) return {taskName, alreadyExists: true};
    throw error;
  }
}

function taskConfig() {
  const projectID = env("GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT", "GCP_PROJECT");
  const workerURL = env("OUTPICK_LOOKBOOK_IMPORT_WORKER_URL").replace(/\/+$/, "");
  return {
    projectID,
    workerURL,
    location: optionalEnv("OUTPICK_LOOKBOOK_DISCOVERY_TASKS_LOCATION") ?? LOCATION,
    queue: optionalEnv("OUTPICK_LOOKBOOK_DISCOVERY_TASKS_QUEUE") ?? DEFAULT_QUEUE,
    serviceAccount: env("OUTPICK_LOOKBOOK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL"),
    audience: optionalEnv("OUTPICK_LOOKBOOK_IMPORT_TASKS_AUDIENCE") ?? workerURL,
  };
}

function terminalize(
  transaction: FirebaseFirestore.Transaction,
  ref: FirebaseFirestore.DocumentReference,
  status: "failed" | "cancelled" | "superseded",
  errorCode: string,
  recommendedAction: "retry" | null
): void {
  const now = new Date();
  transaction.update(ref, {
    status, phase: "completed", errorCode,
    recommendedAction: recommendedAction ?? "none",
    completedAt: FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromDate(
      seasonDiscoveryExpiresAt(status, now) as Date
    ),
    leaseOwner: null, leaseExpiresAt: null,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

function reviewDecision(
  value: unknown
): "connectExistingSeason" | "keepAsNew" | "reject" {
  if (value === "connectExistingSeason" || value === "keepAsNew" || value === "reject") {
    return value;
  }
  throw new HttpsError("invalid-argument", "decision 값이 올바르지 않습니다.");
}
function integerInput(value: unknown, fieldName: string): number {
  if (!Number.isInteger(value) || Number(value) < 0) {
    throw new HttpsError("invalid-argument", `${fieldName} 값이 올바르지 않습니다.`);
  }
  return Number(value);
}
function isActiveStatus(value: unknown): boolean {
  return typeof value === "string" && isActiveSeasonDiscoveryStatus(value as SeasonDiscoveryStatus);
}
function isTerminal(value: unknown): boolean {
  return value === "succeeded" || value === "failed" || value === "cancelled" || value === "superseded";
}
function integer(value: unknown, fallback: number): number {
  return Number.isInteger(value) ? Number(value) : fallback;
}
function timestampMillis(value: unknown): number {
  return value instanceof admin.firestore.Timestamp ? value.toMillis() : 0;
}
function optionalEnv(key: string): string | null {
  return process.env[key]?.trim() || null;
}
function env(...keys: string[]): string {
  for (const key of keys) {
    const value = optionalEnv(key);
    if (value) return value;
  }
  throw new Error(`${keys.join(" 또는 ")} 환경 변수가 필요합니다.`);
}
