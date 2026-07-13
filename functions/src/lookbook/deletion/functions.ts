/* eslint-disable require-jsdoc, valid-jsdoc */
/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

// import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {randomUUID} from "node:crypto";

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import {FieldValue} from "firebase-admin/firestore";
import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {
  optionalDocumentID,
  optionalString,
  recordData,
  requiredAuthUID,
  requiredDocumentID,
  requiredString,
} from "../../core/callable.js";
import {mapWithConcurrency} from "../../core/concurrency.js";
import {
  assertBrandWriteAccess,
  assertOutPickAdmin,
  brandAdminCapabilities,
} from "../../shared/brandAuthorization.js";
import {
  canFinalizePurgeLease,
  isManualRetryDuplicate,
  isPurgeLeaseActive,
  shouldStartManualRetryTrigger,
  visibleManualRetryState,
  type ManualRetryState,
} from "./purgeLease.js";
import {
  drainPurgeCandidatePages,
  initialPurgeDrainSummary,
  mergePurgeDrainSummaries,
  type PurgeDrainCandidate,
  type PurgeDrainPage,
  type PurgeDrainTargetType,
} from "./purgeDrain.js";

const LOOKBOOK_PURGE_LEASE_DURATION_MINUTES = 15;
const LOOKBOOK_PURGE_LEASES_COLLECTION = "lookbookDeletionPurgeLeases";

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

function numericMetric(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return 0;
  }
  return Math.max(0, Math.floor(value));
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

type LookbookDeletionTargetType = "brand" | "season" | "post";
type LookbookPurgeExecutionSource = "scheduled" | "manual";
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
  "purgeFailed" |
  "retryPurgeRequested";

type LookbookPurgeLeaseClaim = {
  requestRef: FirebaseFirestore.DocumentReference;
  leaseRef: FirebaseFirestore.DocumentReference;
  requestID: string;
  leaseToken: string;
  source: LookbookPurgeExecutionSource;
  data: FirebaseFirestore.DocumentData;
};

const LOOKBOOK_DELETION_RETENTION_DAYS = 7;
const LOOKBOOK_DELETION_DEFAULT_LIMIT = 50;
const LOOKBOOK_DELETION_MAX_LIMIT = 100;
const LOOKBOOK_DELETION_BATCH_MAX_COUNT = 20;
const LOOKBOOK_DELETION_BATCH_CONCURRENCY = 3;
const LOOKBOOK_PURGE_QUERY_PAGE_SIZE = 20;
const LOOKBOOK_PURGE_MAX_CONCURRENT_BRANDS = 3;
const LOOKBOOK_PURGE_START_BUDGET_MILLIS = 7 * 60 * 1000;
const LOOKBOOK_PURGE_RETRY_LIMIT = 3;
const LOOKBOOK_PURGE_RETRY_DELAY_HOURS = 24;
const LOOKBOOK_PURGE_PAGE_SIZE = 200;
const LOOKBOOK_PURGE_STORAGE_PREFIX_CONCURRENCY = 3;

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

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function timestampToISO(value: unknown): string | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate().toISOString();
  }
  return null;
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

function manualRetryState(value: unknown): ManualRetryState {
  if (value === "queued" || value === "running" || value === "failed") {
    return value;
  }
  return null;
}

function sanitizedPurgeErrorMessage(value: unknown): string | null {
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }
  if (
    value === "missing_brand_id" ||
    value === "missing_season_id" ||
    value === "missing_post_target_id" ||
    value === "invalid_target_type"
  ) {
    return "삭제 대상 정보가 올바르지 않습니다.";
  }
  return "삭제 처리 중 오류가 발생했습니다. 서버 로그를 확인해주세요.";
}

