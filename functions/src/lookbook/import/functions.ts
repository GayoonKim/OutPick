/* eslint-disable require-jsdoc, valid-jsdoc, max-len */
import * as admin from "firebase-admin";
import {CloudTasksClient} from "@google-cloud/tasks";
import {createHash} from "node:crypto";
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
import {db, defaultStorageBucket} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {
  assertBrandWriteAccess,
} from "../../shared/brandAuthorization.js";
import {
  assertActivePlatformAdmin,
  hasActivePlatformAdminData,
  isActivePlatformAdmin,
} from "../../shared/platformAuthorization.js";
import {
  approvedCandidateKeys,
  nextGeneration,
  requiredReviewDecision,
} from "./reviewContract.js";
import {isExtractionFixRetryEligible} from "./extractionIssueContract.js";
import {
  extractionEvidenceCleanupTarget,
  extractionIssueClusterCleanupTarget,
} from "./evidenceCleanup.js";
import {admitImportFollowup} from "./queue/followup-admission.js";
import {admitSeasonRequest, seasonAdmissionError} from "./queue/season-admission.js";
import {admitDiscoveryRequest} from "./queue/discovery-admission.js";
import {isBatchQueueJob} from "./queue/authorization.js";

const LOOKBOOK_IMPORT_TASKS_LOCATION = "asia-northeast3";
const LOOKBOOK_IMPORT_TASKS_QUEUE = "lookbook-import-jobs";
const LOOKBOOK_IMPORT_TASK_ENDPOINT = "/tasks/import-job";
const LOOKBOOK_DISCOVERY_DIAGNOSTIC_ENDPOINT =
  "/tasks/discover-seasons-diagnostic";
const LOOKBOOK_IMPORT_TASK_MAX_ATTEMPTS = 3;
const LOOKBOOK_EXTRACTION_DIAGNOSTIC_RETENTION_DAYS = 60;
const LOOKBOOK_EXTRACTION_DIAGNOSTIC_CLEANUP_LIMIT = 100;
const LOOKBOOK_EXTRACTION_EVIDENCE_CLEANUP_LIMIT = 100;
const LOOKBOOK_EXTRACTION_ISSUE_CLUSTER_CLEANUP_LIMIT = 100;
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


function optionalDocumentIDList(
  value: unknown,
  fieldName: string,
  maxCount: number
): string[] {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value) || value.length > maxCount) {
    throw new HttpsError("invalid-argument", `${fieldName} 값이 올바르지 않습니다.`);
  }
  return Array.from(new Set(value.map((item) => {
    if (typeof item !== "string") {
      throw new HttpsError("invalid-argument", `${fieldName} 값이 올바르지 않습니다.`);
    }
    return requiredDocumentID(item, fieldName);
  })));
}

function nonNegativeIntegerValue(value: unknown, fallback: number): number {
  return Number.isInteger(value) && Number(value) >= 0 ?
    Number(value) :
    fallback;
}

function optionalNonNegativeIntegerValue(value: unknown): number | null {
  return Number.isInteger(value) && Number(value) >= 0 ? Number(value) : null;
}

function requiredNonNegativeIntegerValue(
  value: unknown,
  fieldName: string
): number {
  if (!Number.isInteger(value) || Number(value) < 0) {
    throw new HttpsError("invalid-argument", `${fieldName} 값이 올바르지 않습니다.`);
  }
  return Number(value);
}

export function blocksDuplicateSeasonImport(status: unknown): boolean {
  return (
    status === "queued" ||
    status === "processing" ||
    status === "awaitingReview" ||
    status === "succeeded" ||
    status === "partialFailed"
  );
}


