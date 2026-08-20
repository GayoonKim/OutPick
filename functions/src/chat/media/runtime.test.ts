import assert from "node:assert/strict";
import test from "node:test";
import {
  chatMediaServiceAccountEmailForEnvironment,
  chatMediaServiceAccountEmailForProject,
} from "./runtime.js";

test("Development와 Production media identity를 환경별로 분리한다", () => {
  assert.equal(
    chatMediaServiceAccountEmailForProject("outpick-test", "orchestrator"),
    "outpick-chat-media-orch-dev@outpick-test.iam.gserviceaccount.com"
  );
  assert.equal(
    chatMediaServiceAccountEmailForProject("outpick-test", "cleanup"),
    "outpick-chat-media-cleanup-dev@outpick-test.iam.gserviceaccount.com"
  );
  assert.equal(
    chatMediaServiceAccountEmailForProject("outpick-664ae", "orchestrator"),
    "outpick-chat-media-orchestrator@outpick-664ae.iam.gserviceaccount.com"
  );
  assert.equal(
    chatMediaServiceAccountEmailForProject("outpick-664ae", "cleanup"),
    "outpick-chat-media-cleanup@outpick-664ae.iam.gserviceaccount.com"
  );
});

test("지원하지 않는 project와 누락된 project 환경은 fail closed한다", () => {
  assert.throws(
    () => chatMediaServiceAccountEmailForProject("unknown", "cleanup"),
    /지원하지 않는 Firebase project/
  );
  assert.throws(
    () => chatMediaServiceAccountEmailForEnvironment({}, "orchestrator"),
    /project ID 환경 변수가 필요/
  );
});
