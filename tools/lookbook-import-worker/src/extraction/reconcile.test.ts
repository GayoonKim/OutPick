import assert from "node:assert/strict";
import test from "node:test";

import {
  makeSeasonReconcilePreview,
  seasonRepairPreviewDisposition,
} from "./reconcile.js";

test("canonical URL 일치는 기존 post를 유지하고 순서만 보정한다", () => {
  const preview = makeSeasonReconcilePreview({
    existingPosts: [
      {
        postID: "post-a",
        sourceURL: "https://brand.example/a.jpg?b=2&a=1",
        contentHash: "hash-a",
        sourceSortIndex: 1,
      },
      {
        postID: "post-b",
        sourceURL: "https://brand.example/b.jpg",
        contentHash: "hash-b",
        sourceSortIndex: 0,
      },
    ],
    candidates: [
      {
        candidateKey: "candidate-a",
        sourceURL: "https://brand.example/a.jpg?a=1&b=2",
        alt: null,
        contentHash: "hash-a",
      },
      {
        candidateKey: "candidate-b",
        sourceURL: "https://brand.example/b.jpg",
        alt: null,
        contentHash: "hash-b",
      },
    ],
  });

  assert.deepEqual(
    preview.reorder.map((entry) => [entry.postID, entry.proposedIndex]),
    [["post-a", 0], ["post-b", 1]],
  );
  assert.deepEqual(preview.add, []);
  assert.deepEqual(preview.removeCandidates, []);
});

test("keep만 있는 동일 결과는 검토 없이 noChanges다", () => {
  assert.equal(
    seasonRepairPreviewDisposition({
      add: [],
      reorder: [],
      removeCandidates: [],
    }),
    "noChanges",
  );
});

test("추가·순서 변경·삭제 후보 중 하나라도 있으면 검토가 필요하다", () => {
  const add = {
    kind: "add" as const,
    postID: "repair-1",
    candidateKey: "candidate-1",
    sourceURL: "https://brand.example/1.jpg",
    alt: null,
    contentHash: null,
    proposedIndex: 0,
  };
  const reorder = {
    kind: "reorder" as const,
    postID: "post-1",
    candidateKey: "candidate-1",
    sourceURL: "https://brand.example/1.jpg",
    previousIndex: 1,
    proposedIndex: 0,
    matchedBy: "canonicalURL" as const,
  };
  const removeCandidate = {
    kind: "removeCandidate" as const,
    postID: "post-2",
    sourceURL: "https://brand.example/2.jpg",
    previousIndex: 1,
    proposedIndex: 1,
  };

  assert.equal(
    seasonRepairPreviewDisposition({
      add: [add],
      reorder: [],
      removeCandidates: [],
    }),
    "reviewRequired",
  );
  assert.equal(
    seasonRepairPreviewDisposition({
      add: [],
      reorder: [reorder],
      removeCandidates: [],
    }),
    "reviewRequired",
  );
  assert.equal(
    seasonRepairPreviewDisposition({
      add: [],
      reorder: [],
      removeCandidates: [removeCandidate],
    }),
    "reviewRequired",
  );
});

test("다른 URL의 동일 content hash는 기존 post ID를 유지한다", () => {
  const preview = makeSeasonReconcilePreview({
    existingPosts: [{
      postID: "post-a",
      sourceURL: "https://old.example/a.jpg",
      contentHash: "same-hash",
      sourceSortIndex: 0,
    }],
    candidates: [{
      candidateKey: "candidate-a",
      sourceURL: "https://new.example/a.jpg",
      alt: null,
      contentHash: "same-hash",
    }],
  });

  assert.equal(preview.keep[0]?.postID, "post-a");
  assert.equal(preview.keep[0]?.matchedBy, "contentHash");
  assert.deepEqual(preview.add, []);
});

test("누락 후보만 deterministic post로 추가하고 사라진 post는 삭제하지 않는다", () => {
  const input = {
    existingPosts: [{
      postID: "legacy-post",
      sourceURL: "https://brand.example/legacy.jpg",
      contentHash: "legacy-hash",
      sourceSortIndex: 0,
    }],
    candidates: [{
      candidateKey: "candidate-new",
      sourceURL: "https://brand.example/new.jpg",
      alt: "new",
      contentHash: "new-hash",
    }],
  };
  const first = makeSeasonReconcilePreview(input);
  const second = makeSeasonReconcilePreview(input);

  assert.equal(first.add.length, 1);
  assert.match(first.add[0]?.postID ?? "", /^repair_[a-f0-9]{24}$/);
  assert.equal(first.removeCandidates[0]?.postID, "legacy-post");
  assert.equal(first.removeCandidates[0]?.proposedIndex, 1);
  assert.equal(first.resultingPostCount, 2);
  assert.equal(first.snapshotHash, second.snapshotHash);
  assert.equal(first.add[0]?.postID, second.add[0]?.postID);
});