export type LookbookImportTaskConfig = {
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
  coverImageSource: "list" | "detail" | "none";
  coverImageStrategy: string | null;
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
  coverImages: {
    coverImageCount: number;
    listCoverImageCount: number;
    detailCoverAttemptCount: number;
    detailCoverSuccessCount: number;
    detailCoverFailureCount: number;
    detailCoverSkippedCount: number;
  };
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

export function lookbookImportTaskConfig(): LookbookImportTaskConfig {
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
  jobID: string,
  dispatchGeneration = 0
): string {
  const encoded = Buffer
    .from(`${brandID}:${jobID}:${dispatchGeneration}`)
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
      coverImageSource: candidate.coverImageSource,
      coverImageStrategy: candidate.coverImageStrategy,
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
      coverImages: seasonDiscovery.coverImages ?? null,
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


async function enqueueLookbookImportTask(
  brandID: string,
  jobID: string,
  dispatchGeneration: number,
  reviewGeneration: number | null,
  reviewSnapshotHash: string | null
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
    deterministicImportTaskID(brandID, jobID, dispatchGeneration)
  );
  const payload = {
    brandID,
    jobID,
    dispatchGeneration,
    reviewGeneration,
    reviewSnapshotHash,
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
      coverImages: diagnostic.coverImages,
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
    try {
      return await admitSeasonRequest(db, uid, recordData(request.data), "url");
    } catch (error) {
      return seasonAdmissionError(error);
    }
  }
);

export const requestSeasonAssetRetry = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    try {
      return await admitSeasonRequest(db, uid, recordData(request.data), "assetRetry");
    } catch (error) {
      return seasonAdmissionError(error);
    }
  }
);

export const requestSeasonCandidateImportJobs = onCall(
  {region: FUNCTIONS_REGION, timeoutSeconds: 120, memory: "512MiB"},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    try {
      return await admitSeasonRequest(db, uid, recordData(request.data), "candidates");
    } catch (error) {
      return seasonAdmissionError(error);
    }
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

export const getLookbookExtractionReview = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const jobID = requiredDocumentID(
      requiredString(data, "jobID", 128),
      "jobID"
    );
    await assertActivePlatformAdmin(db, uid);
    const brandSnapshot = await db.collection("brands").doc(brandID).get();
    if (!brandSnapshot.exists || (brandSnapshot.data()?.deletionStatus &&
        brandSnapshot.data()?.deletionStatus !== "active")) {
      throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
    }
    const snapshot = await db
      .collection("brands")
      .doc(brandID)
      .collection("importJobs")
      .doc(jobID)
      .get();
    const job = snapshot.data();
    if (!snapshot.exists || !job) {
      throw new HttpsError("not-found", "검토할 import job을 찾을 수 없습니다.");
    }
    const candidateKeys = Array.isArray(job.reviewCandidateKeys) ?
      job.reviewCandidateKeys.filter((value): value is string =>
        typeof value === "string") :
      [];
    const imageCandidates = Array.isArray(job.imageCandidates) ?
      job.imageCandidates :
      [];
    const canRetryAfterFix = await isActivePlatformAdmin(db, uid) &&
      hasVerifiedExtractionRetryRuntime(job);
    return {
      jobID,
      brandID,
      status: job.status ?? null,
      reviewStatus: job.reviewStatus ?? null,
      reviewGeneration: nonNegativeIntegerValue(job.reviewGeneration, 0),
      reviewSnapshotHash: job.reviewSnapshotHash ?? null,
      qualityStatus: job.extractionQualityStatus ?? null,
      qualityReasons: job.extractionQualityReasons ?? [],
      expectedCountEvidence: job.expectedCountEvidence ?? [],
      templateSignature: job.templateSignature ?? null,
      extractionIssueStatus: job.extractionIssueStatus ?? null,
      retryAvailableRuntimeVersion: job.retryAvailableRuntimeVersion ?? null,
      extractionIssueWontFixReason: job.extractionIssueWontFixReason ?? null,
      canRetryAfterFix,
      candidates: imageCandidates.map((candidate, index) => {
        const item = candidate as Record<string, unknown>;
        return {
          candidateKey: candidateKeys[index] ?? null,
          sourceURL: typeof item.sourceURL === "string" ? item.sourceURL : null,
          alt: typeof item.alt === "string" ? item.alt : null,
        };
      }).filter((candidate) =>
        candidate.candidateKey !== null && candidate.sourceURL !== null),
    };
  }
);

