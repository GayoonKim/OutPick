/* eslint-disable require-jsdoc, max-len */
import assert from "node:assert/strict";
import test from "node:test";
import * as exportedFunctions from "./index.js";

type Endpoint = {
  availableMemoryMb?: number | null;
  timeoutSeconds?: number | null;
  maxInstances?: number | null;
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
  onRoomClosed: {
    eventType: "google.cloud.firestore.document.v1.updated",
    document: "Rooms/{roomId}",
    timeoutSeconds: null,
    availableMemoryMb: null,
  },
} as const;

const scheduleEndpoints = {
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
} as const;

const callableOverrides = {
  requestSeasonCandidateImportJobs: {timeoutSeconds: 120, availableMemoryMb: 512},
  runLookbookExtractionDiagnostic: {timeoutSeconds: 120, availableMemoryMb: 512},
  discoverSeasonCandidates: {timeoutSeconds: 60, availableMemoryMb: 512},
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

test("Firebase deployment export 이름 49개를 유지한다", () => {
  const expected = [
    ...callableNames,
    ...Object.keys(firestoreEndpoints),
    ...Object.keys(scheduleEndpoints),
  ].sort();
  assert.equal(expected.length, 49);
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
