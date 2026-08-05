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
import {
  assertBrandWriteAccess,
  assertOutPickAdmin,
} from "../../shared/brandAuthorization.js";
import {normalizedHTTPURL} from "../../shared/brandValidation.js";
import {
  seasonDiscoveryCreationFingerprint,
  canonicalDiscoveryURL,
  SEASON_DISCOVERY_CONTRACT_REVISION,
  SEASON_DISCOVERY_EXTRACTOR_VERSION,
  SEASON_DISCOVERY_LIMITS,
  SEASON_DISCOVERY_SCHEMA_VERSION,
} from "../../shared/seasonDiscoveryCreation.js";
import {isExtractionFixRetryEligible} from "./extractionIssueContract.js";
import {
  canRecordSeasonDiscoveryDispatch,
  deterministicSeasonDiscoveryTaskID,
  isActiveSeasonDiscoveryStatus,
  isSeasonAvailableForDiscoveryReview,
  seasonDiscoveryExpiresAt,
  type SeasonDiscoveryStatus,
} from "./seasonDiscoveryContract.js";

const LOCATION = "asia-northeast3";
const DEFAULT_QUEUE = "lookbook-discovery-jobs";
const ENDPOINT = "/tasks/discover-seasons";
const MAX_ATTEMPTS = 3;
const STALE_MILLIS = 15 * 60 * 1000;
const LIMITS = SEASON_DISCOVERY_LIMITS;

type RequestReason =
  "brandCreated" | "manualRefresh" | "archiveURLChanged" | "extractorImproved";
type JobReceipt = {
  brandID: string;
  jobID: string;
  generation: number;
  status: SeasonDiscoveryStatus;
  coalesced: boolean;
  sourceArchiveURL: string;
};

let client: CloudTasksClient | null = null;

