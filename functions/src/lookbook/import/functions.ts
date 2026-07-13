/* eslint-disable require-jsdoc, valid-jsdoc */
import * as admin from "firebase-admin";
import {CloudTasksClient} from "@google-cloud/tasks";
import {createHash, randomUUID} from "node:crypto";
import {FieldValue} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  optionalDocumentID,
  optionalString,
  recordData,
  requiredAuthUID,
  requiredDocumentID,
  requiredString,
} from "../../core/callable.js";
import {mapWithConcurrency} from "../../core/concurrency.js";
import {isAlreadyExistsError, messageFromError} from "../../core/errors.js";
import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {assertBrandWriteAccess} from "../../shared/brandAuthorization.js";
import {
  discoverSeasonCandidates as runDiscoverSeasonCandidates,
} from "./seasonCandidateDiscovery.js";

const LOOKBOOK_IMPORT_TASKS_LOCATION = "asia-northeast3";
const LOOKBOOK_IMPORT_TASKS_QUEUE = "lookbook-import-jobs";
const LOOKBOOK_IMPORT_TASK_ENDPOINT = "/tasks/import-job";
const LOOKBOOK_DISCOVERY_DIAGNOSTIC_ENDPOINT =
  "/tasks/discover-seasons-diagnostic";
const LOOKBOOK_IMPORT_TASK_MAX_ATTEMPTS = 3;
const LOOKBOOK_ASSET_RETRY_MODE = "assetFailureRetry";
const LOOKBOOK_EXTRACTION_DIAGNOSTIC_RETENTION_DAYS = 90;
const LOOKBOOK_EXTRACTION_DIAGNOSTIC_CLEANUP_LIMIT = 100;
const LOOKBOOK_DIAGNOSTIC_LIMITS = {
  maxLoadMoreClicks: 20,
  maxScrollAttempts: 20,
  settleMs: 800,
  timeoutMs: 45000,
  maxDiagnosticCandidates: 120,
  maxStoredCandidates: 80,
};

let cloudTasksClient: CloudTasksClient | null = null;
function numericMetric(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return 0;
  }
  return Math.max(0, Math.floor(value));
}

function normalizedHTTPURL(rawValue: string, fieldName: string): string {
  const candidate = rawValue.includes("://") ? rawValue : `https://${rawValue}`;

  let parsed: URL;
  try {
    parsed = new URL(candidate);
  } catch {
    throw new HttpsError("invalid-argument", `${fieldName} 값이 올바르지 않습니다.`);
  }

  const protocol = parsed.protocol.toLowerCase();
  if (protocol !== "http:" && protocol !== "https:") {
    throw new HttpsError(
      "invalid-argument",
      `${fieldName} 값은 http 또는 https만 지원합니다.`
    );
  }

  if (!parsed.hostname) {
    throw new HttpsError("invalid-argument", `${fieldName} 값에 도메인이 필요합니다.`);
  }

  parsed.protocol = protocol;
  parsed.hostname = parsed.hostname.toLowerCase();
  return parsed.toString();
}

function requiredDocumentIDList(
  value: unknown,
  fieldName: string,
  maxCount: number
): string[] {
  if (!Array.isArray(value)) {
    throw new HttpsError("invalid-argument", `${fieldName} 값이 필요합니다.`);
  }

  const ids = value.map((item) => {
    if (typeof item !== "string") {
      throw new HttpsError(
        "invalid-argument",
        `${fieldName} 값이 올바르지 않습니다.`
      );
    }
    return requiredDocumentID(item, fieldName);
  });

  const uniqueIDs = Array.from(new Set(ids));
  if (uniqueIDs.length === 0 || uniqueIDs.length > maxCount) {
    throw new HttpsError("invalid-argument", `${fieldName} 개수가 올바르지 않습니다.`);
  }
  return uniqueIDs;
}

export function blocksDuplicateSeasonImport(status: unknown): boolean {
  return (
    status === "queued" ||
    status === "processing" ||
    status === "succeeded" ||
    status === "partialFailed"
  );
}

type SeasonCandidateImportSeed = {
  sourceTitle: string | null;
  coverRemoteURL: string | null;
  sourceSortIndex: number | null;
};

type SeasonImportJobReceipt = {
  jobID: string;
  brandID: string;
  status: string;
  seasonURL: string;
  sourceCandidateID: string | null;
  duplicate: boolean;
};

type SeasonCandidateImportTarget = {
  candidateID: string;
  seasonURL: string;
  seed: SeasonCandidateImportSeed;
};

type SeasonCandidateImportFailure = {
  candidateID: string;
  title: string | null;
  errorMessage: string;
};

type LookbookImportTaskConfig = {
  projectID: string;
  locationID: string;
  queueID: string;
  workerURL: string;
  serviceAccountEmail: string;
  audience: string;
};

type LookbookImportTaskReceipt = {
  taskName: string;
  alreadyExists: boolean;
};

type LookbookExtractionDiagnosticType =
  "season_discovery" | "season_image_import";
type LookbookExtractionDiagnosticStatus =
  "passed" | "failed" | "needsReview";
type LookbookExtractionSuggestedFixScope =
  "common_logic" | "brand_adapter" | "unknown";
type LookbookExtractionFailureReason =
  "archive_url_missing" |
  "archive_url_fetch_failed" |
  "no_candidates_found" |
  "low_confidence_candidates" |
  "load_more_detected" |
  "dynamic_rendering_detected" |
  "worker_timeout" |
  "worker_failed" |
  "image_load_failed" |
  "asset_sync_failed" |
  "permission_denied" |
  "unknown";

type LookbookExtractionSuggestedFix = {
  type: string;
  scope: LookbookExtractionSuggestedFixScope;
  confidence: number;
  message: string;
};

type DiagnosticSeasonCandidate = {
  title: string;
  seasonURL: string;
  coverImageURL: string | null;
  score: number;
};

