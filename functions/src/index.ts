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
import {createHash, randomUUID} from "node:crypto";

import {CloudTasksClient} from "@google-cloud/tasks";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  onDocumentUpdated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
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
const LOOKBOOK_ASSET_RETRY_MODE = "assetFailureRetry";
const MEDIA_UPLOAD_CLEANUP_LIMIT = 100;

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
  data: FirebaseFirestore.DocumentData | undefined
): boolean {
  const role = typeof data?.role === "string" ? data.role : "";
  return role === "owner" || role === "admin";
}

function isBrandOwnerData(
  data: FirebaseFirestore.DocumentData | undefined
): boolean {
  return data?.role === "owner";
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

type AssetFailureRetryReceipt = {
  sourceImportJobID: string;
  seasonID: string;
  status: string;
  duplicate: boolean;
  requestID: string;
  taskName: string | null;
};

type BrandRequestStatus = "submitted" | "reviewing" | "added" | "rejected";

type BrandRequestAdminStage =
  "requested" |
  "completed" |
  "processing" |
  "rejected";

type BrandRequestRejectionReason =
  "unavailable" |
  "spam" |
  "other";

type BrandRequestUserListScope = "active" | "history";

type BrandManagerRole = "owner" | "admin";
type LookbookDeletionTargetType = "brand" | "season" | "post";
type LookbookDeletionRequestStatus =
  "active" |
  "cancelled" |
  "restored" |
  "purged" |
  "failed";
type LookbookDeletionAction =
  "requestBrandDeletion" |
  "cancelBrandDeletion" |
  "softDeleteSeason" |
  "restoreSeason" |
  "softDeletePost" |
  "restorePost" |
  "purgeBrand" |
  "purgeSeason" |
  "purgePost" |
  "purgeFailed";

const BRAND_REQUEST_ADMIN_STAGES: BrandRequestAdminStage[] = [
  "requested",
  "processing",
  "completed",
  "rejected",
];

const BRAND_REQUEST_STAGE_UPDATE_TARGETS: BrandRequestAdminStage[] = [
  "requested",
  "rejected",
  "processing",
];

const BRAND_REQUEST_DAILY_LIMIT = 5;
const BRAND_REQUEST_COUNTER_TTL_DAYS = 90;
const BRAND_REQUEST_USER_VISIBLE_DAYS = 14;
const BRAND_REQUEST_DEFAULT_USER_LIMIT = 20;
const BRAND_REQUEST_MAX_USER_LIMIT = 50;
const BRAND_REQUEST_DEFAULT_ADMIN_LIMIT = 50;
const BRAND_REQUEST_MAX_ADMIN_LIMIT = 100;
const BRAND_REQUEST_TIME_ZONE = "Asia/Seoul";
const BRAND_SEARCH_DEFAULT_LIMIT = 20;
const BRAND_SEARCH_MAX_LIMIT = 30;
const LOOKBOOK_DELETION_RETENTION_DAYS = 7;
const LOOKBOOK_DELETION_DEFAULT_LIMIT = 50;
const LOOKBOOK_DELETION_MAX_LIMIT = 100;
const LOOKBOOK_DELETION_BATCH_MAX_COUNT = 20;
const LOOKBOOK_DELETION_BATCH_CONCURRENCY = 3;
const LOOKBOOK_PURGE_TARGET_LIMIT = 20;
const LOOKBOOK_PURGE_RETRY_LIMIT = 3;
const LOOKBOOK_PURGE_RETRY_DELAY_HOURS = 24;
const LOOKBOOK_PURGE_PAGE_SIZE = 200;
const LOOKBOOK_PURGE_STORAGE_PREFIX_CONCURRENCY = 3;

function normalizedEmail(rawValue: string): string {
  const email = rawValue.trim().toLocaleLowerCase();
  if (
    email.length === 0 ||
    email.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  ) {
    throw new HttpsError("invalid-argument", "email 값이 올바르지 않습니다.");
  }
  return email;
}

function requiredBrandManagerRole(rawValue: string): BrandManagerRole {
  const role = rawValue.trim() as BrandManagerRole;
  if (role !== "owner" && role !== "admin") {
    throw new HttpsError("invalid-argument", "role 값이 올바르지 않습니다.");
  }
  return role;
}

function optionalHTTPURLPatch(
  data: Record<string, unknown>,
  key: string
): string | null | undefined {
  if (!Object.prototype.hasOwnProperty.call(data, key)) {
    return undefined;
  }
  const rawValue = optionalString(data, key, 2048);
  if (rawValue === null) {
    return null;
  }
  return normalizedHTTPURL(rawValue, key);
}

function hasBooleanPatch(
  data: Record<string, unknown>,
  key: string
): boolean {
  return Object.prototype.hasOwnProperty.call(data, key);
}

function positiveInteger(
  data: Record<string, unknown>,
  key: string,
  defaultValue: number,
  maxValue: number
): number {
  const value = data[key];
  if (value === undefined || value === null) {
    return defaultValue;
  }
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  const integer = Math.floor(value);
  if (integer <= 0) {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  return Math.min(integer, maxValue);
}

function optionalTimestampFromISO(
  data: Record<string, unknown>,
  key: string
): admin.firestore.Timestamp | null {
  const value = data[key];
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  return admin.firestore.Timestamp.fromDate(date);
}

function dateKeyKST(now: Date): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: BRAND_REQUEST_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);

  const byType = new Map(parts.map((part) => [part.type, part.value]));
  return `${byType.get("year")}${byType.get("month")}${byType.get("day")}`;
}

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function brandRequestDocumentID(
  uid: string,
  normalizedName: string
): string {
  const hash = createHash("sha256")
    .update(normalizedName)
    .digest("hex")
    .slice(0, 24);
  return `${uid}_${hash}`;
}

function brandRequestNameIndexID(normalizedName: string): string {
  return createHash("sha256")
    .update(normalizedName)
    .digest("hex")
    .slice(0, 32);
}

function brandRequestDedupeKey(
  normalizedName: string,
  normalizedEnglishName: string | null
): {
  dedupeKey: string;
  dedupeKeySource: "englishBrandName" | "brandName";
} {
  if (normalizedEnglishName !== null) {
    return {
      dedupeKey: normalizedEnglishName,
      dedupeKeySource: "englishBrandName",
    };
  }

  return {
    dedupeKey: normalizedName,
    dedupeKeySource: "brandName",
  };
}

function requestStatusForAdminStage(
  adminStage: BrandRequestAdminStage
): BrandRequestStatus {
  switch (adminStage) {
  case "requested":
    return "submitted";
  case "processing":
    return "reviewing";
  case "completed":
    return "added";
  case "rejected":
    return "rejected";
  }
}

function requiredAdminStage(
  rawValue: string,
  allowedStages: BrandRequestAdminStage[]
): BrandRequestAdminStage {
  const value = rawValue.trim() as BrandRequestAdminStage;
  if (!allowedStages.includes(value)) {
    throw new HttpsError("invalid-argument", "adminStage 값이 올바르지 않습니다.");
  }
  return value;
}

function optionalAdminStage(
  data: Record<string, unknown>,
  key: string
): BrandRequestAdminStage | null {
  const value = data[key];
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  return requiredAdminStage(value, BRAND_REQUEST_ADMIN_STAGES);
}

function optionalRejectionReason(
  data: Record<string, unknown>,
  key: string
): BrandRequestRejectionReason | null {
  const value = data[key];
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  const reason = value.trim() as BrandRequestRejectionReason;
  if (reason !== "unavailable" && reason !== "spam" && reason !== "other") {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  return reason;
}

function brandRequestUserListScope(
  data: Record<string, unknown>
): BrandRequestUserListScope {
  const value = data.scope;
  if (value === undefined || value === null) {
    return "active";
  }
  if (value !== "active" && value !== "history") {
    throw new HttpsError("invalid-argument", "scope 값이 올바르지 않습니다.");
  }
  return value;
}

function timestampToISO(value: unknown): string | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate().toISOString();
  }
  return null;
}

function brandRequestPublicSummary(
  requestID: string,
  data: FirebaseFirestore.DocumentData | undefined,
  groupData?: FirebaseFirestore.DocumentData
): Record<string, unknown> {
  const source = groupData ?? data;
  return {
    requestID,
    brandName: typeof data?.brandName === "string" ? data.brandName : "",
    normalizedBrandName: typeof data?.normalizedBrandName === "string" ?
      data.normalizedBrandName :
      "",
    englishBrandName: typeof data?.englishBrandName === "string" ?
      data.englishBrandName :
      null,
    normalizedEnglishBrandName:
      typeof data?.normalizedEnglishBrandName === "string" ?
        data.normalizedEnglishBrandName :
        null,
    groupID: typeof data?.groupID === "string" ? data.groupID : null,
    dedupeKey: typeof data?.dedupeKey === "string" ? data.dedupeKey : null,
    dedupeKeySource: typeof data?.dedupeKeySource === "string" ?
      data.dedupeKeySource :
      null,
    status: typeof source?.status === "string" ? source.status : "submitted",
    adminStage: typeof source?.adminStage === "string" ?
      source.adminStage :
      "requested",
    resolvedBrandID: typeof source?.resolvedBrandID === "string" ?
      source.resolvedBrandID :
      null,
    rejectionReason: typeof source?.rejectionReason === "string" ?
      source.rejectionReason :
      null,
    createdAt: timestampToISO(data?.createdAt),
    updatedAt: timestampToISO(source?.updatedAt),
    reviewedAt: timestampToISO(source?.reviewedAt),
    resolvedAt: timestampToISO(source?.resolvedAt),
    rejectedAt: timestampToISO(source?.rejectedAt),
    userVisibleUntil: timestampToISO(source?.userVisibleUntil),
  };
}

function brandRequestAdminSummary(
  requestID: string,
  data: FirebaseFirestore.DocumentData | undefined
): Record<string, unknown> {
  return {
    ...brandRequestPublicSummary(requestID, data),
    requesterUID: typeof data?.requesterUID === "string" ?
      data.requesterUID :
      "",
    requestCount: numericRootValue(data, "requestCount"),
    duplicateOfRequestID: typeof data?.duplicateOfRequestID === "string" ?
      data.duplicateOfRequestID :
      null,
    adminNote: typeof data?.adminNote === "string" ? data.adminNote : null,
  };
}

function brandRequestGroupSummary(
  groupID: string,
  data: FirebaseFirestore.DocumentData | undefined
): Record<string, unknown> {
  return {
    groupID,
    dedupeKey: typeof data?.dedupeKey === "string" ?
      data.dedupeKey :
      (typeof data?.normalizedBrandName === "string" ?
        data.normalizedBrandName :
        ""),
    dedupeKeySource: typeof data?.dedupeKeySource === "string" ?
      data.dedupeKeySource :
      "brandName",
    displayNameSnapshot: typeof data?.displayNameSnapshot === "string" ?
      data.displayNameSnapshot :
      "",
    normalizedBrandName: typeof data?.normalizedBrandName === "string" ?
      data.normalizedBrandName :
      "",
    englishBrandName: typeof data?.englishBrandName === "string" ?
      data.englishBrandName :
      null,
    normalizedEnglishBrandName:
      typeof data?.normalizedEnglishBrandName === "string" ?
        data.normalizedEnglishBrandName :
        null,
    requestCount: numericRootValue(data, "requestCount"),
    adminStage: typeof data?.adminStage === "string" ?
      data.adminStage :
      "requested",
    status: typeof data?.status === "string" ? data.status : "submitted",
    rejectionReason: typeof data?.rejectionReason === "string" ?
      data.rejectionReason :
      null,
    resolvedBrandID: typeof data?.resolvedBrandID === "string" ?
      data.resolvedBrandID :
      null,
    createdBrandID: typeof data?.createdBrandID === "string" ?
      data.createdBrandID :
      null,
    brandCreatedAt: timestampToISO(data?.brandCreatedAt),
    brandCreatedBy: typeof data?.brandCreatedBy === "string" ?
      data.brandCreatedBy :
      null,
    adminNote: typeof data?.adminNote === "string" ? data.adminNote : null,
    lastRequestID: typeof data?.lastRequestID === "string" ?
      data.lastRequestID :
      null,
    lastRequestedAt: timestampToISO(data?.lastRequestedAt),
    createdAt: timestampToISO(data?.createdAt),
    updatedAt: timestampToISO(data?.updatedAt),
    reviewedAt: timestampToISO(data?.reviewedAt),
    resolvedAt: timestampToISO(data?.resolvedAt),
    rejectedAt: timestampToISO(data?.rejectedAt),
    adminArchivedAt: timestampToISO(data?.adminArchivedAt),
  };
}

function brandSearchSummary(
  brandID: string,
  data: FirebaseFirestore.DocumentData | undefined
): Record<string, unknown> {
  return {
    brandID,
    name: typeof data?.name === "string" ? data.name : "",
    englishName: typeof data?.englishName === "string" ?
      data.englishName :
      null,
    websiteURL: typeof data?.websiteURL === "string" ? data.websiteURL : null,
    lookbookArchiveURL: typeof data?.lookbookArchiveURL === "string" ?
      data.lookbookArchiveURL :
      null,
    logoThumbPath: typeof data?.logoThumbPath === "string" ?
      data.logoThumbPath :
      (typeof data?.logoPath === "string" ? data.logoPath : null),
    logoDetailPath: typeof data?.logoDetailPath === "string" ?
      data.logoDetailPath :
      null,
    logoOriginalPath: typeof data?.logoOriginalPath === "string" ?
      data.logoOriginalPath :
      null,
    isFeatured: data?.isFeatured === true,
    discoveryStatus: typeof data?.discoveryStatus === "string" ?
      data.discoveryStatus :
      "idle",
    deletionStatus: typeof data?.deletionStatus === "string" ?
      data.deletionStatus :
      "active",
    lastDiscoveryErrorMessage:
      typeof data?.lastDiscoveryErrorMessage === "string" ?
        data.lastDiscoveryErrorMessage :
        null,
    lastDiscoveryRequestedAt: timestampToISO(data?.lastDiscoveryRequestedAt),
    lastDiscoveryCompletedAt: timestampToISO(data?.lastDiscoveryCompletedAt),
    metrics: {
      likeCount: numericRootValue(data, "likeCount"),
      viewCount: numericRootValue(data, "viewCount"),
      popularScore: numericRootValue(data, "popularScore"),
    },
    updatedAt: timestampToISO(data?.updatedAt),
  };
}

function brandNameIndexEntries(
  normalizedName: string,
  normalizedEnglishName: string | null
): {key: string; source: "name" | "englishName"}[] {
  const entries: {key: string; source: "name" | "englishName"}[] = [
    {key: normalizedName, source: "name"},
  ];
  if (
    normalizedEnglishName !== null &&
    normalizedEnglishName.length > 0 &&
    normalizedEnglishName !== normalizedName
  ) {
    entries.push({key: normalizedEnglishName, source: "englishName"});
  }
  return entries;
}

