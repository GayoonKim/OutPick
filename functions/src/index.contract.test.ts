/* eslint-disable require-jsdoc, max-len */
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {DEVELOPMENT_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL} from "./auth/runtime.js";

process.env.GCLOUD_PROJECT ??= "outpick-test";
// eslint-disable-next-line @typescript-eslint/no-var-requires
const exportedFunctions = require("./index.js") as typeof import("./index.js");

type Endpoint = {
  availableMemoryMb?: number | null;
  timeoutSeconds?: number | null;
  maxInstances?: number | null;
  serviceAccountEmail?: string;
  region?: string[];
  callableTrigger?: Record<string, unknown>;
  httpsTrigger?: {invoker?: string[]};
  eventTrigger?: {
    eventType?: string;
    eventFilterPathPatterns?: {document?: string};
  };
  scheduleTrigger?: {
    schedule?: string;
    timeZone?: string;
  };
};

type ExportedFunction = {__endpoint?: Endpoint};

const callableNames = [
  "exchangeKakaoToken",
  "getMyModerationState",
  "submitUserReport",
  "submitRoomReport",
  "listModerationReports",
  "getModerationReportDetail",
  "mutateModerationReview",
  "mutateAccountModeration",
  "getBrandAdminCapabilities",
  "createStyleMood",
  "updateStyleMood",
  "updateSeasonMoods",
  "checkNicknameAvailability",
  "completeOnboarding",
  "updatePublicProfile",
  "updateStylePreferences",
  "prepareAccountDeletion",
  "requestAccountDeletion",
  "cancelAccountDeletion",
  "getAccountDeletionStatus",
  "createBrand",
  "updateBrand",
  "addBrandManager",
  "removeBrandManager",
  "updateBrandLogoPaths",
  "submitBrandRequest",
  "listMyBrandRequests",
  "listBrandRequests",
  "listBrandRequestGroups",
  "updateBrandRequestStage",
  "updateBrandRequestGroupStage",
  "resolveBrandRequestGroup",
  "markBrandRequestGroupBrandCreated",
  "resolveBrandRequest",
  "searchBrands",
  "requestBrandDeletion",
  "cancelBrandDeletion",
  "cancelSeasonDiscovery",
  "softDeleteSeason",
  "batchSoftDeleteSeasons",
  "restoreSeason",
  "softDeletePost",
  "batchSoftDeletePosts",
  "restorePost",
  "listLookbookDeletionRequests",
  "retryFailedLookbookDeletionPurge",
  "setBrandEngagement",
  "setPostEngagement",
  "setSeasonEngagement",
  "setCommentEngagement",
  "createComment",
  "createReply",
  "deleteComment",
  "reportComment",
  "blockUser",
  "unblockUser",
  "loadHiddenCommentUserIDs",
  "requestSeasonImport",
  "requestSeasonAssetRetry",
  "requestSeasonCandidateImportJobs",
  "requestSeasonDiscovery",
  "retrySeasonDiscoveryAfterExtractionFix",
  "resolveSeasonDiscoveryCandidate",
  "retrySeasonDiscovery",
  "getLookbookExtractionReview",
  "reviewLookbookExtraction",
  "retryLookbookExtractionAfterFix",
  "requestLookbookSeasonRepair",
  "previewLookbookSeasonRepair",
  "applyLookbookSeasonRepair",
  "runLookbookExtractionDiagnostic",
  "getLatestLookbookExtractionDiagnostic",
  "discoverSeasonCandidates",
  "deleteChatMessage",
  "getMyRoomAccess",
  "acknowledgeRoomClosure",
  "closeOwnedChatRoom",
  "closeRoomByModeration",
  "removeRoomMember",
  "unbanRoomMember",
  "listRoomBans",
] as const;