type SeasonDiscoveryWorkerDiagnostic = {
  staticCandidateCount: number;
  renderedCandidateCount: number | null;
  candidateCountBeforeExpansion: number;
  candidateCountAfterExpansion: number;
  storedCandidateCount: number;
  diagnosticCandidateCount: number;
  loadMoreDetected: boolean;
  loadMoreClickCount: number;
  infiniteScrollAttempted: boolean;
  scrollAttemptCount: number;
  dynamicRenderingDetected: boolean;
  renderedFallbackUsed: boolean;
  parserStrategy: string;
  adapterKey: string | null;
  failureReasons: LookbookExtractionFailureReason[];
  suggestedFixScope: LookbookExtractionSuggestedFixScope;
  suggestedFixes: LookbookExtractionSuggestedFix[];
  summaryMessage: string | null;
  errorMessage: string | null;
};

type SeasonDiscoveryWorkerResponse = {
  status: LookbookExtractionDiagnosticStatus;
  sourceURL: string;
  candidates: DiagnosticSeasonCandidate[];
  diagnostic: SeasonDiscoveryWorkerDiagnostic;
};

type AssetFailureRetryReceipt = {
  sourceImportJobID: string;
  seasonID: string;
  status: string;
  duplicate: boolean;
  requestID: string;
  taskName: string | null;
};

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function timestampToISO(value: unknown): string | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate().toISOString();
  }
  return null;
}

function requiredRuntimeEnv(key: string): string {
  const value = process.env[key]?.trim();
  if (!value) {
    throw new Error(`${key} 환경 변수가 필요합니다.`);
  }
  return value;
}

function optionalRuntimeEnv(key: string): string | null {
  const value = process.env[key]?.trim();
  return value && value.length > 0 ? value : null;
}

function googleCloudProjectID(): string {
  const projectID =
    optionalRuntimeEnv("GCLOUD_PROJECT") ??
    optionalRuntimeEnv("GOOGLE_CLOUD_PROJECT") ??
    optionalRuntimeEnv("GCP_PROJECT");
  if (!projectID) {
    throw new Error("Google Cloud project ID 환경 변수가 필요합니다.");
  }
  return projectID;
}

function lookbookImportTaskConfig(): LookbookImportTaskConfig {
  const workerURL = requiredRuntimeEnv("OUTPICK_LOOKBOOK_IMPORT_WORKER_URL")
    .replace(/\/+$/, "");
  return {
    projectID: googleCloudProjectID(),
    locationID:
      optionalRuntimeEnv("OUTPICK_LOOKBOOK_IMPORT_TASKS_LOCATION") ??
      LOOKBOOK_IMPORT_TASKS_LOCATION,
    queueID:
      optionalRuntimeEnv("OUTPICK_LOOKBOOK_IMPORT_TASKS_QUEUE") ??
      LOOKBOOK_IMPORT_TASKS_QUEUE,
    workerURL,
    serviceAccountEmail: requiredRuntimeEnv(
      "OUTPICK_LOOKBOOK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL"
    ),
    audience:
      optionalRuntimeEnv("OUTPICK_LOOKBOOK_IMPORT_TASKS_AUDIENCE") ??
      workerURL,
  };
}

function tasksClient(): CloudTasksClient {
  cloudTasksClient ??= new CloudTasksClient();
  return cloudTasksClient;
}

export function deterministicImportTaskID(
  brandID: string,
  jobID: string
): string {
  const encoded = Buffer
    .from(`${brandID}:${jobID}`)
    .toString("base64url");
  return `import-${encoded}`.slice(0, 500);
}

export function deterministicAssetRetryTaskID(
  brandID: string,
  seasonID: string,
  sourceJobID: string,
  requestID: string
): string {
  const encoded = Buffer
    .from(`${brandID}:${seasonID}:${sourceJobID}:${requestID}`)
    .toString("base64url");
  return `asset-retry-${encoded}`.slice(0, 500);
}

function lookbookDiagnosticCollection(): FirebaseFirestore.CollectionReference {
  return db.collection("lookbookExtractionDiagnostics");
}

export function requiredDiagnosticType(
  value: unknown
): LookbookExtractionDiagnosticType {
  if (value !== "season_discovery" && value !== "season_image_import") {
    throw new HttpsError("invalid-argument", "type 값이 올바르지 않습니다.");
  }
  return value;
}

function diagnosticExpiresAt(nowDate = new Date()): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromDate(
    addDays(nowDate, LOOKBOOK_EXTRACTION_DIAGNOSTIC_RETENTION_DAYS)
  );
}

export function diagnosticCandidateID(seasonURL: string): string {
  return createHash("sha1").update(seasonURL).digest("hex").slice(0, 24);
}

async function identityTokenForAudience(audience: string): Promise<string> {
  const url =
    "http://metadata/computeMetadata/v1/instance/service-accounts/default/" +
    `identity?audience=${encodeURIComponent(audience)}`;
  const response = await fetch(url, {
    headers: {"Metadata-Flavor": "Google"},
  });
  if (!response.ok) {
    throw new Error(`worker 인증 토큰 발급 실패: HTTP ${response.status}`);
  }
  return (await response.text()).trim();
}

async function callSeasonDiscoveryDiagnosticWorker(
  brandID: string,
  archiveURL: string,
  requestedBy: string,
  diagnosticID: string
): Promise<SeasonDiscoveryWorkerResponse> {
  const config = lookbookImportTaskConfig();
  const token = await identityTokenForAudience(config.audience);
  const response = await fetch(
    `${config.workerURL}${LOOKBOOK_DISCOVERY_DIAGNOSTIC_ENDPOINT}`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        brandID,
        archiveURL,
        requestedBy,
        diagnosticID,
        limits: LOOKBOOK_DIAGNOSTIC_LIMITS,
      }),
    }
  );
  const rawBody = await response.text();
  if (!response.ok) {
    throw new Error(
      `worker 시즌 목록 진단 실패: HTTP ${response.status} ${rawBody}`
    );
  }
  return JSON.parse(rawBody) as SeasonDiscoveryWorkerResponse;
}