function optionalDeletionTargetType(
  data: Record<string, unknown>,
  key: string
): LookbookDeletionTargetType | null {
  const value = data[key];
  if (value === undefined || value === null) {
    return null;
  }
  if (value !== "brand" && value !== "season" && value !== "post") {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  return value;
}

function optionalDeletionRequestStatus(
  data: Record<string, unknown>,
  key: string
): LookbookDeletionRequestStatus | null {
  const value = data[key];
  if (value === undefined || value === null) {
    return null;
  }
  if (
    value !== "active" &&
    value !== "cancelled" &&
    value !== "restored" &&
    value !== "purged" &&
    value !== "failed"
  ) {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  return value;
}

function deletionRequestSummary(
  requestID: string,
  data: FirebaseFirestore.DocumentData | undefined
): Record<string, unknown> {
  return {
    requestID,
    targetType: typeof data?.targetType === "string" ?
      data.targetType :
      "brand",
    targetID: typeof data?.targetID === "string" ? data.targetID : "",
    targetPath: typeof data?.targetPath === "string" ? data.targetPath : "",
    brandID: typeof data?.brandID === "string" ? data.brandID : "",
    seasonID: typeof data?.seasonID === "string" ? data.seasonID : null,
    postID: typeof data?.postID === "string" ? data.postID : null,
    status: typeof data?.status === "string" ? data.status : "active",
    requestedBy: typeof data?.requestedBy === "string" ?
      data.requestedBy :
      "",
    requestedAt: timestampToISO(data?.requestedAt),
    restoreUntil: timestampToISO(data?.restoreUntil),
    purgeAfter: timestampToISO(data?.purgeAfter),
    reason: typeof data?.reason === "string" ? data.reason : null,
    cancelledBy: typeof data?.cancelledBy === "string" ?
      data.cancelledBy :
      null,
    cancelledAt: timestampToISO(data?.cancelledAt),
    restoredBy: typeof data?.restoredBy === "string" ?
      data.restoredBy :
      null,
    restoredAt: timestampToISO(data?.restoredAt),
    updatedBy: typeof data?.updatedBy === "string" ? data.updatedBy : null,
    updatedAt: timestampToISO(data?.updatedAt),
    targetDisplayName: typeof data?.targetDisplayName === "string" ?
      data.targetDisplayName :
      null,
    targetImagePath: typeof data?.targetImagePath === "string" ?
      data.targetImagePath :
      null,
    brandName: typeof data?.brandName === "string" ? data.brandName : null,
    brandEnglishName: typeof data?.brandEnglishName === "string" ?
      data.brandEnglishName :
      null,
    brandLogoThumbPath: typeof data?.brandLogoThumbPath === "string" ?
      data.brandLogoThumbPath :
      null,
    seasonTitle: typeof data?.seasonTitle === "string" ?
      data.seasonTitle :
      null,
    seasonCoverThumbPath: typeof data?.seasonCoverThumbPath === "string" ?
      data.seasonCoverThumbPath :
      null,
    postCaption: typeof data?.postCaption === "string" ?
      data.postCaption :
      null,
    postImageThumbPath: typeof data?.postImageThumbPath === "string" ?
      data.postImageThumbPath :
      null,
  };
}

function nonEmptyDisplayString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function firstNonEmptyDisplayString(values: unknown[]): string | null {
  for (const value of values) {
    if (nonEmptyDisplayString(value)) {
      return value.trim();
    }
  }
  return null;
}

function deletionFallbackDisplayName(
  targetType: LookbookDeletionTargetType
): string {
  switch (targetType) {
  case "brand":
    return "삭제된 브랜드";
  case "season":
    return "삭제된 시즌";
  case "post":
    return "삭제된 포스트";
  }
}

function displayTargetType(value: unknown): LookbookDeletionTargetType {
  if (value === "season" || value === "post") {
    return value;
  }
  return "brand";
}

function mergeMissingDisplaySnapshot(
  summary: Record<string, unknown>,
  snapshot: Record<string, unknown>
): Record<string, unknown> {
  const result = {...summary};
  for (const [key, value] of Object.entries(snapshot)) {
    if (!nonEmptyDisplayString(result[key]) && nonEmptyDisplayString(value)) {
      result[key] = value;
    }
  }
  return result;
}

async function deletionRequestSummaryWithDisplayFallback(
  requestID: string,
  data: FirebaseFirestore.DocumentData | undefined
): Promise<Record<string, unknown>> {
  const summary = deletionRequestSummary(requestID, data);
  const targetType = displayTargetType(summary.targetType);
  const hasPrimaryName = nonEmptyDisplayString(summary.targetDisplayName);
  const hasTargetName =
    targetType === "brand" ?
      nonEmptyDisplayString(summary.brandName) :
      targetType === "season" ?
        nonEmptyDisplayString(summary.seasonTitle) :
        nonEmptyDisplayString(summary.postCaption);

  if (
    targetType === "season" &&
    nonEmptyDisplayString(summary.seasonTitle) &&
    (
      !hasPrimaryName ||
      summary.targetDisplayName === deletionFallbackDisplayName("season")
    )
  ) {
    return {
      ...summary,
      targetDisplayName: summary.seasonTitle,
    };
  }

  if (hasPrimaryName && hasTargetName) {
    return summary;
  }

  const brandID = nonEmptyDisplayString(summary.brandID) ?
    summary.brandID :
    null;
  if (brandID === null) {
    return {
      ...summary,
      targetDisplayName: hasPrimaryName ?
        summary.targetDisplayName :
        deletionFallbackDisplayName(targetType),
    };
  }

  const brandRef = db.collection("brands").doc(brandID);
  const seasonID = nonEmptyDisplayString(summary.seasonID) ?
    summary.seasonID :
    null;
  const postID = nonEmptyDisplayString(summary.postID) ?
    summary.postID :
    null;

  const brandSnap = await brandRef.get();
  const seasonSnap =
    seasonID !== null && (targetType === "season" || targetType === "post") ?
      await brandRef.collection("seasons").doc(seasonID).get() :
      null;
  const postSnap =
    seasonID !== null && postID !== null && targetType === "post" ?
      await brandRef
        .collection("seasons")
        .doc(seasonID)
        .collection("posts")
        .doc(postID)
        .get() :
      null;

  const enriched = mergeMissingDisplaySnapshot(
    summary,
    lookbookDeletionDisplaySnapshot(
      targetType,
      brandSnap.data(),
      seasonSnap?.data(),
      postSnap?.data()
    )
  );

  if (!nonEmptyDisplayString(enriched.targetDisplayName)) {
    enriched.targetDisplayName = deletionFallbackDisplayName(targetType);
  }
  if (
    targetType === "season" &&
    nonEmptyDisplayString(enriched.seasonTitle) &&
    enriched.targetDisplayName === deletionFallbackDisplayName("season")
  ) {
    enriched.targetDisplayName = enriched.seasonTitle;
  }
  return enriched;
}

function mediaThumbPath(data: FirebaseFirestore.DocumentData | undefined):
  string | null {
  const media = data?.media;
  if (!Array.isArray(media)) {
    return null;
  }

  for (const item of media) {
    if (item === null || typeof item !== "object" || Array.isArray(item)) {
      continue;
    }
    const entry = item as Record<string, unknown>;
    if (typeof entry.thumbPath === "string" && entry.thumbPath.length > 0) {
      return entry.thumbPath;
    }
    if (typeof entry.detailPath === "string" && entry.detailPath.length > 0) {
      return entry.detailPath;
    }
    if (
      typeof entry.originalPath === "string" &&
      entry.originalPath.length > 0
    ) {
      return entry.originalPath;
    }
  }
  return null;
}

function lookbookDeletionDisplaySnapshot(
  targetType: LookbookDeletionTargetType,
  brandData: FirebaseFirestore.DocumentData | undefined,
  seasonData?: FirebaseFirestore.DocumentData,
  postData?: FirebaseFirestore.DocumentData
): Record<string, unknown> {
  const brandName = typeof brandData?.name === "string" ? brandData.name : null;
  const brandEnglishName = typeof brandData?.englishName === "string" ?
    brandData.englishName :
    null;
  const brandLogoThumbPath =
    typeof brandData?.logoThumbPath === "string" ?
      brandData.logoThumbPath :
      (typeof brandData?.logoPath === "string" ? brandData.logoPath : null);
  const seasonTitle = firstNonEmptyDisplayString([
    seasonData?.displayTitle,
    seasonData?.title,
    seasonData?.sourceTitle,
  ]);
  const seasonCoverThumbPath =
    typeof seasonData?.coverThumbPath === "string" ?
      seasonData.coverThumbPath :
      (typeof seasonData?.coverPath === "string" ?
        seasonData.coverPath :
        null);
  const postCaption =
    typeof postData?.caption === "string" ? postData.caption : null;
  const postImageThumbPath = mediaThumbPath(postData);

  let targetDisplayName: string | null = brandName;
  let targetImagePath: string | null = brandLogoThumbPath;
  if (targetType === "season") {
    targetDisplayName = seasonTitle;
    targetImagePath = seasonCoverThumbPath;
  } else if (targetType === "post") {
    targetDisplayName =
      postCaption !== null && postCaption.trim().length > 0 ?
        postCaption :
        "포스트";
    targetImagePath = postImageThumbPath;
  }

  return {
    targetDisplayName,
    targetImagePath,
    brandName,
    brandEnglishName,
    brandLogoThumbPath,
    seasonTitle,
    seasonCoverThumbPath,
    postCaption,
    postImageThumbPath,
  };
}

function deletionTargetID(
  targetType: LookbookDeletionTargetType,
  brandID: string,
  seasonID: string | null,
  postID: string | null
): string {
  switch (targetType) {
  case "brand":
    return brandID;
  case "season":
    return seasonID ?? "";
  case "post":
    return postID ?? "";
  }
}

function deletionTargetPath(
  targetType: LookbookDeletionTargetType,
  brandID: string,
  seasonID: string | null,
  postID: string | null
): string {
  switch (targetType) {
  case "brand":
    return `brands/${brandID}`;
  case "season":
    return `brands/${brandID}/seasons/${seasonID ?? ""}`;
  case "post":
    return `brands/${brandID}/seasons/${seasonID ?? ""}/posts/${postID ?? ""}`;
  }
}

function deletionRequestPatch(
  requestID: string,
  targetType: LookbookDeletionTargetType,
  brandID: string,
  seasonID: string | null,
  postID: string | null,
  actorUID: string,
  reason: string | null,
  nowDate: Date,
  displaySnapshot: Record<string, unknown> = {}
): Record<string, unknown> {
  const now = admin.firestore.Timestamp.fromDate(nowDate);
  const purgeAfter = admin.firestore.Timestamp.fromDate(
    addDays(nowDate, LOOKBOOK_DELETION_RETENTION_DAYS)
  );
  return {
    requestID,
    targetType,
    targetID: deletionTargetID(targetType, brandID, seasonID, postID),
    targetPath: deletionTargetPath(targetType, brandID, seasonID, postID),
    brandID,
    seasonID,
    postID,
    status: "active",
    requestedBy: actorUID,
    requestedAt: now,
    restoreUntil: purgeAfter,
    purgeAfter,
    reason,
    cancelledBy: null,
    cancelledAt: null,
    restoredBy: null,
    restoredAt: null,
    purgeErrorMessage: null,
    updatedBy: actorUID,
    updatedAt: now,
    ...displaySnapshot,
  };
}

function deletionAuditPatch(
  action: LookbookDeletionAction,
  requestID: string,
  targetType: LookbookDeletionTargetType,
  brandID: string,
  seasonID: string | null,
  postID: string | null,
  actorUID: string,
  reason: string | null,
  nowDate: Date,
  beforeStatus: string | null,
  afterStatus: string
): Record<string, unknown> {
  return {
    action,
    requestID,
    targetType,
    targetID: deletionTargetID(targetType, brandID, seasonID, postID),
    targetPath: deletionTargetPath(targetType, brandID, seasonID, postID),
    brandID,
    seasonID,
    postID,
    actorUID,
    reason,
    before: {
      deletionStatus: beforeStatus,
    },
    after: {
      deletionStatus: afterStatus,
    },
    createdAt: admin.firestore.Timestamp.fromDate(nowDate),
  };
}

function clearDeletionFields(): Record<string, unknown> {
  return {
    deletionStatus: "active",
    deletionRequestedAt: FieldValue.delete(),
    deletionRequestedBy: FieldValue.delete(),
    deletedAt: FieldValue.delete(),
    deletedBy: FieldValue.delete(),
    deletionReason: FieldValue.delete(),
    deleteReason: FieldValue.delete(),
    restoreUntil: FieldValue.delete(),
    purgeAfter: FieldValue.delete(),
    deleteRequestID: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function lookbookDeletionFailureResult(
  targetType: LookbookDeletionTargetType,
  brandID: string,
  seasonID: string | null,
  postID: string | null,
  error: unknown
): Record<string, unknown> {
  const codeValue = (error as {code?: unknown})?.code;
  const code = typeof codeValue === "string" ? codeValue : "internal";
  const message = error instanceof Error && error.message.length > 0 ?
    error.message :
    "삭제 요청을 처리하지 못했습니다.";
  return {
    success: false,
    targetType,
    targetID: deletionTargetID(targetType, brandID, seasonID, postID),
    brandID,
    seasonID,
    postID,
    code,
    message: message.slice(0, 1000),
  };
}

function lookbookDeletionBatchResponse(
  targetType: LookbookDeletionTargetType,
  brandID: string,
  requestedCount: number,
  results: Record<string, unknown>[]
): Record<string, unknown> {
  const succeededCount = results.filter((result) =>
    result.success === true
  ).length;
  return {
    brandID,
    targetType,
    requestedCount,
    succeededCount,
    failedCount: results.length - succeededCount,
    results,
  };
}

async function assertBatchDeletionPreconditions(
  brandID: string,
  seasonID: string | null,
  targetLabel: "시즌" | "포스트"
): Promise<void> {
  const brandRef = db.collection("brands").doc(brandID);
  const brandSnap = await brandRef.get();
  if (!brandSnap.exists) {
    throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
  }
  if (brandSnap.data()?.deletionStatus === "deletionRequested") {
    throw new HttpsError(
      "failed-precondition",
      `삭제 요청 중인 브랜드의 ${targetLabel}는 삭제할 수 없습니다.`
    );
  }

  if (seasonID === null) {
    return;
  }

  const seasonSnap = await brandRef.collection("seasons").doc(seasonID).get();
  if (!seasonSnap.exists) {
    throw new HttpsError("not-found", "시즌을 찾을 수 없습니다.");
  }
  if (seasonSnap.data()?.deletionStatus === "deleted") {
    throw new HttpsError(
      "failed-precondition",
      "삭제된 시즌의 포스트는 개별 삭제할 수 없습니다."
    );
  }
}

async function softDeleteSeasonTarget(
  uid: string,
  brandID: string,
  seasonID: string,
  reason: string | null
): Promise<Record<string, unknown>> {
  const requestID = randomUUID();
  const brandRef = db.collection("brands").doc(brandID);
  const seasonRef = brandRef.collection("seasons").doc(seasonID);
  const requestRef = db.collection("lookbookDeletionRequests").doc(requestID);
  const auditRef = db.collection("lookbookDeletionAuditLogs").doc();

  return await db.runTransaction(async (transaction) => {
    const [brandSnap, seasonSnap] = await Promise.all([
      transaction.get(brandRef),
      transaction.get(seasonRef),
    ]);
    if (!brandSnap.exists) {
      throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
    }
    if (!seasonSnap.exists) {
      throw new HttpsError("not-found", "시즌을 찾을 수 없습니다.");
    }
    if (brandSnap.data()?.deletionStatus === "deletionRequested") {
      throw new HttpsError(
        "failed-precondition",
        "삭제 요청 중인 브랜드의 시즌은 삭제할 수 없습니다."
      );
    }

    const brandData = brandSnap.data();
    const seasonData = seasonSnap.data();
    if (seasonData?.deletionStatus === "deleted") {
      return {
        success: true,
        targetType: "season",
        targetID: seasonID,
        brandID,
        seasonID,
        requestID: typeof seasonData.deleteRequestID === "string" ?
          seasonData.deleteRequestID :
          null,
        status: "active",
        duplicate: true,
      };
    }

    const nowDate = new Date();
    const displaySnapshot = lookbookDeletionDisplaySnapshot(
      "season",
      brandData,
      seasonData
    );
    const deletionPatch = deletionRequestPatch(
      requestID,
      "season",
      brandID,
      seasonID,
      null,
      uid,
      reason,
      nowDate,
      displaySnapshot
    );
    transaction.update(seasonRef, {
      deletionStatus: "deleted",
      deletedAt: deletionPatch.requestedAt,
      deletedBy: uid,
      deleteReason: reason,
      restoreUntil: deletionPatch.restoreUntil,
      purgeAfter: deletionPatch.purgeAfter,
      deleteRequestID: requestID,
      updatedAt: deletionPatch.updatedAt,
    });
    transaction.set(requestRef, deletionPatch);
    transaction.set(auditRef, deletionAuditPatch(
      "softDeleteSeason",
      requestID,
      "season",
      brandID,
      seasonID,
      null,
      uid,
      reason,
      nowDate,
      typeof seasonData?.deletionStatus === "string" ?
        seasonData.deletionStatus :
        "active",
      "deleted"
    ));

    return {
      success: true,
      targetType: "season",
      targetID: seasonID,
      brandID,
      seasonID,
      requestID,
      status: "active",
      duplicate: false,
    };
  });
}

async function softDeletePostTarget(
  uid: string,
  brandID: string,
  seasonID: string,
  postID: string,
  reason: string | null
): Promise<Record<string, unknown>> {
  const requestID = randomUUID();
  const brandRef = db.collection("brands").doc(brandID);
  const seasonRef = brandRef.collection("seasons").doc(seasonID);
  const postRef = seasonRef.collection("posts").doc(postID);
  const requestRef = db.collection("lookbookDeletionRequests").doc(requestID);
  const auditRef = db.collection("lookbookDeletionAuditLogs").doc();

  return await db.runTransaction(async (transaction) => {
    const [brandSnap, seasonSnap, postSnap] = await Promise.all([
      transaction.get(brandRef),
      transaction.get(seasonRef),
      transaction.get(postRef),
    ]);
    if (!brandSnap.exists) {
      throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
    }
    if (!seasonSnap.exists) {
      throw new HttpsError("not-found", "시즌을 찾을 수 없습니다.");
    }
    if (!postSnap.exists) {
      throw new HttpsError("not-found", "포스트를 찾을 수 없습니다.");
    }
    if (brandSnap.data()?.deletionStatus === "deletionRequested") {
      throw new HttpsError(
        "failed-precondition",
        "삭제 요청 중인 브랜드의 포스트는 삭제할 수 없습니다."
      );
    }
    if (seasonSnap.data()?.deletionStatus === "deleted") {
      throw new HttpsError(
        "failed-precondition",
        "삭제된 시즌의 포스트는 개별 삭제할 수 없습니다."
      );
    }

    const brandData = brandSnap.data();
    const seasonData = seasonSnap.data();
    const postData = postSnap.data();
    if (postData?.deletionStatus === "deleted") {
      return {
        success: true,
        targetType: "post",
        targetID: postID,
        brandID,
        seasonID,
        postID,
        requestID: typeof postData.deleteRequestID === "string" ?
          postData.deleteRequestID :
          null,
        status: "active",
        duplicate: true,
      };
    }

    const nowDate = new Date();
    const displaySnapshot = lookbookDeletionDisplaySnapshot(
      "post",
      brandData,
      seasonData,
      postData
    );
    const deletionPatch = deletionRequestPatch(
      requestID,
      "post",
      brandID,
      seasonID,
      postID,
      uid,
      reason,
      nowDate,
      displaySnapshot
    );
    transaction.update(postRef, {
      deletionStatus: "deleted",
      deletedAt: deletionPatch.requestedAt,
      deletedBy: uid,
      deleteReason: reason,
      restoreUntil: deletionPatch.restoreUntil,
      purgeAfter: deletionPatch.purgeAfter,
      deleteRequestID: requestID,
      updatedAt: deletionPatch.updatedAt,
    });
    transaction.set(requestRef, deletionPatch);
    transaction.set(auditRef, deletionAuditPatch(
      "softDeletePost",
      requestID,
      "post",
      brandID,
      seasonID,
      postID,
      uid,
      reason,
      nowDate,
      typeof postData?.deletionStatus === "string" ?
        postData.deletionStatus :
        "active",
      "deleted"
    ));

    return {
      success: true,
      targetType: "post",
      targetID: postID,
      brandID,
      seasonID,
      postID,
      requestID,
      status: "active",
      duplicate: false,
    };
  });
}

function firestoreTimestampMillis(value: unknown): number | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toMillis();
  }
  return null;
}

function lookbookPurgeErrorMessage(error: unknown): string {
  const rawMessage = error instanceof Error ? error.message : String(error);
  return rawMessage.slice(0, 1000);
}

function retryAfterTimestamp(nowDate: Date): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromDate(
    new Date(
      nowDate.getTime() +
      LOOKBOOK_PURGE_RETRY_DELAY_HOURS * 60 * 60 * 1000
    )
  );
}

function stringField(
  data: FirebaseFirestore.DocumentData | undefined,
  key: string
): string | null {
  const value = data?.[key];
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function safeLookbookStoragePath(
  brandID: string,
  rawPath: string | null
): string | null {
  if (rawPath === null) {
    return null;
  }

  const normalized = rawPath.trim().replace(/^\/+/, "");
  if (
    normalized.length === 0 ||
    normalized.includes("..") ||
    normalized.includes("://") ||
    normalized.startsWith("/") ||
    !normalized.startsWith(`brands/${brandID}/`)
  ) {
    return null;
  }
  return normalized;
}

function addStoragePath(
  paths: Set<string>,
  brandID: string,
  rawPath: string | null
): void {
  const path = safeLookbookStoragePath(brandID, rawPath);
  if (path !== null) {
    paths.add(path);
  }
}

function collectBrandStoragePaths(
  brandID: string,
  data: FirebaseFirestore.DocumentData | undefined,
  paths: Set<string>
): void {
  addStoragePath(paths, brandID, stringField(data, "logoPath"));
  addStoragePath(paths, brandID, stringField(data, "logoThumbPath"));
  addStoragePath(paths, brandID, stringField(data, "logoDetailPath"));
  addStoragePath(paths, brandID, stringField(data, "logoOriginalPath"));
}

function collectSeasonStoragePaths(
  brandID: string,
  data: FirebaseFirestore.DocumentData | undefined,
  paths: Set<string>
): void {
  addStoragePath(paths, brandID, stringField(data, "coverPath"));
  addStoragePath(paths, brandID, stringField(data, "coverThumbPath"));
  addStoragePath(paths, brandID, stringField(data, "coverOriginalPath"));
}

function collectMediaStoragePaths(
  brandID: string,
  mediaValue: unknown,
  paths: Set<string>
): void {
  if (!Array.isArray(mediaValue)) {
    return;
  }

  for (const item of mediaValue) {
    if (item === null || typeof item !== "object" || Array.isArray(item)) {
      continue;
    }
    const media = item as Record<string, unknown>;
    addStoragePath(paths, brandID, stringField(media, "thumbPath"));
    addStoragePath(paths, brandID, stringField(media, "detailPath"));
    addStoragePath(paths, brandID, stringField(media, "originalPath"));
  }
}

function collectPostStoragePaths(
  brandID: string,
  data: FirebaseFirestore.DocumentData | undefined,
  paths: Set<string>
): void {
  collectMediaStoragePaths(brandID, data?.media, paths);
  addStoragePath(paths, brandID, stringField(data, "thumbPath"));
  addStoragePath(paths, brandID, stringField(data, "detailPath"));
  addStoragePath(paths, brandID, stringField(data, "originalPath"));
}

function collectReplacementStoragePaths(
  brandID: string,
  data: FirebaseFirestore.DocumentData | undefined,
  paths: Set<string>
): void {
  collectMediaStoragePaths(brandID, data?.media, paths);
  addStoragePath(paths, brandID, stringField(data, "thumbPath"));
  addStoragePath(paths, brandID, stringField(data, "detailPath"));
  addStoragePath(paths, brandID, stringField(data, "originalPath"));
  addStoragePath(paths, brandID, stringField(data, "imagePath"));
}

function collectCommentStoragePaths(
  brandID: string,
  data: FirebaseFirestore.DocumentData | undefined,
  paths: Set<string>
): void {
  collectMediaStoragePaths(brandID, data?.attachments, paths);
  addStoragePath(paths, brandID, stringField(data, "thumbPath"));
  addStoragePath(paths, brandID, stringField(data, "detailPath"));
  addStoragePath(paths, brandID, stringField(data, "originalPath"));
}

async function deleteDocumentSnapshotPage(
  snapshot: FirebaseFirestore.QuerySnapshot
): Promise<number> {
  if (snapshot.empty) {
    return 0;
  }

  const batch = db.batch();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  return snapshot.size;
}

async function deleteCollectionGroupByField(
  collectionID: string,
  field: string,
  value: string
): Promise<number> {
  let deletedCount = 0;
  let hasMore = true;
  while (hasMore) {
    const snapshot = await db
      .collectionGroup(collectionID)
      .where(field, "==", value)
      .limit(LOOKBOOK_PURGE_PAGE_SIZE)
      .get();
    if (snapshot.empty) {
      return deletedCount;
    }
    deletedCount += await deleteDocumentSnapshotPage(snapshot);
    hasMore = !snapshot.empty;
  }
  return deletedCount;
}

async function deleteCollectionGroupByFields(
  collectionID: string,
  filters: [string, string][]
): Promise<number> {
  let deletedCount = 0;
  let hasMore = true;
  while (hasMore) {
    let query: FirebaseFirestore.Query = db.collectionGroup(collectionID);
    for (const [field, value] of filters) {
      query = query.where(field, "==", value);
    }
    const snapshot = await query
      .limit(LOOKBOOK_PURGE_PAGE_SIZE)
      .get();
    if (snapshot.empty) {
      return deletedCount;
    }
    deletedCount += await deleteDocumentSnapshotPage(snapshot);
    hasMore = !snapshot.empty;
  }
  return deletedCount;
}

async function collectPostSubresourceStoragePaths(
  brandID: string,
  postRef: FirebaseFirestore.DocumentReference,
  paths: Set<string>
): Promise<void> {
  let lastComment: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  let hasMoreComments = true;
  while (hasMoreComments) {
    let query: FirebaseFirestore.Query = postRef
      .collection("comments")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(LOOKBOOK_PURGE_PAGE_SIZE);
    if (lastComment !== null) {
      query = query.startAfter(lastComment);
    }
    const comments = await query.get();
    if (comments.empty) {
      break;
    }
    comments.forEach((doc) =>
      collectCommentStoragePaths(brandID, doc.data(), paths)
    );
    lastComment = comments.docs[comments.docs.length - 1];
    hasMoreComments = !comments.empty;
  }

  let lastReplacement: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  let hasMoreReplacements = true;
  while (hasMoreReplacements) {
    let query: FirebaseFirestore.Query = postRef
      .collection("replacements")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(LOOKBOOK_PURGE_PAGE_SIZE);
    if (lastReplacement !== null) {
      query = query.startAfter(lastReplacement);
    }
    const replacements = await query.get();
    if (replacements.empty) {
      break;
    }
    replacements.forEach((doc) =>
      collectReplacementStoragePaths(brandID, doc.data(), paths)
    );
    lastReplacement = replacements.docs[replacements.docs.length - 1];
    hasMoreReplacements = !replacements.empty;
  }
}

async function collectSeasonSubresourceStoragePaths(
  brandID: string,
  seasonRef: FirebaseFirestore.DocumentReference,
  paths: Set<string>
): Promise<void> {
  let lastPost: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  let hasMorePosts = true;
  while (hasMorePosts) {
    let query: FirebaseFirestore.Query = seasonRef
      .collection("posts")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(LOOKBOOK_PURGE_PAGE_SIZE);
    if (lastPost !== null) {
      query = query.startAfter(lastPost);
    }
    const posts = await query.get();
    if (posts.empty) {
      break;
    }
    for (const post of posts.docs) {
      collectPostStoragePaths(brandID, post.data(), paths);
      await collectPostSubresourceStoragePaths(brandID, post.ref, paths);
    }
    lastPost = posts.docs[posts.docs.length - 1];
    hasMorePosts = !posts.empty;
  }
}

async function collectBrandSubresourceStoragePaths(
  brandID: string,
  brandRef: FirebaseFirestore.DocumentReference,
  paths: Set<string>
): Promise<void> {
  let lastSeason: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  let hasMoreSeasons = true;
  while (hasMoreSeasons) {
    let query: FirebaseFirestore.Query = brandRef
      .collection("seasons")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(LOOKBOOK_PURGE_PAGE_SIZE);
    if (lastSeason !== null) {
      query = query.startAfter(lastSeason);
    }
    const seasons = await query.get();
    if (seasons.empty) {
      break;
    }
    for (const season of seasons.docs) {
      collectSeasonStoragePaths(brandID, season.data(), paths);
      await collectSeasonSubresourceStoragePaths(brandID, season.ref, paths);
    }
    lastSeason = seasons.docs[seasons.docs.length - 1];
    hasMoreSeasons = !seasons.empty;
  }
}

async function deleteLookbookStorageTargets(
  brandID: string,
  prefixes: string[],
  paths: Set<string>
): Promise<void> {
  const bucket = admin.storage().bucket();
  const safePrefixes = prefixes
    .map((prefix) => prefix.replace(/^\/+/, ""))
    .filter((prefix) =>
      prefix.startsWith(`brands/${brandID}/`) && !prefix.includes("..")
    );

  await mapWithConcurrency(
    safePrefixes,
    LOOKBOOK_PURGE_STORAGE_PREFIX_CONCURRENCY,
    async (prefix) => {
      await bucket.deleteFiles({prefix, force: true});
    }
  );

  const prefixSet = new Set(safePrefixes);
  const explicitPaths = Array.from(paths)
    .filter((path) =>
      !Array.from(prefixSet).some((prefix) => path.startsWith(prefix))
    );

  await mapWithConcurrency(explicitPaths, 10, async (path) => {
    await bucket.file(path).delete({ignoreNotFound: true});
  });
}

async function deleteBrandNameIndexes(
  brandID: string,
  brandData: FirebaseFirestore.DocumentData | undefined
): Promise<number> {
  const keys = new Set<string>();
  const normalizedName = stringField(brandData, "normalizedName");
  const normalizedEnglishName = stringField(brandData, "normalizedEnglishName");

  if (normalizedName !== null) {
    brandNameIndexEntries(normalizedName, normalizedEnglishName).forEach(
      (entry) => keys.add(entry.key)
    );
  }

  const snapshot = await db
    .collection("brandNameIndex")
    .where("brandID", "==", brandID)
    .get();
  snapshot.docs.forEach((doc) => keys.add(doc.id));

  if (keys.size === 0) {
    return 0;
  }

  const batch = db.batch();
  Array.from(keys).forEach((key) =>
    batch.delete(db.collection("brandNameIndex").doc(key))
  );
  await batch.commit();
  return keys.size;
}

function spamLimitPatch(
  uid: string,
  spamCount: number,
  now: Date
): Record<string, unknown> {
  const patch: Record<string, unknown> = {
    uid,
    spamCount,
    lastSpamAt: admin.firestore.Timestamp.fromDate(now),
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (spamCount >= 10) {
    patch.permanentBlocked = true;
    patch.blockedUntil = null;
    patch.lastBlockedAt = admin.firestore.Timestamp.fromDate(now);
    return patch;
  }

  if (spamCount >= 5) {
    patch.permanentBlocked = false;
    patch.blockedUntil = admin.firestore.Timestamp.fromDate(addDays(now, 30));
    patch.lastBlockedAt = admin.firestore.Timestamp.fromDate(now);
    return patch;
  }

  if (spamCount >= 3) {
    patch.permanentBlocked = false;
    patch.blockedUntil = admin.firestore.Timestamp.fromDate(addDays(now, 7));
    patch.lastBlockedAt = admin.firestore.Timestamp.fromDate(now);
    return patch;
  }

  patch.permanentBlocked = false;
  return patch;
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

function deterministicImportTaskID(brandID: string, jobID: string): string {
  const encoded = Buffer
    .from(`${brandID}:${jobID}`)
    .toString("base64url");
  return `import-${encoded}`.slice(0, 500);
}

function deterministicAssetRetryTaskID(
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

function isAlreadyExistsError(error: unknown): boolean {
  const code = (error as {code?: unknown})?.code;
  return code === 6 || code === "ALREADY_EXISTS";
}

function messageFromError(error: unknown): string {
  if (error instanceof Error && error.message.trim().length > 0) {
    return error.message;
  }
  return "시즌 가져오기 작업을 준비하지 못했습니다.";
}

async function mapWithConcurrency<T, R>(
  values: T[],
  concurrency: number,
  work: (value: T, index: number) => Promise<R>
): Promise<R[]> {
  const results: R[] = [];
  let cursor = 0;
  const workerCount = Math.min(Math.max(1, concurrency), values.length);
  const workers = Array.from({length: workerCount}, async () => {
    for (;;) {
      const index = cursor;
      cursor += 1;
      const value = values[index];
      if (value === undefined) {
        return;
      }
      results[index] = await work(value, index);
    }
  });
  await Promise.all(workers);
  return results;
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

/**
 * Checks whether the caller can create new brands.
 */
async function assertBrandCreationAccess(uid: string): Promise<void> {
  if (!(await isTotalBrandAdmin(uid))) {
    throw new HttpsError("permission-denied", "총 관리자 권한이 없습니다.");
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
  const adminRef = brandRef.collection("admins").doc(uid);
  const [brandSnap, totalAdmin, adminSnap] = await Promise.all([
    brandRef.get(),
    isTotalBrandAdmin(uid),
    adminRef.get(),
  ]);

  if (!brandSnap.exists) {
    throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
  }

  if (!totalAdmin && !hasBrandWriteAccessData(adminSnap.data())) {
    throw new HttpsError("permission-denied", "브랜드 수정 권한이 없습니다.");
  }
}

/**
 * Returns the brand admin capability summary for a Firebase Auth uid.
 */
async function brandAdminCapabilities(uid: string): Promise<{
  isTotalAdmin: boolean;
  roles: string[];
  ownedBrandIDs: string[];
  adminBrandIDs: string[];
}> {
  const adminRef = db.collection("brandAdmins").doc(uid);
  const adminSnap = await adminRef.get();
  const adminData = adminSnap.data();
  const roles = stringList(adminData?.roles);
  const isTotalAdmin = adminSnap.exists && adminData?.isActive === true;

  if (isTotalAdmin) {
    return {
      isTotalAdmin: true,
      roles,
      ownedBrandIDs: [],
      adminBrandIDs: [],
    };
  }

  const brandManagersSnap = await db
    .collectionGroup("admins")
    .where("uid", "==", uid)
    .get();

  const ownedBrandIDs: string[] = [];
  const adminBrandIDs: string[] = [];
  brandManagersSnap.docs.forEach((doc) => {
    const data = doc.data();
    const brandID = typeof data.brandID === "string" ?
      data.brandID :
      doc.ref.parent.parent?.id ?? "";
    if (brandID.length === 0) {
      return;
    }
    if (data.role === "owner") {
      ownedBrandIDs.push(brandID);
    } else if (data.role === "admin") {
      adminBrandIDs.push(brandID);
    }
  });

  if (!adminSnap.exists) {
    return {
      isTotalAdmin: false,
      roles: [],
      ownedBrandIDs,
      adminBrandIDs,
    };
  }

  return {
    isTotalAdmin: false,
    roles,
    ownedBrandIDs,
    adminBrandIDs,
  };
}

async function isTotalBrandAdmin(uid: string): Promise<boolean> {
  const adminSnap = await db.collection("brandAdmins").doc(uid).get();
  return adminSnap.exists && adminSnap.data()?.isActive === true;
}

async function assertOutPickAdmin(uid: string): Promise<void> {
  if (!(await isTotalBrandAdmin(uid))) {
    throw new HttpsError("permission-denied", "관리자 권한이 없습니다.");
  }
}

async function findUserIDByEmail(email: string): Promise<string> {
  const snapshot = await db
    .collection("users")
    .where("email", "==", email)
    .limit(2)
    .get();

  if (snapshot.empty) {
    throw new HttpsError("not-found", "이메일에 해당하는 사용자를 찾을 수 없습니다.");
  }
  if (snapshot.size > 1) {
    throw new HttpsError(
      "failed-precondition",
      "같은 이메일을 가진 사용자가 여러 명입니다."
    );
  }
  return snapshot.docs[0].id;
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
      isTotalAdmin: capabilities.isTotalAdmin,
      roles: capabilities.roles,
      ownedBrandIDs: capabilities.ownedBrandIDs,
      adminBrandIDs: capabilities.adminBrandIDs,
    };
  }
);

export const submitBrandRequest = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandName = canonicalBrandName(requiredString(data, "brandName", 80));
    const normalizedName = normalizedBrandName(brandName);
    const englishBrandName = optionalString(data, "englishBrandName", 80);
    const canonicalEnglishBrandName = englishBrandName === null ?
      null :
      canonicalBrandName(englishBrandName);
    const normalizedEnglishName = canonicalEnglishBrandName === null ?
      null :
      normalizedBrandName(canonicalEnglishBrandName);
    const {dedupeKey, dedupeKeySource} = brandRequestDedupeKey(
      normalizedName,
      normalizedEnglishName
    );
    const requestID = brandRequestDocumentID(uid, dedupeKey);
    const groupID = brandRequestNameIndexID(dedupeKey);
    const nowDate = new Date();
    const now = admin.firestore.Timestamp.fromDate(nowDate);
    const dateKey = dateKeyKST(nowDate);
    const expiresAt = admin.firestore.Timestamp.fromDate(
      addDays(nowDate, BRAND_REQUEST_COUNTER_TTL_DAYS)
    );

    const requestRef = db.collection("brandRequests").doc(requestID);
    const nameIndexRef = db
      .collection("brandRequestNameIndex")
      .doc(groupID);
    const counterRef = db
      .collection("brandRequestDailyCounters")
      .doc(uid)
      .collection("brandRequestDays")
      .doc(dateKey);
    const userLimitRef = db.collection("brandRequestUserLimits").doc(uid);

    return await db.runTransaction(async (transaction) => {
      const [userLimitSnap, requestSnap, counterSnap, nameIndexSnap] =
        await Promise.all([
          transaction.get(userLimitRef),
          transaction.get(requestRef),
          transaction.get(counterRef),
          transaction.get(nameIndexRef),
        ]);

      const userLimit = userLimitSnap.data();
      if (userLimit?.permanentBlocked === true) {
        throw new HttpsError(
          "permission-denied",
          "브랜드 요청이 제한된 계정입니다."
        );
      }

      const blockedUntil = userLimit?.blockedUntil;
      if (
        blockedUntil instanceof admin.firestore.Timestamp &&
        blockedUntil.toDate().getTime() > nowDate.getTime()
      ) {
        throw new HttpsError(
          "permission-denied",
          "일시적으로 브랜드 요청이 제한된 계정입니다."
        );
      }

      const counterData = counterSnap.data();
      const currentCount = numericRootValue(counterData, "count");

      if (requestSnap.exists) {
        return {
          requestID,
          groupID,
          status: requestSnap.get("status") ?? "submitted",
          adminStage: requestSnap.get("adminStage") ?? "requested",
          isDuplicate: true,
          remainingToday: Math.max(0, BRAND_REQUEST_DAILY_LIMIT - currentCount),
        };
      }

      if (currentCount >= BRAND_REQUEST_DAILY_LIMIT) {
        throw new HttpsError(
          "resource-exhausted",
          "오늘 요청 가능 횟수를 모두 사용했습니다."
        );
      }

      const nameIndexData = nameIndexSnap.data();
      const groupAdminStage = requiredAdminStage(
        typeof nameIndexData?.adminStage === "string" ?
          nameIndexData.adminStage :
          "requested",
        BRAND_REQUEST_ADMIN_STAGES
      );
      const groupStatus = requestStatusForAdminStage(groupAdminStage);
      const groupRejectionReason =
        typeof nameIndexData?.rejectionReason === "string" ?
          nameIndexData.rejectionReason :
          null;
      const groupResolvedBrandID =
        typeof nameIndexData?.resolvedBrandID === "string" ?
          nameIndexData.resolvedBrandID :
          null;
      const isGroupRejected = groupAdminStage === "rejected";
      const isGroupCompleted = groupAdminStage === "completed";
      const userVisibleUntil =
        isGroupRejected || isGroupCompleted ?
          admin.firestore.Timestamp.fromDate(
            addDays(nowDate, BRAND_REQUEST_USER_VISIBLE_DAYS)
          ) :
          null;

      transaction.set(requestRef, {
        requestID,
        groupID,
        brandName,
        normalizedBrandName: normalizedName,
        englishBrandName: canonicalEnglishBrandName,
        normalizedEnglishBrandName: normalizedEnglishName,
        dedupeKey,
        dedupeKeySource,
        requesterUID: uid,
        status: groupStatus,
        adminStage: groupAdminStage,
        requestCount: 1,
        duplicateOfRequestID: null,
        resolvedBrandID: groupResolvedBrandID,
        rejectionReason: isGroupRejected ? groupRejectionReason : null,
        createdAt: now,
        updatedAt: now,
        reviewedAt: groupAdminStage === "requested" ? null : now,
        resolvedAt: isGroupCompleted ? now : null,
        rejectedAt: isGroupRejected ? now : null,
        userVisibleUntil,
        adminArchivedAt: isGroupRejected || isGroupCompleted ? now : null,
        adminNote: nameIndexData?.adminNote ?? null,
      });

      const nextCount = currentCount + 1;
      transaction.set(counterRef, {
        uid,
        dateKey,
        count: nextCount,
        firstRequestedAt: counterSnap.exists ?
          counterData?.firstRequestedAt ?? now :
          now,
        lastRequestedAt: now,
        createdAt: counterSnap.exists ?
          counterData?.createdAt ?? now :
          now,
        updatedAt: now,
        expiresAt,
      }, {merge: true});

      const currentRequestCount = numericRootValue(
        nameIndexSnap.data(),
        "requestCount"
      );
      transaction.set(nameIndexRef, {
        groupID,
        dedupeKey,
        dedupeKeySource,
        normalizedBrandName: normalizedName,
        englishBrandName: canonicalEnglishBrandName,
        normalizedEnglishBrandName: normalizedEnglishName,
        displayNameSnapshot: brandName,
        requestCount: currentRequestCount + 1,
        status: nameIndexSnap.exists ? groupStatus : "submitted",
        adminStage: nameIndexSnap.exists ? groupAdminStage : "requested",
        rejectionReason: nameIndexSnap.exists ? groupRejectionReason : null,
        resolvedBrandID: nameIndexSnap.exists ? groupResolvedBrandID : null,
        reviewedAt: nameIndexSnap.exists ?
          nameIndexData?.reviewedAt ?? null :
          null,
        resolvedAt: nameIndexSnap.exists ?
          nameIndexData?.resolvedAt ?? null :
          null,
        rejectedAt: nameIndexSnap.exists ?
          nameIndexData?.rejectedAt ?? null :
          null,
        adminArchivedAt: nameIndexSnap.exists ?
          nameIndexData?.adminArchivedAt ?? null :
          null,
        adminNote: nameIndexSnap.exists ?
          nameIndexData?.adminNote ?? null :
          null,
        lastRequestID: requestID,
        lastRequestedAt: now,
        createdAt: nameIndexSnap.exists ?
          nameIndexSnap.data()?.createdAt ?? now :
          now,
        updatedAt: now,
      }, {merge: true});

      return {
        requestID,
        groupID,
        status: groupStatus,
        adminStage: groupAdminStage,
        isDuplicate: false,
        remainingToday: Math.max(0, BRAND_REQUEST_DAILY_LIMIT - nextCount),
      };
    });
  }
);

export const listMyBrandRequests = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data ?? {});
    const scope = brandRequestUserListScope(data);
    const limit = positiveInteger(
      data,
      "limit",
      BRAND_REQUEST_DEFAULT_USER_LIMIT,
      BRAND_REQUEST_MAX_USER_LIMIT
    );
    const cursorCreatedAt = optionalTimestampFromISO(data, "cursorCreatedAt");
    const cursorRequestID = optionalString(data, "cursorRequestID", 256);

    if ((cursorCreatedAt === null) !== (cursorRequestID === null)) {
      throw new HttpsError("invalid-argument", "cursor 값이 올바르지 않습니다.");
    }

    const pageSize = limit * 3;
    let query: FirebaseFirestore.Query = db
      .collection("brandRequests")
      .where("requesterUID", "==", uid)
      .orderBy("createdAt", "desc")
      .orderBy("requestID", "desc")
      .limit(Math.min(pageSize, BRAND_REQUEST_MAX_USER_LIMIT * 3));

    if (cursorCreatedAt && cursorRequestID) {
      query = query.startAfter(cursorCreatedAt, cursorRequestID);
    }

    const snapshot = await query.get();
    const last = snapshot.docs[snapshot.docs.length - 1];
    const groupRefs = snapshot.docs
      .map((doc) => {
        const groupID = doc.get("groupID");
        return typeof groupID === "string" && groupID.length > 0 ?
          db.collection("brandRequestNameIndex").doc(groupID) :
          null;
      })
      .filter((ref): ref is FirebaseFirestore.DocumentReference =>
        ref !== null
      );
    const groupSnaps = groupRefs.length > 0 ?
      await db.getAll(...groupRefs) :
      [];
    const groupDataByID = new Map<string, FirebaseFirestore.DocumentData>();
    for (const groupSnap of groupSnaps) {
      if (groupSnap.exists) {
        groupDataByID.set(groupSnap.id, groupSnap.data() ?? {});
      }
    }

    const requests = snapshot.docs
      .filter((doc) => {
        const docData = doc.data();
        const groupID = typeof docData.groupID === "string" ?
          docData.groupID :
          null;
        const groupData = groupID ? groupDataByID.get(groupID) : undefined;
        const source = groupData ?? docData;
        const status = source.status;
        const isInProgress = status === "submitted" || status === "reviewing";
        const isResolved = status === "added" || status === "rejected";

        if (scope === "active") {
          return isInProgress;
        }
        return isResolved;
      })
      .slice(0, limit)
      .map((doc) => {
        const docData = doc.data();
        const groupID = typeof docData.groupID === "string" ?
          docData.groupID :
          null;
        return brandRequestPublicSummary(
          doc.id,
          docData,
          groupID ? groupDataByID.get(groupID) : undefined
        );
      });

    return {
      requests,
      nextCursor: last ? {
        createdAt: timestampToISO(last.get("createdAt")),
        requestID: last.get("requestID") ?? last.id,
      } : null,
      scope,
    };
  }
);

