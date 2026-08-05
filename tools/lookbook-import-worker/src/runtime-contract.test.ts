/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";

import {loadConfig} from "./config.js";
import {processExtractionSmoke, workerRuntimeContract} from "./runtime-contract.js";

const config = loadConfig({
  OUTPICK_FIREBASE_PROJECT_ID: "outpick-test",
  OUTPICK_FIREBASE_STORAGE_BUCKET: "outpick-test.firebasestorage.app",
  OUTPICK_IMPORT_OIDC_AUDIENCE:
    "https://lookbook-import-worker-development-xyenspjiwa-du.a.run.app",
  OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL:
    "outpick-lookbook-task-dev@outpick-test.iam.gserviceaccount.com",
  OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL:
    "86635107099-compute@developer.gserviceaccount.com",
  K_REVISION: "lookbook-import-worker-development-00001-test",
  OUTPICK_WORKER_SOURCE_REVISION: "b".repeat(40),
  OUTPICK_SEASON_DISCOVERY_CONTRACT_REVISION: "1",
  OUTPICK_SEASON_DISCOVERY_EXTRACTOR_VERSION: "season-discovery-v1",
});

test("runtime contract는 실행 revision과 extractor/adapter 버전을 고정한다", () => {
  assert.deepEqual(workerRuntimeContract(config), {
    schemaVersion: 1,
    projectID: "outpick-test",
    workerRevision: "lookbook-import-worker-development-00001-test",
    workerSourceRevision: "b".repeat(40),
    seasonDiscoveryContractRevision: 1,
    seasonDiscoveryExtractorVersion: "season-discovery-v1",
    imageExtractorVersion: "1.2.3",
    adapterVersions: {cafe24: "1.0.1"},
  });
});

test("smoke는 fingerprint, stage와 정확한 job path를 fail closed 검증한다", async () => {
  await assert.rejects(processExtractionSmoke({
    fingerprint: "unsafe",
    stage: "seasonImageImport",
    sourceURL: "https://example.com/lookbook",
    sourceJobPath: "brands/a/importJobs/b",
  }, workerRuntimeContract(config)), /fingerprint/);
  await assert.rejects(processExtractionSmoke({
    fingerprint: "a".repeat(40),
    stage: "seasonImageImport",
    sourceURL: "http://example.com/lookbook",
    sourceJobPath: "brands/a/importJobs/b",
  }, workerRuntimeContract(config)), /HTTPS/);
});