const firestoreEndpoints = {
  onLookbookDeletionManualRetryQueued: {
    eventType: "google.cloud.firestore.document.v1.updated",
    document: "lookbookDeletionRequests/{requestID}",
    timeoutSeconds: 540,
    availableMemoryMb: 1024,
  },
  onSeasonImportQueued: {
    eventType: "google.cloud.firestore.document.v1.written",
    document: "brands/{brandID}/importJobs/{jobID}",
    timeoutSeconds: 60,
    availableMemoryMb: 256,
  },
  onSeasonDiscoveryQueued: {
    eventType: "google.cloud.firestore.document.v1.written",
    document: "brands/{brandID}/seasonDiscoveryJobs/{jobID}",
    timeoutSeconds: 60,
    availableMemoryMb: 256,
  },
  onRoomClosed: {
    eventType: "google.cloud.firestore.document.v1.updated",
    document: "Rooms/{roomId}",
    timeoutSeconds: null,
    availableMemoryMb: null,
  },
  onChatMessageCleanupQueued: {
    eventType: "google.cloud.firestore.document.v1.created",
    document: "chatMessageCleanupJobs/{jobID}",
    timeoutSeconds: null,
    availableMemoryMb: null,
  },
  onModerationRoomCleanupQueued: {
    eventType: "google.cloud.firestore.document.v1.created",
    document: "moderationRoomCleanupJobs/{roomID}",
    timeoutSeconds: null,
    availableMemoryMb: null,
  },
  onRoomOwnershipSuccessionQueued: {
    eventType: "google.cloud.firestore.document.v1.created",
    document: "roomOwnershipSuccessionJobs/{jobID}",
    timeoutSeconds: null,
    availableMemoryMb: null,
  },
} as const;

const scheduleEndpoints = {
  finalizeExpiredAccountDeletions: {
    schedule: "0 * * * *",
    timeZone: "Asia/Seoul",
    timeoutSeconds: 540,
    availableMemoryMb: 1024,
  },
  purgeExpiredLookbookDeletions: {
    schedule: "0 4 * * *",
    timeZone: "Asia/Seoul",
    timeoutSeconds: 540,
    availableMemoryMb: 1024,
  },
  cleanupExpiredChatMediaUploads: {
    schedule: "0 4 * * *",
    timeZone: "Asia/Seoul",
    timeoutSeconds: null,
    availableMemoryMb: null,
  },
  cleanupExpiredLookbookExtractionDiagnostics: {
    schedule: "30 4 * * *",
    timeZone: "Asia/Seoul",
    timeoutSeconds: null,
    availableMemoryMb: null,
  },
  cleanupExpiredLookbookExtractionEvidence: {
    schedule: "45 4 * * *",
    timeZone: "Asia/Seoul",
    timeoutSeconds: null,
    availableMemoryMb: null,
  },
  reconcileSeasonDiscoveryJobs: {
    schedule: "every 10 minutes",
    timeZone: "Asia/Seoul",
    timeoutSeconds: null,
    availableMemoryMb: null,
  },
  reconcileLookbookExtractionFixReleases: {
    schedule: "every 10 minutes",
    timeZone: "Asia/Seoul",
    timeoutSeconds: 300,
    availableMemoryMb: 512,
  },
  drainChatModerationCleanupJobs: {
    schedule: "every 5 minutes",
    timeZone: "Asia/Seoul",
    timeoutSeconds: null,
    availableMemoryMb: null,
  },
  drainRoomOwnershipSuccessionJobs: {
    schedule: "every 5 minutes",
    timeZone: "Asia/Seoul",
    timeoutSeconds: null,
    availableMemoryMb: null,
  },
} as const;

const callableOverrides = {
  requestSeasonCandidateImportJobs: {timeoutSeconds: 120, availableMemoryMb: 512},
  runLookbookExtractionDiagnostic: {timeoutSeconds: 120, availableMemoryMb: 512},
  discoverSeasonCandidates: {timeoutSeconds: 60, availableMemoryMb: 512},
  applyLookbookSeasonRepair: {timeoutSeconds: 120, availableMemoryMb: 512},
} as const;

function endpoint(namedExport: string): Endpoint {
  const value = exportedFunctions[namedExport as keyof typeof exportedFunctions] as ExportedFunction;
  assert.ok(value?.__endpoint, `${namedExport}의 __endpoint metadata가 필요합니다.`);
  return value.__endpoint;
}

function assertCommonMetadata(namedExport: string, value: Endpoint): void {
  assert.deepEqual(value.region, ["asia-northeast3"], `${namedExport} region`);
  assert.equal(value.maxInstances, 10, `${namedExport} maxInstances`);
}

function runtimeNumber(value: unknown): number | null {
  // Firebase는 미지정 런타임 옵션을 내부 ResetValue 객체로 노출한다.
  return typeof value === "number" ? value : null;
}