export const listBrandRequests = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    await assertOutPickAdmin(uid);

    const data = recordData(request.data ?? {});
    const limit = positiveInteger(
      data,
      "limit",
      BRAND_REQUEST_DEFAULT_ADMIN_LIMIT,
      BRAND_REQUEST_MAX_ADMIN_LIMIT
    );
    const adminStage = optionalAdminStage(data, "adminStage");
    const cursorUpdatedAt = optionalTimestampFromISO(data, "cursorUpdatedAt");
    const cursorRequestID = optionalString(data, "cursorRequestID", 256);

    if ((cursorUpdatedAt === null) !== (cursorRequestID === null)) {
      throw new HttpsError("invalid-argument", "cursor 값이 올바르지 않습니다.");
    }

    let query: FirebaseFirestore.Query = db.collection("brandRequests");
    if (adminStage) {
      query = query.where("adminStage", "==", adminStage);
    } else {
      query = query.where("adminStage", "in", ["requested", "processing"]);
    }
    query = query
      .orderBy("updatedAt", "desc")
      .orderBy("requestID", "desc")
      .limit(limit);

    if (cursorUpdatedAt && cursorRequestID) {
      query = query.startAfter(cursorUpdatedAt, cursorRequestID);
    }

    const snapshot = await query.get();
    const requests = snapshot.docs.map((doc) =>
      brandRequestAdminSummary(doc.id, doc.data())
    );
    const last = snapshot.docs[snapshot.docs.length - 1];

    return {
      requests,
      nextCursor: last ? {
        updatedAt: timestampToISO(last.get("updatedAt")),
        requestID: last.get("requestID") ?? last.id,
      } : null,
    };
  }
);