async function replaceDiagnosticSeasonCandidates(
  brandID: string,
  archiveURL: string,
  candidates: DiagnosticSeasonCandidate[]
): Promise<void> {
  const collectionRef = db
    .collection("brands")
    .doc(brandID)
    .collection("seasonCandidates");
  const existingSnapshot = await collectionRef.limit(300).get();
  const batch = db.batch();

  existingSnapshot.docs.forEach((doc) => {
    batch.delete(doc.ref);
  });
  candidates.forEach((candidate, index) => {
    batch.set(collectionRef.doc(diagnosticCandidateID(candidate.seasonURL)), {
      brandID,
      title: candidate.title,
      seasonURL: candidate.seasonURL,
      coverImageURL: candidate.coverImageURL,
      sourceArchiveURL: archiveURL,
      extractionScore: candidate.score,
      sortIndex: index,
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  await batch.commit();
}

function diagnosticSummary(
  diagnosticID: string,
  data: FirebaseFirestore.DocumentData
): Record<string, unknown> {
  const seasonDiscovery = data.seasonDiscovery &&
    typeof data.seasonDiscovery === "object" ?
    data.seasonDiscovery as Record<string, unknown> :
    null;
  const seasonImageImport = data.seasonImageImport &&
    typeof data.seasonImageImport === "object" ?
    data.seasonImageImport as Record<string, unknown> :
    null;
  const summary: Record<string, unknown> = {
    id: diagnosticID,
    brandID: data.brandID ?? "",
    type: data.type ?? "season_discovery",
    status: data.status ?? "failed",
    phase: data.phase ?? "completed",
    sourceURL: data.sourceURL ?? null,
    summaryMessage: data.summaryMessage ?? null,
    errorMessage: data.errorMessage ?? null,
    failureReasons: Array.isArray(data.failureReasons) ?
      data.failureReasons :
      [],
    suggestedFixScope: data.suggestedFixScope ?? "unknown",
    suggestedFixes: Array.isArray(data.suggestedFixes) ?
      data.suggestedFixes :
      [],
    createdAt: timestampToISO(data.createdAt),
    updatedAt: timestampToISO(data.updatedAt),
    completedAt: timestampToISO(data.completedAt),
    expiresAt: timestampToISO(data.expiresAt),
  };
  if (seasonDiscovery) {
    summary.seasonDiscovery = {
      staticCandidateCount: seasonDiscovery.staticCandidateCount ?? 0,
      renderedCandidateCount: seasonDiscovery.renderedCandidateCount ?? null,
      candidateCountBeforeExpansion:
        seasonDiscovery.candidateCountBeforeExpansion ?? 0,
      candidateCountAfterExpansion:
        seasonDiscovery.candidateCountAfterExpansion ?? 0,
      storedCandidateCount: seasonDiscovery.storedCandidateCount ?? 0,
      diagnosticCandidateCount:
        seasonDiscovery.diagnosticCandidateCount ?? 0,
      loadMoreDetected: seasonDiscovery.loadMoreDetected === true,
      loadMoreClickCount: seasonDiscovery.loadMoreClickCount ?? 0,
      infiniteScrollAttempted:
        seasonDiscovery.infiniteScrollAttempted === true,
      scrollAttemptCount: seasonDiscovery.scrollAttemptCount ?? 0,
      dynamicRenderingDetected:
        seasonDiscovery.dynamicRenderingDetected === true,
      renderedFallbackUsed: seasonDiscovery.renderedFallbackUsed === true,
      parserStrategy: seasonDiscovery.parserStrategy ?? "unknown",
      adapterKey: seasonDiscovery.adapterKey ?? null,
    };
  }
  if (seasonImageImport) {
    summary.seasonImageImport = {
      sourceImportJobID: seasonImageImport.sourceImportJobID ?? "",
      targetSeasonID: seasonImageImport.targetSeasonID ?? null,
      seasonTitle: seasonImageImport.seasonTitle ?? null,
      expectedImageCount: seasonImageImport.expectedImageCount ?? 0,
      importedImageCount: seasonImageImport.importedImageCount ?? 0,
      failedImageCount: seasonImageImport.failedImageCount ?? 0,
      retryable: seasonImageImport.retryable === true,
    };
  }
  return summary;
}

function seasonCandidateImportSeedFromData(
  data: FirebaseFirestore.DocumentData | undefined
): SeasonCandidateImportSeed {
  return {
    sourceTitle: typeof data?.title === "string" ? data.title.trim() : null,
    coverRemoteURL:
      typeof data?.coverImageURL === "string" ?
        data.coverImageURL.trim() :
        null,
    sourceSortIndex: Number.isInteger(data?.sortIndex) ?
      Number(data?.sortIndex) :
      null,
  };
}

async function enqueueLookbookImportTask(
  brandID: string,
  jobID: string
): Promise<LookbookImportTaskReceipt> {
  const config = lookbookImportTaskConfig();
  const client = tasksClient();
  const parent = client.queuePath(
    config.projectID,
    config.locationID,
    config.queueID
  );
  const taskName = client.taskPath(
    config.projectID,
    config.locationID,
    config.queueID,
    deterministicImportTaskID(brandID, jobID)
  );
  const payload = {
    brandID,
    jobID,
    maxAttempts: LOOKBOOK_IMPORT_TASK_MAX_ATTEMPTS,
    requestedAt: new Date().toISOString(),
  };

  try {
    const [task] = await client.createTask({
      parent,
      task: {
        name: taskName,
        httpRequest: {
          httpMethod: "POST",
          url: `${config.workerURL}${LOOKBOOK_IMPORT_TASK_ENDPOINT}`,
          headers: {
            "Content-Type": "application/json",
          },
          body: Buffer.from(JSON.stringify(payload)),
          oidcToken: {
            serviceAccountEmail: config.serviceAccountEmail,
            audience: config.audience,
          },
        },
      },
    });

    return {
      taskName: task.name ?? taskName,
      alreadyExists: false,
    };
  } catch (error) {
    if (isAlreadyExistsError(error)) {
      return {
        taskName,
        alreadyExists: true,
      };
    }
    throw error;
  }
}

async function enqueueLookbookAssetRetryTask(
  brandID: string,
  seasonID: string,
  sourceJobID: string,
  requestID: string
): Promise<LookbookImportTaskReceipt> {
  const config = lookbookImportTaskConfig();
  const client = tasksClient();
  const parent = client.queuePath(
    config.projectID,
    config.locationID,
    config.queueID
  );
  const taskName = client.taskPath(
    config.projectID,
    config.locationID,
    config.queueID,
    deterministicAssetRetryTaskID(brandID, seasonID, sourceJobID, requestID)
  );
  const payload = {
    mode: LOOKBOOK_ASSET_RETRY_MODE,
    brandID,
    seasonID,
    sourceJobID,
    requestID,
    maxAttempts: LOOKBOOK_IMPORT_TASK_MAX_ATTEMPTS,
    requestedAt: new Date().toISOString(),
  };

  try {
    const [task] = await client.createTask({
      parent,
      task: {
        name: taskName,
        httpRequest: {
          httpMethod: "POST",
          url: `${config.workerURL}${LOOKBOOK_IMPORT_TASK_ENDPOINT}`,
          headers: {
            "Content-Type": "application/json",
          },
          body: Buffer.from(JSON.stringify(payload)),
          oidcToken: {
            serviceAccountEmail: config.serviceAccountEmail,
            audience: config.audience,
          },
        },
      },
    });

    return {
      taskName: task.name ?? taskName,
      alreadyExists: false,
    };
  } catch (error) {
    if (isAlreadyExistsError(error)) {
      return {taskName, alreadyExists: true};
    }
    throw error;
  }
}

async function seasonCandidateImportSeed(
  brandRef: FirebaseFirestore.DocumentReference,
  sourceCandidateID: string | null,
  seasonURL: string
): Promise<SeasonCandidateImportSeed> {
  if (sourceCandidateID === null) {
    return {
      sourceTitle: null,
      coverRemoteURL: null,
      sourceSortIndex: null,
    };
  }

  const candidateSnap = await brandRef
    .collection("seasonCandidates")
    .doc(sourceCandidateID)
    .get();

  if (!candidateSnap.exists) {
    throw new HttpsError("not-found", "시즌 후보를 찾을 수 없습니다.");
  }

  const candidateURL = candidateSnap.data()?.seasonURL;
  if (
    typeof candidateURL !== "string" ||
    normalizedHTTPURL(candidateURL, "seasonCandidate.seasonURL") !== seasonURL
  ) {
    throw new HttpsError(
      "invalid-argument",
      "시즌 후보와 시즌 URL이 일치하지 않습니다."
    );
  }

  const data = candidateSnap.data();
  return seasonCandidateImportSeedFromData(data);
}

async function requestSeasonImportJob(
  uid: string,
  brandID: string,
  seasonURL: string,
  sourceCandidateID: string | null
): Promise<SeasonImportJobReceipt> {
  const brandRef = db.collection("brands").doc(brandID);
  const candidateSeed = await seasonCandidateImportSeed(
    brandRef,
    sourceCandidateID,
    seasonURL
  );
  return createSeasonImportJobFromSeed(
    uid,
    brandID,
    seasonURL,
    sourceCandidateID,
    candidateSeed
  );
}

async function createSeasonImportJobFromSeed(
  uid: string,
  brandID: string,
  seasonURL: string,
  sourceCandidateID: string | null,
  candidateSeed: SeasonCandidateImportSeed
): Promise<SeasonImportJobReceipt> {
  const retryReceipt = await requestAssetRetryForExistingImportIfNeeded(
    uid,
    brandID,
    seasonURL,
    sourceCandidateID
  );
  if (retryReceipt !== null) {
    return retryReceipt;
  }

  const brandRef = db.collection("brands").doc(brandID);
  const importJobsRef = brandRef.collection("importJobs");
  const jobRef = importJobsRef.doc();

  return db.runTransaction(
    async (transaction): Promise<SeasonImportJobReceipt> => {
      const sourceURLSnapshot = await transaction.get(
        importJobsRef.where("sourceURL", "==", seasonURL)
      );

      const sourceCandidateSnapshot = sourceCandidateID === null ?
        null :
        await transaction.get(
          importJobsRef.where("sourceCandidateID", "==", sourceCandidateID)
        );

      const activeDuplicate = [
        ...sourceURLSnapshot.docs,
        ...(sourceCandidateSnapshot?.docs ?? []),
      ].find((snapshot) => {
        const job = snapshot.data();
        return (
          job.jobType === "importSeasonFromURL" &&
          blocksDuplicateSeasonImport(job.status)
        );
      });

      if (activeDuplicate) {
        const job = activeDuplicate.data();
        const duplicatePatch: Record<string, unknown> = {};
        if (
          typeof job.sourceTitle !== "string" &&
          candidateSeed.sourceTitle !== null
        ) {
          duplicatePatch.sourceTitle = candidateSeed.sourceTitle;
        }
        if (
          typeof job.coverRemoteURL !== "string" &&
          candidateSeed.coverRemoteURL !== null
        ) {
          duplicatePatch.coverRemoteURL = candidateSeed.coverRemoteURL;
        }
        if (
          !Number.isInteger(job.sourceSortIndex) &&
          candidateSeed.sourceSortIndex !== null
        ) {
          duplicatePatch.sourceSortIndex = candidateSeed.sourceSortIndex;
        }
        if (Object.keys(duplicatePatch).length > 0) {
          duplicatePatch.updatedAt = FieldValue.serverTimestamp();
          transaction.update(activeDuplicate.ref, duplicatePatch);
        }

        return {
          jobID: activeDuplicate.id,
          brandID,
          status: String(job.status ?? "queued"),
          seasonURL,
          sourceCandidateID: typeof job.sourceCandidateID === "string" ?
            job.sourceCandidateID :
            sourceCandidateID,
          duplicate: true,
        };
      }

      transaction.set(jobRef, {
        brandID,
        jobType: "importSeasonFromURL",
        status: "queued",
        phase: "dispatching",
        dispatchMode: "cloudTasks",
        sourceURL: seasonURL,
        sourceCandidateID,
        sourceTitle: candidateSeed.sourceTitle,
        coverRemoteURL: candidateSeed.coverRemoteURL,
        sourceSortIndex: candidateSeed.sourceSortIndex,
        requestedBy: uid,
        errorMessage: null,
        assetCompletedCount: 0,
        assetFailedCount: 0,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {
        jobID: jobRef.id,
        brandID,
        status: "queued",
        seasonURL,
        sourceCandidateID,
        duplicate: false,
      };
    }
  );
}

async function requestAssetRetryForExistingImportIfNeeded(
  uid: string,
  brandID: string,
  seasonURL: string,
  sourceCandidateID: string | null
): Promise<SeasonImportJobReceipt | null> {
  const importJobsRef = db
    .collection("brands")
    .doc(brandID)
    .collection("importJobs");
  const sourceURLSnapshot = await importJobsRef
    .where("sourceURL", "==", seasonURL)
    .get();
  const sourceCandidateSnapshot = sourceCandidateID === null ?
    null :
    await importJobsRef
      .where("sourceCandidateID", "==", sourceCandidateID)
      .get();
  const retryableJob = [
    ...sourceURLSnapshot.docs,
    ...(sourceCandidateSnapshot?.docs ?? []),
  ].find((snapshot) => {
    const job = snapshot.data();
    return (
      job.jobType === "importSeasonFromURL" &&
      (job.status === "partialFailed" || job.status === "failed") &&
      typeof job.targetSeasonID === "string" &&
      Number(job.assetFailedCount ?? 0) > 0
    );
  });

  if (!retryableJob) {
    return null;
  }

  const retryReceipt = await requestSeasonAssetFailureRetry(
    uid,
    brandID,
    retryableJob.id
  );
  const sourceJob = retryableJob.data();
  return {
    jobID: retryReceipt.sourceImportJobID,
    brandID,
    status: retryReceipt.status,
    seasonURL,
    sourceCandidateID: typeof sourceJob.sourceCandidateID === "string" ?
      sourceJob.sourceCandidateID :
      sourceCandidateID,
    duplicate: retryReceipt.duplicate,
  };
}

function isInFlightAssetRetryStatus(status: unknown): boolean {
  return status === "queued" || status === "processing";
}

async function requestSeasonAssetFailureRetry(
  uid: string,
  brandID: string,
  sourceJobID: string
): Promise<AssetFailureRetryReceipt> {
  const brandRef = db.collection("brands").doc(brandID);
  const importJobsRef = brandRef.collection("importJobs");
  const sourceJobRef = importJobsRef.doc(sourceJobID);

  const marker = await db.runTransaction(async (transaction) => {
    const sourceJobSnapshot = await transaction.get(sourceJobRef);
    if (!sourceJobSnapshot.exists) {
      throw new HttpsError("not-found", "원본 import job을 찾을 수 없습니다.");
    }
    const sourceJob = sourceJobSnapshot.data() ?? {};
    if (
      sourceJob.jobType !== "importSeasonFromURL" ||
      !["partialFailed", "failed"].includes(String(sourceJob.status))
    ) {
      throw new HttpsError(
        "failed-precondition",
        "실패 asset이 있는 완료 job만 재시도할 수 있습니다."
      );
    }
    const targetSeasonID = requiredDocumentID(
      requiredString(sourceJob, "targetSeasonID", 128),
      "targetSeasonID"
    );
    normalizedHTTPURL(
      requiredString(sourceJob, "sourceURL", 2048),
      "sourceURL"
    );
    requiredDocumentIDList(
      sourceJob.createdPostIDs,
      "createdPostIDs",
      120
    );
    if (
      isInFlightAssetRetryStatus(sourceJob.assetRetryStatus) &&
      typeof sourceJob.assetRetryRequestID === "string"
    ) {
      return {
        requestID: sourceJob.assetRetryRequestID,
        status: String(sourceJob.assetRetryStatus),
        sourceImportJobID: sourceJobID,
        seasonID: targetSeasonID,
        duplicate: true,
        enqueue: false,
      };
    }

    const requestID = randomUUID();
    transaction.update(sourceJobRef, {
      assetRetryStatus: "queued",
      assetRetryRequestID: requestID,
      assetRetryRequestedBy: uid,
      assetRetryRequestedAt: FieldValue.serverTimestamp(),
      assetRetryTaskName: null,
      assetRetryErrorMessage: null,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      requestID,
      status: "queued",
      sourceImportJobID: sourceJobID,
      seasonID: targetSeasonID,
      duplicate: false,
      enqueue: true,
    };
  });

  if (marker.duplicate || !marker.enqueue) {
    return {
      sourceImportJobID: marker.sourceImportJobID,
      seasonID: marker.seasonID,
      status: marker.status,
      duplicate: true,
      requestID: marker.requestID,
      taskName: null,
    };
  }

  try {
    const taskReceipt = await enqueueLookbookAssetRetryTask(
      brandID,
      marker.seasonID,
      sourceJobID,
      marker.requestID
    );
    await sourceJobRef.update({
      assetRetryTaskName: taskReceipt.taskName,
      assetRetryTaskEnqueuedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      sourceImportJobID: marker.sourceImportJobID,
      seasonID: marker.seasonID,
      status: marker.status,
      duplicate: taskReceipt.alreadyExists,
      requestID: marker.requestID,
      taskName: taskReceipt.taskName,
    };
  } catch (error) {
    await sourceJobRef.update({
      assetRetryStatus: "failed",
      assetRetryErrorMessage: messageFromError(error),
      updatedAt: FieldValue.serverTimestamp(),
    });
    throw error;
  }
}

async function runSeasonDiscoveryDiagnostic(
  uid: string,
  brandID: string
): Promise<Record<string, unknown>> {
  const brandRef = db.collection("brands").doc(brandID);
  const brandSnap = await brandRef.get();
  if (!brandSnap.exists) {
    throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
  }
  const brandData = brandSnap.data() ?? {};
  const brandName =
    typeof brandData.name === "string" ? brandData.name.trim() : null;
  const diagnosticRef = lookbookDiagnosticCollection().doc();
  const nowDate = new Date();
  const now = admin.firestore.Timestamp.fromDate(nowDate);
  const expiresAt = diagnosticExpiresAt(nowDate);
  const archiveURLValue = brandData.lookbookArchiveURL;

  if (
    typeof archiveURLValue !== "string" ||
    archiveURLValue.trim().length === 0
  ) {
    const documentData = {
      brandID,
      brandName,
      type: "season_discovery",
      status: "failed",
      phase: "completed",
      sourceURL: null,
      requestedBy: uid,
      failureReasons: ["archive_url_missing"],
      suggestedFixScope: "unknown",
      suggestedFixes: [],
      summaryMessage: null,
      errorMessage: "룩북 목록 URL이 등록되어 있지 않습니다.",
      expiresAt,
      createdAt: now,
      updatedAt: now,
      completedAt: now,
      seasonDiscovery: null,
      seasonImageImport: null,
    };
    await diagnosticRef.set(documentData);
    await brandRef.update({
      lastSeasonDiscoveryDiagnosticID: diagnosticRef.id,
      lastSeasonDiscoveryStatus: "failed",
      lastSeasonDiscoveryCandidateCount: 0,
      lastSeasonDiscoverySuggestedFixScope: "unknown",
      lastSeasonDiscoveryAt: FieldValue.serverTimestamp(),
      lastSeasonDiscoveryErrorMessage: documentData.errorMessage,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return diagnosticSummary(diagnosticRef.id, documentData);
  }

  const archiveURL = normalizedHTTPURL(
    archiveURLValue,
    "lookbookArchiveURL"
  );
  const workerResponse = await callSeasonDiscoveryDiagnosticWorker(
    brandID,
    archiveURL,
    uid,
    diagnosticRef.id
  );
  const diagnostic = workerResponse.diagnostic;
  const documentData = {
    brandID,
    brandName,
    type: "season_discovery",
    status: workerResponse.status,
    phase: "completed",
    sourceURL: workerResponse.sourceURL,
    requestedBy: uid,
    failureReasons: diagnostic.failureReasons,
    suggestedFixScope: diagnostic.suggestedFixScope,
    suggestedFixes: diagnostic.suggestedFixes,
    summaryMessage: diagnostic.summaryMessage,
    errorMessage: diagnostic.errorMessage,
    expiresAt,
    createdAt: now,
    updatedAt: now,
    completedAt: now,
    seasonDiscovery: {
      archiveURL,
      staticCandidateCount: diagnostic.staticCandidateCount,
      renderedCandidateCount: diagnostic.renderedCandidateCount,
      candidateCountBeforeExpansion:
        diagnostic.candidateCountBeforeExpansion,
      candidateCountAfterExpansion: diagnostic.candidateCountAfterExpansion,
      storedCandidateCount: diagnostic.storedCandidateCount,
      diagnosticCandidateCount: diagnostic.diagnosticCandidateCount,
      loadMoreDetected: diagnostic.loadMoreDetected,
      loadMoreClickCount: diagnostic.loadMoreClickCount,
      infiniteScrollAttempted: diagnostic.infiniteScrollAttempted,
      scrollAttemptCount: diagnostic.scrollAttemptCount,
      dynamicRenderingDetected: diagnostic.dynamicRenderingDetected,
      renderedFallbackUsed: diagnostic.renderedFallbackUsed,
      parserStrategy: diagnostic.parserStrategy,
      adapterKey: diagnostic.adapterKey,
      limits: LOOKBOOK_DIAGNOSTIC_LIMITS,
    },
    seasonImageImport: null,
  };

  await replaceDiagnosticSeasonCandidates(
    brandID,
    archiveURL,
    workerResponse.candidates
  );
  await diagnosticRef.set(documentData);
  await brandRef.update({
    lastSeasonDiscoveryDiagnosticID: diagnosticRef.id,
    lastSeasonDiscoveryStatus: workerResponse.status,
    lastSeasonDiscoveryCandidateCount: diagnostic.storedCandidateCount,
    lastSeasonDiscoverySuggestedFixScope: diagnostic.suggestedFixScope,
    lastSeasonDiscoveryAt: FieldValue.serverTimestamp(),
    lastSeasonDiscoveryErrorMessage: diagnostic.errorMessage,
    discoveryStatus: workerResponse.status === "passed" ?
      "success" :
      "failed",
    lastDiscoveryCompletedAt: FieldValue.serverTimestamp(),
    lastDiscoveryErrorMessage: diagnostic.errorMessage,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return diagnosticSummary(diagnosticRef.id, documentData);
}

async function runSeasonImageImportDiagnostic(
  uid: string,
  brandID: string,
  sourceImportJobID: string,
  seasonID: string | null
): Promise<Record<string, unknown>> {
  const brandRef = db.collection("brands").doc(brandID);
  const brandSnap = await brandRef.get();
  if (!brandSnap.exists) {
    throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
  }
  const jobRef = brandRef.collection("importJobs").doc(sourceImportJobID);
  const jobSnap = await jobRef.get();
  if (!jobSnap.exists) {
    throw new HttpsError("not-found", "source import job을 찾을 수 없습니다.");
  }
  const jobData = jobSnap.data() ?? {};
  if (jobData.jobType !== "importSeasonFromURL") {
    throw new HttpsError(
      "failed-precondition",
      "시즌 URL import job만 이미지 진단을 실행할 수 있습니다."
    );
  }
  const targetSeasonID =
    typeof jobData.targetSeasonID === "string" ?
      requiredDocumentID(jobData.targetSeasonID, "targetSeasonID") :
      null;
  if (
    seasonID !== null &&
    targetSeasonID !== null &&
    seasonID !== targetSeasonID
  ) {
    throw new HttpsError(
      "invalid-argument",
      "seasonID가 source import job의 시즌과 일치하지 않습니다."
    );
  }
  const sourceURL = normalizedHTTPURL(
    requiredString(jobData, "sourceURL", 2048),
    "sourceURL"
  );
  const importedImageCount = numericMetric(jobData.assetCompletedCount);
  const failedImageCount = numericMetric(jobData.assetFailedCount);
  const expectedImageCount = importedImageCount + failedImageCount;
  const status: LookbookExtractionDiagnosticStatus =
    failedImageCount > 0 ? "failed" : "passed";
  const nowDate = new Date();
  const now = admin.firestore.Timestamp.fromDate(nowDate);
  const expiresAt = diagnosticExpiresAt(nowDate);
  const diagnosticRef = lookbookDiagnosticCollection().doc();
  const seasonTitle =
    typeof jobData.sourceTitle === "string" ?
      jobData.sourceTitle.trim() :
      null;
  const summaryMessage =
    `이미지 ${expectedImageCount}개 중 ${failedImageCount}개 실패`;
  const documentData = {
    brandID,
    brandName:
      typeof brandSnap.data()?.name === "string" ?
        brandSnap.data()?.name :
        null,
    type: "season_image_import",
    status,
    phase: "completed",
    sourceURL,
    requestedBy: uid,
    failureReasons: failedImageCount > 0 ? ["image_load_failed"] : [],
    suggestedFixScope: failedImageCount > 0 ? "common_logic" : "unknown",
    suggestedFixes: failedImageCount > 0 ? [{
      type: "inspect_remote_image_failure",
      scope: "common_logic",
      confidence: 0.7,
      message: "원격 이미지 로드 실패 원인을 확인해야 합니다.",
    }] : [{
      type: "none",
      scope: "unknown",
      confidence: 1,
      message: "추가 조치가 필요하지 않습니다.",
    }],
    summaryMessage,
    errorMessage: failedImageCount > 0 ? summaryMessage : null,
    expiresAt,
    createdAt: now,
    updatedAt: now,
    completedAt: now,
    seasonDiscovery: null,
    seasonImageImport: {
      sourceImportJobID,
      targetSeasonID,
      seasonID: seasonID ?? targetSeasonID,
      seasonTitle,
      sourceURL,
      expectedImageCount,
      importedImageCount,
      failedImageCount,
      retryable: failedImageCount > 0 && targetSeasonID !== null,
    },
  };

  await diagnosticRef.set(documentData);
  await jobRef.update({
    lastImageImportDiagnosticID: diagnosticRef.id,
    lastImageImportDiagnosticStatus: status,
    lastImageImportDiagnosticAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return diagnosticSummary(diagnosticRef.id, documentData);
}


export const requestSeasonImport = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const seasonURL = normalizedHTTPURL(
      requiredString(data, "seasonURL", 2048),
      "seasonURL"
    );
    const sourceCandidateID = optionalDocumentID(
      optionalString(data, "sourceCandidateID", 128),
      "sourceCandidateID"
    );

    await assertBrandWriteAccess(uid, brandID);

    return requestSeasonImportJob(uid, brandID, seasonURL, sourceCandidateID);
  }
);

export const requestSeasonAssetRetry = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const sourceJobID = requiredDocumentID(
      requiredString(data, "sourceJobID", 128),
      "sourceJobID"
    );

    await assertBrandWriteAccess(uid, brandID);
    return requestSeasonAssetFailureRetry(uid, brandID, sourceJobID);
  }
);

export const requestSeasonCandidateImportJobs = onCall(
  {region: FUNCTIONS_REGION, timeoutSeconds: 120, memory: "512MiB"},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const candidateIDs = requiredDocumentIDList(
      data.candidateIDs,
      "candidateIDs",
      80
    );

    await assertBrandWriteAccess(uid, brandID);

    const brandRef = db.collection("brands").doc(brandID);
    const candidateRefs = candidateIDs.map((candidateID) => {
      return brandRef.collection("seasonCandidates").doc(candidateID);
    });
    const candidateSnapshots = await db.getAll(...candidateRefs);
    const failures: SeasonCandidateImportFailure[] = [];
    const targetBySeasonURL = new Map<string, SeasonCandidateImportTarget>();
    let duplicateWithinBatchCount = 0;

    candidateSnapshots.forEach((candidateSnapshot) => {
      const candidateID = candidateSnapshot.id;
      const candidateData = candidateSnapshot.data();
      const title = typeof candidateData?.title === "string" ?
        candidateData.title.trim() :
        null;

      if (!candidateSnapshot.exists || !candidateData) {
        failures.push({
          candidateID,
          title,
          errorMessage: "시즌 후보를 찾을 수 없습니다.",
        });
        return;
      }

      try {
        const seasonURL = normalizedHTTPURL(
          requiredString(candidateData, "seasonURL", 2048),
          "seasonCandidate.seasonURL"
        );
        if (targetBySeasonURL.has(seasonURL)) {
          duplicateWithinBatchCount += 1;
          return;
        }
        targetBySeasonURL.set(seasonURL, {
          candidateID,
          seasonURL,
          seed: seasonCandidateImportSeedFromData(candidateData),
        });
      } catch (error) {
        failures.push({
          candidateID,
          title,
          errorMessage: messageFromError(error),
        });
      }
    });

    const targets = Array.from(targetBySeasonURL.values());
    const creationResults = await mapWithConcurrency(
      targets,
      10,
      async (target): Promise<
        | {ok: true; receipt: SeasonImportJobReceipt}
        | {ok: false; failure: SeasonCandidateImportFailure}
      > => {
        try {
          return {
            ok: true,
            receipt: await createSeasonImportJobFromSeed(
              uid,
              brandID,
              target.seasonURL,
              target.candidateID,
              target.seed
            ),
          };
        } catch (error) {
          return {
            ok: false,
            failure: {
              candidateID: target.candidateID,
              title: target.seed.sourceTitle,
              errorMessage: messageFromError(error),
            },
          };
        }
      }
    );

    const receipts = creationResults
      .filter((result): result is {
        ok: true;
        receipt: SeasonImportJobReceipt;
      } => {
        return result.ok;
      })
      .map((result) => result.receipt);
    failures.push(
      ...creationResults
        .filter((result): result is {
          ok: false;
          failure: SeasonCandidateImportFailure;
        } => {
          return !result.ok;
        })
        .map((result) => result.failure)
    );

    const jobIDs = Array.from(
      new Set(receipts.map((receipt) => receipt.jobID))
    );
    return {
      brandID,
      candidateIDs,
      jobIDs,
      requestedJobCount: candidateIDs.length,
      createdJobCount: receipts.filter((receipt) => !receipt.duplicate).length,
      duplicateJobCount:
        receipts.filter((receipt) => receipt.duplicate).length +
        duplicateWithinBatchCount,
      requestedImportJobCount: receipts.length,
      failedJobCount: failures.length,
      skippedJobCount: duplicateWithinBatchCount,
      failedCandidates: failures,
    };
  }
);

export const runLookbookExtractionDiagnostic = onCall(
  {region: FUNCTIONS_REGION, timeoutSeconds: 120, memory: "512MiB"},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const type = requiredDiagnosticType(data.type);
    const sourceImportJobID = optionalDocumentID(
      optionalString(data, "sourceImportJobID", 128),
      "sourceImportJobID"
    );
    const seasonID = optionalDocumentID(
      optionalString(data, "seasonID", 128),
      "seasonID"
    );

    await assertBrandWriteAccess(uid, brandID);

    if (type === "season_discovery") {
      if (sourceImportJobID !== null || seasonID !== null) {
        throw new HttpsError(
          "invalid-argument",
          "시즌 목록 진단에는 sourceImportJobID와 seasonID를 보낼 수 없습니다."
        );
      }
      return {
        diagnostic: await runSeasonDiscoveryDiagnostic(uid, brandID),
      };
    }

    if (sourceImportJobID === null) {
      throw new HttpsError(
        "invalid-argument",
        "이미지 진단에는 sourceImportJobID가 필요합니다."
      );
    }
    return {
      diagnostic: await runSeasonImageImportDiagnostic(
        uid,
        brandID,
        sourceImportJobID,
        seasonID
      ),
    };
  }
);

export const getLatestLookbookExtractionDiagnostic = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const type = requiredDiagnosticType(data.type);
    const sourceImportJobID = optionalDocumentID(
      optionalString(data, "sourceImportJobID", 128),
      "sourceImportJobID"
    );

    await assertBrandWriteAccess(uid, brandID);

    let diagnosticID: string | null = null;
    if (type === "season_discovery") {
      if (sourceImportJobID !== null) {
        throw new HttpsError(
          "invalid-argument",
          "시즌 목록 진단 조회에는 sourceImportJobID를 보낼 수 없습니다."
        );
      }
      const brandSnap = await db.collection("brands").doc(brandID).get();
      const value = brandSnap.data()?.lastSeasonDiscoveryDiagnosticID;
      diagnosticID = typeof value === "string" ? value : null;
    } else {
      if (sourceImportJobID === null) {
        throw new HttpsError(
          "invalid-argument",
          "이미지 진단 조회에는 sourceImportJobID가 필요합니다."
        );
      }
      const jobSnap = await db
        .collection("brands")
        .doc(brandID)
        .collection("importJobs")
        .doc(sourceImportJobID)
        .get();
      if (!jobSnap.exists) {
        throw new HttpsError("not-found", "source import job을 찾을 수 없습니다.");
      }
      const value = jobSnap.data()?.lastImageImportDiagnosticID;
      diagnosticID = typeof value === "string" ? value : null;
    }

    if (diagnosticID === null) {
      return {diagnostic: null};
    }
    const diagnosticSnap = await lookbookDiagnosticCollection()
      .doc(diagnosticID)
      .get();
    if (!diagnosticSnap.exists) {
      return {diagnostic: null};
    }
    return {
      diagnostic: diagnosticSummary(
        diagnosticSnap.id,
        diagnosticSnap.data() ?? {}
      ),
    };
  }
);

export const onSeasonImportQueued = onDocumentWritten(
  {
    document: "brands/{brandID}/importJobs/{jobID}",
    region: FUNCTIONS_REGION,
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (event) => {
    const afterSnap = event.data?.after;
    if (!afterSnap?.exists) {
      return;
    }

    const before = event.data?.before.data() as
      Record<string, unknown> | undefined;
    const after = afterSnap.data() as Record<string, unknown> | undefined;
    if (!after) {
      return;
    }

    const shouldEnqueue =
      (
        after.jobType === "importSeasonFromURL" ||
        after.jobType === "retrySeasonAssets"
      ) &&
      after.status === "queued" &&
      (
        !before ||
        before.status !== "queued"
      );

    if (!shouldEnqueue) {
      return;
    }

    const brandID = String(event.params.brandID ?? "");
    const jobID = String(event.params.jobID ?? "");
    if (!brandID || !jobID) {
      return;
    }

    const receipt = await enqueueLookbookImportTask(brandID, jobID);
    await afterSnap.ref.set({
      phase: "dispatching",
      dispatchMode: "cloudTasks",
      dispatchStatus: receipt.alreadyExists ? "alreadyEnqueued" : "enqueued",
      taskName: receipt.taskName,
      taskEnqueuedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    console.log("[onSeasonImportQueued] task enqueued", {
      brandID,
      jobID,
      taskName: receipt.taskName,
      alreadyExists: receipt.alreadyExists,
    });
  }
);

export const discoverSeasonCandidates = onCall(
  {region: FUNCTIONS_REGION, timeoutSeconds: 60, memory: "512MiB"},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );

    await assertBrandWriteAccess(uid, brandID);

    const brandSnap = await db.collection("brands").doc(brandID).get();
    const brandData = brandSnap.data();
    const lookbookArchiveURLValue = brandData?.lookbookArchiveURL;
    if (
      typeof lookbookArchiveURLValue !== "string" ||
      lookbookArchiveURLValue.trim().length === 0
    ) {
      throw new HttpsError(
        "failed-precondition",
        "룩북 목록 URL이 등록되어 있지 않습니다."
      );
    }

    const lookbookArchiveURL = normalizedHTTPURL(
      lookbookArchiveURLValue,
      "lookbookArchiveURL"
    );

    return runDiscoverSeasonCandidates(db, brandID, lookbookArchiveURL);
  }
);

export const cleanupExpiredLookbookExtractionDiagnostics = onSchedule(
  {
    schedule: "30 4 * * *",
    region: FUNCTIONS_REGION,
    timeZone: "Asia/Seoul",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const snapshot = await lookbookDiagnosticCollection()
      .where("expiresAt", "<=", now)
      .limit(LOOKBOOK_EXTRACTION_DIAGNOSTIC_CLEANUP_LIMIT)
      .get();

    if (snapshot.empty) {
      console.log(
        "[cleanupExpiredLookbookExtractionDiagnostics] No expired diagnostics."
      );
      return;
    }

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    console.log("[cleanupExpiredLookbookExtractionDiagnostics] Completed", {
      deletedCount: snapshot.size,
    });
  }
);

// Start writing functions
// https://firebase.google.com/docs/functions/typescript

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.

// export const helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