export const reviewLookbookExtraction = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    if (data.decision === "approved" || data.decision === "approvedWithExclusions") {
      try {
        return await admitImportFollowup(db, uid, data, "reviewApproval");
      } catch (error) {
        return seasonAdmissionError(error);
      }
    }
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const jobID = requiredDocumentID(
      requiredString(data, "jobID", 128),
      "jobID"
    );
    const reviewGeneration = requiredNonNegativeIntegerValue(
      data.reviewGeneration,
      "reviewGeneration"
    );
    const reviewSnapshotHash = requiredString(
      data,
      "reviewSnapshotHash",
      128
    );
    let decision;
    try {
      decision = requiredReviewDecision(data.decision);
    } catch (error) {
      throw new HttpsError("invalid-argument", messageFromError(error));
    }
    const excludedCandidateKeys = optionalDocumentIDList(
      data.excludedCandidateKeys,
      "excludedCandidateKeys",
      240
    );
    const expectedCandidateCount = data.expectedCandidateCount === undefined ||
      data.expectedCandidateCount === null ?
      null :
      requiredNonNegativeIntegerValue(
        data.expectedCandidateCount,
        "expectedCandidateCount"
      );
    const note = optionalString(data, "note", 500);
    const brandRef = db.collection("brands").doc(brandID);
    const jobRef = db.collection("brands").doc(brandID)
      .collection("importJobs").doc(jobID);
    const reviewRef = jobRef.collection("reviews")
      .doc(String(reviewGeneration));
    const platformAdminRef = db.collection("platformAdmins").doc(uid);
    return db.runTransaction(async (transaction) => {
      const [brandSnapshot, jobSnapshot, existingReview, platformAdmin] = await Promise.all([
        transaction.get(brandRef),
        transaction.get(jobRef),
        transaction.get(reviewRef),
        transaction.get(platformAdminRef),
      ]);
      if (!hasActivePlatformAdminData(platformAdmin.data())) {
        throw new HttpsError("permission-denied", "플랫폼 관리자 권한이 필요합니다.");
      }
      if (!brandSnapshot.exists || (brandSnapshot.data()?.deletionStatus &&
          brandSnapshot.data()?.deletionStatus !== "active")) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }
      if (existingReview.exists) {
        const existing = existingReview.data() ?? {};
        if (
          existing.reviewSnapshotHash !== reviewSnapshotHash ||
          existing.decision !== decision
        ) {
          throw new HttpsError(
            "failed-precondition",
            "이미 다른 검토 결과로 확정된 generation입니다."
          );
        }
        return {
          jobID,
          reviewGeneration,
          decision,
          duplicate: true,
          status: existing.resultStatus ?? "awaitingReview",
        };
      }
      const job = jobSnapshot.data();
      if (!jobSnapshot.exists || !job) {
        throw new HttpsError("not-found", "검토할 import job을 찾을 수 없습니다.");
      }
      if (
        job.status !== "awaitingReview" ||
        nonNegativeIntegerValue(job.reviewGeneration, 0) !== reviewGeneration ||
        job.reviewSnapshotHash !== reviewSnapshotHash
      ) {
        throw new HttpsError(
          "failed-precondition",
          "검토 snapshot이 최신 상태가 아닙니다."
        );
      }
      const candidateKeys = Array.isArray(job.reviewCandidateKeys) ?
        job.reviewCandidateKeys.filter((value): value is string =>
          typeof value === "string") :
        [];
      let approvedKeys: string[];
      try {
        approvedKeys = approvedCandidateKeys({
          decision,
          candidateKeys,
          excludedCandidateKeys,
        });
      } catch (error) {
        throw new HttpsError("invalid-argument", messageFromError(error));
      }
      const issueFingerprint =
        typeof job.issueFingerprint === "string" &&
        /^[a-f0-9]{40}$/.test(job.issueFingerprint) ?
          job.issueFingerprint :
          null;
      const issueClusterRef = decision === "insufficientImages" &&
        issueFingerprint !== null ?
        db.collection("lookbookExtractionIssueClusters")
          .doc(issueFingerprint) :
        null;
      const issueClusterSnapshot = issueClusterRef === null ?
        null :
        await transaction.get(issueClusterRef);
      const now = FieldValue.serverTimestamp();
      const resultStatus = decision === "insufficientImages" ?
        "awaitingReview" :
        "queued";
      transaction.set(reviewRef, {
        brandID,
        jobID,
        reviewGeneration,
        reviewSnapshotHash,
        decision,
        positiveCandidateKeys: approvedKeys,
        negativeCandidateKeys: excludedCandidateKeys,
        expectedCandidateCount,
        note,
        qualityStatus: job.extractionQualityStatus ?? null,
        qualityReasons: job.extractionQualityReasons ?? [],
        templateSignature: job.templateSignature ?? null,
        imageExtractorVersion: job.imageExtractorVersion ?? null,
        platformAdapterKey: job.platformAdapterKey ?? null,
        platformAdapterVersion: job.platformAdapterVersion ?? null,
        domainAdapterKey: job.domainAdapterKey ?? null,
        domainAdapterVersion: job.domainAdapterVersion ?? null,
        issueFingerprint,
        reviewedBy: uid,
        reviewedAt: now,
        resultStatus,
      });
      if (decision === "insufficientImages") {
        transaction.update(jobRef, {
          reviewStatus: "correctionRequired",
          adminExpectedCandidateCount: expectedCandidateCount,
          reviewedBy: uid,
          reviewedAt: now,
          updatedAt: now,
        });
        if (issueClusterRef !== null && issueClusterSnapshot?.exists) {
          const issueCluster = issueClusterSnapshot.data() ?? {};
          const existingCounts = Array.isArray(
            issueCluster.adminExpectedCandidateCounts
          ) ?
            issueCluster.adminExpectedCandidateCounts.filter(
              (value): value is number =>
                typeof value === "number" && Number.isInteger(value)
            ) :
            [];
          const adminExpectedCandidateCounts =
            expectedCandidateCount === null ?
              existingCounts :
              Array.from(new Set([
                ...existingCounts,
                expectedCandidateCount,
              ])).sort((left, right) => left - right).slice(-20);
          transaction.update(issueClusterRef, {
            adminFeedbackCount:
              numericMetric(issueCluster.adminFeedbackCount) + 1,
            adminExpectedCandidateCounts,
            lastAdminFeedbackAt: now,
            updatedAt: now,
          });
        }
      } else {
        const dispatchGeneration = nextGeneration(job.dispatchGeneration);
        transaction.update(jobRef, {
          status: "queued",
          phase: "dispatching",
          resumeFrom: "materializing",
          reviewStatus: "approved",
          approvedCandidateKeys: approvedKeys,
          dispatchGeneration,
          reviewedBy: uid,
          reviewedAt: now,
          leaseOwner: null,
          leaseExpiresAt: null,
          updatedAt: now,
        });
        if (
          decision === "approved" &&
          job.trustEligible === true &&
          typeof job.trustBaselineID === "string" &&
          /^[a-f0-9]{40}$/.test(job.trustBaselineID)
        ) {
          transaction.set(
            db.collection("lookbookExtractionTrustBaselines")
              .doc(job.trustBaselineID),
            {
              isActive: true,
              brandID,
              sourceHost: new URL(String(job.sourceURL)).hostname.toLowerCase(),
              templateSignature: job.templateSignature ?? null,
              imageExtractorVersion: job.imageExtractorVersion ?? null,
              platformAdapterKey: job.platformAdapterKey ?? null,
              platformAdapterVersion: job.platformAdapterVersion ?? null,
              domainAdapterKey: job.domainAdapterKey ?? null,
              domainAdapterVersion: job.domainAdapterVersion ?? null,
              approvedBy: uid,
              approvedAt: now,
              sourceImportJobID: jobID,
              updatedAt: now,
            },
            {merge: true}
          );
        }
      }
      return {
        jobID,
        reviewGeneration,
        decision,
        duplicate: false,
        status: resultStatus,
      };
    });
  }
);