export const listBrandRequestGroups = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    await assertOutPickAdmin(uid);

    const data = recordData(request.data ?? {});
    const limit = positiveInteger(
      data,
      "limit",
      BRAND_REQUEST_DEFAULT_ADMIN_LIMIT,
      BRAND_REQUEST_MAX_ADMIN_LIMIT
    );
    const adminStage = optionalAdminStage(data, "adminStage");
    const cursorUpdatedAt = optionalTimestampFromISO(data, "cursorUpdatedAt");
    const cursorGroupID = optionalString(data, "cursorGroupID", 256);

    if ((cursorUpdatedAt === null) !== (cursorGroupID === null)) {
      throw new HttpsError("invalid-argument", "cursor 값이 올바르지 않습니다.");
    }

    let query: FirebaseFirestore.Query = db.collection("brandRequestNameIndex");
    if (adminStage) {
      query = query.where("adminStage", "==", adminStage);
    } else {
      query = query.where("adminStage", "in", ["requested", "processing"]);
    }
    query = query
      .orderBy("updatedAt", "desc")
      .orderBy("groupID", "desc")
      .limit(limit);

    if (cursorUpdatedAt && cursorGroupID) {
      query = query.startAfter(cursorUpdatedAt, cursorGroupID);
    }

    const snapshot = await query.get();
    const groups = snapshot.docs.map((doc) =>
      brandRequestGroupSummary(doc.id, doc.data())
    );
    const last = snapshot.docs[snapshot.docs.length - 1];

    return {
      groups,
      nextCursor: last ? {
        updatedAt: timestampToISO(last.get("updatedAt")),
        groupID: last.get("groupID") ?? last.id,
      } : null,
    };
  }
);

