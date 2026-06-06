/* eslint-disable require-jsdoc, valid-jsdoc */
/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

import {setGlobalOptions} from "firebase-functions";
// import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

import {CloudTasksClient} from "@google-cloud/tasks";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  onDocumentUpdated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {
  processNextSeasonImportJob as runNextSeasonImportJob,
  processSeasonImportJobs as runSeasonImportJobs,
} from "./lookbookImportWorker.js";
import {
  createSeasonContentFromImportJobs as runCreateSeasonContentFromImportJobs,
} from "./lookbookImportMaterializer.js";
import {
  syncSeasonImportAssetsForJob as runSyncSeasonImportAssetsForJob,
} from "./lookbookAssetSyncWorker.js";
import {
  discoverSeasonCandidates as runDiscoverSeasonCandidates,
} from "./lookbookSeasonCandidateDiscovery.js";

admin.initializeApp();
const db = getFirestore();
setGlobalOptions({maxInstances: 10});
const FUNCTIONS_REGION = "asia-northeast3";
const LOOKBOOK_IMPORT_TASKS_LOCATION = "asia-northeast3";
const LOOKBOOK_IMPORT_TASKS_QUEUE = "lookbook-import-jobs";
const LOOKBOOK_IMPORT_TASK_ENDPOINT = "/tasks/import-job";
const LOOKBOOK_IMPORT_TASK_MAX_ATTEMPTS = 3;

let cloudTasksClient: CloudTasksClient | null = null;

interface KakaoAccessTokenInfoResponse {
  id?: number;
}

interface KakaoMeResponse {
  id?: number;
  kakao_account?: {
    email?: string;
  };
}

/**
 * Ensures callable payload is a plain object.
 */
function recordData(data: unknown): Record<string, unknown> {
  if (data === null || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "요청 데이터가 올바르지 않습니다.");
  }
  return data as Record<string, unknown>;
}

/**
 * Reads a required trimmed string from callable payload.
 */
