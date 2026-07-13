/* eslint-disable require-jsdoc, valid-jsdoc */
import * as admin from "firebase-admin";
import {createHash} from "node:crypto";
import {FieldValue} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  optionalString,
  recordData,
  requiredAuthUID,
  requiredDocumentID,
  requiredString,
} from "../../core/callable.js";
import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {assertOutPickAdmin} from "../../shared/brandAuthorization.js";
import {
  canonicalBrandName,
  normalizedBrandName,
} from "../../shared/brandValidation.js";

function numericRootValue(
  data: FirebaseFirestore.DocumentData | undefined,
  key: string
): number {
  const value = data?.[key];
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

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
type ProcessedRequestScope = "recent" | "history";

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
const ADMIN_REQUEST_RECENT_PROCESSED_DAYS = 14;
const ADMIN_REQUEST_MAX_RECENT_PROCESSED_DAYS = 30;
const BRAND_REQUEST_TIME_ZONE = "Asia/Seoul";
const BRAND_SEARCH_DEFAULT_LIMIT = 20;
const BRAND_SEARCH_MAX_LIMIT = 30;
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

export function dateKeyKST(now: Date): string {
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

export function requestStatusForAdminStage(
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

function optionalProcessedRequestScope(
  data: Record<string, unknown>,
  key: string
): ProcessedRequestScope | null {
  const value = data[key];
  if (value === undefined || value === null) {
    return null;
  }
  if (value !== "recent" && value !== "history") {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  return value;
}

function isProcessedBrandRequestStage(
  adminStage: BrandRequestAdminStage | null
): boolean {
  return adminStage === "completed" || adminStage === "rejected";
}

function recentProcessedBoundary(
  days: number,
  now: Date = new Date()
): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromDate(addDays(now, -days));
}

function applyProcessedScopeQuery(
  query: FirebaseFirestore.Query,
  scope: ProcessedRequestScope,
  boundary: admin.firestore.Timestamp
): FirebaseFirestore.Query {
  return scope === "history" ?
    query.where("updatedAt", "<", boundary) :
    query.where("updatedAt", ">=", boundary);
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

export function brandRequestUserListScope(
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

export function brandRequestPublicSummary(
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

export function brandRequestGroupSummary(
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

export function brandSearchSummary(
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
    const processedScope = optionalProcessedRequestScope(
      data,
      "processedScope"
    ) ?? "recent";
    const recentProcessedDays = positiveInteger(
      data,
      "recentProcessedDays",
      ADMIN_REQUEST_RECENT_PROCESSED_DAYS,
      ADMIN_REQUEST_MAX_RECENT_PROCESSED_DAYS
    );
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
    if (isProcessedBrandRequestStage(adminStage)) {
      query = applyProcessedScopeQuery(
        query,
        processedScope,
        recentProcessedBoundary(recentProcessedDays)
      );
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