export const updateBrandRequestStage = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    await assertOutPickAdmin(uid);

    const data = recordData(request.data);
    const requestID = requiredDocumentID(
      requiredString(data, "requestID", 256),
      "requestID"
    );
    const adminStage = requiredAdminStage(
      requiredString(data, "adminStage", 32),
      BRAND_REQUEST_STAGE_UPDATE_TARGETS
    );
    const adminNote = optionalString(data, "adminNote", 2000);
    const rejectionReason = optionalRejectionReason(data, "rejectionReason");

    if (adminStage === "rejected" && rejectionReason === null) {
      throw new HttpsError("invalid-argument", "rejectionReason 값이 필요합니다.");
    }
    if (adminStage !== "rejected" && rejectionReason !== null) {
      throw new HttpsError(
        "invalid-argument",
        "rejected 상태에서만 rejectionReason을 사용할 수 있습니다."
      );
    }

    const requestRef = db.collection("brandRequests").doc(requestID);

    return await db.runTransaction(async (transaction) => {
      const requestSnap = await transaction.get(requestRef);
      if (!requestSnap.exists) {
        throw new HttpsError("not-found", "브랜드 요청을 찾을 수 없습니다.");
      }

      const requestData = requestSnap.data();
      const previousStage = requestData?.adminStage;
      const requesterUID = typeof requestData?.requesterUID === "string" ?
        requestData.requesterUID :
        "";
      if (requesterUID.length === 0) {
        throw new HttpsError("failed-precondition", "요청자 정보가 없습니다.");
      }

      const previousRejectionReason = requestData?.rejectionReason;
      const shouldIncrementSpam =
        adminStage === "rejected" &&
        rejectionReason === "spam" &&
        !(previousStage === "rejected" && previousRejectionReason === "spam");
      const userLimitRef = db
        .collection("brandRequestUserLimits")
        .doc(requesterUID);
      const userLimitSnap = shouldIncrementSpam ?
        await transaction.get(userLimitRef) :
        null;

      const nowDate = new Date();
      const now = admin.firestore.Timestamp.fromDate(nowDate);
      const isRejected = adminStage === "rejected";
      const patch: Record<string, unknown> = {
        adminStage,
        status: requestStatusForAdminStage(adminStage),
        reviewedAt: now,
        updatedAt: now,
        reviewedBy: uid,
        rejectionReason: isRejected ? rejectionReason : null,
        rejectedAt: isRejected ? now : null,
        userVisibleUntil: isRejected ?
          admin.firestore.Timestamp.fromDate(
            addDays(nowDate, BRAND_REQUEST_USER_VISIBLE_DAYS)
          ) :
          null,
        adminArchivedAt: isRejected ? now : null,
      };
      if (adminNote !== null) {
        patch.adminNote = adminNote;
      }

      transaction.update(requestRef, patch);

      if (shouldIncrementSpam && userLimitSnap) {
        const spamCount =
          numericRootValue(userLimitSnap.data(), "spamCount") + 1;
        transaction.set(
          userLimitRef,
          spamLimitPatch(requesterUID, spamCount, nowDate),
          {merge: true}
        );
      }

      return {
        requestID,
        status: patch.status,
        adminStage,
      };
    });
  }
);

export const updateBrandRequestGroupStage = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    await assertOutPickAdmin(uid);

    const data = recordData(request.data);
    const groupID = requiredDocumentID(
      requiredString(data, "groupID", 256),
      "groupID"
    );
    const adminStage = requiredAdminStage(
      requiredString(data, "adminStage", 32),
      BRAND_REQUEST_STAGE_UPDATE_TARGETS
    );
    const adminNote = optionalString(data, "adminNote", 2000);
    const rejectionReason = optionalRejectionReason(data, "rejectionReason");

    if (adminStage === "rejected" && rejectionReason === null) {
      throw new HttpsError("invalid-argument", "rejectionReason 값이 필요합니다.");
    }
    if (adminStage !== "rejected" && rejectionReason !== null) {
      throw new HttpsError(
        "invalid-argument",
        "rejected 상태에서만 rejectionReason을 사용할 수 있습니다."
      );
    }

    const groupRef = db.collection("brandRequestNameIndex").doc(groupID);
    const groupRequestsQuery = db
      .collection("brandRequests")
      .where("groupID", "==", groupID)
      .limit(500);

    return await db.runTransaction(async (transaction) => {
      const [groupSnap, groupRequestsSnap] = await Promise.all([
        transaction.get(groupRef),
        transaction.get(groupRequestsQuery),
      ]);
      if (!groupSnap.exists) {
        throw new HttpsError("not-found", "브랜드 요청 그룹을 찾을 수 없습니다.");
      }

      const groupData = groupSnap.data();
      const groupRequestCount = numericRootValue(groupData, "requestCount");

      const nowDate = new Date();
      const now = admin.firestore.Timestamp.fromDate(nowDate);
      const isRejected = adminStage === "rejected";
      const status = requestStatusForAdminStage(adminStage);
      const patch: Record<string, unknown> = {
        adminStage,
        status,
        reviewedAt: now,
        updatedAt: now,
        reviewedBy: uid,
        rejectionReason: isRejected ? rejectionReason : null,
        rejectedAt: isRejected ? now : null,
        userVisibleUntil: isRejected ?
          admin.firestore.Timestamp.fromDate(
            addDays(nowDate, BRAND_REQUEST_USER_VISIBLE_DAYS)
          ) :
          null,
        adminArchivedAt: isRejected ? now : null,
      };
      if (adminNote !== null) {
        patch.adminNote = adminNote;
      }

      transaction.update(groupRef, patch);
      for (const requestDoc of groupRequestsSnap.docs) {
        transaction.update(requestDoc.ref, patch);
      }

      return {
        groupID,
        status,
        adminStage,
        updatedRequestCount: groupRequestsSnap.size || groupRequestCount,
      };
    });
  }
);

export const resolveBrandRequestGroup = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    await assertOutPickAdmin(uid);

    const data = recordData(request.data);
    const groupID = requiredDocumentID(
      requiredString(data, "groupID", 256),
      "groupID"
    );
    const resolvedBrandID = requiredDocumentID(
      requiredString(data, "resolvedBrandID", 128),
      "resolvedBrandID"
    );
    const adminNote = optionalString(data, "adminNote", 2000);

    const groupRef = db.collection("brandRequestNameIndex").doc(groupID);
    const brandRef = db.collection("brands").doc(resolvedBrandID);
    const groupRequestsQuery = db
      .collection("brandRequests")
      .where("groupID", "==", groupID)
      .limit(500);

    return await db.runTransaction(async (transaction) => {
      const [groupSnap, brandSnap, groupRequestsSnap] = await Promise.all([
        transaction.get(groupRef),
        transaction.get(brandRef),
        transaction.get(groupRequestsQuery),
      ]);

      if (!groupSnap.exists) {
        throw new HttpsError("not-found", "브랜드 요청 그룹을 찾을 수 없습니다.");
      }
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }

      const nowDate = new Date();
      const now = admin.firestore.Timestamp.fromDate(nowDate);
      const patch: Record<string, unknown> = {
        adminStage: "completed",
        status: "added",
        resolvedBrandID,
        rejectionReason: null,
        resolvedAt: now,
        reviewedAt: now,
        updatedAt: now,
        reviewedBy: uid,
        userVisibleUntil: admin.firestore.Timestamp.fromDate(
          addDays(nowDate, BRAND_REQUEST_USER_VISIBLE_DAYS)
        ),
        adminArchivedAt: now,
      };
      if (adminNote !== null) {
        patch.adminNote = adminNote;
      }
      transaction.update(groupRef, patch);
      for (const requestDoc of groupRequestsSnap.docs) {
        transaction.update(requestDoc.ref, patch);
      }

      return {
        groupID,
        status: "added",
        adminStage: "completed",
        resolvedBrandID,
        updatedRequestCount: groupRequestsSnap.size || numericRootValue(
          groupSnap.data(),
          "requestCount"
        ),
      };
    });
  }
);

