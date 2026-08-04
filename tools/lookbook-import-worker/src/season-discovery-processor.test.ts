import assert from "node:assert/strict";
import test from "node:test";

import {
  canClaimSeasonDiscoveryJob,
  isCurrentSeasonDiscoveryAttempt,
  seasonDiscoveryIssueFingerprint,
} from "./season-discovery-processor.js";

const request = {
  generation: 2,
  dispatchGeneration: 1,
  extractorVersion: "season-discovery-v1",
  extractionContractRevision: 1,
};

test("queued와 dispatching의 정확한 generation만 claim한다", () => {
  const job = {...request, status: "queued"};
  assert.equal(canClaimSeasonDiscoveryJob(job, request), true);
  const legacyJob: Record<string, unknown> = {...job};
  delete legacyJob.extractionContractRevision;
  assert.equal(canClaimSeasonDiscoveryJob(legacyJob, request), true);
  assert.equal(canClaimSeasonDiscoveryJob(
    {...job, status: "dispatching"}, request,
  ), true);
  assert.equal(canClaimSeasonDiscoveryJob(
    {...job, status: "running"}, request,
  ), false);
  assert.equal(canClaimSeasonDiscoveryJob(
    {...job, generation: 3}, request,
  ), false);
});

test("시즌 discovery issue fingerprint는 redacted 40자 계약을 따른다", () => {
  const fingerprint = seasonDiscoveryIssueFingerprint({
    status: "needsReview",
    sourceURL: "https://example.com/lookbooks?private=value",
    candidates: [],
    diagnostic: {
      parserStrategy: "anchor_scan",
      adapterKey: null,
      failureReasons: ["no_candidates_found"],
      errorMessage: null,
    },
  } as never);
  assert.match(fingerprint, /^[a-f0-9]{40}$/);
  assert.equal(fingerprint.includes("private"), false);
});

test("현재 brand pointer와 dispatch lease가 같은 attempt만 확정한다", () => {
  const attempt = {...request, jobID: "job-1", leaseOwner: "lease-1"};
  const brand = {
    activeSeasonDiscoveryJobID: "job-1",
    lastSeasonDiscoveryGeneration: 2,
  };
  const job = {...request, status: "running", leaseOwner: "lease-1"};
  assert.equal(isCurrentSeasonDiscoveryAttempt(brand, job, attempt), true);
  assert.equal(isCurrentSeasonDiscoveryAttempt(
    brand, {...job, leaseOwner: "lease-2"}, attempt,
  ), false);
  assert.equal(isCurrentSeasonDiscoveryAttempt(
    {...brand, activeSeasonDiscoveryJobID: "job-2"}, job, attempt,
  ), false);
  assert.equal(isCurrentSeasonDiscoveryAttempt(
    brand, {...job, dispatchGeneration: 2}, attempt,
  ), false);
});