function deletionRequestSummary(
  requestID: string,
  data: FirebaseFirestore.DocumentData | undefined,
  includesPurgeError: boolean
): Record<string, unknown> {
  const leaseUntilMillis = firestoreTimestampMillis(data?.purgeLeaseUntil);
  const purgeInProgress = isPurgeLeaseActive(leaseUntilMillis, Date.now());
  const storedManualRetryState = manualRetryState(data?.manualRetryState);
  const responseManualRetryState = visibleManualRetryState(
    storedManualRetryState,
    purgeInProgress
  );
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
    autoRetryEligible: data?.autoRetryEligible === true,
    retryAfter: timestampToISO(data?.retryAfter),
    purgeAttemptCount: numericMetric(data?.purgeAttemptCount),
    purgeErrorMessage: includesPurgeError ?
      sanitizedPurgeErrorMessage(data?.purgeErrorMessage) :
      null,
    manualRetryState: responseManualRetryState,
    manualRetryCount: numericMetric(data?.manualRetryCount),
    purgeInProgress,
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

function targetSpecificDisplayName(
  targetType: LookbookDeletionTargetType,
  summary: Record<string, unknown>
): string | null {
  switch (targetType) {
  case "brand":
    return firstNonEmptyDisplayString([summary.brandName]);
  case "season":
    return firstNonEmptyDisplayString([summary.seasonTitle]);
  case "post":
    return firstNonEmptyDisplayString([summary.postCaption]);
  }
}

function shouldReplaceDeletionTargetDisplayName(
  targetType: LookbookDeletionTargetType,
  targetDisplayName: unknown
): boolean {
  if (!nonEmptyDisplayString(targetDisplayName)) {
    return true;
  }
  const trimmed = targetDisplayName.trim();
  return trimmed === deletionFallbackDisplayName(targetType) ||
    (targetType === "post" && trimmed === "포스트");
}

function normalizeDeletionDisplayName(
  summary: Record<string, unknown>
): Record<string, unknown> {
  const targetType = displayTargetType(summary.targetType);
  const targetName = targetSpecificDisplayName(targetType, summary);
  if (
    targetName !== null &&
    shouldReplaceDeletionTargetDisplayName(
      targetType,
      summary.targetDisplayName
    )
  ) {
    return {
      ...summary,
      targetDisplayName: targetName,
    };
  }
  if (!nonEmptyDisplayString(summary.targetDisplayName)) {
    return {
      ...summary,
      targetDisplayName: deletionFallbackDisplayName(targetType),
    };
  }
  return summary;
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
  data: FirebaseFirestore.DocumentData | undefined,
  includesPurgeError: boolean
): Promise<Record<string, unknown>> {
  const summary = deletionRequestSummary(
    requestID,
    data,
    includesPurgeError
  );
  const targetType = displayTargetType(summary.targetType);
  const hasTargetName = targetSpecificDisplayName(targetType, summary) !== null;
  const hasPrimaryName =
    nonEmptyDisplayString(summary.targetDisplayName) &&
    !shouldReplaceDeletionTargetDisplayName(
      targetType,
      summary.targetDisplayName
    );

  if (hasPrimaryName && hasTargetName) {
    return normalizeDeletionDisplayName(summary);
  }

  const brandID = nonEmptyDisplayString(summary.brandID) ?
    summary.brandID :
    null;
  if (brandID === null) {
    return normalizeDeletionDisplayName({
      ...summary,
      targetDisplayName: hasPrimaryName ?
        summary.targetDisplayName :
        deletionFallbackDisplayName(targetType),
    });
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

  return normalizeDeletionDisplayName(enriched);
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
        .where("status", "in", ["active", "failed"]);
    if (brandID !== null) {
      query = query.where("brandID", "==", brandID);
    }
    if (targetType !== null) {
      query = query.where("targetType", "==", targetType);
    }
    query = query
      .orderBy("updatedAt", "desc")
      .orderBy("requestID", "desc")
      .limit(limit + 1);

    if (cursorUpdatedAt && cursorRequestID) {
      query = query.startAfter(cursorUpdatedAt, cursorRequestID);
    }

    const snapshot = await query.get();
    const hasNextPage = snapshot.docs.length > limit;
    const pageDocs = snapshot.docs.slice(0, limit);
    const requests = await Promise.all(pageDocs.map((doc) =>
      deletionRequestSummaryWithDisplayFallback(
        doc.id,
        doc.data(),
        capabilities.isTotalAdmin
      )
    )
    );
    const last = pageDocs[pageDocs.length - 1];

    return {
      requests,
      nextCursor: hasNextPage && last ? {
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

type ActivePurgeQueryCursor = {
  purgeAfter: admin.firestore.Timestamp;
  requestID: string;
};

type FailedPurgeQueryCursor = ActivePurgeQueryCursor & {
  retryAfter: admin.firestore.Timestamp;
};

type ScheduledPurgeCandidate = PurgeDrainCandidate & {
  requestRef: FirebaseFirestore.DocumentReference;
  seasonID: string | null;
  postID: string | null;
};

function scheduledPurgeCandidate(
  doc: FirebaseFirestore.QueryDocumentSnapshot,
  targetType: PurgeDrainTargetType
): ScheduledPurgeCandidate {
  const data = doc.data();
  return {
    requestID: doc.id,
    requestRef: doc.ref,
    brandID: stringField(data, "brandID"),
    seasonID: stringField(data, "seasonID"),
    postID: stringField(data, "postID"),
    targetType,
    purgeAfterMillis: firestoreTimestampMillis(data.purgeAfter) ?? 0,
  };
}

function expiredDeletionRequestPageLoader(
  now: admin.firestore.Timestamp,
  targetType: PurgeDrainTargetType
): () => Promise<PurgeDrainPage<ScheduledPurgeCandidate>> {
  let activeCursor: ActivePurgeQueryCursor | null = null;
  let failedCursor: FailedPurgeQueryCursor | null = null;
  let activeExhausted = false;
  let failedExhausted = false;

  return async () => {
    let activeQuery: FirebaseFirestore.Query | null = activeExhausted ?
      null :
      db.collection("lookbookDeletionRequests")
        .where("status", "==", "active")
        .where("targetType", "==", targetType)
        .where("purgeAfter", "<=", now)
        .orderBy("purgeAfter", "asc")
        .orderBy("requestID", "asc")
        .limit(LOOKBOOK_PURGE_QUERY_PAGE_SIZE);
    if (activeQuery !== null && activeCursor !== null) {
      activeQuery = activeQuery.startAfter(
        activeCursor.purgeAfter,
        activeCursor.requestID
      );
    }

    let failedQuery: FirebaseFirestore.Query | null = failedExhausted ?
      null :
      db.collection("lookbookDeletionRequests")
        .where("status", "==", "failed")
        .where("autoRetryEligible", "==", true)
        .where("targetType", "==", targetType)
        .where("purgeAfter", "<=", now)
        .where("retryAfter", "<=", now)
        .orderBy("purgeAfter", "asc")
        .orderBy("retryAfter", "asc")
        .orderBy("requestID", "asc")
        .limit(LOOKBOOK_PURGE_QUERY_PAGE_SIZE);
    if (failedQuery !== null && failedCursor !== null) {
      failedQuery = failedQuery.startAfter(
        failedCursor.purgeAfter,
        failedCursor.retryAfter,
        failedCursor.requestID
      );
    }

    const [activeSnapshot, failedSnapshot] = await Promise.all([
      activeQuery?.get() ?? Promise.resolve(null),
      failedQuery?.get() ?? Promise.resolve(null),
    ]);

    if (activeSnapshot !== null) {
      const last = activeSnapshot.docs[activeSnapshot.docs.length - 1];
      if (last !== undefined) {
        activeCursor = {
          purgeAfter: last.get("purgeAfter"),
          requestID: last.get("requestID"),
        };
      }
      activeExhausted =
        activeSnapshot.docs.length < LOOKBOOK_PURGE_QUERY_PAGE_SIZE;
    }
    if (failedSnapshot !== null) {
      const last = failedSnapshot.docs[failedSnapshot.docs.length - 1];
      if (last !== undefined) {
        failedCursor = {
          purgeAfter: last.get("purgeAfter"),
          retryAfter: last.get("retryAfter"),
          requestID: last.get("requestID"),
        };
      }
      failedExhausted =
        failedSnapshot.docs.length < LOOKBOOK_PURGE_QUERY_PAGE_SIZE;
    }

    const candidates = [
      ...(activeSnapshot?.docs ?? []),
      ...(failedSnapshot?.docs ?? []),
    ].map((doc) => scheduledPurgeCandidate(doc, targetType));
    return {
      candidates,
      hasMore: !activeExhausted || !failedExhausted,
    };
  };
}

function purgeLeaseUntilTimestamp(
  nowDate: Date
): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromDate(
    new Date(
      nowDate.getTime() +
      LOOKBOOK_PURGE_LEASE_DURATION_MINUTES * 60 * 1000
    )
  );
}

function lookbookPurgeLeaseRef(
  brandID: string | null,
  requestID: string
): FirebaseFirestore.DocumentReference {
  const leaseScopeID = brandID ?? `request-${requestID}`;
  return db.collection(LOOKBOOK_PURGE_LEASES_COLLECTION).doc(leaseScopeID);
}

function scheduledPurgeEligible(
  data: FirebaseFirestore.DocumentData,
  nowMillis: number
): boolean {
  const purgeAfterMillis = firestoreTimestampMillis(data.purgeAfter);
  if (purgeAfterMillis === null || purgeAfterMillis > nowMillis) {
    return false;
  }
  if (data.status === "active") {
    return true;
  }
  return data.status === "failed" &&
    data.autoRetryEligible === true &&
    shouldRetryFailedPurge(data, nowMillis);
}

async function claimLookbookDeletionPurge(
  requestRef: FirebaseFirestore.DocumentReference,
  source: LookbookPurgeExecutionSource,
  expectedManualRetryToken: string | null
): Promise<LookbookPurgeLeaseClaim | null> {
  const nowDate = new Date();
  const now = admin.firestore.Timestamp.fromDate(nowDate);
  const nowMillis = now.toMillis();
  const leaseUntil = purgeLeaseUntilTimestamp(nowDate);
  const leaseToken = randomUUID();

  return db.runTransaction(async (transaction) => {
    const requestSnap = await transaction.get(requestRef);
    if (!requestSnap.exists) {
      return null;
    }

    const data = requestSnap.data() ?? {};
    const manualToken = stringField(data, "manualRetryToken");
    const currentManualState = manualRetryState(data.manualRetryState);

    if (source === "manual") {
      if (
        data.status !== "failed" ||
        expectedManualRetryToken === null ||
        manualToken !== expectedManualRetryToken ||
        currentManualState !== "queued"
      ) {
        return null;
      }
    } else if (!scheduledPurgeEligible(data, nowMillis)) {
      return null;
    }

    const brandID = stringField(data, "brandID");
    const leaseRef = lookbookPurgeLeaseRef(brandID, requestRef.id);
    const leaseSnap = await transaction.get(leaseRef);
    const leaseData = leaseSnap.data();
    const activeLease = isPurgeLeaseActive(
      firestoreTimestampMillis(leaseData?.leaseUntil),
      nowMillis
    );
    if (activeLease) {
      return null;
    }

    transaction.set(leaseRef, {
      leaseToken,
      leaseUntil,
      requestID: requestRef.id,
      brandID,
      source,
      claimedAt: now,
    });

    const requestPatch: Record<string, unknown> = {
      purgeLeaseToken: leaseToken,
      purgeLeaseUntil: leaseUntil,
      purgeExecutionSource: source,
      lastPurgeClaimedAt: now,
    };
    if (currentManualState === "queued") {
      requestPatch.manualRetryState = "running";
    }
    transaction.set(requestRef, requestPatch, {merge: true});

    return {
      requestRef,
      leaseRef,
      requestID: requestRef.id,
      leaseToken,
      source,
      data: {
        ...data,
        ...requestPatch,
      },
    };
  });
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
    manualRetryState: null,
    purgeLeaseToken: null,
    purgeLeaseUntil: null,
    purgeExecutionSource: null,
    updatedBy: "system",
    updatedAt: now,
  };
}

async function finalizePurgeSuccess(
  claim: LookbookPurgeLeaseClaim,
  now: admin.firestore.Timestamp,
  attemptCount: number
): Promise<boolean> {
  return db.runTransaction(async (transaction) => {
    const [requestSnap, leaseSnap] = await Promise.all([
      transaction.get(claim.requestRef),
      transaction.get(claim.leaseRef),
    ]);
    const requestToken = stringField(
      requestSnap.data(),
      "purgeLeaseToken"
    );
    const leaseToken = stringField(leaseSnap.data(), "leaseToken");
    if (
      !canFinalizePurgeLease(requestToken, claim.leaseToken) ||
      !canFinalizePurgeLease(leaseToken, claim.leaseToken)
    ) {
      return false;
    }

    transaction.set(claim.requestRef, {
      ...purgeSuccessPatch(now),
      purgeAttemptCount: attemptCount,
    }, {merge: true});
    transaction.delete(claim.leaseRef);
    return true;
  });
}

async function finalizePurgeFailure(
  claim: LookbookPurgeLeaseClaim,
  nowDate: Date,
  attemptCount: number,
  errorMessage: string
): Promise<boolean> {
  const now = admin.firestore.Timestamp.fromDate(nowDate);
  return db.runTransaction(async (transaction) => {
    const [requestSnap, leaseSnap] = await Promise.all([
      transaction.get(claim.requestRef),
      transaction.get(claim.leaseRef),
    ]);
    const requestToken = stringField(
      requestSnap.data(),
      "purgeLeaseToken"
    );
    const leaseToken = stringField(leaseSnap.data(), "leaseToken");
    if (
      !canFinalizePurgeLease(requestToken, claim.leaseToken) ||
      !canFinalizePurgeLease(leaseToken, claim.leaseToken)
    ) {
      return false;
    }

    transaction.set(claim.requestRef, {
      status: "failed",
      purgeAttemptCount: attemptCount,
      lastPurgeAttemptAt: now,
      autoRetryEligible: attemptCount < LOOKBOOK_PURGE_RETRY_LIMIT,
      retryAfter: attemptCount >= LOOKBOOK_PURGE_RETRY_LIMIT ?
        null :
        retryAfterTimestamp(nowDate),
      purgeErrorMessage: errorMessage,
      manualRetryState: stringField(
        claim.data,
        "manualRetryToken"
      ) !== null ? "failed" : null,
      purgeLeaseToken: null,
      purgeLeaseUntil: null,
      purgeExecutionSource: null,
      updatedBy: "system",
      updatedAt: now,
    }, {merge: true});
    transaction.delete(claim.leaseRef);
    return true;
  });
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

async function purgeClaimedLookbookDeletionRequest(
  claim: LookbookPurgeLeaseClaim
): Promise<void> {
  const data = claim.data;
  const targetType = data.targetType;
  const brandID = stringField(data, "brandID");
  const seasonID = stringField(data, "seasonID");
  const postID = stringField(data, "postID");
  const nowDate = new Date();
  const now = admin.firestore.Timestamp.fromDate(nowDate);
  const attemptCount = numericMetric(data.purgeAttemptCount) + 1;
  const auditRef = db.collection("lookbookDeletionAuditLogs").doc();
  let result: Record<string, number>;
  let action: LookbookDeletionAction;

  try {
    if (brandID === null) {
      throw new Error("missing_brand_id");
    }

    switch (targetType) {
    case "brand":
      result = await purgeBrandTarget(brandID);
      action = "purgeBrand";
      await markRelatedDeletionRequestsPurged(
        claim.requestID,
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
        claim.requestID,
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
  } catch (error) {
    const errorMessage = lookbookPurgeErrorMessage(error);
    const finalized = await finalizePurgeFailure(
      claim,
      nowDate,
      attemptCount,
      errorMessage
    );
    if (finalized) {
      await auditRef.set({
        ...deletionAuditPatch(
          "purgeFailed",
          claim.requestID,
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
        purgeExecutionSource: claim.source,
        errorMessage,
      }).catch((auditError) => {
        console.error(
          "[purgeLookbookDeletionRequest] Failed to write failure audit",
          {requestID: claim.requestID, auditError}
        );
      });
    } else {
      console.warn(
        "[purgeLookbookDeletionRequest] Ignored stale failure finalize",
        {requestID: claim.requestID, leaseToken: claim.leaseToken}
      );
    }
    throw error;
  }

  const finalized = await finalizePurgeSuccess(claim, now, attemptCount);
  if (!finalized) {
    console.warn(
      "[purgeLookbookDeletionRequest] Ignored stale success finalize",
      {requestID: claim.requestID, leaseToken: claim.leaseToken}
    );
    return;
  }

  await auditRef.set({
    ...deletionAuditPatch(
      action,
      claim.requestID,
      targetType as LookbookDeletionTargetType,
      brandID ?? "",
      seasonID,
      postID,
      "system",
      typeof data.reason === "string" ? data.reason : null,
      nowDate,
      typeof data.status === "string" ? data.status : null,
      "purged"
    ),
    purgeAttemptCount: attemptCount,
    purgeExecutionSource: claim.source,
    purgeResult: result,
  }).catch((auditError) => {
    console.error(
      "[purgeLookbookDeletionRequest] Failed to write success audit",
      {requestID: claim.requestID, auditError}
    );
  });
}

async function runLookbookDeletionPurge(
  requestRef: FirebaseFirestore.DocumentReference,
  source: LookbookPurgeExecutionSource,
  expectedManualRetryToken: string | null
): Promise<boolean> {
  const claim = await claimLookbookDeletionPurge(
    requestRef,
    source,
    expectedManualRetryToken
  );
  if (claim === null) {
    return false;
  }
  await purgeClaimedLookbookDeletionRequest(claim);
  return true;
}

export const retryFailedLookbookDeletionPurge = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    await assertOutPickAdmin(uid);

    const payload = recordData(request.data ?? {});
    const requestID = requiredDocumentID(
      requiredString(payload, "requestID", 256),
      "requestID"
    );
    const requestRef = db
      .collection("lookbookDeletionRequests")
      .doc(requestID);
    const auditRef = db.collection("lookbookDeletionAuditLogs").doc();

    return db.runTransaction(async (transaction) => {
      const requestSnap = await transaction.get(requestRef);
      if (!requestSnap.exists) {
        throw new HttpsError(
          "not-found",
          "삭제 요청을 찾을 수 없습니다."
        );
      }

      const data = requestSnap.data() ?? {};
      if (data.status !== "failed") {
        throw new HttpsError(
          "failed-precondition",
          "실패한 삭제 요청만 다시 시도할 수 있습니다."
        );
      }

      const targetType = data.targetType;
      if (
        targetType !== "brand" &&
        targetType !== "season" &&
        targetType !== "post"
      ) {
        throw new HttpsError(
          "failed-precondition",
          "삭제 요청 대상 정보가 올바르지 않습니다."
        );
      }

      const currentState = manualRetryState(data.manualRetryState);
      const currentToken = stringField(data, "manualRetryToken");
      const requestLeaseActive = isPurgeLeaseActive(
        firestoreTimestampMillis(data.purgeLeaseUntil),
        Date.now()
      );
      if (isManualRetryDuplicate(currentState, requestLeaseActive)) {
        return {
          requestID,
          manualRetryToken: currentToken,
          manualRetryState: currentState ?? "running",
          duplicate: true,
        };
      }

      const nowDate = new Date();
      const now = admin.firestore.Timestamp.fromDate(nowDate);
      const manualRetryToken = randomUUID();
      const manualRetryCount = numericMetric(data.manualRetryCount) + 1;
      const brandID = stringField(data, "brandID") ?? "";
      const seasonID = stringField(data, "seasonID");
      const postID = stringField(data, "postID");

      transaction.set(requestRef, {
        autoRetryEligible: true,
        retryAfter: now,
        purgeAttemptCount: 0,
        manualRetryState: "queued",
        manualRetryToken,
        manualRetryCount,
        manualRetryRequestedAt: now,
        manualRetryRequestedBy: uid,
        purgeLeaseToken: null,
        purgeLeaseUntil: null,
        purgeExecutionSource: null,
        updatedBy: uid,
        updatedAt: now,
      }, {merge: true});
      transaction.set(auditRef, {
        ...deletionAuditPatch(
          "retryPurgeRequested",
          requestID,
          targetType,
          brandID,
          seasonID,
          postID,
          uid,
          typeof data.reason === "string" ? data.reason : null,
          nowDate,
          "failed",
          "failed"
        ),
        manualRetryToken,
        manualRetryCount,
      });

      return {
        requestID,
        manualRetryToken,
        manualRetryState: "queued",
        duplicate: false,
      };
    });
  }
);

export const onLookbookDeletionManualRetryQueued = onDocumentUpdated(
  {
    document: "lookbookDeletionRequests/{requestID}",
    region: FUNCTIONS_REGION,
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (event) => {
    const beforeSnap = event.data?.before;
    const afterSnap = event.data?.after;
    if (!beforeSnap?.exists || !afterSnap?.exists) {
      return;
    }

    const beforeData = beforeSnap.data();
    const afterData = afterSnap.data();
    const beforeToken = stringField(beforeData, "manualRetryToken");
    const afterToken = stringField(afterData, "manualRetryToken");
    if (!shouldStartManualRetryTrigger(
      beforeToken,
      afterToken,
      manualRetryState(afterData.manualRetryState)
    )) {
      return;
    }

    try {
      const started = await runLookbookDeletionPurge(
        afterSnap.ref,
        "manual",
        afterToken
      );
      if (!started) {
        console.log(
          "[onLookbookDeletionManualRetryQueued] Purge claim skipped",
          {requestID: afterSnap.id}
        );
      }
    } catch (error) {
      console.error(
        "[onLookbookDeletionManualRetryQueued] Purge failed",
        {requestID: afterSnap.id, error}
      );
    }
  }
);

export const purgeExpiredLookbookDeletions = onSchedule(
  {
    schedule: "0 4 * * *",
    region: FUNCTIONS_REGION,
    timeZone: "Asia/Seoul",
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async () => {
    const startedAtMillis = Date.now();
    const stopStartingAtMillis =
      startedAtMillis + LOOKBOOK_PURGE_START_BUDGET_MILLIS;
    const now = admin.firestore.Timestamp.now();
    const canStartNewWork = () => Date.now() < stopStartingAtMillis;
    let summary = initialPurgeDrainSummary();

    const targetTypes: PurgeDrainTargetType[] = [
      "brand",
      "season",
      "post",
    ];
    for (const targetType of targetTypes) {
      const targetSummary = await drainPurgeCandidatePages({
        loadPage: expiredDeletionRequestPageLoader(now, targetType),
        execute: async (candidate) => {
          try {
            const started = await runLookbookDeletionPurge(
              candidate.requestRef,
              "scheduled",
              null
            );
            return started ? "succeeded" : "skipped";
          } catch (error) {
            console.error(
              "[purgeExpiredLookbookDeletions] Failed to purge request",
              {
                requestID: candidate.requestID,
                targetType: candidate.targetType,
                brandID: candidate.brandID,
                seasonID: candidate.seasonID,
                postID: candidate.postID,
                error,
              }
            );
            return "failed";
          }
        },
        canStartNewWork,
        maxConcurrentBrands: LOOKBOOK_PURGE_MAX_CONCURRENT_BRANDS,
      });
      summary = mergePurgeDrainSummaries(summary, targetSummary);
      if (targetSummary.stopReason === "time_budget") {
        break;
      }
    }

    console.log("[purgeExpiredLookbookDeletions] Completed", {
      ...summary,
      elapsedMillis: Date.now() - startedAtMillis,
      pageSize: LOOKBOOK_PURGE_QUERY_PAGE_SIZE,
      maxConcurrentBrands: LOOKBOOK_PURGE_MAX_CONCURRENT_BRANDS,
      startBudgetMillis: LOOKBOOK_PURGE_START_BUDGET_MILLIS,
    });
  }
);