export const markBrandRequestGroupBrandCreated = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    await assertOutPickAdmin(uid);

    const data = recordData(request.data);
    const groupID = requiredDocumentID(
      requiredString(data, "groupID", 256),
      "groupID"
    );
    const createdBrandID = requiredDocumentID(
      requiredString(data, "createdBrandID", 128),
      "createdBrandID"
    );

    const groupRef = db.collection("brandRequestNameIndex").doc(groupID);
    const brandRef = db.collection("brands").doc(createdBrandID);

    return await db.runTransaction(async (transaction) => {
      const [groupSnap, brandSnap] = await Promise.all([
        transaction.get(groupRef),
        transaction.get(brandRef),
      ]);

      if (!groupSnap.exists) {
        throw new HttpsError("not-found", "브랜드 요청 그룹을 찾을 수 없습니다.");
      }
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }

      const groupData = groupSnap.data();
      const adminStage = typeof groupData?.adminStage === "string" ?
        groupData.adminStage :
        "requested";
      if (adminStage !== "processing") {
        throw new HttpsError(
          "failed-precondition",
          "처리 중인 브랜드 요청 그룹만 생성 브랜드를 연결할 수 있습니다."
        );
      }

      const existingCreatedBrandID =
        typeof groupData?.createdBrandID === "string" ?
          groupData.createdBrandID :
          null;
      if (
        existingCreatedBrandID !== null &&
        existingCreatedBrandID !== createdBrandID
      ) {
        throw new HttpsError(
          "already-exists",
          "이미 다른 브랜드가 생성된 요청 그룹입니다."
        );
      }

      const now = admin.firestore.Timestamp.fromDate(new Date());
      transaction.update(groupRef, {
        createdBrandID,
        brandCreatedAt: groupData?.brandCreatedAt ?? now,
        brandCreatedBy: groupData?.brandCreatedBy ?? uid,
        updatedAt: now,
      });

      return {
        groupID,
        status: typeof groupData?.status === "string" ?
          groupData.status :
          "reviewing",
        adminStage,
        createdBrandID,
        updatedRequestCount: numericRootValue(groupData, "requestCount"),
      };
    });
  }
);

export const resolveBrandRequest = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    await assertOutPickAdmin(uid);

    const data = recordData(request.data);
    const requestID = requiredDocumentID(
      requiredString(data, "requestID", 256),
      "requestID"
    );
    const resolvedBrandID = requiredDocumentID(
      requiredString(data, "resolvedBrandID", 128),
      "resolvedBrandID"
    );

    const requestRef = db.collection("brandRequests").doc(requestID);
    const brandRef = db.collection("brands").doc(resolvedBrandID);

    await db.runTransaction(async (transaction) => {
      const [requestSnap, brandSnap] = await Promise.all([
        transaction.get(requestRef),
        transaction.get(brandRef),
      ]);

      if (!requestSnap.exists) {
        throw new HttpsError("not-found", "브랜드 요청을 찾을 수 없습니다.");
      }
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }

      const nowDate = new Date();
      const now = admin.firestore.Timestamp.fromDate(nowDate);
      transaction.update(requestRef, {
        adminStage: "completed",
        status: "added",
        resolvedBrandID,
        rejectionReason: null,
        resolvedAt: now,
        reviewedAt: now,
        updatedAt: now,
        reviewedBy: uid,
        userVisibleUntil: admin.firestore.Timestamp.fromDate(
          addDays(nowDate, BRAND_REQUEST_USER_VISIBLE_DAYS)
        ),
        adminArchivedAt: now,
      });
    });

    return {
      requestID,
      status: "added",
      adminStage: "completed",
      resolvedBrandID,
    };
  }
);

export const searchBrands = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data ?? {});
    const query = normalizedBrandName(requiredString(data, "query", 80));
    const limit = positiveInteger(
      data,
      "limit",
      BRAND_SEARCH_DEFAULT_LIMIT,
      BRAND_SEARCH_MAX_LIMIT
    );

    const [nameSnapshot, englishNameSnapshot] = await Promise.all([
      db
        .collection("brands")
        .orderBy("normalizedName")
        .startAt(query)
        .endAt(`${query}\uf8ff`)
        .limit(limit)
        .get(),
      db
        .collection("brands")
        .orderBy("normalizedEnglishName")
        .startAt(query)
        .endAt(`${query}\uf8ff`)
        .limit(limit)
        .get(),
    ]);

    const brands = new Map<string, Record<string, unknown>>();
    for (const doc of [...nameSnapshot.docs, ...englishNameSnapshot.docs]) {
      if (brands.has(doc.id)) {
        continue;
      }
      brands.set(doc.id, brandSearchSummary(doc.id, doc.data()));
      if (brands.size >= limit) {
        break;
      }
    }

    return {
      brands: Array.from(brands.values()),
      query,
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
    const englishNameInput = optionalString(data, "englishName", 80);
    const englishName = englishNameInput === null ?
      null :
      canonicalBrandName(englishNameInput);
    const normalizedEnglishName = englishName === null ?
      null :
      normalizedBrandName(englishName);
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
    const nameIndexEntries = brandNameIndexEntries(
      normalizedName,
      normalizedEnglishName
    );
    const nameIndexRefs = nameIndexEntries.map((entry) =>
      db.collection("brandNameIndex").doc(entry.key)
    );

    await db.runTransaction(async (transaction) => {
      const nameIndexSnaps = await Promise.all(
        nameIndexRefs.map((ref) => transaction.get(ref))
      );
      if (nameIndexSnaps.some((snap) => snap.exists)) {
        throw new HttpsError("already-exists", "이미 존재하는 브랜드명입니다.");
      }

      transaction.set(brandRef, {
        name,
        normalizedName,
        englishName,
        normalizedEnglishName,
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
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      nameIndexRefs.forEach((ref, index) => {
        const entry = nameIndexEntries[index];
        transaction.set(ref, {
          brandID,
          name,
          normalizedName,
          englishName,
          normalizedEnglishName,
          source: entry.source,
          createdBy: uid,
          createdAt: FieldValue.serverTimestamp(),
        });
      });
    });

    return {brandID};
  }
);

export const updateBrand = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const hasNamePatch = Object.prototype.hasOwnProperty.call(data, "name");
    const name = hasNamePatch ?
      canonicalBrandName(requiredString(data, "name", 80)) :
      null;
    const normalizedName = name === null ? null : normalizedBrandName(name);
    const hasEnglishNamePatch = Object.prototype.hasOwnProperty.call(
      data,
      "englishName"
    );
    const englishNamePatch = hasEnglishNamePatch ?
      optionalString(data, "englishName", 80) :
      null;
    const englishName = !hasEnglishNamePatch || englishNamePatch === null ?
      null :
      canonicalBrandName(englishNamePatch);
    const normalizedEnglishName = !hasEnglishNamePatch || englishName === null ?
      null :
      normalizedBrandName(englishName);
    const websiteURL = optionalHTTPURLPatch(data, "websiteURL");
    const lookbookArchiveURL = optionalHTTPURLPatch(data, "lookbookArchiveURL");
    const hasFeaturedPatch = hasBooleanPatch(data, "isFeatured");
    const isFeatured = hasFeaturedPatch ?
      requiredBoolean(data, "isFeatured") :
      null;

    if (
      !hasNamePatch &&
      !hasEnglishNamePatch &&
      websiteURL === undefined &&
      lookbookArchiveURL === undefined &&
      !hasFeaturedPatch
    ) {
      throw new HttpsError("invalid-argument", "수정할 브랜드 필드가 없습니다.");
    }

    const isTotalAdmin = await isTotalBrandAdmin(uid);
    if (hasFeaturedPatch && !isTotalAdmin) {
      throw new HttpsError("permission-denied", "피처드 수정 권한이 없습니다.");
    }

    const brandRef = db.collection("brands").doc(brandID);
    const managerRef = brandRef.collection("admins").doc(uid);

    await db.runTransaction(async (transaction) => {
      const brandSnap = await transaction.get(brandRef);
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }

      const brandData = brandSnap.data();
      let hasWriteAccess = isTotalAdmin;
      if (!hasWriteAccess) {
        const managerSnap = await transaction.get(managerRef);
        hasWriteAccess = hasBrandWriteAccessData(managerSnap.data());
      }
      if (!hasWriteAccess) {
        throw new HttpsError("permission-denied", "브랜드 수정 권한이 없습니다.");
      }

      const patch: Record<string, unknown> = {
        updatedBy: uid,
        updatedAt: FieldValue.serverTimestamp(),
      };

      if (
        (hasNamePatch && name !== null && normalizedName !== null) ||
        hasEnglishNamePatch
      ) {
        const nextName = name ?? (
          typeof brandData?.name === "string" ? brandData.name : ""
        );
        const nextNormalizedName = normalizedName ?? (
          typeof brandData?.normalizedName === "string" ?
            brandData.normalizedName :
            normalizedBrandName(nextName)
        );
        const nextEnglishName = hasEnglishNamePatch ?
          englishName :
          (typeof brandData?.englishName === "string" ?
            brandData.englishName :
            null);
        const nextNormalizedEnglishName = hasEnglishNamePatch ?
          normalizedEnglishName :
          (typeof brandData?.normalizedEnglishName === "string" ?
            brandData.normalizedEnglishName :
            null);
        const previousNormalizedName =
          typeof brandData?.normalizedName === "string" ?
            brandData.normalizedName :
            "";
        const previousNormalizedEnglishName =
          typeof brandData?.normalizedEnglishName === "string" ?
            brandData.normalizedEnglishName :
            null;
        const previousIndexKeys = new Set(
          brandNameIndexEntries(
            previousNormalizedName,
            previousNormalizedEnglishName
          ).map((entry) => entry.key)
        );
        const nextIndexEntries = brandNameIndexEntries(
          nextNormalizedName,
          nextNormalizedEnglishName
        );
        const nextIndexKeys = new Set(
          nextIndexEntries.map((entry) => entry.key)
        );
        const refsToCheck = nextIndexEntries
          .filter((entry) => !previousIndexKeys.has(entry.key))
          .map((entry) => db.collection("brandNameIndex").doc(entry.key));
        const newNameIndexSnaps = await Promise.all(
          refsToCheck.map((ref) => transaction.get(ref))
        );
        if (
          newNameIndexSnaps.some((snap) =>
            snap.exists && snap.get("brandID") !== brandID
          )
        ) {
          throw new HttpsError("already-exists", "이미 존재하는 브랜드명입니다.");
        }

        for (const previousKey of previousIndexKeys) {
          if (!nextIndexKeys.has(previousKey)) {
            transaction.delete(
              db.collection("brandNameIndex").doc(previousKey)
            );
          }
        }

        for (const entry of nextIndexEntries) {
          const indexRef = db.collection("brandNameIndex").doc(entry.key);
          transaction.set(indexRef, {
            brandID,
            name: nextName,
            normalizedName: nextNormalizedName,
            englishName: nextEnglishName,
            normalizedEnglishName: nextNormalizedEnglishName,
            source: entry.source,
            updatedBy: uid,
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        }

        if (hasNamePatch && name !== null && normalizedName !== null) {
          patch.name = name;
          patch.normalizedName = normalizedName;
        }
        if (hasEnglishNamePatch) {
          patch.englishName = englishName;
          patch.normalizedEnglishName = normalizedEnglishName;
        }
      }

      if (websiteURL !== undefined) {
        patch.websiteURL = websiteURL;
      }
      if (lookbookArchiveURL !== undefined) {
        patch.lookbookArchiveURL = lookbookArchiveURL;
      }
      if (isFeatured !== null) {
        patch.isFeatured = isFeatured;
      }

      transaction.update(brandRef, patch);
    });

    const updatedBrandSnap = await brandRef.get();
    return {
      brandID,
      brand: brandSearchSummary(brandID, updatedBrandSnap.data()),
    };
  }
);

