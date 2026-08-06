/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";

import {parseVerifyFixRequest} from "./releaseContract.js";

const request = {
  apiVersion: 1,
  environment: "production",
  requestID: "release_request_123",
  action: "verifyFix",
  payload: {
    fingerprint: "a".repeat(40),
    expectedStateVersion: 2,
    stage: "seasonImageImport",
    targetRuntimeVersion: "extractor:1.3.0",
    workerRevision: "lookbook-import-worker-00025-test",
    workerSourceRevision: "b".repeat(40),
  },
};

test("verify-fix strict 계약은 canonical runtime과 revision만 허용한다", () => {
  assert.equal(parseVerifyFixRequest(request).payload.targetRuntimeVersion, "extractor:1.3.0");
  assert.throws(() => parseVerifyFixRequest({
    ...request,
    payload: {...request.payload, targetRuntimeVersion: "contract:2"},
  }), /stage/);
  assert.throws(() => parseVerifyFixRequest({
    ...request,
    payload: {...request.payload, arbitraryURL: "https://evil.example"},
  }), /허용되지 않은/);
});
