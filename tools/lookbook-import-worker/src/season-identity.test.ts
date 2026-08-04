import assert from "node:assert/strict";
import test from "node:test";
import {
  normalizedSeasonTitleKey,
  resolveSeasonCandidateIdentities,
} from "./season-identity.js";

test("시즌 표현을 year-term key로 정규화하고 일반명은 제외한다", () => {
  assert.equal(normalizedSeasonTitleKey("2025 S/S LOOKBOOK"), "25-ss");
  assert.equal(normalizedSeasonTitleKey("SS25"), "25-ss");
  assert.equal(normalizedSeasonTitleKey("Fall / Winter 2024"), "24-fw");
  assert.equal(normalizedSeasonTitleKey("LOOKBOOK"), null);
});

test("URL 일치와 유일 정규화 이름 일치를 구분한다", () => {
  const existing = [
    {seasonID: "s1", title: "2025 SS", sourceURL: "https://x.test/s25"},
    {seasonID: "s2", title: "2024 FW", sourceURL: "https://x.test/f24"},
  ];
  const result = resolveSeasonCandidateIdentities([
    {candidateID: "c1", title: "다른 이름", seasonURL: "https://x.test/s25#top"},
    {candidateID: "c2", title: "F/W 2024", seasonURL: "https://x.test/new-f24"},
    {candidateID: "c3", title: "2026 SS", seasonURL: "https://x.test/s26"},
  ], existing);
  assert.deepEqual(result.map((item) => item.resolution), [
    "matchedByURL", "matchedByUniqueNormalizedTitle", "newSeason",
  ]);
});

test("URL-이름 충돌, 복수 이름 일치, 다중 후보 수렴은 검토로 격리한다", () => {
  const existing = [
    {seasonID: "s1", title: "2025 SS", sourceURL: "https://x.test/s25"},
    {seasonID: "s2", title: "2024 FW", sourceURL: "https://x.test/f24"},
    {seasonID: "s3", title: "2024 FW", sourceURL: "https://x.test/f24-2"},
  ];
  const result = resolveSeasonCandidateIdentities([
    {candidateID: "conflict", title: "2024 FW", seasonURL: "https://x.test/s25"},
    {candidateID: "ambiguous", title: "2024 FW", seasonURL: "https://x.test/new"},
    {candidateID: "a", title: "2025 SS", seasonURL: "https://x.test/a"},
    {candidateID: "b", title: "SS25", seasonURL: "https://x.test/b"},
  ], existing);
  assert.deepEqual(result.map((item) => item.resolution), [
    "awaitingReviewConflictingMatch",
    "awaitingReviewAmbiguousTitle",
    "awaitingReviewDuplicateConvergence",
    "awaitingReviewDuplicateConvergence",
  ]);
});