export const addBrandManager = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const email = normalizedEmail(requiredString(data, "email", 254));
    const role = requiredBrandManagerRole(requiredString(data, "role", 16));
    const targetUID = await findUserIDByEmail(email);
    const isTotalAdmin = await isTotalBrandAdmin(uid);
    const brandRef = db.collection("brands").doc(brandID);
    const callerManagerRef = brandRef.collection("admins").doc(uid);
    const targetManagerRef = brandRef.collection("admins").doc(targetUID);

    const result = await db.runTransaction(async (transaction) => {
      const brandSnap = await transaction.get(brandRef);
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }

      let callerIsOwner = false;
      if (!isTotalAdmin) {
        const callerManagerSnap = await transaction.get(callerManagerRef);
        callerIsOwner = isBrandOwnerData(callerManagerSnap.data());
      }

      if (!isTotalAdmin) {
        if (!callerIsOwner) {
          throw new HttpsError("permission-denied", "관리자 추가 권한이 없습니다.");
        }
        if (role === "owner") {
          throw new HttpsError("permission-denied", "owner 추가 권한이 없습니다.");
        }
      }

      const targetManagerSnap = await transaction.get(targetManagerRef);
      const currentRole =
        typeof targetManagerSnap.data()?.role === "string" ?
          targetManagerSnap.data()?.role :
          null;
      let duplicate = currentRole === role;

      if (role === "owner") {
        transaction.set(targetManagerRef, {
          uid: targetUID,
          brandID,
          role,
          email,
          normalizedEmail: email,
          addedBy: targetManagerSnap.exists ?
            targetManagerSnap.data()?.addedBy ?? uid :
            uid,
          addedAt: targetManagerSnap.exists ?
            targetManagerSnap.data()?.addedAt ?? FieldValue.serverTimestamp() :
            FieldValue.serverTimestamp(),
          updatedBy: uid,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      } else {
        if (currentRole === "owner") {
          duplicate = true;
        } else {
          transaction.set(targetManagerRef, {
            uid: targetUID,
            brandID,
            role,
            email,
            normalizedEmail: email,
            addedBy: targetManagerSnap.exists ?
              targetManagerSnap.data()?.addedBy ?? uid :
              uid,
            addedAt: targetManagerSnap.exists ?
              targetManagerSnap.data()?.addedAt ??
                FieldValue.serverTimestamp() :
              FieldValue.serverTimestamp(),
            updatedBy: uid,
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        }
      }

      transaction.update(brandRef, {
        updatedBy: uid,
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {targetUID, duplicate};
    });

    return {
      brandID,
      uid: result.targetUID,
      email,
      role,
      duplicate: result.duplicate,
    };
  }
);

export const removeBrandManager = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const email = normalizedEmail(requiredString(data, "email", 254));
    const role = requiredBrandManagerRole(requiredString(data, "role", 16));
    const targetUID = await findUserIDByEmail(email);
    const isTotalAdmin = await isTotalBrandAdmin(uid);
    const brandRef = db.collection("brands").doc(brandID);
    const callerManagerRef = brandRef.collection("admins").doc(uid);
    const targetManagerRef = brandRef.collection("admins").doc(targetUID);

    const result = await db.runTransaction(async (transaction) => {
      const brandSnap = await transaction.get(brandRef);
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }

      let callerIsOwner = false;
      if (!isTotalAdmin) {
        const callerManagerSnap = await transaction.get(callerManagerRef);
        callerIsOwner = isBrandOwnerData(callerManagerSnap.data());
      }

      if (!isTotalAdmin) {
        if (!callerIsOwner) {
          throw new HttpsError("permission-denied", "관리자 삭제 권한이 없습니다.");
        }
        if (role === "owner") {
          throw new HttpsError("permission-denied", "owner 삭제 권한이 없습니다.");
        }
      }

      const targetManagerSnap = await transaction.get(targetManagerRef);
      const currentRole =
        typeof targetManagerSnap.data()?.role === "string" ?
          targetManagerSnap.data()?.role :
          null;
      let removed = false;

      if (currentRole === role) {
        removed = true;
      }

      if (removed && role === "owner") {
        const ownerQuerySnap = await transaction.get(
          brandRef.collection("admins")
            .where("role", "==", "owner")
            .limit(2)
        );
        const hasOtherOwner = ownerQuerySnap.docs.some((doc) => {
          return doc.id !== targetUID;
        });
        if (!hasOtherOwner) {
          throw new HttpsError(
            "failed-precondition",
            "마지막 owner는 삭제할 수 없습니다."
          );
        }
      }

      if (removed) {
        transaction.delete(targetManagerRef);
      }

      transaction.update(brandRef, {
        updatedBy: uid,
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {targetUID, removed};
    });

    return {
      brandID,
      uid: result.targetUID,
      email,
      role,
      removed: result.removed,
    };
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

export const requestBrandDeletion = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    await assertOutPickAdmin(uid);

    const data = recordData(request.data);
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const reason = optionalString(data, "reason", 1000);
    const requestID = randomUUID();
    const brandRef = db.collection("brands").doc(brandID);
    const requestRef = db.collection("lookbookDeletionRequests").doc(requestID);
    const auditRef = db.collection("lookbookDeletionAuditLogs").doc();

    return await db.runTransaction(async (transaction) => {
      const brandSnap = await transaction.get(brandRef);
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }

      const brandData = brandSnap.data();
      if (brandData?.deletionStatus === "deletionRequested") {
        return {
          brandID,
          requestID: typeof brandData.deleteRequestID === "string" ?
            brandData.deleteRequestID :
            null,
          status: "active",
          duplicate: true,
        };
      }

      const nowDate = new Date();
      const displaySnapshot = lookbookDeletionDisplaySnapshot(
        "brand",
        brandData
      );
      const deletionPatch = deletionRequestPatch(
        requestID,
        "brand",
        brandID,
        null,
        null,
        uid,
        reason,
        nowDate,
        displaySnapshot
      );
      transaction.update(brandRef, {
        deletionStatus: "deletionRequested",
        deletionRequestedAt: deletionPatch.requestedAt,
        deletionRequestedBy: uid,
        deletionReason: reason,
        restoreUntil: deletionPatch.restoreUntil,
        purgeAfter: deletionPatch.purgeAfter,
        deleteRequestID: requestID,
        updatedBy: uid,
        updatedAt: deletionPatch.updatedAt,
      });
      transaction.set(requestRef, deletionPatch);
      transaction.set(auditRef, deletionAuditPatch(
        "requestBrandDeletion",
        requestID,
        "brand",
        brandID,
        null,
        null,
        uid,
        reason,
        nowDate,
        typeof brandData?.deletionStatus === "string" ?
          brandData.deletionStatus :
          "active",
        "deletionRequested"
      ));

      return {
        brandID,
        requestID,
        status: "active",
        duplicate: false,
      };
    });
  }
);

export const cancelBrandDeletion = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    await assertOutPickAdmin(uid);

    const data = recordData(request.data);
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const brandRef = db.collection("brands").doc(brandID);
    const auditRef = db.collection("lookbookDeletionAuditLogs").doc();

    return await db.runTransaction(async (transaction) => {
      const brandSnap = await transaction.get(brandRef);
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }

      const brandData = brandSnap.data();
      if (brandData?.deletionStatus !== "deletionRequested") {
        return {
          brandID,
          requestID: null,
          status: "cancelled",
          cancelled: false,
        };
      }

      const requestID = typeof brandData.deleteRequestID === "string" ?
        brandData.deleteRequestID :
        "";
      if (requestID.length === 0) {
        throw new HttpsError(
          "failed-precondition",
          "삭제 요청 ID가 없습니다."
        );
      }

      const nowDate = new Date();
      const now = admin.firestore.Timestamp.fromDate(nowDate);
      const requestRef = db
        .collection("lookbookDeletionRequests")
        .doc(requestID);

      transaction.update(brandRef, {
        ...clearDeletionFields(),
        updatedBy: uid,
      });
      transaction.set(requestRef, {
        status: "cancelled",
        cancelledBy: uid,
        cancelledAt: now,
        updatedBy: uid,
        updatedAt: now,
      }, {merge: true});
      transaction.set(auditRef, deletionAuditPatch(
        "cancelBrandDeletion",
        requestID,
        "brand",
        brandID,
        null,
        null,
        uid,
        typeof brandData.deletionReason === "string" ?
          brandData.deletionReason :
          null,
        nowDate,
        "deletionRequested",
        "active"
      ));

      return {
        brandID,
        requestID,
        status: "cancelled",
        cancelled: true,
      };
    });
  }
);

export const softDeleteSeason = onCall(
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
    const reason = optionalString(data, "reason", 1000);

    await assertBrandWriteAccess(uid, brandID);
    return await softDeleteSeasonTarget(uid, brandID, seasonID, reason);
  }
);

export const batchSoftDeleteSeasons = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const seasonIDs = requiredDocumentIDList(
      data.seasonIDs,
      "seasonIDs",
      LOOKBOOK_DELETION_BATCH_MAX_COUNT
    );
    const reason = optionalString(data, "reason", 1000);

    await assertBrandWriteAccess(uid, brandID);
    await assertBatchDeletionPreconditions(brandID, null, "시즌");

    const results = await mapWithConcurrency(
      seasonIDs,
      LOOKBOOK_DELETION_BATCH_CONCURRENCY,
      async (seasonID) => {
        try {
          return await softDeleteSeasonTarget(uid, brandID, seasonID, reason);
        } catch (error) {
          return lookbookDeletionFailureResult(
            "season",
            brandID,
            seasonID,
            null,
            error
          );
        }
      }
    );

    return lookbookDeletionBatchResponse(
      "season",
      brandID,
      seasonIDs.length,
      results
    );
  }
);

export const restoreSeason = onCall(
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

    await assertBrandWriteAccess(uid, brandID);

    const brandRef = db.collection("brands").doc(brandID);
    const seasonRef = brandRef.collection("seasons").doc(seasonID);
    const auditRef = db.collection("lookbookDeletionAuditLogs").doc();

    return await db.runTransaction(async (transaction) => {
      const [brandSnap, seasonSnap] = await Promise.all([
        transaction.get(brandRef),
        transaction.get(seasonRef),
      ]);
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }
      if (!seasonSnap.exists) {
        throw new HttpsError("not-found", "시즌을 찾을 수 없습니다.");
      }
      if (brandSnap.data()?.deletionStatus === "deletionRequested") {
        throw new HttpsError(
          "failed-precondition",
          "삭제 요청 중인 브랜드의 시즌은 복구할 수 없습니다."
        );
      }

      const seasonData = seasonSnap.data();
      if (seasonData?.deletionStatus !== "deleted") {
        return {
          brandID,
          seasonID,
          requestID: null,
          status: "restored",
          restored: false,
        };
      }

      const requestID = typeof seasonData.deleteRequestID === "string" ?
        seasonData.deleteRequestID :
        "";
      if (requestID.length === 0) {
        throw new HttpsError(
          "failed-precondition",
          "삭제 요청 ID가 없습니다."
        );
      }

      const nowDate = new Date();
      const now = admin.firestore.Timestamp.fromDate(nowDate);
      const requestRef = db
        .collection("lookbookDeletionRequests")
        .doc(requestID);
      transaction.update(seasonRef, clearDeletionFields());
      transaction.set(requestRef, {
        status: "restored",
        restoredBy: uid,
        restoredAt: now,
        updatedBy: uid,
        updatedAt: now,
      }, {merge: true});
      transaction.set(auditRef, deletionAuditPatch(
        "restoreSeason",
        requestID,
        "season",
        brandID,
        seasonID,
        null,
        uid,
        typeof seasonData.deleteReason === "string" ?
          seasonData.deleteReason :
          null,
        nowDate,
        "deleted",
        "active"
      ));

      return {
        brandID,
        seasonID,
        requestID,
        status: "restored",
        restored: true,
      };
    });
  }
);

export const softDeletePost = onCall(
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
    const reason = optionalString(data, "reason", 1000);

    await assertBrandWriteAccess(uid, brandID);
    return await softDeletePostTarget(uid, brandID, seasonID, postID, reason);
  }
);

export const batchSoftDeletePosts = onCall(
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
    const postIDs = requiredDocumentIDList(
      data.postIDs,
      "postIDs",
      LOOKBOOK_DELETION_BATCH_MAX_COUNT
    );
    const reason = optionalString(data, "reason", 1000);

    await assertBrandWriteAccess(uid, brandID);
    await assertBatchDeletionPreconditions(brandID, seasonID, "포스트");

    const results = await mapWithConcurrency(
      postIDs,
      LOOKBOOK_DELETION_BATCH_CONCURRENCY,
      async (postID) => {
        try {
          return await softDeletePostTarget(
            uid,
            brandID,
            seasonID,
            postID,
            reason
          );
        } catch (error) {
          return lookbookDeletionFailureResult(
            "post",
            brandID,
            seasonID,
            postID,
            error
          );
        }
      }
    );

    return lookbookDeletionBatchResponse(
      "post",
      brandID,
      postIDs.length,
      results
    );
  }
);

export const restorePost = onCall(
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

    await assertBrandWriteAccess(uid, brandID);

    const brandRef = db.collection("brands").doc(brandID);
    const seasonRef = brandRef.collection("seasons").doc(seasonID);
    const postRef = seasonRef.collection("posts").doc(postID);
    const auditRef = db.collection("lookbookDeletionAuditLogs").doc();

    return await db.runTransaction(async (transaction) => {
      const [brandSnap, seasonSnap, postSnap] = await Promise.all([
        transaction.get(brandRef),
        transaction.get(seasonRef),
        transaction.get(postRef),
      ]);
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }
      if (!seasonSnap.exists) {
        throw new HttpsError("not-found", "시즌을 찾을 수 없습니다.");
      }
      if (!postSnap.exists) {
        throw new HttpsError("not-found", "포스트를 찾을 수 없습니다.");
      }
      if (brandSnap.data()?.deletionStatus === "deletionRequested") {
        throw new HttpsError(
          "failed-precondition",
          "삭제 요청 중인 브랜드의 포스트는 복구할 수 없습니다."
        );
      }
      if (seasonSnap.data()?.deletionStatus === "deleted") {
        throw new HttpsError(
          "failed-precondition",
          "삭제된 시즌의 포스트는 개별 복구할 수 없습니다."
        );
      }

      const postData = postSnap.data();
      if (postData?.deletionStatus !== "deleted") {
        return {
          brandID,
          seasonID,
          postID,
          requestID: null,
          status: "restored",
          restored: false,
        };
      }

      const requestID = typeof postData.deleteRequestID === "string" ?
        postData.deleteRequestID :
        "";
      if (requestID.length === 0) {
        throw new HttpsError(
          "failed-precondition",
          "삭제 요청 ID가 없습니다."
        );
      }

      const nowDate = new Date();
      const now = admin.firestore.Timestamp.fromDate(nowDate);
      const requestRef = db
        .collection("lookbookDeletionRequests")
        .doc(requestID);
      transaction.update(postRef, clearDeletionFields());
      transaction.set(requestRef, {
        status: "restored",
        restoredBy: uid,
        restoredAt: now,
        updatedBy: uid,
        updatedAt: now,
      }, {merge: true});
      transaction.set(auditRef, deletionAuditPatch(
        "restorePost",
        requestID,
        "post",
        brandID,
        seasonID,
        postID,
        uid,
        typeof postData.deleteReason === "string" ?
          postData.deleteReason :
          null,
        nowDate,
        "deleted",
        "active"
      ));

      return {
        brandID,
        seasonID,
        postID,
        requestID,
        status: "restored",
        restored: true,
      };
    });
  }
);

export const listLookbookDeletionRequests = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const capabilities = await brandAdminCapabilities(uid);

    if (
      !capabilities.isTotalAdmin &&
      capabilities.ownedBrandIDs.length === 0 &&
      capabilities.adminBrandIDs.length === 0
    ) {
      throw new HttpsError("permission-denied", "삭제 요청 조회 권한이 없습니다.");
    }

    const data = recordData(request.data ?? {});
    const limit = positiveInteger(
      data,
      "limit",
      LOOKBOOK_DELETION_DEFAULT_LIMIT,
      LOOKBOOK_DELETION_MAX_LIMIT
    );
    const status = optionalDeletionRequestStatus(data, "status") ?? "active";
    const targetType = optionalDeletionTargetType(data, "targetType");
    const brandID = optionalDocumentID(
      optionalString(data, "brandID", 128),
      "brandID"
    );
    const cursorUpdatedAt = optionalTimestampFromISO(data, "cursorUpdatedAt");
    const cursorRequestID = optionalString(data, "cursorRequestID", 256);

    if ((cursorUpdatedAt === null) !== (cursorRequestID === null)) {
      throw new HttpsError("invalid-argument", "cursor 값이 올바르지 않습니다.");
    }

    if (!capabilities.isTotalAdmin) {
      if (brandID === null) {
        throw new HttpsError(
          "invalid-argument",
          "브랜드 관리자 조회에는 brandID가 필요합니다."
        );
      }
      const allowedBrandIDs = new Set([
        ...capabilities.ownedBrandIDs,
        ...capabilities.adminBrandIDs,
      ]);
      if (!allowedBrandIDs.has(brandID)) {
        throw new HttpsError(
          "permission-denied",
          "해당 브랜드 삭제 요청 조회 권한이 없습니다."
        );
      }
    }

    let query: FirebaseFirestore.Query =
      db.collection("lookbookDeletionRequests")
        .where("status", "==", status);
    if (brandID !== null) {
      query = query.where("brandID", "==", brandID);
    }
    if (targetType !== null) {
      query = query.where("targetType", "==", targetType);
    }
    query = query
      .orderBy("updatedAt", "desc")
      .orderBy("requestID", "desc")
      .limit(limit);

    if (cursorUpdatedAt && cursorRequestID) {
      query = query.startAfter(cursorUpdatedAt, cursorRequestID);
    }

    const snapshot = await query.get();
    const requests = await Promise.all(snapshot.docs.map((doc) =>
      deletionRequestSummaryWithDisplayFallback(doc.id, doc.data())
    )
    );
    const last = snapshot.docs[snapshot.docs.length - 1];

    return {
      requests,
      nextCursor: last ? {
        updatedAt: timestampToISO(last.get("updatedAt")),
        requestID: last.get("requestID") ?? last.id,
      } : null,
    };
  }
);