test("Firebase deployment export 이름 100개를 유지한다", () => {
  const expected = [
    ...callableNames,
    ...Object.keys(firestoreEndpoints),
    ...Object.keys(scheduleEndpoints),
    "lookbookExtractionIssueOpsRead",
    "lookbookExtractionIssueOpsWrite",
    "verifyLookbookExtractionFix",
  ].sort();
  assert.equal(expected.length, 100);
  assert.deepEqual(Object.keys(exportedFunctions).sort(), expected);
});

test("extraction issue 운영 HTTP API는 private invoker를 유지한다", () => {
  for (const name of [
    "lookbookExtractionIssueOpsRead",
    "lookbookExtractionIssueOpsWrite",
  ]) {
    const value = endpoint(name);
    assertCommonMetadata(name, value);
    assert.deepEqual(value.httpsTrigger?.invoker, ["private"]);
    assert.equal(runtimeNumber(value.timeoutSeconds), 60);
    assert.equal(runtimeNumber(value.availableMemoryMb), 512);
  }
  const release = endpoint("verifyLookbookExtractionFix");
  assertCommonMetadata("verifyLookbookExtractionFix", release);
  assert.deepEqual(release.httpsTrigger?.invoker, ["private"]);
  assert.equal(runtimeNumber(release.timeoutSeconds), 300);
  assert.equal(runtimeNumber(release.availableMemoryMb), 1024);
});

test("callable runtime metadata를 유지한다", () => {
  for (const name of callableNames) {
    const value = endpoint(name);
    assertCommonMetadata(name, value);
    assert.ok(value.callableTrigger, `${name} callableTrigger`);

    const override = callableOverrides[name as keyof typeof callableOverrides];
    assert.equal(runtimeNumber(value.timeoutSeconds), runtimeNumber(override?.timeoutSeconds), `${name} timeout`);
    assert.equal(runtimeNumber(value.availableMemoryMb), runtimeNumber(override?.availableMemoryMb), `${name} memory`);
  }

  assert.equal(
    endpoint("exchangeKakaoToken").serviceAccountEmail,
    DEVELOPMENT_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL
  );
});

test("Firestore trigger metadata를 유지한다", () => {
  for (const [name, expected] of Object.entries(firestoreEndpoints)) {
    const value = endpoint(name);
    assertCommonMetadata(name, value);
    assert.equal(value.eventTrigger?.eventType, expected.eventType, `${name} eventType`);
    assert.equal(
      value.eventTrigger?.eventFilterPathPatterns?.document,
      expected.document,
      `${name} document path`
    );
    assert.equal(runtimeNumber(value.timeoutSeconds), expected.timeoutSeconds, `${name} timeout`);
    assert.equal(runtimeNumber(value.availableMemoryMb), expected.availableMemoryMb, `${name} memory`);
  }
});

test("scheduler metadata를 유지한다", () => {
  for (const [name, expected] of Object.entries(scheduleEndpoints)) {
    const value = endpoint(name);
    assertCommonMetadata(name, value);
    assert.equal(value.scheduleTrigger?.schedule, expected.schedule, `${name} schedule`);
    assert.equal(value.scheduleTrigger?.timeZone, expected.timeZone, `${name} timezone`);
    assert.equal(runtimeNumber(value.timeoutSeconds), expected.timeoutSeconds, `${name} timeout`);
    assert.equal(runtimeNumber(value.availableMemoryMb), expected.availableMemoryMb, `${name} memory`);
  }
});

test("시즌 탐색 watchdog 상태 조회용 컬렉션 그룹 인덱스를 유지한다", () => {
  const indexConfig = JSON.parse(
    readFileSync("../firestore.indexes.json", "utf8")
  ) as {
    indexes?: Array<{
      collectionGroup?: string;
      queryScope?: string;
      fields?: Array<{fieldPath?: string; order?: string}>;
    }>;
    fieldOverrides?: Array<{
      collectionGroup?: string;
      fieldPath?: string;
      ttl?: boolean;
      indexes?: Array<{order?: string; queryScope?: string}>;
    }>;
  };

  const statusOverride = indexConfig.fieldOverrides?.find(
    (override) =>
      override.collectionGroup === "seasonDiscoveryJobs" &&
      override.fieldPath === "status"
  );

  assert.ok(statusOverride, "seasonDiscoveryJobs/status field override가 필요합니다.");
  assert.ok(
    statusOverride.indexes?.some(
      (index) =>
        index.order === "ASCENDING" &&
        index.queryScope === "COLLECTION_GROUP"
    ),
    "watchdog collectionGroup 조회용 ASCENDING 인덱스가 필요합니다."
  );
});

