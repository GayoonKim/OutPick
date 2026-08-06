import assert from "node:assert/strict";
import test from "node:test";

import {
  IssueOperationsRequestError,
  parseReadRequest,
  parseWriteRequest,
} from "./contract.js";

const envelope = {
  apiVersion: 1,
  environment: "development",
  requestID: "request_12345678",
};

test("list는 bounded 기본값을 사용하고 brandID 필드를 거부한다", () => {
  const parsed = parseReadRequest({
    ...envelope,
    action: "listClusters",
    payload: {},
  });
  assert.equal(parsed.action, "listClusters");
  assert.equal(parsed.payload.limit, 20);
  assert.deepEqual(
    parsed.payload.statuses,
    ["open", "inProgress", "needsGroundTruth"],
  );
  assert.throws(() => parseReadRequest({
    ...envelope,
    action: "listClusters",
    payload: {brandID: "brand-a"},
  }), IssueOperationsRequestError);
});

test("batch는 최대 20개와 정확한 fingerprint만 허용한다", () => {
  assert.throws(() => parseReadRequest({
    ...envelope,
    action: "getClustersBatch",
    payload: {fingerprints: Array.from({length: 21}, () => "a".repeat(40))},
  }), IssueOperationsRequestError);
  assert.throws(() => parseReadRequest({
    ...envelope,
    action: "getCluster",
    payload: {fingerprint: "../unsafe"},
  }), IssueOperationsRequestError);
});

test("ground truth는 확정 enum과 redacted candidate key만 허용한다", () => {
  const parsed = parseWriteRequest({
    ...envelope,
    action: "recordGroundTruthAndResume",
    payload: {
      fingerprint: "b".repeat(40),
      expectedStateVersion: 2,
      groundTruth: {
        expectedCandidateCount: 12,
        candidateKeys: ["c".repeat(24)],
        sourceClassification: "completeGallery",
        note: "관리자 확인",
      },
    },
  });
  assert.equal(
    parsed.payload.groundTruth?.sourceClassification,
    "completeGallery",
  );
  assert.throws(() => parseWriteRequest({
    ...envelope,
    action: "recordGroundTruthAndResume",
    payload: {
      fingerprint: "b".repeat(40),
      expectedStateVersion: 2,
      groundTruth: {
        candidateKeys: ["https://brand.example/private?token=value"],
        sourceClassification: "completeGallery",
      },
    },
  }), IssueOperationsRequestError);
});

test("wont-fix는 확정된 사유와 bounded note를 요구한다", () => {
  assert.equal(parseWriteRequest({
    ...envelope,
    action: "markWontFix",
    payload: {
      fingerprint: "d".repeat(40),
      expectedStateVersion: 3,
      wontFixReason: "unsupportedStructure",
      note: "지원 범위에서 제외",
    },
  }).payload.wontFixReason, "unsupportedStructure");
  assert.throws(() => parseWriteRequest({
    ...envelope,
    action: "markWontFix",
    payload: {
      fingerprint: "d".repeat(40),
      expectedStateVersion: 3,
      wontFixReason: "other",
      note: "임의 사유",
    },
  }), IssueOperationsRequestError);
});
