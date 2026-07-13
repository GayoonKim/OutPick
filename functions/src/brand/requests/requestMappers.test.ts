/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";
import * as admin from "firebase-admin";
import {
  brandRequestGroupSummary,
  brandRequestPublicSummary,
  brandSearchSummary,
} from "./functions.js";

test("public summary는 내부 관리자 필드를 노출하지 않는다", () => {
  const createdAt = admin.firestore.Timestamp.fromDate(
    new Date("2026-01-01T00:00:00.000Z")
  );
  const summary = brandRequestPublicSummary("request-1", {
    brandName: "OutPick",
    requesterUID: "secret-user",
    adminNote: "secret-note",
    createdAt,
  });
  assert.equal(summary.requestID, "request-1");
  assert.equal(summary.createdAt, "2026-01-01T00:00:00.000Z");
  assert.equal("requesterUID" in summary, false);
  assert.equal("adminNote" in summary, false);
});

test("group과 brand summary는 누락 값을 기존 기본값으로 매핑한다", () => {
  assert.deepEqual(brandRequestGroupSummary("group-1", undefined), {
    groupID: "group-1",
    dedupeKey: "",
    dedupeKeySource: "brandName",
    displayNameSnapshot: "",
    normalizedBrandName: "",
    englishBrandName: null,
    normalizedEnglishBrandName: null,
    requestCount: 0,
    adminStage: "requested",
    status: "submitted",
    rejectionReason: null,
    resolvedBrandID: null,
    createdBrandID: null,
    brandCreatedAt: null,
    brandCreatedBy: null,
    adminNote: null,
    lastRequestID: null,
    lastRequestedAt: null,
    createdAt: null,
    updatedAt: null,
    reviewedAt: null,
    resolvedAt: null,
    rejectedAt: null,
    adminArchivedAt: null,
  });
  const brand = brandSearchSummary("brand-1", undefined);
  assert.equal(brand.brandID, "brand-1");
  assert.deepEqual(
    brand.metrics,
    {likeCount: 0, viewCount: 0, popularScore: 0}
  );
});
