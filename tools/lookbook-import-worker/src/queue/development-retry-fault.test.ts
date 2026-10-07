/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {retryFaultCampaign} from "./development-retry-fault.js";

test("KR15 장애 장치는 명시적 Development campaign과 revision·검증 digest가 있어야 활성화된다", () => {
  const env = {OUTPICK_Q7_RETRY_FAULT_CAMPAIGN: "11111111-1111-4111-8111-111111111111",
    OUTPICK_FIREBASE_PROJECT_ID: "outpick-test", K_SERVICE: "lookbook-import-worker-development",
    K_REVISION: "lookbook-import-worker-development-00025-test",
    OUTPICK_WORKER_VERIFICATION_DIGEST: "a".repeat(64)};
  assert.equal(retryFaultCampaign(env), env.OUTPICK_Q7_RETRY_FAULT_CAMPAIGN);
  assert.equal(retryFaultCampaign({}), null);
  for (const change of [{OUTPICK_FIREBASE_PROJECT_ID: "outpick-664ae"},
    {K_SERVICE: "lookbook-import-worker"}, {K_REVISION: "production-00001"},
    {OUTPICK_Q7_RETRY_FAULT_CAMPAIGN: "../foreign"}, {OUTPICK_WORKER_VERIFICATION_DIGEST: ""}]) {
    assert.throws(() => retryFaultCampaign({...env, ...change}), /ENVIRONMENT_INVALID/);
  }
});