function shouldRetryFailedPurge(
  data: FirebaseFirestore.DocumentData,
  nowMillis: number
): boolean {
  const attemptCount = numericMetric(data.purgeAttemptCount);
  if (attemptCount >= LOOKBOOK_PURGE_RETRY_LIMIT) {
    return false;
  }

  const retryAfterMillis = firestoreTimestampMillis(data.retryAfter);
  return retryAfterMillis === null || retryAfterMillis <= nowMillis;
}

async function loadExpiredDeletionRequests(
  now: admin.firestore.Timestamp
): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  const snapshots = await Promise.all([
    db.collection("lookbookDeletionRequests")
      .where("status", "==", "active")
      .where("purgeAfter", "<=", now)
      .orderBy("purgeAfter", "asc")
      .limit(LOOKBOOK_PURGE_TARGET_LIMIT)
      .get(),
    db.collection("lookbookDeletionRequests")
      .where("status", "==", "failed")
      .where("autoRetryEligible", "==", true)
      .where("purgeAfter", "<=", now)
      .orderBy("purgeAfter", "asc")
      .limit(LOOKBOOK_PURGE_TARGET_LIMIT)
      .get(),
  ]);

  const nowMillis = now.toMillis();
  const byID = new Map<string, FirebaseFirestore.QueryDocumentSnapshot>();
  snapshots.flatMap((snapshot) => snapshot.docs).forEach((doc) => {
    const data = doc.data();
    if (data.status === "failed" && !shouldRetryFailedPurge(data, nowMillis)) {
      return;
    }
    byID.set(doc.id, doc);
  });

  return Array.from(byID.values())
    .sort((lhs, rhs) => {
      const lhsPurgeAfter =
        firestoreTimestampMillis(lhs.get("purgeAfter")) ?? 0;
      const rhsPurgeAfter =
        firestoreTimestampMillis(rhs.get("purgeAfter")) ?? 0;
      if (lhsPurgeAfter !== rhsPurgeAfter) {
        return lhsPurgeAfter - rhsPurgeAfter;
      }
      return lhs.id.localeCompare(rhs.id);
    })
    .slice(0, LOOKBOOK_PURGE_TARGET_LIMIT);
}

function purgeSuccessPatch(
  now: admin.firestore.Timestamp
): Record<string, unknown> {
  return {
    status: "purged",
    purgedBy: "system",
    purgedAt: now,
    autoRetryEligible: false,
    purgeErrorMessage: null,
    retryAfter: null,
    updatedBy: "system",
    updatedAt: now,
  };
}

async function markDeletionRequestPurged(
  ref: FirebaseFirestore.DocumentReference,
  now: admin.firestore.Timestamp
): Promise<void> {
  await ref.set(purgeSuccessPatch(now), {merge: true});
}

async function markRelatedDeletionRequestsPurged(
  currentRequestID: string,
  brandID: string,
  seasonID: string | null,
  postID: string | null,
  now: admin.firestore.Timestamp
): Promise<number> {
  let query: FirebaseFirestore.Query = db
    .collection("lookbookDeletionRequests")
    .where("brandID", "==", brandID)
    .where("status", "in", ["active", "failed"]);

  if (seasonID !== null) {
    query = query.where("seasonID", "==", seasonID);
  }
  if (postID !== null) {
    query = query.where("postID", "==", postID);
  }

  const snapshot = await query.get();
  const relatedDocs = snapshot.docs.filter((doc) =>
    doc.id !== currentRequestID
  );
  if (relatedDocs.length === 0) {
    return 0;
  }

  let updatedCount = 0;
  for (let index = 0; index < relatedDocs.length; index += 400) {
    const batch = db.batch();
    relatedDocs.slice(index, index + 400).forEach((doc) => {
      batch.set(doc.ref, purgeSuccessPatch(now), {merge: true});
    });
    await batch.commit();
    updatedCount += relatedDocs.slice(index, index + 400).length;
  }
  return updatedCount;
}

async function purgePostTarget(
  brandID: string,
  seasonID: string,
  postID: string
): Promise<Record<string, number>> {
  const postRef = lookbookPostDocument(brandID, seasonID, postID);
  const postSnap = await postRef.get();
  const paths = new Set<string>();

  if (postSnap.exists) {
    collectPostStoragePaths(brandID, postSnap.data(), paths);
    await collectPostSubresourceStoragePaths(brandID, postRef, paths);
  }

  const [postStateCount, commentStateCount] = await Promise.all([
    deleteCollectionGroupByFields("postStates", [
      ["brandID", brandID],
      ["seasonID", seasonID],
      ["postID", postID],
    ]),
    deleteCollectionGroupByFields("commentStates", [
      ["brandID", brandID],
      ["seasonID", seasonID],
      ["postID", postID],
    ]),
  ]);

  if (postSnap.exists) {
    await db.recursiveDelete(postRef);
  }
  await deleteLookbookStorageTargets(
    brandID,
    [`brands/${brandID}/seasons/${seasonID}/posts/${postID}/`],
    paths
  );

  return {
    postStateCount,
    commentStateCount,
    storagePathCount: paths.size,
  };
}

async function purgeSeasonTarget(
  brandID: string,
  seasonID: string
): Promise<Record<string, number>> {
  const seasonRef = db
    .collection("brands")
    .doc(brandID)
    .collection("seasons")
    .doc(seasonID);
  const seasonSnap = await seasonRef.get();
  const paths = new Set<string>();

  if (seasonSnap.exists) {
    collectSeasonStoragePaths(brandID, seasonSnap.data(), paths);
    await collectSeasonSubresourceStoragePaths(brandID, seasonRef, paths);
  }

  const [seasonStateCount, postStateCount, commentStateCount] =
    await Promise.all([
      deleteCollectionGroupByFields("seasonStates", [
        ["brandID", brandID],
        ["seasonID", seasonID],
      ]),
      deleteCollectionGroupByFields("postStates", [
        ["brandID", brandID],
        ["seasonID", seasonID],
      ]),
      deleteCollectionGroupByFields("commentStates", [
        ["brandID", brandID],
        ["seasonID", seasonID],
      ]),
    ]);

  if (seasonSnap.exists) {
    await db.recursiveDelete(seasonRef);
  }
  await deleteLookbookStorageTargets(
    brandID,
    [`brands/${brandID}/seasons/${seasonID}/`],
    paths
  );

  return {
    seasonStateCount,
    postStateCount,
    commentStateCount,
    storagePathCount: paths.size,
  };
}

async function purgeBrandTarget(
  brandID: string
): Promise<Record<string, number>> {
  const brandRef = db.collection("brands").doc(brandID);
  const brandSnap = await brandRef.get();
  const paths = new Set<string>();

  if (brandSnap.exists) {
    collectBrandStoragePaths(brandID, brandSnap.data(), paths);
    await collectBrandSubresourceStoragePaths(brandID, brandRef, paths);
  }

  const [
    brandStateCount,
    seasonStateCount,
    postStateCount,
    commentStateCount,
    brandNameIndexCount,
  ] = await Promise.all([
    deleteCollectionGroupByField("brandStates", "brandID", brandID),
    deleteCollectionGroupByField("seasonStates", "brandID", brandID),
    deleteCollectionGroupByField("postStates", "brandID", brandID),
    deleteCollectionGroupByField("commentStates", "brandID", brandID),
    deleteBrandNameIndexes(brandID, brandSnap.data()),
  ]);

  if (brandSnap.exists) {
    await db.recursiveDelete(brandRef);
  }
  await deleteLookbookStorageTargets(
    brandID,
    [`brands/${brandID}/`],
    paths
  );

  return {
    brandStateCount,
    seasonStateCount,
    postStateCount,
    commentStateCount,
    brandNameIndexCount,
    storagePathCount: paths.size,
  };
}

async function purgeLookbookDeletionRequest(
  doc: FirebaseFirestore.QueryDocumentSnapshot
): Promise<void> {
  const data = doc.data();
  const targetType = data.targetType;
  const brandID = stringField(data, "brandID");
  const seasonID = stringField(data, "seasonID");
  const postID = stringField(data, "postID");
  const nowDate = new Date();
  const now = admin.firestore.Timestamp.fromDate(nowDate);
  const attemptCount = numericMetric(data.purgeAttemptCount) + 1;
  const auditRef = db.collection("lookbookDeletionAuditLogs").doc();

  try {
    if (brandID === null) {
      throw new Error("missing_brand_id");
    }

    let result: Record<string, number>;
    let action: LookbookDeletionAction;
    switch (targetType) {
    case "brand":
      result = await purgeBrandTarget(brandID);
      action = "purgeBrand";
      await markRelatedDeletionRequestsPurged(
        doc.id,
        brandID,
        null,
        null,
        now
      );
      break;
    case "season":
      if (seasonID === null) {
        throw new Error("missing_season_id");
      }
      result = await purgeSeasonTarget(brandID, seasonID);
      action = "purgeSeason";
      await markRelatedDeletionRequestsPurged(
        doc.id,
        brandID,
        seasonID,
        null,
        now
      );
      break;
    case "post":
      if (seasonID === null || postID === null) {
        throw new Error("missing_post_target_id");
      }
      result = await purgePostTarget(brandID, seasonID, postID);
      action = "purgePost";
      break;
    default:
      throw new Error("invalid_target_type");
    }

    await markDeletionRequestPurged(doc.ref, now);
    await auditRef.set({
      ...deletionAuditPatch(
        action,
        doc.id,
        targetType as LookbookDeletionTargetType,
        brandID,
        seasonID,
        postID,
        "system",
        typeof data.reason === "string" ? data.reason : null,
        nowDate,
        typeof data.status === "string" ? data.status : null,
        "purged"
      ),
      purgeAttemptCount: attemptCount,
      purgeResult: result,
    });
  } catch (error) {
    const errorMessage = lookbookPurgeErrorMessage(error);
    await doc.ref.set({
      status: "failed",
      purgeAttemptCount: attemptCount,
      lastPurgeAttemptAt: now,
      autoRetryEligible: attemptCount < LOOKBOOK_PURGE_RETRY_LIMIT,
      retryAfter: attemptCount >= LOOKBOOK_PURGE_RETRY_LIMIT ?
        null :
        retryAfterTimestamp(nowDate),
      purgeErrorMessage: errorMessage,
      updatedBy: "system",
      updatedAt: now,
    }, {merge: true});

    await auditRef.set({
      ...deletionAuditPatch(
        "purgeFailed",
        doc.id,
        targetType as LookbookDeletionTargetType,
        brandID ?? "",
        seasonID,
        postID,
        "system",
        typeof data.reason === "string" ? data.reason : null,
        nowDate,
        typeof data.status === "string" ? data.status : null,
        "failed"
      ),
      purgeAttemptCount: attemptCount,
      errorMessage,
    });
    throw error;
  }
}

export const purgeExpiredLookbookDeletions = onSchedule(
  {
    schedule: "0 4 * * *",
    region: FUNCTIONS_REGION,
    timeZone: "Asia/Seoul",
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const requests = await loadExpiredDeletionRequests(now);

    if (requests.length === 0) {
      console.log("[purgeExpiredLookbookDeletions] No expired requests.");
      return;
    }

    let successCount = 0;
    let failureCount = 0;
    for (const requestDoc of requests) {
      try {
        await purgeLookbookDeletionRequest(requestDoc);
        successCount += 1;
      } catch (error) {
        failureCount += 1;
        console.error(
          "[purgeExpiredLookbookDeletions] Failed to purge request",
          {
            requestID: requestDoc.id,
            targetType: requestDoc.get("targetType"),
            brandID: requestDoc.get("brandID"),
            seasonID: requestDoc.get("seasonID"),
            postID: requestDoc.get("postID"),
            error,
          }
        );
      }
    }

    console.log("[purgeExpiredLookbookDeletions] Completed", {
      requestedCount: requests.length,
      successCount,
      failureCount,
    });
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
    const managerRef = brandRef.collection("admins").doc(uid);
    const postRef = lookbookPostDocument(brandID, seasonID, postID);
    const commentRef = postRef.collection("comments").doc(commentID);
    const deletionLogRef = db.collection("commentDeletionLogs").doc();
    const isTotalAdmin = await isTotalBrandAdmin(uid);

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

      let canDelete = authorID === uid || isTotalAdmin;
      if (!canDelete) {
        const managerSnap = await transaction.get(managerRef);
        canDelete = hasBrandWriteAccessData(managerSnap.data());
      }
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

    console.log(
      "[onRoomClosed] Room close cleanup is handled synchronously " +
        "by the Socket close path. Skip trigger cleanup.",
      {roomId: event.params.roomId}
    );
  }
);

export const cleanupExpiredChatMediaUploads = onSchedule(
  {
    schedule: "0 4 * * *",
    region: FUNCTIONS_REGION,
    timeZone: "Asia/Seoul",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const snapshot = await db
      .collectionGroup("MediaUploads")
      .where("status", "==", "pending")
      .where("expiresAt", "<=", now)
      .limit(MEDIA_UPLOAD_CLEANUP_LIMIT)
      .get();

    if (snapshot.empty) {
      console.log("[cleanupExpiredChatMediaUploads] No expired uploads.");
      return;
    }

    const bucket = admin.storage().bucket();

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const roomRef = doc.ref.parent.parent;
      const roomID = roomRef?.id;
      const messageID = typeof data.messageID === "string" ?
        data.messageID :
        doc.id;
      const storagePrefix = typeof data.storagePrefix === "string" ?
        data.storagePrefix :
        "";

      if (!roomRef || !roomID || !messageID || storagePrefix.length === 0) {
        await doc.ref.set({
          status: "cleanupFailed",
          lastError: "invalid_reservation",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        continue;
      }

      const expectedPrefix = `rooms/${roomID}/messages/${messageID}`;
      if (storagePrefix !== expectedPrefix) {
        await doc.ref.set({
          status: "cleanupFailed",
          lastError: "storage_prefix_mismatch",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        continue;
      }

      const messageSnap = await roomRef
        .collection("Messages")
        .doc(messageID)
        .get();
      if (messageSnap.exists) {
        await doc.ref.delete();
        continue;
      }

      try {
        await bucket.deleteFiles({
          prefix: `${storagePrefix}/`,
          force: true,
        });
        await doc.ref.delete();
        console.log(
          "[cleanupExpiredChatMediaUploads] Deleted expired media prefix",
          {roomID, messageID, storagePrefix}
        );
      } catch (err) {
        console.error(
          "[cleanupExpiredChatMediaUploads] Failed to delete media prefix",
          {roomID, messageID, storagePrefix, err}
        );
        await doc.ref.set({
          status: "cleanupFailed",
          lastError: err instanceof Error ? err.message : String(err),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
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