test("extraction issue 운영 projection·audit 인덱스를 유지한다", () => {
  const config = JSON.parse(
    readFileSync("../firestore.indexes.json", "utf8")
  ) as {
    indexes?: Array<{
      collectionGroup?: string;
      queryScope?: string;
      fields?: Array<{fieldPath?: string; order?: string}>;
    }>;
    fieldOverrides?: Array<{
      collectionGroup?: string;
      fieldPath?: string;
      ttl?: boolean;
      indexes?: Array<{order?: string; queryScope?: string}>;
    }>;
  };
  for (const collectionGroup of ["seasonDiscoveryJobs", "importJobs"]) {
    assert.ok(config.fieldOverrides?.some((override) =>
      override.collectionGroup === collectionGroup &&
      override.fieldPath === "extractionIssueFingerprint" &&
      override.indexes?.some((index) =>
        index.order === "ASCENDING" &&
        index.queryScope === "COLLECTION_GROUP")
    ));
  }
  assert.ok(config.fieldOverrides?.some((override) =>
    override.collectionGroup === "lookbookExtractionIssueAuditLogs" &&
    override.fieldPath === "expiresAt" && override.ttl === true
  ));
  for (const collectionGroup of [
    "lookbookExtractionFixVerificationRuns",
    "lookbookExtractionFixReleases",
  ]) {
    assert.ok(config.fieldOverrides?.some((override) =>
      override.collectionGroup === collectionGroup &&
      override.fieldPath === "expiresAt" && override.ttl === true
    ));
  }
});

test("chat moderation cleanup due query와 TTL 인덱스를 유지한다", () => {
  const config = JSON.parse(
    readFileSync("../firestore.indexes.json", "utf8")
  ) as {
    indexes?: Array<{
      collectionGroup?: string;
      queryScope?: string;
      fields?: Array<{fieldPath?: string; order?: string}>;
    }>;
    fieldOverrides?: Array<{
      collectionGroup?: string;
      fieldPath?: string;
      ttl?: boolean;
    }>;
  };
  for (const collectionGroup of [
    "chatMessageCleanupJobs",
    "moderationRoomCleanupJobs",
  ]) {
    assert.ok(config.indexes?.some((index) =>
      index.collectionGroup === collectionGroup &&
      index.queryScope === "COLLECTION" &&
      index.fields?.[0]?.fieldPath === "status" &&
      index.fields?.[1]?.fieldPath === "nextAttemptAt"
    ));
    assert.ok(config.fieldOverrides?.some((override) =>
      override.collectionGroup === collectionGroup &&
      override.fieldPath === "expiresAt" && override.ttl === true
    ));
  }
  assert.ok(config.fieldOverrides?.some((override) =>
    override.collectionGroup === "roomClosureNotices" &&
    override.fieldPath === "expiresAt" && override.ttl === true
  ));
});

test("active Rooms 목록·검색 query 인덱스를 유지한다", () => {
  const config = JSON.parse(
    readFileSync("../firestore.indexes.json", "utf8")
  ) as {
    indexes?: Array<{
      collectionGroup?: string;
      queryScope?: string;
      fields?: Array<{
        fieldPath?: string;
        order?: string;
        arrayConfig?: string;
      }>;
    }>;
  };
  const roomIndexes = config.indexes?.filter((index) =>
    index.collectionGroup === "Rooms" && index.queryScope === "COLLECTION"
  ) ?? [];
  const hasActivePrefix = (index: typeof roomIndexes[number]) =>
    index.fields?.[0]?.fieldPath === "isClosed" &&
    index.fields?.[0]?.order === "ASCENDING" &&
    index.fields?.[1]?.fieldPath === "lifecycleStatus" &&
    index.fields?.[1]?.order === "ASCENDING";

  assert.ok(roomIndexes.some((index) =>
    hasActivePrefix(index) &&
    index.fields?.[2]?.fieldPath === "lastMessageAt" &&
    index.fields?.[2]?.order === "DESCENDING"
  ));
  for (const searchField of ["roomSearchChars", "roomSearchNgrams2"]) {
    assert.ok(roomIndexes.some((index) =>
      hasActivePrefix(index) &&
      index.fields?.[2]?.fieldPath === searchField &&
      index.fields?.[2]?.arrayConfig === "CONTAINS" &&
      index.fields?.[3]?.fieldPath === "lastMessageAt" &&
      index.fields?.[3]?.order === "DESCENDING"
    ));
  }
});
