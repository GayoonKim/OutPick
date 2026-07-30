/* eslint-disable require-jsdoc */
import {createHash} from "node:crypto";

export const EXPECTED_DEVELOPMENT_PROJECT_ID = "outpick-664ae";
export const EXPECTED_DEVELOPMENT_STORAGE_BUCKET =
  "outpick-664ae.appspot.com";
export const LOOKBOOK_IMPORT_QUEUE_LOCATION = "asia-northeast3";
export const LOOKBOOK_IMPORT_QUEUE_ID = "lookbook-import-jobs";

export const BRAND_CHAT_DELETE_ROOT_COLLECTIONS = [
  "Rooms",
  "brandNameIndex",
  "brandRequestDailyCounters",
  "brandRequestNameIndex",
  "brandRequestUserLimits",
  "brandRequests",
  "brands",
  "commentDeletionLogs",
  "commentReports",
  "lookbookDeletionAuditLogs",
  "lookbookDeletionPurgeLeases",
  "lookbookDeletionRequests",
  "lookbookExtractionDiagnostics",
  "lookbookExtractionEvidence",
  "lookbookExtractionIssueClusters",
  "lookbookExtractionTrustBaselines",
  "seasonCandidates",
  "tagAliases",
  "tagConcepts",
  "tags",
] as const;

export const BRAND_CHAT_DELETE_USER_SUBCOLLECTIONS = [
  "brandStates",
  "commentStates",
  "joinedRooms",
  "postStates",
  "roomStates",
  "seasonStates",
] as const;

export const BRAND_CHAT_DELETE_NESTED_COLLECTIONS = [
  "MediaUploads",
  "Messages",
  "admins",
  "assetFailures",
  "brandRequestDays",
  "comments",
  "importJobs",
  "mediaIndex",
  "members",
  "messages",
  "posts",
  "repairs",
  "replacements",
  "reviews",
  "seasonCandidates",
  "seasons",
] as const;

export const BRAND_CHAT_DELETE_STORAGE_PREFIXES = [
  "brands/",
  "lookbook-extraction-evidence/",
  "rooms/",
] as const;

export const BRAND_CHAT_PRESERVE_ROOT_COLLECTIONS = [
  "accountDeletionAuditLogs",
  "accountDeletionIntents",
  "accountDeletionNotificationOutbox",
  "accountDeletionRequests",
  "brandAdmins",
  "completedDeletionSuppressions",
  "nicknameIndex",
  "styleMoodSeedMetadata",
  "styleMoodTermIndex",
  "styleMoods",
  "userIdentities",
  "userPublicProfiles",
  "users",
] as const;

export type RootCollectionClassification = {
  delete: string[];
  preserve: string[];
  unknown: string[];
};

type JsonValue =
  | null
  | boolean
  | number
  | string
  | JsonValue[]
  | {[key: string]: JsonValue};

function sortedUnique(values: readonly string[]): string[] {
  return [...new Set(values)].sort();
}

function stableValue(value: JsonValue): JsonValue {
  if (Array.isArray(value)) {
    return value.map(stableValue);
  }
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, child]) => [key, stableValue(child)])
    );
  }
  return value;
}

export function classifyRootCollections(
  collectionIDs: readonly string[]
): RootCollectionClassification {
  const deleteSet = new Set<string>(BRAND_CHAT_DELETE_ROOT_COLLECTIONS);
  const preserveSet = new Set<string>(BRAND_CHAT_PRESERVE_ROOT_COLLECTIONS);
  const classification: RootCollectionClassification = {
    delete: [],
    preserve: [],
    unknown: [],
  };

  for (const collectionID of sortedUnique(collectionIDs)) {
    if (deleteSet.has(collectionID)) {
      classification.delete.push(collectionID);
    } else if (preserveSet.has(collectionID)) {
      classification.preserve.push(collectionID);
    } else {
      classification.unknown.push(collectionID);
    }
  }
  return classification;
}

export function confirmationHash(manifest: JsonValue): string {
  const stableManifest = stableValue(manifest);
  return createHash("sha256")
    .update(JSON.stringify(stableManifest))
    .digest("hex");
}

export function assertApplyGate(input: {
  requestedProjectID: string;
  initializedProjectID: string | null;
  confirmationHash: string;
  expectedConfirmationHash: string;
  unknownRootCollections: readonly string[];
  queueState: string;
  queueTaskCount: number;
  processingImportJobCount: number;
}): void {
  if (input.requestedProjectID !== EXPECTED_DEVELOPMENT_PROJECT_ID) {
    throw new Error(
      `허용되지 않은 Firebase project입니다: ${input.requestedProjectID}`
    );
  }
  if (input.initializedProjectID !== input.requestedProjectID) {
    throw new Error(
      "초기화된 Firebase project가 요청 project와 일치하지 않습니다."
    );
  }
  if (input.unknownRootCollections.length > 0) {
    throw new Error(
      "미분류 root collection이 있습니다: " +
      `${input.unknownRootCollections.join(", ")}`
    );
  }
  if (input.queueState !== "PAUSED") {
    throw new Error(
      `lookbook import queue가 PAUSED 상태가 아닙니다: ${input.queueState}`
    );
  }
  if (input.queueTaskCount !== 0) {
    throw new Error(
      `lookbook import queue에 task가 남아 있습니다: ${input.queueTaskCount}`
    );
  }
  if (input.processingImportJobCount !== 0) {
    throw new Error(
      "processing import job이 남아 있습니다: " +
      `${input.processingImportJobCount}`
    );
  }
  if (
    input.confirmationHash.length === 0 ||
    input.confirmationHash !== input.expectedConfirmationHash
  ) {
    throw new Error("confirmation hash가 현재 manifest와 일치하지 않습니다.");
  }
}
