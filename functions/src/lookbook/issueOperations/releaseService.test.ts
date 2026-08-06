/* eslint-disable max-len */
import {createHash} from "node:crypto";
import assert from "node:assert/strict";
import test from "node:test";

import type {VerifyFixRequest} from "./releaseContract.js";
import {
  releaseJobProjectionEligible,
  validateReleaseCandidate,
} from "./releaseService.js";

const jobPath = "brands/brand-a/importJobs/job-a";
const payload: VerifyFixRequest["payload"] = {
  fingerprint: "a".repeat(40),
  expectedStateVersion: 2,
  stage: "seasonImageImport",
  targetRuntimeVersion: "extractor:1.3.0",
  workerRevision: "lookbook-import-worker-00025-test",
  workerSourceRevision: "b".repeat(40),
};
const service = {
  uri: "https://worker.example.run.app",
  ready: true,
  reconciling: false,
  traffic: [{revision: payload.workerRevision, percent: 100}],
};
const runtime = {
  schemaVersion: 1 as const,
  projectID: "outpick-664ae",
  workerRevision: payload.workerRevision,
  workerSourceRevision: payload.workerSourceRevision,
  seasonDiscoveryContractRevision: 1,
  seasonDiscoveryExtractorVersion: "season-discovery-v1",
  imageExtractorVersion: "1.3.0",
  adapterVersions: {cafe24: "1.0.0"},
};
const smoke = {
  fingerprint: payload.fingerprint,
  stage: payload.stage,
  sourceJobPathHash: createHash("sha256").update(jobPath).digest("hex").slice(0, 40),
  candidateCount: 2,
  candidateKeys: ["c".repeat(24), "d".repeat(24)],
  logicIssueDetected: false,
  failureReasons: [],
  qualityReasons: ["expected_count_unverified"],
  runtime,
};

test("parse 실패 보강은 100% traffic/runtime/smoke 일치 시 통과한다", () => {
  validateReleaseCandidate({
    environment: "production",
    cluster: {
      stage: payload.stage,
      status: "inProgress",
      stateVersion: 2,
      blockedRuntimeVersion: "extractor:1.2.3",
      failureReasons: ["parse_failed"],
      qualityReasons: ["no_candidates"],
    },
    payload, service, runtime, smoke, jobPath,
  });
});

test("partial traffic, runtime mismatch와 stale stateVersion을 거부한다", () => {
  const cluster = {
    stage: payload.stage,
    status: "inProgress",
    stateVersion: 2,
    blockedRuntimeVersion: "extractor:1.2.3",
    failureReasons: ["parse_failed"],
  };
  assert.throws(() => validateReleaseCandidate({
    environment: "production",
    cluster, payload,
    service: {...service, traffic: [{revision: payload.workerRevision, percent: 90}]},
    runtime, smoke, jobPath,
  }), /traffic/);
  assert.throws(() => validateReleaseCandidate({
    environment: "production",
    cluster, payload, service,
    runtime: {...runtime, workerSourceRevision: "e".repeat(40)},
    smoke, jobPath,
  }), /runtime/);
  assert.throws(() => validateReleaseCandidate({
    environment: "production",
    cluster: {...cluster, stateVersion: 3}, payload, service, runtime, smoke, jobPath,
  }), /stateVersion/);
});

test("완전성 문제는 ground truth와 정확한 결과 일치를 요구한다", () => {
  const cluster = {
    stage: payload.stage,
    status: "inProgress",
    stateVersion: 2,
    blockedRuntimeVersion: "extractor:1.2.3",
    failureReasons: [],
    qualityReasons: ["expected_count_mismatch"],
  };
  assert.throws(() => validateReleaseCandidate({
    environment: "production",
    cluster, payload, service, runtime, smoke, jobPath,
  }), /ground truth/);
  validateReleaseCandidate({
    environment: "production",
    cluster: {
      ...cluster,
      groundTruth: {
        expectedCandidateCount: 2,
        candidateKeys: smoke.candidateKeys,
        sourceClassification: "completeGallery",
      },
    },
    payload, service, runtime, smoke, jobPath,
  });
});

test("Development runtime은 Development project와만 일치한다", () => {
  const cluster = {
    stage: payload.stage,
    status: "inProgress",
    stateVersion: 2,
    blockedRuntimeVersion: "extractor:1.2.3",
    failureReasons: ["parse_failed"],
  };
  const developmentRuntime = {...runtime, projectID: "outpick-test"};
  validateReleaseCandidate({
    environment: "development",
    cluster,
    payload,
    service,
    runtime: developmentRuntime,
    smoke: {...smoke, runtime: developmentRuntime},
    jobPath,
  });
  assert.throws(() => validateReleaseCandidate({
    environment: "development",
    cluster, payload, service, runtime,
    smoke, jobPath,
  }), /runtime/);
});

test("projection은 이전 runtime에서 막힌 미해결 job만 retry 대상으로 표시한다", () => {
  assert.equal(releaseJobProjectionEligible({
    blockedRuntimeVersion: "extractor:1.2.3",
    extractionIssueStatus: "open",
  }, "extractor:1.3.0"), true);
  assert.equal(releaseJobProjectionEligible({
    blockedRuntimeVersion: "extractor:1.3.0",
    extractionIssueStatus: "open",
  }, "extractor:1.3.0"), false);
  assert.equal(releaseJobProjectionEligible({
    blockedRuntimeVersion: "extractor:1.2.3",
    extractionIssueStatus: "fixed",
  }, "extractor:1.3.0"), false);
  assert.equal(releaseJobProjectionEligible({
    blockedRuntimeVersion: "extractor:1.2.3",
    resolvedByGeneration: 4,
  }, "extractor:1.3.0"), false);
});
