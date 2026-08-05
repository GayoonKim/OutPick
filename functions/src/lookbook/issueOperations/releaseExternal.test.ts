import assert from "node:assert/strict";
import test from "node:test";

import {releaseWorkerServiceResource} from "./releaseExternal.js";

test("release verifier는 실행 project의 Worker만 조회한다", () => {
  assert.equal(
    releaseWorkerServiceResource("outpick-test"),
    "https://run.googleapis.com/v2/projects/outpick-test/locations/" +
      "asia-northeast3/services/lookbook-import-worker-development",
  );
  assert.equal(
    releaseWorkerServiceResource("outpick-664ae"),
    "https://run.googleapis.com/v2/projects/outpick-664ae/locations/" +
      "asia-northeast3/services/lookbook-import-worker",
  );
  assert.throws(
    () => releaseWorkerServiceResource("unexpected-project"),
    /지원하지 않는/,
  );
});
