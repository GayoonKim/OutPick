import assert from "node:assert/strict";
import test from "node:test";

import {
  repairRequestDisposition,
  seasonRepairPlan,
} from "./repairContract.js";

test("repair plan은 keep/add/reorder/remove를 분리해 검증한다", () => {
  const plan = seasonRepairPlan({
    keep: [{
      postID: "post-a",
      sourceURL: "https://brand.example/a.jpg",
      proposedIndex: 0,
    }],
    reorder: [],
    add: [{
      postID: "repair_new",
      candidateKey: "candidate-new",
      sourceURL: "https://brand.example/new.jpg",
      alt: null,
      contentHash: "a".repeat(64),
      proposedIndex: 1,
    }],
    removeCandidates: [{
      postID: "legacy",
      sourceURL: "https://brand.example/legacy.jpg",
      previousIndex: 2,
      proposedIndex: 2,
    }],
    orderedPostIDs: ["post-a", "repair_new"],
    allPostIDs: ["post-a", "repair_new", "legacy"],
    resultingPostCount: 3,
  });

  assert.deepEqual(plan.orderedPostIDs, ["post-a", "repair_new"]);
  assert.deepEqual(
    plan.removeCandidates.map((entry) => entry.postID),
    ["legacy"]
  );
  assert.equal(plan.resultingPostCount, 3);
});

test("진행 중 동일 repair는 duplicate이고 다른 active 작업은 거부한다", () => {
  assert.equal(
    repairRequestDisposition({
      jobStatus: "awaitingReview",
      repairStatus: "previewReady",
      repairTargetSeasonID: "season-a",
      requestedSeasonID: "season-a",
    }),
    "duplicate"
  );
  assert.equal(
    repairRequestDisposition({
      jobStatus: "failed",
      repairStatus: "analyzing",
      repairTargetSeasonID: "season-a",
      requestedSeasonID: "season-a",
    }),
    "start"
  );
  assert.throws(() => repairRequestDisposition({
    jobStatus: "processing",
    repairStatus: null,
    repairTargetSeasonID: null,
    requestedSeasonID: "season-a",
  }));
  assert.equal(
    repairRequestDisposition({
      jobStatus: "succeeded",
      repairStatus: null,
      repairTargetSeasonID: null,
      requestedSeasonID: "season-a",
    }),
    "start"
  );
});

test("변경 없음으로 끝난 repair는 같은 시즌을 다시 비교할 수 있다", () => {
  assert.equal(
    repairRequestDisposition({
      jobStatus: "succeeded",
      repairStatus: "noChanges",
      repairTargetSeasonID: "season-1",
      requestedSeasonID: "season-1",
    }),
    "start",
  );
});
