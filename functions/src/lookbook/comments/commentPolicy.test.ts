import assert from "node:assert/strict";
import test from "node:test";
import {postMetrics} from "./functions.js";

test("댓글 mutation이 사용하는 post metric 기본값을 유지한다", () => {
  assert.deepEqual(postMetrics(undefined), {
    likeCount: 0,
    commentCount: 0,
    replacementCount: 0,
    saveCount: 0,
    viewCount: 0,
  });
  assert.deepEqual(postMetrics({metrics: {commentCount: 4}}), {
    likeCount: 0,
    commentCount: 4,
    replacementCount: 0,
    saveCount: 0,
    viewCount: 0,
  });
});
