import assert from "node:assert/strict";
import test from "node:test";
import {
  assertApplyGate,
  BRAND_CHAT_DELETE_NESTED_COLLECTIONS,
  BRAND_CHAT_DELETE_ROOT_COLLECTIONS,
  BRAND_CHAT_DELETE_STORAGE_PREFIXES,
  BRAND_CHAT_DELETE_USER_SUBCOLLECTIONS,
  classifyRootCollections,
  confirmationHash,
  EXPECTED_DEVELOPMENT_PROJECT_ID,
} from "./brandChatManifest.js";

test("브랜드·채팅 삭제 대상과 사용자 보존 경계를 분류한다", () => {
  const result = classifyRootCollections([
    "users",
    "Rooms",
    "brands",
    "styleMoods",
    "futureCollection",
    "Rooms",
  ]);

  assert.deepEqual(result, {
    delete: ["Rooms", "brands"],
    preserve: ["styleMoods", "users"],
    unknown: ["futureCollection"],
  });
  assert.ok(BRAND_CHAT_DELETE_ROOT_COLLECTIONS.includes("brandNameIndex"));
  assert.ok(
    BRAND_CHAT_DELETE_NESTED_COLLECTIONS.includes("brandRequestDays")
  );
  assert.ok(BRAND_CHAT_DELETE_NESTED_COLLECTIONS.includes("Messages"));
  assert.ok(BRAND_CHAT_DELETE_USER_SUBCOLLECTIONS.includes("joinedRooms"));
  assert.ok(BRAND_CHAT_DELETE_STORAGE_PREFIXES.includes("rooms/"));
});

test("confirmation hash는 key 순서와 무관하고 값 변경을 감지한다", () => {
  const first = confirmationHash({
    projectID: EXPECTED_DEVELOPMENT_PROJECT_ID,
    counts: {Rooms: 2, brands: 1},
  });
  const reordered = confirmationHash({
    counts: {brands: 1, Rooms: 2},
    projectID: EXPECTED_DEVELOPMENT_PROJECT_ID,
  });
  const changed = confirmationHash({
    projectID: EXPECTED_DEVELOPMENT_PROJECT_ID,
    counts: {Rooms: 3, brands: 1},
  });

  assert.equal(first, reordered);
  assert.notEqual(first, changed);
});

test("apply gate는 정확한 project·hash와 정지된 빈 queue만 허용한다", () => {
  const valid = {
    requestedProjectID: EXPECTED_DEVELOPMENT_PROJECT_ID,
    initializedProjectID: EXPECTED_DEVELOPMENT_PROJECT_ID,
    confirmationHash: "hash",
    expectedConfirmationHash: "hash",
    unknownRootCollections: [],
    queueState: "PAUSED",
    queueTaskCount: 0,
    processingImportJobCount: 0,
  };

  assert.doesNotThrow(() => assertApplyGate(valid));
  assert.throws(
    () => assertApplyGate({...valid, queueState: "RUNNING"}),
    /PAUSED/
  );
  assert.throws(
    () => assertApplyGate({...valid, queueTaskCount: 1}),
    /task가 남아/
  );
  assert.throws(
    () => assertApplyGate({...valid, processingImportJobCount: 1}),
    /processing import job/
  );
  assert.throws(
    () => assertApplyGate({...valid, confirmationHash: "stale"}),
    /confirmation hash/
  );
  assert.throws(
    () => assertApplyGate({...valid, unknownRootCollections: ["unknown"]}),
    /미분류 root collection/
  );
});
