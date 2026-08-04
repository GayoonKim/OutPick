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
  "loadHiddenCommentUserIDs",
  "requestSeasonImport",
  "requestSeasonAssetRetry",
  "requestSeasonCandidateImportJobs",
  "requestSeasonDiscovery",
  "requestSeasonDiscoveryImprovement",
  "reanalyzeSeasonDiscoveryWithLatestExtractor",
  "resolveSeasonDiscoveryCandidate",
  "retrySeasonDiscovery",
  "getLookbookExtractionReview",
  "reviewLookbookExtraction",
  "requestLookbookExtractionReanalysis",
  "requestLookbookSeasonRepair",
  "previewLookbookSeasonRepair",
  "applyLookbookSeasonRepair",
  "runLookbookExtractionDiagnostic",
  "getLatestLookbookExtractionDiagnostic",
  "discoverSeasonCandidates",
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

test("Firebase deployment export 이름 76개를 유지한다", () => {
  const expected = [
    ...callableNames,
    ...Object.keys(firestoreEndpoints),
    ...Object.keys(scheduleEndpoints),
  ].sort();
  assert.equal(expected.length, 76);
  assert.deepEqual(Object.keys(exportedFunctions).sort(), expected);
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
  assert.ok(
    indexConfig.indexes?.some((index) =>
      index.collectionGroup === "seasonDiscoveryJobs" &&
      index.queryScope === "COLLECTION_GROUP" &&
      index.fields?.map((field) => field.fieldPath).join(",") ===
        "status,improvementRequested"
    ),
    "개선 요청 reconciler용 복합 인덱스가 필요합니다."
  );
});
