import assert from "node:assert/strict";
import test from "node:test";
import {
  assetWriteCleanupObjects, isAssetWriteCleanupDue,
  targetReferencesAssetPath,
} from "./asset-retention.js";

test("PQ12 asset cleanup은 terminal write와 24시간 기준을 모두 요구한다", () => {
  const due = {status: "replaced", cleanupState: "pending", cleanupAfter: 10};
  assert.equal(isAssetWriteCleanupDue(due, 9), false);
  assert.equal(isAssetWriteCleanupDue(due, 10), true);
  assert.equal(isAssetWriteCleanupDue(
    {...due, status: "uploading"}, 10), false);
  assert.equal(isAssetWriteCleanupDue({...due, cleanupState: "completed"}, 10),
    false);
  assert.equal(isAssetWriteCleanupDue({...due, cleanupAfter: "10"}, 10), false);
});

test("PQ12 cleanup은 두 JPEG의 저장 generation이 검증될 때만 대상을 만든다", () => {
  const ledger = {thumbPath: "brands/a/thumb.jpg",
    detailPath: "brands/a/detail.jpg",
    objects: {thumb: {generation: "101", size: 12},
      detail: {generation: 102, size: 40}}};
  assert.deepEqual(assetWriteCleanupObjects(ledger), [
    {variant: "thumb", path: "brands/a/thumb.jpg", generation: "101"},
    {variant: "detail", path: "brands/a/detail.jpg", generation: "102"},
  ]);
  assert.equal(assetWriteCleanupObjects({...ledger,
    objects: {thumb: {size: 12}}}), null);
  assert.deepEqual(assetWriteCleanupObjects({...ledger,
    objects: {thumb: {generation: "101", size: 12,
      deletedAt: 20}}}), []);
});

test("PQ12 현재 문서의 중첩 필드가 경로를 참조하면 cleanup을 보호한다", () => {
  assert.equal(targetReferencesAssetPath(
    {media: [{thumbPath: "brands/a/t.jpg"}]},
    ["brands/a/t.jpg"]), true);
  assert.equal(targetReferencesAssetPath({coverPath: "brands/a/t.jpg"},
    ["brands/a/t.jpg"]), true);
  assert.equal(targetReferencesAssetPath({url: "https://x/brands/a/t.jpg"},
    ["brands/a/t.jpg"]), false);
});
