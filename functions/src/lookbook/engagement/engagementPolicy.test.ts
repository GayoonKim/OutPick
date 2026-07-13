import assert from "node:assert/strict";
import test from "node:test";
import {
  commentStateDocumentID,
  numericMetric,
  postMetrics,
  postStateDocumentID,
  seasonStateDocumentID,
} from "./functions.js";

test("engagement state document ID 계약을 유지한다", () => {
  assert.equal(postStateDocumentID("b", "s", "p"), "b_s_p");
  assert.equal(seasonStateDocumentID("b", "s"), "b_s");
  assert.equal(commentStateDocumentID("b", "s", "p", "c"), "b_s_p_c");
});

test("누락되거나 유효하지 않은 metric은 0으로 매핑한다", () => {
  assert.equal(numericMetric(undefined), 0);
  assert.equal(numericMetric(Number.NaN), 0);
  assert.equal(numericMetric(3), 3);
  assert.deepEqual(postMetrics({metrics: {likeCount: 2, saveCount: 1}}), {
    likeCount: 2,
    commentCount: 0,
    replacementCount: 0,
    saveCount: 1,
    viewCount: 0,
  });
});