export const retryLookbookExtractionAfterFix = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    try {
      return await admitImportFollowup(db, uid, recordData(request.data), "manualRetry");
    } catch (error) {
      return seasonAdmissionError(error);
    }
  }
);

function hasVerifiedExtractionRetryRuntime(job: Record<string, unknown>): boolean {
  return isExtractionFixRetryEligible({
    issueStatus: job.extractionIssueStatus,
    blockedRuntimeVersion: job.blockedRuntimeVersion,
    retryAvailableRuntimeVersion: job.retryAvailableRuntimeVersion,
    stage: "seasonImageImport",
  });
}

export const requestLookbookSeasonRepair = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    try {
      return await admitImportFollowup(db, uid, recordData(request.data), "repairAnalyze");
    } catch (error) {
      return seasonAdmissionError(error);
    }
  }
);

export const previewLookbookSeasonRepair = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const jobID = requiredDocumentID(
      requiredString(data, "jobID", 128),
      "jobID"
    );
    await assertActivePlatformAdmin(db, uid);
    const brandSnapshot = await db.collection("brands").doc(brandID).get();
    if (!brandSnapshot.exists || (brandSnapshot.data()?.deletionStatus &&
        brandSnapshot.data()?.deletionStatus !== "active")) {
      throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
    }
    const jobRef = db.collection("brands").doc(brandID)
      .collection("importJobs").doc(jobID);
    const jobSnapshot = await jobRef.get();
    const job = jobSnapshot.data();
    if (!jobSnapshot.exists || !job) {
      throw new HttpsError("not-found", "시즌 보수 job을 찾을 수 없습니다.");
    }
    const repairGeneration = nonNegativeIntegerValue(
      job.repairGeneration,
      0
    );
    if (
      (
        job.repairStatus !== "previewReady" &&
        job.repairStatus !== "noChanges"
      ) ||
      repairGeneration <= 0 ||
      typeof job.repairSnapshotHash !== "string"
    ) {
      throw new HttpsError(
        "failed-precondition",
        "시즌 보수 미리보기를 준비하고 있습니다."
      );
    }
    const repairSnapshot = await jobRef.collection("repairs")
      .doc(String(repairGeneration))
      .get();
    const repair = repairSnapshot.data();
    if (!repairSnapshot.exists || !repair) {
      throw new HttpsError("not-found", "시즌 보수 미리보기가 없습니다.");
    }
    return {
      jobID,
      brandID,
      seasonID: repair.seasonID,
      repairGeneration,
      repairSnapshotHash: repair.repairSnapshotHash,
      status: repair.status,
      keep: repair.keep ?? [],
      add: repair.add ?? [],
      reorder: repair.reorder ?? [],
      removeCandidates: repair.removeCandidates ?? [],
      resultingPostCount: repair.resultingPostCount ?? 0,
    };
  }
);