export const requestSeasonDiscovery = onCall(
  {region: FUNCTIONS_REGION},
  async (request): Promise<JobReceipt> => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128), "brandID"
    );
    const reason = requestReason(data.requestReason);
    await assertBrandWriteAccess(uid, brandID);

    const brandRef = db.collection("brands").doc(brandID);
    const newJobRef = brandRef.collection("seasonDiscoveryJobs").doc();
    return db.runTransaction(async (transaction): Promise<JobReceipt> => {
      const brandSnap = await transaction.get(brandRef);
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }
      const brand = brandSnap.data() ?? {};
      if (brand.deletionStatus && brand.deletionStatus !== "active") {
        throw new HttpsError("failed-precondition", "비활성 브랜드입니다.");
      }
      const sourceValue = brand.lookbookArchiveURL;
      if (typeof sourceValue !== "string" || !sourceValue.trim()) {
        throw new HttpsError(
          "failed-precondition", "룩북 목록 URL이 등록되어 있지 않습니다."
        );
      }
      const sourceArchiveURL = normalizedHTTPURL(
        sourceValue, "lookbookArchiveURL"
      );
      const fingerprint = requestFingerprint(brandID, sourceArchiveURL);
      const activeJobID = typeof brand.activeSeasonDiscoveryJobID === "string" ?
        brand.activeSeasonDiscoveryJobID : null;
      const activeSnap = activeJobID ? await transaction.get(
        brandRef.collection("seasonDiscoveryJobs").doc(activeJobID)
      ) : null;
      const active = activeSnap?.data();
      if (activeSnap?.exists && active?.requestFingerprint === fingerprint &&
          isActiveStatus(active.status)) {
        transaction.update(activeSnap.ref, {
          coalescedRequestCount: FieldValue.increment(1),
          lastRequestedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        return {
          brandID, jobID: activeSnap.id,
          generation: integer(active.generation, 1),
          status: active.status as SeasonDiscoveryStatus,
          coalesced: true, sourceArchiveURL,
        };
      }

      const generation = integer(brand.lastSeasonDiscoveryGeneration, 0) + 1;
      if (activeSnap?.exists && isActiveStatus(active?.status)) {
        const now = new Date();
        transaction.update(activeSnap.ref, {
          status: "superseded",
          phase: "completed",
          recommendedAction: "none",
          completedAt: FieldValue.serverTimestamp(),
          expiresAt: admin.firestore.Timestamp.fromDate(
            seasonDiscoveryExpiresAt("superseded", now) as Date
          ),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      transaction.set(newJobRef, jobData({
        brandID, generation, fingerprint, sourceArchiveURL,
        requestedBy: uid, reason,
      }));
      transaction.update(brandRef, {
        activeSeasonDiscoveryJobID: newJobRef.id,
        lastSeasonDiscoveryGeneration: generation,
        discoveryStatus: "queued",
        publishedSeasonDiscoveryJobID: null,
        publishedSeasonDiscoveryGeneration: null,
        publishedSeasonDiscoverySnapshotHash: null,
        publishedSeasonDiscoveryExpiresAt: null,
        lastDiscoveryRequestedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {
        brandID, jobID: newJobRef.id, generation, status: "queued",
        coalesced: false, sourceArchiveURL,
      };
    });
  }
);

export const cancelSeasonDiscovery = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(requiredString(data, "brandID", 128), "brandID");
    const jobID = requiredDocumentID(requiredString(data, "jobID", 128), "jobID");
    await assertBrandWriteAccess(uid, brandID);
    const brandRef = db.collection("brands").doc(brandID);
    const jobRef = brandRef
      .collection("seasonDiscoveryJobs").doc(jobID);
    await db.runTransaction(async (transaction) => {
      const [brandSnap, snap] = await Promise.all([
        transaction.get(brandRef), transaction.get(jobRef),
      ]);
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
    const data = recordData(request.data);
    const brandID = requiredDocumentID(requiredString(data, "brandID", 128), "brandID");
    const jobID = requiredDocumentID(requiredString(data, "jobID", 128), "jobID");
    await assertBrandWriteAccess(uid, brandID);
    const brandRef = db.collection("brands").doc(brandID);
    const jobRef = brandRef.collection("seasonDiscoveryJobs").doc(jobID);
    const receipt = await db.runTransaction(async (transaction) => {
      const [brandSnap, jobSnap] = await Promise.all([
        transaction.get(brandRef), transaction.get(jobRef),
      ]);
      const brand = brandSnap.data();
      const job = jobSnap.data();
      if (!brandSnap.exists || !jobSnap.exists) {
        throw new HttpsError("not-found", "탐색 작업을 찾을 수 없습니다.");
      }
      if (brand?.activeSeasonDiscoveryJobID !== jobID ||
          job?.status !== "failed" || job?.retryable !== true) {
        throw new HttpsError("failed-precondition", "같은 작업으로 재시도할 수 없습니다.");
      }
      const dispatchGeneration = integer(job.dispatchGeneration, 0) + 1;
      transaction.update(jobRef, {
        status: "queued", phase: "dispatching", dispatchGeneration,
        attemptCount: 0,
        errorCode: null, errorMessage: null, expiresAt: null,
        leaseOwner: null, leaseExpiresAt: null,
        recommendedAction: "none",
        lastRequestedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.update(brandRef, {
        discoveryStatus: "queued",
        lastDiscoveryRequestedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {brandID, jobID, dispatchGeneration, status: "queued"};
    });
    return receipt;
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
    await assertBrandWriteAccess(uid, brandID);

    const brandRef = db.collection("brands").doc(brandID);
    const jobRef = brandRef.collection("seasonDiscoveryJobs").doc(jobID);
    const candidateRef = jobRef.collection("candidates").doc(candidateID);
    const reviewRef = jobRef.collection("reviews").doc();
    const outcome = await db.runTransaction(async (transaction) => {
      const [brandSnap, jobSnap, candidateSnap, candidatesSnap] = await Promise.all([
        transaction.get(brandRef),
        transaction.get(jobRef),
        transaction.get(candidateRef),
        transaction.get(jobRef.collection("candidates")),
      ]);
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
  async (request): Promise<JobReceipt> => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(requiredString(data, "brandID", 128), "brandID");
    const jobID = requiredDocumentID(requiredString(data, "jobID", 128), "jobID");
    const generation = integerInput(data.generation, "generation");
    const snapshotHash = requiredString(data, "candidateSnapshotHash", 128);
    await assertOutPickAdmin(uid);

    const brandRef = db.collection("brands").doc(brandID);
    const jobRef = brandRef.collection("seasonDiscoveryJobs").doc(jobID);
    const newJobRef = brandRef.collection("seasonDiscoveryJobs").doc();
    return db.runTransaction(async (transaction): Promise<JobReceipt> => {
      const [brandSnap, jobSnap, candidatesSnap] = await Promise.all([
        transaction.get(brandRef),
        transaction.get(jobRef),
        transaction.get(jobRef.collection("candidates")),
      ]);
      const brand = brandSnap.data();
      const job = jobSnap.data();
      if (!brandSnap.exists || !jobSnap.exists) {
        throw new HttpsError("not-found", "다시 분석할 탐색 결과를 찾을 수 없습니다.");
      }
      if (typeof job?.resolvedByJobID === "string") {
        const resolvedSnap = await transaction.get(
          brandRef.collection("seasonDiscoveryJobs").doc(job.resolvedByJobID)
        );
        const resolved = resolvedSnap.data();
        if (resolvedSnap.exists) {
          return {
            brandID,
            jobID: resolvedSnap.id,
            generation: integer(resolved?.generation, generation + 1),
            status: (resolved?.status ?? "queued") as SeasonDiscoveryStatus,
            coalesced: true,
            sourceArchiveURL: String(resolved?.sourceArchiveURL ?? job?.sourceArchiveURL ?? ""),
          };
        }
      }
      const sourceValue = typeof brand?.lookbookArchiveURL === "string" ?
        brand.lookbookArchiveURL : "";
      const sourceArchiveURL = normalizedHTTPURL(sourceValue, "lookbookArchiveURL");
      const originalSourceURL = typeof job?.sourceArchiveURL === "string" ?
        job.sourceArchiveURL : "";
      if ((brand?.deletionStatus && brand.deletionStatus !== "active") ||
          typeof brand?.activeSeasonDiscoveryJobID === "string" ||
          brand?.publishedSeasonDiscoveryJobID !== jobID ||
          job?.status !== "correctionRequired" ||
          integer(job?.generation, -1) !== generation ||
          job?.candidateSnapshotHash !== snapshotHash ||
          canonicalDiscoveryURL(sourceArchiveURL) !== canonicalDiscoveryURL(originalSourceURL) ||
          !hasVerifiedRetryRuntime(job)) {
        throw new HttpsError(
          "failed-precondition",
          "개선된 추출 방식이 준비된 최신 결과만 다시 가져올 수 있습니다."
        );
      }

      const nextGeneration = integer(brand.lastSeasonDiscoveryGeneration, 0) + 1;
      const fingerprint = requestFingerprint(brandID, sourceArchiveURL);
      const now = FieldValue.serverTimestamp();
      const candidateExpiresAt = admin.firestore.Timestamp.fromMillis(
        Date.now() + 30 * 24 * 60 * 60 * 1000
      );
      const jobExpiresAt = admin.firestore.Timestamp.fromMillis(
        Date.now() + 60 * 24 * 60 * 60 * 1000
      );
      transaction.set(newJobRef, jobData({
        brandID,
        generation: nextGeneration,
        fingerprint,
        sourceArchiveURL,
        requestedBy: uid,
        reason: "extractorImproved",
      }));
      transaction.update(jobRef, {
        status: "superseded",
        phase: "completed",
        errorCode: "reanalysis_started",
        recommendedAction: "none",
        resolvedByJobID: newJobRef.id,
        resolvedAt: now,
        completedAt: now,
        expiresAt: jobExpiresAt,
        updatedAt: now,
      });
      candidatesSnap.docs.forEach((candidate) => {
        transaction.update(candidate.ref, {expiresAt: candidateExpiresAt});
      });
      transaction.update(brandRef, {
        activeSeasonDiscoveryJobID: newJobRef.id,
        lastSeasonDiscoveryGeneration: nextGeneration,
        discoveryStatus: "queued",
        publishedSeasonDiscoveryJobID: null,
        publishedSeasonDiscoveryGeneration: null,
        publishedSeasonDiscoverySnapshotHash: null,
        publishedSeasonDiscoveryExpiresAt: null,
        lastDiscoveryRequestedAt: now,
        updatedAt: now,
      });
      return {
        brandID,
        jobID: newJobRef.id,
        generation: nextGeneration,
        status: "queued",
        coalesced: false,
        sourceArchiveURL,
      };
    });
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
    if (!afterSnap?.exists || after?.status !== "queued") return;
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
      if (!isActiveStatus(data.status) || timestampMillis(data.updatedAt) > cutoff) continue;
      await db.runTransaction(async (transaction) => {
        const fresh = await transaction.get(document.ref);
        const job = fresh.data();
        if (!fresh.exists || !isActiveStatus(job?.status) ||
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

function jobData(input: {
  brandID: string; generation: number; fingerprint: string;
  sourceArchiveURL: string; requestedBy: string; reason: RequestReason;
}): Record<string, unknown> {
  return {
    brandID: input.brandID,
    generation: input.generation,
    requestFingerprint: input.fingerprint,
    sourceArchiveURL: input.sourceArchiveURL,
    sourceArchiveURLFingerprint: input.fingerprint,
    schemaVersion: SEASON_DISCOVERY_SCHEMA_VERSION,
    extractorVersion: SEASON_DISCOVERY_EXTRACTOR_VERSION,
    extractionContractRevision: SEASON_DISCOVERY_CONTRACT_REVISION,
    adapterKey: null,
    adapterVersion: null,
    limits: LIMITS,
    status: "queued",
    phase: "dispatching",
    dispatchGeneration: 0,
    attemptCount: 0,
    requestedBy: input.requestedBy,
    requestReason: input.reason,
    coalescedRequestCount: 0,
    recommendedAction: "none",
    resolvedByJobID: null,
    leaseOwner: null,
    leaseExpiresAt: null,
    expiresAt: null,
    createdAt: FieldValue.serverTimestamp(),
    lastRequestedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function hasVerifiedRetryRuntime(job: Record<string, unknown>): boolean {
  return isExtractionFixRetryEligible({
    issueStatus: job.extractionIssueStatus,
    blockedRuntimeVersion: job.blockedRuntimeVersion,
    retryAvailableRuntimeVersion: job.retryAvailableRuntimeVersion,
    stage: "seasonDiscovery",
  });
}

function requestFingerprint(brandID: string, sourceArchiveURL: string): string {
  return seasonDiscoveryCreationFingerprint(brandID, sourceArchiveURL);
}

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

function requestReason(value: unknown): RequestReason {
  if (value === "manualRefresh" || value === "archiveURLChanged") return value;
  throw new HttpsError("invalid-argument", "requestReason 값이 올바르지 않습니다.");
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