function requiredString(
  data: Record<string, unknown>,
  key: string,
  maxLength: number
): string {
  const value = data[key];
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${key} 값이 필요합니다.`);
  }

  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > maxLength) {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  return trimmed;
}

/**
 * Reads an optional trimmed string from callable payload.
 */
function optionalString(
  data: Record<string, unknown>,
  key: string,
  maxLength: number
): string | null {
  const value = data[key];
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }

  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return null;
  }
  if (trimmed.length > maxLength) {
    throw new HttpsError("invalid-argument", `${key} 값이 너무 깁니다.`);
  }
  return trimmed;
}

function requiredBoolean(
  data: Record<string, unknown>,
  key: string
): boolean {
  const value = data[key];
  if (typeof value !== "boolean") {
    throw new HttpsError("invalid-argument", `${key} 값이 필요합니다.`);
  }
  return value;
}

/**
 * Extracts Firebase Auth uid from an authenticated callable request.
 */
function requiredAuthUID(uid: string | undefined): string {
  if (!uid) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  }
  return uid;
}

function requiredDocumentID(rawValue: string, fieldName: string): string {
  const value = rawValue.trim();
  if (value.length === 0 || value.includes("/")) {
    throw new HttpsError("invalid-argument", `${fieldName} 값이 올바르지 않습니다.`);
  }
  return value;
}

function optionalDocumentID(
  rawValue: string | null,
  fieldName: string
): string | null {
  if (rawValue === null) {
    return null;
  }
  return requiredDocumentID(rawValue, fieldName);
}

function postStateDocumentID(
  brandID: string,
  seasonID: string,
  postID: string
): string {
  return `${brandID}_${seasonID}_${postID}`;
}

function seasonStateDocumentID(
  brandID: string,
  seasonID: string
): string {
  return `${brandID}_${seasonID}`;
}

function commentStateDocumentID(
  brandID: string,
  seasonID: string,
  postID: string,
  commentID: string
): string {
  return `${brandID}_${seasonID}_${postID}_${commentID}`;
}

function lookbookPostDocument(
  brandID: string,
  seasonID: string,
  postID: string
): FirebaseFirestore.DocumentReference {
  return db
    .collection("brands")
    .doc(brandID)
    .collection("seasons")
    .doc(seasonID)
    .collection("posts")
    .doc(postID);
}

function commentReportDocumentID(
  reporterUserID: string,
  targetType: string,
  brandID: string,
  seasonID: string,
  postID: string,
  commentID: string
): string {
  return [
    reporterUserID,
    targetType,
    brandID,
    seasonID,
    postID,
    commentID,
  ].join("__");
}

function hasBrandWriteAccessData(
  uid: string,
  data: FirebaseFirestore.DocumentData | undefined
): boolean {
  const ownerUIDs = stringList(data?.ownerUIDs);
  const adminUIDs = stringList(data?.adminUIDs);
  return ownerUIDs.includes(uid) || adminUIDs.includes(uid);
}

function numericMetric(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return 0;
  }
  return Math.max(0, Math.floor(value));
}

function numericRootValue(
  data: FirebaseFirestore.DocumentData | undefined,
  key: string
): number {
  return numericMetric(data?.[key]);
}

function postMetrics(data: FirebaseFirestore.DocumentData | undefined): {
  likeCount: number;
  commentCount: number;
  replacementCount: number;
  saveCount: number;
  viewCount: number;
} {
  const metrics =
    data?.metrics &&
    typeof data.metrics === "object" &&
    !Array.isArray(data.metrics) ?
      data.metrics as Record<string, unknown> :
      {};

  return {
    likeCount: numericMetric(metrics.likeCount),
    commentCount: numericMetric(metrics.commentCount),
    replacementCount: numericMetric(metrics.replacementCount),
    saveCount: numericMetric(metrics.saveCount),
    viewCount: numericMetric(metrics.viewCount),
  };
}

function canonicalBrandName(rawName: string): string {
  return rawName
    .normalize("NFKC")
    .trim()
    .replace(/\s+/g, " ");
}

function normalizedBrandName(rawName: string): string {
  const normalized = canonicalBrandName(rawName).toLocaleLowerCase();
  if (normalized.length === 0) {
    throw new HttpsError("invalid-argument", "name 값이 올바르지 않습니다.");
  }
  return normalized;
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

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((item) => typeof item === "string")
    .map((item) => item.trim())
    .filter((item) => item.length > 0) as string[];
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

function blocksDuplicateSeasonImport(status: unknown): boolean {
  return (
    status === "queued" ||
    status === "processing" ||
    status === "succeeded" ||
    status === "partialFailed"
  );
}

function isInFlightSeasonImportStatus(status: unknown): boolean {
  return (
    status === "queued" ||
    status === "processing"
  );
}

/**
 * Ensures client uploaded logo paths belong to the requested brand.
 */
function validateBrandLogoPath(
  brandID: string,
  path: string | null,
  fileName: "thumb.jpg" | "detail.jpg"
): void {
  if (path === null) {
    return;
  }

  const expected = `brands/${brandID}/logo/${fileName}`;
  if (path !== expected) {
    throw new HttpsError(
      "invalid-argument",
      `${fileName} 경로가 brandID와 일치하지 않습니다.`
    );
  }
}

type SeasonCandidateImportSeed = {
  sourceTitle: string | null;
  coverRemoteURL: string | null;
  sourceSortIndex: number | null;
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

function deterministicImportTaskID(brandID: string, jobID: string): string {
  const encoded = Buffer
    .from(`${brandID}:${jobID}`)
    .toString("base64url");
  return `import-${encoded}`.slice(0, 500);
}

function isAlreadyExistsError(error: unknown): boolean {
  const code = (error as {code?: unknown})?.code;
  return code === 6 || code === "ALREADY_EXISTS";
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

async function requestSeasonImportJob(
  uid: string,
  brandID: string,
  seasonURL: string,
  sourceCandidateID: string | null
): Promise<{
  jobID: string;
  brandID: string;
  status: string;
  seasonURL: string;
  sourceCandidateID: string | null;
  duplicate: boolean;
}> {
  const brandRef = db.collection("brands").doc(brandID);
  const importJobsRef = brandRef.collection("importJobs");
  const jobRef = importJobsRef.doc();

  const candidateSeed = await seasonCandidateImportSeed(
    brandRef,
    sourceCandidateID,
    seasonURL
  );

  return db.runTransaction(async (transaction) => {
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
  });
}

async function requestSeasonAssetRetryJob(
  uid: string,
  brandID: string,
  sourceJobID: string
): Promise<{
  jobID: string;
  brandID: string;
  status: string;
  sourceImportJobID: string;
  duplicate: boolean;
}> {
  const brandRef = db.collection("brands").doc(brandID);
  const importJobsRef = brandRef.collection("importJobs");
  const sourceJobRef = importJobsRef.doc(sourceJobID);
  const retryJobRef = importJobsRef.doc();

  return db.runTransaction(async (transaction) => {
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
    const sourceURL = normalizedHTTPURL(
      requiredString(sourceJob, "sourceURL", 2048),
      "sourceURL"
    );
    const createdPostIDs = requiredDocumentIDList(
      sourceJob.createdPostIDs,
      "createdPostIDs",
      120
    );

    const existingSnapshot = await transaction.get(
      importJobsRef.where("sourceImportJobID", "==", sourceJobID)
    );
    const activeDuplicate = existingSnapshot.docs.find((snapshot) => {
      const job = snapshot.data();
      return (
        job.jobType === "retrySeasonAssets" &&
        isInFlightSeasonImportStatus(job.status)
      );
    });
    if (activeDuplicate) {
      return {
        jobID: activeDuplicate.id,
        brandID,
        status: String(activeDuplicate.data().status ?? "queued"),
        sourceImportJobID: sourceJobID,
        duplicate: true,
      };
    }

    transaction.set(retryJobRef, {
      brandID,
      jobType: "retrySeasonAssets",
      status: "queued",
      phase: "dispatching",
      dispatchMode: "cloudTasks",
      sourceImportJobID: sourceJobID,
      sourceURL,
      targetSeasonID,
      createdPostIDs,
      requestedBy: uid,
      errorMessage: null,
      assetTotalCount: Number(sourceJob.assetTotalCount ?? 0),
      assetCompletedCount: Number(sourceJob.assetCompletedCount ?? 0),
      assetFailedCount: Number(sourceJob.assetFailedCount ?? 0),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      jobID: retryJobRef.id,
      brandID,
      status: "queued",
      sourceImportJobID: sourceJobID,
      duplicate: false,
    };
  });
}

/**
 * Checks whether the caller can create new brands.
 */
async function assertBrandCreationAccess(uid: string): Promise<void> {
  const capabilities = await brandAdminCapabilities(uid);
  if (!capabilities.exists) {
    throw new HttpsError("permission-denied", "브랜드 관리자 권한이 없습니다.");
  }
  if (!capabilities.canCreateBrands) {
    throw new HttpsError("permission-denied", "브랜드 생성 권한이 없습니다.");
  }
}

/**
 * Checks whether the caller can modify the target brand.
 */
async function assertBrandWriteAccess(
  uid: string,
  brandID: string
): Promise<void> {
  const brandRef = db.collection("brands").doc(brandID);
  const brandSnap = await brandRef.get();

  if (!brandSnap.exists) {
    throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
  }

  const data = brandSnap.data();
  const ownerUIDs = stringList(data?.ownerUIDs);
  const adminUIDs = stringList(data?.adminUIDs);
  const hasAccess = ownerUIDs.includes(uid) || adminUIDs.includes(uid);

  if (!hasAccess) {
    throw new HttpsError("permission-denied", "브랜드 수정 권한이 없습니다.");
  }
}

/**
 * Returns the brand admin capability summary for a Firebase Auth uid.
 */
async function brandAdminCapabilities(uid: string): Promise<{
  exists: boolean;
  canCreateBrands: boolean;
  roles: string[];
}> {
  const adminRef = db.collection("brandAdmins").doc(uid);
  const adminSnap = await adminRef.get();
  if (!adminSnap.exists) {
    return {
      exists: false,
      canCreateBrands: false,
      roles: [],
    };
  }

  const data = adminSnap.data();
  const roles = stringList(data?.roles);

  const canCreateBrands =
    data?.isActive === true &&
    (
      data?.canCreateBrands === true ||
      roles.includes("brandCreator") ||
      roles.includes("owner")
    );

  return {
    exists: true,
    canCreateBrands,
    roles,
  };
}

/**
 * Calls Kakao API with the provided access token and parses JSON.
 */
async function fetchKakaoJSON<T>(
  url: string,
  accessToken: string
): Promise<T> {
  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (!response.ok) {
    throw new HttpsError("unauthenticated", "Kakao 토큰 검증에 실패했습니다.");
  }

  return await response.json() as T;
}

export const exchangeKakaoToken = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    try {
      const data = recordData(request.data);
      const accessToken = requiredString(data, "accessToken", 4096);

      const tokenInfo = await fetchKakaoJSON<KakaoAccessTokenInfoResponse>(
        "https://kapi.kakao.com/v1/user/access_token_info",
        accessToken
      );
      const me = await fetchKakaoJSON<KakaoMeResponse>(
        "https://kapi.kakao.com/v2/user/me",
        accessToken
      );

      const kakaoID = me.id ?? tokenInfo.id;
      if (!kakaoID || (tokenInfo.id && tokenInfo.id !== kakaoID)) {
        throw new HttpsError(
          "unauthenticated",
          "Kakao 사용자 식별에 실패했습니다."
        );
      }

      const providerUserID = String(kakaoID);
      const identityKey = `kakao:${providerUserID}`;
      const email = me.kakao_account?.email?.trim().toLowerCase() || null;

      const firebaseCustomToken = await admin.auth().createCustomToken(
        identityKey,
        {
          provider: "kakao",
          providerUserID,
        }
      );

      return {
        firebaseCustomToken,
        identityKey,
        provider: "kakao",
        providerUserID,
        email,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      console.error("[exchangeKakaoToken] unexpected error", error);
      throw new HttpsError(
        "internal",
        "Kakao Firebase token exchange failed.",
        {
          message: error instanceof Error ? error.message : String(error),
        }
      );
    }
  }
);

export const getBrandAdminCapabilities = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const capabilities = await brandAdminCapabilities(uid);

    return {
      canCreateBrands: capabilities.canCreateBrands,
      roles: capabilities.roles,
    };
  }
);

export const createBrand = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const name = canonicalBrandName(requiredString(data, "name", 80));
    const normalizedName = normalizedBrandName(name);
    const isFeatured = data.isFeatured === true;
    const websiteURLInput = optionalString(data, "websiteURL", 2048);
    const websiteURL = websiteURLInput ?
      normalizedHTTPURL(websiteURLInput, "websiteURL") :
      null;
    const lookbookArchiveURLInput = optionalString(
      data,
      "lookbookArchiveURL",
      2048
    );
    const lookbookArchiveURL = lookbookArchiveURLInput ?
      normalizedHTTPURL(lookbookArchiveURLInput, "lookbookArchiveURL") :
      null;

    await assertBrandCreationAccess(uid);

    const brandRef = db.collection("brands").doc();
    const brandID = brandRef.id;
    const nameIndexRef = db.collection("brandNameIndex").doc(normalizedName);

    await db.runTransaction(async (transaction) => {
      const nameIndexSnap = await transaction.get(nameIndexRef);
      if (nameIndexSnap.exists) {
        throw new HttpsError("already-exists", "이미 존재하는 브랜드명입니다.");
      }

      transaction.set(brandRef, {
        name,
        normalizedName,
        websiteURL,
        lookbookArchiveURL,
        logoPath: null,
        logoThumbPath: null,
        logoDetailPath: null,
        logoOriginalPath: null,
        isFeatured,
        discoveryStatus: "idle",
        lastDiscoveryErrorMessage: null,
        lastDiscoveryRequestedAt: null,
        lastDiscoveryCompletedAt: null,
        likeCount: 0,
        viewCount: 0,
        popularScore: 0,
        createdBy: uid,
        updatedBy: uid,
        ownerUIDs: [uid],
        adminUIDs: [],
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      transaction.set(nameIndexRef, {
        brandID,
        name,
        normalizedName,
        createdBy: uid,
        createdAt: FieldValue.serverTimestamp(),
      });
    });

    return {brandID};
  }
);

export const updateBrandLogoPaths = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const logoThumbPath = optionalString(data, "logoThumbPath", 512);
    const logoDetailPath = optionalString(data, "logoDetailPath", 512);

    if (logoThumbPath === null && logoDetailPath === null) {
      throw new HttpsError(
        "invalid-argument",
        "업데이트할 로고 경로가 없습니다."
      );
    }

    validateBrandLogoPath(brandID, logoThumbPath, "thumb.jpg");
    validateBrandLogoPath(brandID, logoDetailPath, "detail.jpg");

    await assertBrandWriteAccess(uid, brandID);

    const patch: Record<string, unknown> = {
      updatedBy: uid,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (logoThumbPath !== null) {
      patch.logoPath = logoThumbPath;
      patch.logoThumbPath = logoThumbPath;
    }
    if (logoDetailPath !== null) {
      patch.logoDetailPath = logoDetailPath;
    }

    await db.collection("brands").doc(brandID).update(patch);

    return {brandID};
  }
);

export const setBrandEngagement = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const isLiked = requiredBoolean(data, "isLiked");

    const brandRef = db.collection("brands").doc(brandID);
    const userStateRef = db
      .collection("users")
      .doc(uid)
      .collection("brandStates")
      .doc(brandID);

    return await db.runTransaction(async (transaction) => {
      const brandSnap = await transaction.get(brandRef);
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }

      const stateSnap = await transaction.get(userStateRef);
      const currentLiked = stateSnap.exists;
      const currentLikeCount = numericRootValue(brandSnap.data(), "likeCount");
      const likeDelta =
        currentLiked === isLiked ? 0 :
          isLiked ? 1 : -1;
      const nextLikeCount = Math.max(0, currentLikeCount + likeDelta);
      const now = FieldValue.serverTimestamp();

      if (likeDelta !== 0) {
        transaction.update(brandRef, {
          likeCount: nextLikeCount,
          updatedAt: now,
        });
      }

      if (isLiked) {
        transaction.set(userStateRef, {
          brandID,
          likedAt: now,
        }, {merge: true});
      } else if (stateSnap.exists) {
        transaction.delete(userStateRef);
      }

      return {
        brandID,
        userID: uid,
        isLiked,
        likeCount: nextLikeCount,
      };
    });
  }
);

export const setPostEngagement = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const seasonID = requiredDocumentID(
      requiredString(data, "seasonID", 128),
      "seasonID"
    );
    const postID = requiredDocumentID(
      requiredString(data, "postID", 128),
      "postID"
    );
    const kind = requiredString(data, "kind", 16);
    const isEnabled = requiredBoolean(data, "isEnabled");

    if (kind !== "like" && kind !== "save") {
      throw new HttpsError("invalid-argument", "kind 값이 올바르지 않습니다.");
    }

    const postRef = db
      .collection("brands")
      .doc(brandID)
      .collection("seasons")
      .doc(seasonID)
      .collection("posts")
      .doc(postID);
    const userStateRef = db
      .collection("users")
      .doc(uid)
      .collection("postStates")
      .doc(postStateDocumentID(brandID, seasonID, postID));

    return await db.runTransaction(async (transaction) => {
      const postSnap = await transaction.get(postRef);
      if (!postSnap.exists) {
        throw new HttpsError("not-found", "포스트를 찾을 수 없습니다.");
      }

      const stateSnap = await transaction.get(userStateRef);
      const stateData = stateSnap.data();
      const metrics = postMetrics(postSnap.data());
      const currentLiked = stateData?.isLiked === true;
      const currentSaved = stateData?.isSaved === true;
      let nextLiked = currentLiked;
      let nextSaved = currentSaved;
      let likeDelta = 0;
      let saveDelta = 0;

      if (kind === "like" && currentLiked !== isEnabled) {
        nextLiked = isEnabled;
        likeDelta = isEnabled ? 1 : -1;
      }
      if (kind === "save" && currentSaved !== isEnabled) {
        nextSaved = isEnabled;
        saveDelta = isEnabled ? 1 : -1;
      }

      const nextMetrics = {
        ...metrics,
        likeCount: Math.max(0, metrics.likeCount + likeDelta),
        saveCount: Math.max(0, metrics.saveCount + saveDelta),
      };

      if (likeDelta !== 0 || saveDelta !== 0) {
        transaction.update(postRef, {
          "metrics.likeCount": nextMetrics.likeCount,
          "metrics.saveCount": nextMetrics.saveCount,
          "metricsUpdatedAt": FieldValue.serverTimestamp(),
        });
      }

      if (nextLiked || nextSaved) {
        const statePatch: Record<string, unknown> = {
          brandID,
          seasonID,
          postID,
          postPath: postRef.path,
          userID: uid,
          isLiked: nextLiked,
          isSaved: nextSaved,
          updatedAt: FieldValue.serverTimestamp(),
        };

        if (kind === "like") {
          statePatch.likedAt = nextLiked ?
            FieldValue.serverTimestamp() :
            null;
        }
        if (kind === "save") {
          statePatch.savedAt = nextSaved ?
            FieldValue.serverTimestamp() :
            null;
        }

        transaction.set(userStateRef, statePatch, {merge: true});
      } else if (stateSnap.exists) {
        transaction.delete(userStateRef);
      }

      return {
        postID,
        userID: uid,
        isLiked: nextLiked,
        isSaved: nextSaved,
        metrics: nextMetrics,
      };
    });
  }
);

export const setSeasonEngagement = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const seasonID = requiredDocumentID(
      requiredString(data, "seasonID", 128),
      "seasonID"
    );
    const isLiked = requiredBoolean(data, "isLiked");

    const seasonRef = db
      .collection("brands")
      .doc(brandID)
      .collection("seasons")
      .doc(seasonID);
    const userStateRef = db
      .collection("users")
      .doc(uid)
      .collection("seasonStates")
      .doc(seasonStateDocumentID(brandID, seasonID));

    return await db.runTransaction(async (transaction) => {
      const seasonSnap = await transaction.get(seasonRef);
      if (!seasonSnap.exists) {
        throw new HttpsError("not-found", "시즌을 찾을 수 없습니다.");
      }

      const stateSnap = await transaction.get(userStateRef);
      const currentLiked = stateSnap.exists;
      const currentLikeCount = numericRootValue(seasonSnap.data(), "likeCount");
      const likeDelta =
        currentLiked === isLiked ? 0 :
          isLiked ? 1 : -1;
      const nextLikeCount = Math.max(0, currentLikeCount + likeDelta);
      const now = FieldValue.serverTimestamp();

      if (likeDelta !== 0) {
        transaction.update(seasonRef, {
          likeCount: nextLikeCount,
          updatedAt: now,
        });
      }

      if (isLiked) {
        transaction.set(userStateRef, {
          brandID,
          seasonID,
          seasonPath: seasonRef.path,
          userID: uid,
          isLiked,
          likedAt: now,
          updatedAt: now,
        }, {merge: true});
      } else if (stateSnap.exists) {
        transaction.delete(userStateRef);
      }

      return {
        brandID,
        seasonID,
        userID: uid,
        isLiked,
        likeCount: nextLikeCount,
      };
    });
  }
);

export const setCommentEngagement = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const seasonID = requiredDocumentID(
      requiredString(data, "seasonID", 128),
      "seasonID"
    );
    const postID = requiredDocumentID(
      requiredString(data, "postID", 128),
      "postID"
    );
    const commentID = requiredDocumentID(
      requiredString(data, "commentID", 128),
      "commentID"
    );
    const isLiked = requiredBoolean(data, "isLiked");

    const postRef = lookbookPostDocument(brandID, seasonID, postID);
    const commentRef = postRef.collection("comments").doc(commentID);
    const userStateRef = db
      .collection("users")
      .doc(uid)
      .collection("commentStates")
      .doc(commentStateDocumentID(brandID, seasonID, postID, commentID));

    return await db.runTransaction(async (transaction) => {
      const postSnap = await transaction.get(postRef);
      if (!postSnap.exists) {
        throw new HttpsError("not-found", "포스트를 찾을 수 없습니다.");
      }

      const commentSnap = await transaction.get(commentRef);
      if (!commentSnap.exists) {
        throw new HttpsError("not-found", "댓글을 찾을 수 없습니다.");
      }

      const commentData = commentSnap.data();
      if (commentData?.isDeleted === true) {
        throw new HttpsError(
          "failed-precondition",
          "삭제된 댓글에는 좋아요를 누를 수 없습니다."
        );
      }

      const stateSnap = await transaction.get(userStateRef);
      const currentLiked = stateSnap.data()?.isLiked === true;
      const currentLikeCount = numericRootValue(commentData, "likeCount");
      const likeDelta =
        currentLiked === isLiked ? 0 :
          isLiked ? 1 : -1;
      const nextLikeCount = Math.max(0, currentLikeCount + likeDelta);
      const parentCommentID =
        typeof commentData?.parentCommentID === "string" ?
          commentData.parentCommentID :
          null;
      const now = FieldValue.serverTimestamp();

      if (likeDelta !== 0) {
        transaction.update(commentRef, {
          likeCount: nextLikeCount,
          updatedAt: now,
        });
      }

      if (isLiked) {
        transaction.set(userStateRef, {
          brandID,
          seasonID,
          postID,
          commentID,
          commentPath: commentRef.path,
          userID: uid,
          parentCommentID,
          isLiked: true,
          likedAt: now,
          updatedAt: now,
        }, {merge: true});
      } else if (stateSnap.exists) {
        transaction.delete(userStateRef);
      }

      return {
        brandID,
        seasonID,
        postID,
        commentID,
        userID: uid,
        parentCommentID,
        isLiked,
        likeCount: nextLikeCount,
      };
    });
  }
);

export const createComment = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const seasonID = requiredDocumentID(
      requiredString(data, "seasonID", 128),
      "seasonID"
    );
    const postID = requiredDocumentID(
      requiredString(data, "postID", 128),
      "postID"
    );
    const message = requiredString(data, "message", 1000);

    const postRef = lookbookPostDocument(brandID, seasonID, postID);
    const commentRef = postRef.collection("comments").doc();

    return await db.runTransaction(async (transaction) => {
      const postSnap = await transaction.get(postRef);
      if (!postSnap.exists) {
        throw new HttpsError("not-found", "포스트를 찾을 수 없습니다.");
      }

      const metrics = postMetrics(postSnap.data());
      const nextCommentCount = metrics.commentCount + 1;
      const now = FieldValue.serverTimestamp();

      transaction.set(commentRef, {
        postID,
        userID: uid,
        createdBy: uid,
        message,
        createdAt: now,
        updatedAt: now,
        isDeleted: false,
        likeCount: 0,
        replyCount: 0,
        isPinned: false,
        pinnedAt: null,
        pinnedBy: null,
        parentCommentID: null,
        attachments: [],
      });
      transaction.update(postRef, {
        "metrics.commentCount": nextCommentCount,
        "metricsUpdatedAt": now,
      });

      return {
        brandID,
        seasonID,
        postID,
        commentID: commentRef.id,
        userID: uid,
        parentCommentID: null,
        commentCount: nextCommentCount,
        replyCount: 0,
      };
    });
  }
);

export const createReply = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const seasonID = requiredDocumentID(
      requiredString(data, "seasonID", 128),
      "seasonID"
    );
    const postID = requiredDocumentID(
      requiredString(data, "postID", 128),
      "postID"
    );
    const parentCommentID = requiredDocumentID(
      requiredString(data, "parentCommentID", 128),
      "parentCommentID"
    );
    const message = requiredString(data, "message", 1000);

    const postRef = lookbookPostDocument(brandID, seasonID, postID);
    const parentCommentRef = postRef
      .collection("comments")
      .doc(parentCommentID);
    const replyRef = postRef.collection("comments").doc();

    return await db.runTransaction(async (transaction) => {
      const postSnap = await transaction.get(postRef);
      if (!postSnap.exists) {
        throw new HttpsError("not-found", "포스트를 찾을 수 없습니다.");
      }

      const parentSnap = await transaction.get(parentCommentRef);
      if (!parentSnap.exists) {
        throw new HttpsError("not-found", "원댓글을 찾을 수 없습니다.");
      }

      const parentData = parentSnap.data();
      if (parentData?.isDeleted === true) {
        throw new HttpsError("failed-precondition", "삭제된 댓글에는 답글을 달 수 없습니다.");
      }
      if (parentData?.parentCommentID !== null &&
        parentData?.parentCommentID !== undefined) {
        throw new HttpsError("failed-precondition", "답글에는 다시 답글을 달 수 없습니다.");
      }

      const metrics = postMetrics(postSnap.data());
      const currentReplyCount = numericRootValue(parentData, "replyCount");
      const nextCommentCount = metrics.commentCount + 1;
      const nextReplyCount = currentReplyCount + 1;
      const now = FieldValue.serverTimestamp();

      transaction.set(replyRef, {
        postID,
        userID: uid,
        createdBy: uid,
        message,
        createdAt: now,
        updatedAt: now,
        isDeleted: false,
        likeCount: 0,
        replyCount: 0,
        isPinned: false,
        pinnedAt: null,
        pinnedBy: null,
        parentCommentID,
        attachments: [],
      });
      transaction.update(parentCommentRef, {
        replyCount: nextReplyCount,
        updatedAt: now,
      });
      transaction.update(postRef, {
        "metrics.commentCount": nextCommentCount,
        "metricsUpdatedAt": now,
      });

      return {
        brandID,
        seasonID,
        postID,
        commentID: replyRef.id,
        userID: uid,
        parentCommentID,
        commentCount: nextCommentCount,
        replyCount: nextReplyCount,
      };
    });
  }
);

export const deleteComment = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const seasonID = requiredDocumentID(
      requiredString(data, "seasonID", 128),
      "seasonID"
    );
    const postID = requiredDocumentID(
      requiredString(data, "postID", 128),
      "postID"
    );
    const commentID = requiredDocumentID(
      requiredString(data, "commentID", 128),
      "commentID"
    );
    const reason = optionalString(data, "reason", 500);

    const brandRef = db.collection("brands").doc(brandID);
    const postRef = lookbookPostDocument(brandID, seasonID, postID);
    const commentRef = postRef.collection("comments").doc(commentID);
    const deletionLogRef = db.collection("commentDeletionLogs").doc();

    return await db.runTransaction(async (transaction) => {
      const brandSnap = await transaction.get(brandRef);
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }

      const postSnap = await transaction.get(postRef);
      if (!postSnap.exists) {
        throw new HttpsError("not-found", "포스트를 찾을 수 없습니다.");
      }

      const commentSnap = await transaction.get(commentRef);
      if (!commentSnap.exists) {
        throw new HttpsError("not-found", "댓글을 찾을 수 없습니다.");
      }

      const commentData = commentSnap.data();
      const authorID =
        typeof commentData?.userID === "string" ?
          commentData.userID :
          typeof commentData?.createdBy === "string" ?
            commentData.createdBy :
            "";
      if (authorID.length === 0) {
        throw new HttpsError("failed-precondition", "댓글 작성자 정보가 없습니다.");
      }

      const canDelete =
        authorID === uid || hasBrandWriteAccessData(uid, brandSnap.data());
      if (!canDelete) {
        throw new HttpsError("permission-denied", "댓글 삭제 권한이 없습니다.");
      }

      const parentCommentID =
        typeof commentData?.parentCommentID === "string" ?
          commentData.parentCommentID :
          null;
      const isReply = parentCommentID !== null;
      let deletedReplyCount = 0;

      if (isReply) {
        const parentRef = postRef.collection("comments").doc(parentCommentID);
        const parentSnap = await transaction.get(parentRef);
        if (parentSnap.exists) {
          const nextReplyCount = Math.max(
            0,
            numericRootValue(parentSnap.data(), "replyCount") - 1
          );
          transaction.update(parentRef, {
            replyCount: nextReplyCount,
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
      } else {
        const repliesSnap = await transaction.get(
          postRef
            .collection("comments")
            .where("parentCommentID", "==", commentID)
        );
        if (repliesSnap.size > 400) {
          throw new HttpsError(
            "resource-exhausted",
            "답글이 많은 댓글은 운영자 처리가 필요합니다."
          );
        }
        deletedReplyCount = repliesSnap.size;
        for (const replyDoc of repliesSnap.docs) {
          transaction.delete(replyDoc.ref);
        }
      }

      const metrics = postMetrics(postSnap.data());
      const deletedCommentCount = 1 + deletedReplyCount;
      const nextCommentCount = Math.max(
        0,
        metrics.commentCount - deletedCommentCount
      );
      const now = FieldValue.serverTimestamp();

      transaction.delete(commentRef);
      transaction.update(postRef, {
        "metrics.commentCount": nextCommentCount,
        "metricsUpdatedAt": now,
      });
      transaction.create(deletionLogRef, {
        logID: deletionLogRef.id,
        brandID,
        seasonID,
        postID,
        commentID,
        parentCommentID,
        targetType: isReply ? "reply" : "comment",
        deletedBy: uid,
        authorID,
        deletedReplyCount,
        deletedCommentCount,
        reason,
        messageSnapshot:
          typeof commentData?.message === "string" ?
            commentData.message.slice(0, 1000) :
            null,
        createdAtSnapshot: commentData?.createdAt ?? null,
        deletedAt: now,
      });

      return {
        brandID,
        seasonID,
        postID,
        commentID,
        userID: uid,
        parentCommentID,
        targetType: isReply ? "reply" : "comment",
        deletedReplyCount,
        deletedCommentCount,
        commentCount: nextCommentCount,
        replyCount: isReply ? 0 : deletedReplyCount,
      };
    });
  }
);

export const reportComment = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const reporterUserID = requiredDocumentID(
      requiredString(data, "reporterUserID", 128),
      "reporterUserID"
    );
    const targetType = requiredString(data, "targetType", 16);
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const seasonID = requiredDocumentID(
      requiredString(data, "seasonID", 128),
      "seasonID"
    );
    const postID = requiredDocumentID(
      requiredString(data, "postID", 128),
      "postID"
    );
    const commentID = requiredDocumentID(
      requiredString(data, "commentID", 128),
      "commentID"
    );
    const parentCommentID = optionalDocumentID(
      optionalString(data, "parentCommentID", 128),
      "parentCommentID"
    );
    const reason = requiredString(data, "reason", 64);
    const detail = optionalString(data, "detail", 500);
    const authorNicknameSnapshot = optionalString(
      data,
      "targetAuthorNicknameSnapshot",
      80
    );

    if (reporterUserID !== uid) {
      throw new HttpsError("permission-denied", "신고자 정보가 올바르지 않습니다.");
    }
    if (targetType !== "comment" && targetType !== "reply") {
      throw new HttpsError("invalid-argument", "targetType 값이 올바르지 않습니다.");
    }

    const postRef = lookbookPostDocument(brandID, seasonID, postID);
    const targetRef = postRef.collection("comments").doc(commentID);
    const reportID = commentReportDocumentID(
      uid,
      targetType,
      brandID,
      seasonID,
      postID,
      commentID
    );
    const reportRef = db.collection("commentReports").doc(reportID);
    const createdAtMillis = Date.now();

    return await db.runTransaction(async (transaction) => {
      const reportSnap = await transaction.get(reportRef);
      if (reportSnap.exists) {
        throw new HttpsError("already-exists", "이미 신고한 댓글입니다.");
      }

      const postSnap = await transaction.get(postRef);
      if (!postSnap.exists) {
        throw new HttpsError("not-found", "포스트를 찾을 수 없습니다.");
      }

      const targetSnap = await transaction.get(targetRef);
      if (!targetSnap.exists) {
        throw new HttpsError("not-found", "신고 대상을 찾을 수 없습니다.");
      }

      const targetData = targetSnap.data();
      if (targetData?.isDeleted === true) {
        throw new HttpsError("failed-precondition", "삭제된 댓글은 신고할 수 없습니다.");
      }

      const storedParentCommentID =
        typeof targetData?.parentCommentID === "string" ?
          targetData.parentCommentID :
          null;
      if (targetType === "comment" && storedParentCommentID !== null) {
        throw new HttpsError("invalid-argument", "신고 대상 유형이 올바르지 않습니다.");
      }
      if (targetType === "reply" && storedParentCommentID === null) {
        throw new HttpsError("invalid-argument", "신고 대상 유형이 올바르지 않습니다.");
      }
      if (parentCommentID !== storedParentCommentID) {
        throw new HttpsError(
          "invalid-argument",
          "parentCommentID 값이 올바르지 않습니다."
        );
      }

      const targetAuthorID =
        typeof targetData?.userID === "string" ?
          targetData.userID :
          typeof targetData?.createdBy === "string" ?
            targetData.createdBy :
            "";
      if (targetAuthorID.length === 0) {
        throw new HttpsError("failed-precondition", "댓글 작성자 정보가 없습니다.");
      }
      if (targetAuthorID === uid) {
        throw new HttpsError("failed-precondition", "본인 댓글은 신고할 수 없습니다.");
      }

      const targetContentSnapshot =
        typeof targetData?.message === "string" ?
          targetData.message.slice(0, 1000) :
          "";
      if (targetContentSnapshot.trim().length === 0) {
        throw new HttpsError("failed-precondition", "신고 대상 내용이 없습니다.");
      }

      const now = FieldValue.serverTimestamp();
      transaction.create(reportRef, {
        reportID,
        reporterUserID: uid,
        targetAuthorID,
        targetType,
        targetCommentID: commentID,
        parentCommentID: storedParentCommentID,
        brandID,
        seasonID,
        postID,
        reason,
        detail,
        targetContentSnapshot,
        targetAuthorNicknameSnapshot: authorNicknameSnapshot,
        status: "pending",
        createdAt: now,
        updatedAt: now,
      });

      return {
        reportID,
        reporterUserID: uid,
        targetAuthorID,
        targetType,
        targetCommentID: commentID,
        parentCommentID: storedParentCommentID,
        brandID,
        seasonID,
        postID,
        reason,
        detail,
        targetContentSnapshot,
        targetAuthorNicknameSnapshot: authorNicknameSnapshot,
        status: "pending",
        createdAtMillis,
      };
    });
  }
);

export const blockUser = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const blockerUserID = requiredDocumentID(
      requiredString(data, "blockerUserID", 128),
      "blockerUserID"
    );
    const blockedUserID = requiredDocumentID(
      requiredString(data, "blockedUserID", 128),
      "blockedUserID"
    );
    const blockedUserNicknameSnapshot = optionalString(
      data,
      "blockedUserNicknameSnapshot",
      80
    );
    const source = requiredString(data, "source", 16);

    if (blockerUserID !== uid) {
      throw new HttpsError("permission-denied", "차단 요청자 정보가 올바르지 않습니다.");
    }
    if (blockedUserID === uid) {
      throw new HttpsError("failed-precondition", "본인은 차단할 수 없습니다.");
    }
    if (source !== "comment" && source !== "reply" && source !== "profile") {
      throw new HttpsError("invalid-argument", "source 값이 올바르지 않습니다.");
    }

    const createdAtMillis = Date.now();
    const now = FieldValue.serverTimestamp();
    await db
      .collection("users")
      .doc(uid)
      .collection("blockedUsers")
      .doc(blockedUserID)
      .set(
        {
          blockerUserID: uid,
          blockedUserID,
          blockedUserNicknameSnapshot,
          source,
          createdAt: now,
          updatedAt: now,
        },
        {merge: true}
      );

    return {
      blockerUserID: uid,
      blockedUserID,
      blockedUserNicknameSnapshot,
      source,
      createdAtMillis,
    };
  }
);

export const loadHiddenCommentUserIDs = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const currentUserID = requiredDocumentID(
      requiredString(data, "currentUserID", 128),
      "currentUserID"
    );

    if (currentUserID !== uid) {
      throw new HttpsError("permission-denied", "사용자 정보가 올바르지 않습니다.");
    }

    const blockedByMeSnapshot = await db
      .collection("users")
      .doc(uid)
      .collection("blockedUsers")
      .get();
    const blockedByMeIDs = blockedByMeSnapshot.docs.map((doc) => doc.id);

    const blockingMeSnapshot = await db
      .collectionGroup("blockedUsers")
      .where("blockedUserID", "==", uid)
      .get();
    const blockingMeIDs = blockingMeSnapshot.docs
      .map((doc) => doc.data().blockerUserID)
      .filter(
        (value): value is string =>
          typeof value === "string" && value.length > 0
      );

    return {
      hiddenUserIDs: Array.from(new Set([...blockedByMeIDs, ...blockingMeIDs])),
    };
  }
);

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
    return requestSeasonAssetRetryJob(uid, brandID, sourceJobID);
  }
);

export const processNextSeasonImportJob = onCall(
  {region: FUNCTIONS_REGION, timeoutSeconds: 60, memory: "512MiB"},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );

    await assertBrandWriteAccess(uid, brandID);

    return runNextSeasonImportJob(db, brandID);
  }
);

export const processSeasonImportJobs = onCall(
  {region: FUNCTIONS_REGION, timeoutSeconds: 120, memory: "512MiB"},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const jobIDs = requiredDocumentIDList(data.jobIDs, "jobIDs", 80);

    await assertBrandWriteAccess(uid, brandID);

    return runSeasonImportJobs(db, brandID, jobIDs, 3);
  }
);

export const requestSeasonCandidateImportsAndProcess = onCall(
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

    const receipts: Array<{
      jobID: string;
      brandID: string;
      status: string;
      seasonURL: string;
      sourceCandidateID: string | null;
      duplicate: boolean;
    }> = [];

    for (const candidateSnapshot of candidateSnapshots) {
      if (!candidateSnapshot.exists) {
        throw new HttpsError("not-found", "시즌 후보를 찾을 수 없습니다.");
      }

      const candidateData = candidateSnapshot.data();
      const seasonURL = normalizedHTTPURL(
        requiredString(candidateData ?? {}, "seasonURL", 2048),
        "seasonCandidate.seasonURL"
      );

      const receipt = await requestSeasonImportJob(
        uid,
        brandID,
        seasonURL,
        candidateSnapshot.id
      );
      receipts.push(receipt);
    }

    const jobIDs = Array.from(
      new Set(receipts.map((receipt) => receipt.jobID))
    );
    return {
      brandID,
      candidateIDs,
      jobIDs,
      requestedJobCount: receipts.length,
      duplicateJobCount: receipts.filter((receipt) => receipt.duplicate).length,
      processedJobCount: 0,
      failedJobCount: 0,
      skippedJobCount: 0,
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

export const createSeasonContentFromImportJobs = onCall(
  {region: FUNCTIONS_REGION, timeoutSeconds: 120, memory: "512MiB"},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const jobIDs = requiredDocumentIDList(data.jobIDs, "jobIDs", 80);

    await assertBrandWriteAccess(uid, brandID);

    return runCreateSeasonContentFromImportJobs(db, brandID, jobIDs, 3);
  }
);

export const onSeasonImportParsed = onDocumentUpdated(
  {
    document: "brands/{brandID}/importJobs/{jobID}",
    region: FUNCTIONS_REGION,
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (event) => {
    const beforeSnap = event.data?.before;
    const afterSnap = event.data?.after;

    if (!beforeSnap || !afterSnap) {
      return;
    }

    const before = beforeSnap.data() as Record<string, unknown> | undefined;
    const after = afterSnap.data() as Record<string, unknown> | undefined;
    if (!before || !after) {
      return;
    }

    const shouldStart =
      after.jobType === "importSeasonFromURL" &&
      after.dispatchMode !== "cloudTasks" &&
      after.processingEngine !== "cloudRunWorker" &&
      after.status === "parsed" &&
      before.status !== "parsed" &&
      before.status !== "success" &&
      after.contentStatus !== "creating" &&
      after.contentStatus !== "created";

    if (!shouldStart) {
      return;
    }

    const brandID = String(event.params.brandID ?? "");
    const jobID = String(event.params.jobID ?? "");
    if (!brandID || !jobID) {
      return;
    }

    const result = await runCreateSeasonContentFromImportJobs(
      db,
      brandID,
      [jobID],
      1
    );
    console.log("[onSeasonImportParsed] materialize result", result);
  }
);

export const onSeasonImportContentCreated = onDocumentUpdated(
  {
    document: "brands/{brandID}/importJobs/{jobID}",
    region: FUNCTIONS_REGION,
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (event) => {
    const beforeSnap = event.data?.before;
    const afterSnap = event.data?.after;

    if (!beforeSnap || !afterSnap) {
      return;
    }

    const before = beforeSnap.data() as Record<string, unknown> | undefined;
    const after = afterSnap.data() as Record<string, unknown> | undefined;
    if (!before || !after) {
      return;
    }

    const shouldStart =
      after.jobType === "importSeasonFromURL" &&
      after.dispatchMode !== "cloudTasks" &&
      after.processingEngine !== "cloudRunWorker" &&
      after.status === "success" &&
      after.contentStatus === "created" &&
      after.assetSyncStatus === "pending" &&
      (
        before.contentStatus !== "created" ||
        before.assetSyncStatus !== "pending"
      );

    if (!shouldStart) {
      return;
    }

    const brandID = String(event.params.brandID ?? "");
    const jobID = String(event.params.jobID ?? "");
    if (!brandID || !jobID) {
      return;
    }

    const result = await runSyncSeasonImportAssetsForJob(db, brandID, jobID);
    console.log("[onSeasonImportContentCreated] asset sync result", result);
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

export const onRoomClosed = onDocumentUpdated(
  {
    document: "Rooms/{roomId}",
    region: FUNCTIONS_REGION,
  },
  async (event) => {
    const beforeSnap = event.data?.before;
    const afterSnap = event.data?.after;

    if (!beforeSnap || !afterSnap) {
      console.log(
        "[onRoomClosed] No before/after snapshot. Skip."
      );
      return;
    }

    interface RoomDoc {
      isClosed?: boolean;
      participantIDs?: string[];
    }

    const before = beforeSnap.data() as RoomDoc | undefined;
    const after = afterSnap.data() as RoomDoc | undefined;

    if (!before || !after) {
      console.log("[onRoomClosed] Empty data. Skip.");
      return;
    }

    // 1) isClosed 가 false -> true 로 바뀐 경우만 처리
    const beforeClosed = !!before.isClosed;
    const afterClosed = !!after.isClosed;

    if (beforeClosed === true || afterClosed !== true) {
      console.log(
        "[onRoomClosed] isClosed did not change " +
          "from false to true. Skip.",
        {beforeClosed, afterClosed}
      );
      return;
    }

    const roomId = event.params.roomId as string;
    const participantIDs: string[] =
        Array.isArray(after.participantIDs) ?
          after.participantIDs :
          [];

    console.log(
      `[onRoomClosed] Room ${roomId} closed. participants = ` +
        `${participantIDs.length}`
    );

    // 2) joinedRooms 에서 roomId 제거
    if (participantIDs.length > 0) {
      const BATCH_LIMIT = 500; // Firestore 배치 write 제한
      const IN_QUERY_LIMIT = 30; // Firestore where-in 제한

      for (let i = 0; i < participantIDs.length; i += BATCH_LIMIT) {
        const slice = participantIDs.slice(i, i + BATCH_LIMIT);
        const batch = db.batch();

        const normalizedSlice = Array.from(
          new Set(
            slice
              .map((email) => email.trim().toLowerCase())
              .filter((email) => email.length > 0)
          )
        );

        let updatedUsers = 0;
        for (let j = 0; j < normalizedSlice.length; j += IN_QUERY_LIMIT) {
          const emailChunk = normalizedSlice.slice(j, j + IN_QUERY_LIMIT);
          const usersSnap = await db
            .collection("users")
            .where("email", "in", emailChunk)
            .get();

          for (const userDoc of usersSnap.docs) {
            batch.update(userDoc.ref, {
              joinedRooms: FieldValue.arrayRemove(roomId),
            });
            updatedUsers += 1;
          }
        }

        console.log(
          "[onRoomClosed] Committing batch for " +
            `${updatedUsers} users (roomId=${roomId})`
        );
        if (updatedUsers > 0) {
          await batch.commit();
        }
      }
    } else {
      console.log(
        "[onRoomClosed] No participants. " +
          "Skipping joinedRooms cleanup."
      );
    }

    // 3) 마지막으로 Rooms/{roomId} 문서 삭제
    try {
      await db.collection("Rooms").doc(roomId).delete();
      console.log(
        `[onRoomClosed] Room document deleted: ${roomId}`
      );
    } catch (err) {
      console.error(
        "[onRoomClosed] Failed to delete room " +
          `${roomId} after cleanup`,
        err
      );
      // 필요하면 여기서 throw 해서 재시도 유도 가능
      // throw err;
    }
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
// });