export const applyLookbookSeasonRepair = onCall(
  {region: FUNCTIONS_REGION, timeoutSeconds: 120, memory: "512MiB"},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    try {
      return await admitImportFollowup(db, uid, recordData(request.data), "repairApply");
    } catch (error) {
      return seasonAdmissionError(error);
    }
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
    if (!after || isBatchQueueJob(after)) {
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

    const dispatchGeneration = nonNegativeIntegerValue(
      after.dispatchGeneration,
      0
    );
    const reviewGeneration = optionalNonNegativeIntegerValue(
      after.reviewGeneration
    );
    const reviewSnapshotHash = typeof after.reviewSnapshotHash === "string" ?
      after.reviewSnapshotHash :
      null;
    const receipt = await enqueueLookbookImportTask(
      brandID,
      jobID,
      dispatchGeneration,
      reviewGeneration,
      reviewSnapshotHash
    );
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
    try {
      return await admitDiscoveryRequest(db, uid,
        {...recordData(request.data), requestReason: "manualRefresh"}, "request");
    } catch (error) {
      return seasonAdmissionError(error);
    }
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

export const cleanupExpiredLookbookExtractionEvidence = onSchedule(
  {
    schedule: "45 4 * * *",
    region: FUNCTIONS_REGION,
    timeZone: "Asia/Seoul",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const snapshot = await db.collection("lookbookExtractionEvidence")
      .where("expiresAt", "<=", now)
      .limit(LOOKBOOK_EXTRACTION_EVIDENCE_CLEANUP_LIMIT)
      .get();
    if (snapshot.empty) {
      console.log(
        "[cleanupExpiredLookbookExtractionEvidence] No expired evidence."
      );
    }

    const targets = snapshot.docs.map((document) => ({
      document,
      target: extractionEvidenceCleanupTarget({
        evidenceID: document.id,
        storagePath: document.data().storagePath,
      }),
    }));
    const results = await mapWithConcurrency(targets, 10, async (item) => {
      if (item.target === null) {
        console.error(
          "[cleanupExpiredLookbookExtractionEvidence] Invalid storage path",
          {evidenceID: item.document.id}
        );
        return {document: item.document, deleted: false};
      }
      try {
        await defaultStorageBucket()
          .file(item.target.storagePath)
          .delete({ignoreNotFound: true});
        return {document: item.document, deleted: true};
      } catch (error) {
        console.error(
          "[cleanupExpiredLookbookExtractionEvidence] Storage delete failed",
          {
            evidenceID: item.document.id,
            errorMessage: messageFromError(error),
          }
        );
        return {document: item.document, deleted: false};
      }
    });
    const deleted = results.filter((result) => result.deleted);
    if (deleted.length > 0) {
      const batch = db.batch();
      deleted.forEach((result) => batch.delete(result.document.ref));
      await batch.commit();
    }
    console.log("[cleanupExpiredLookbookExtractionEvidence] Completed", {
      candidateCount: snapshot.size,
      deletedCount: deleted.length,
    });

    const clusterSnapshot = await db
      .collection("lookbookExtractionIssueClusters")
      .where("expiresAt", "<=", now)
      .limit(LOOKBOOK_EXTRACTION_ISSUE_CLUSTER_CLEANUP_LIMIT)
      .get();
    const clusterTargets = clusterSnapshot.docs.map((document) => ({
      document,
      target: extractionIssueClusterCleanupTarget({
        fingerprint: document.id,
        representativeEvidenceID: document.data().representativeEvidenceID,
        representativeStoragePath:
          document.data().representativeEvidenceStoragePath,
      }),
    }));
    const clusterResults = await mapWithConcurrency(
      clusterTargets,
      10,
      async (item) => {
        if (item.target === null) {
          console.error(
            "[cleanupExpiredLookbookExtractionEvidence] Invalid cluster storage path",
            {fingerprint: item.document.id}
          );
          return {document: item.document, deleted: false};
        }
        try {
          await defaultStorageBucket()
            .file(item.target.representativeStoragePath)
            .delete({ignoreNotFound: true});
          return {document: item.document, deleted: true};
        } catch (error) {
          console.error(
            "[cleanupExpiredLookbookExtractionEvidence] Cluster storage delete failed",
            {
              fingerprint: item.document.id,
              errorMessage: messageFromError(error),
            }
          );
          return {document: item.document, deleted: false};
        }
      }
    );
    const deletedClusters = clusterResults.filter((result) => result.deleted);
    if (deletedClusters.length > 0) {
      const batch = db.batch();
      deletedClusters.forEach((result) => batch.delete(result.document.ref));
      await batch.commit();
    }
    console.log("[cleanupExpiredLookbookExtractionEvidence] Cluster cleanup completed", {
      candidateCount: clusterSnapshot.size,
      deletedCount: deletedClusters.length,
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
