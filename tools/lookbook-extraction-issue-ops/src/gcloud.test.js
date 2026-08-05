import assert from "node:assert/strict";
import test from "node:test";

import {resolveInvocation} from "./gcloud.js";

test("고정 project/function/operator로 endpoint와 token을 조회한다", () => {
  const calls = [];
  const execute = (_command, args) => {
    calls.push(args);
    return args[0] === "functions" ?
      "https://issue-read-abc-du.a.run.app\n" : "secret-token\n";
  };
  const result = resolveInvocation("development", "read", execute);
  assert.equal(result.uri, "https://issue-read-abc-du.a.run.app");
  assert.equal(result.token, "secret-token");
  assert.ok(calls[0].includes("--project=outpick-test"));
  assert.ok(calls[1].some((value) => value.includes(
    "outpick-extraction-ops-dev@outpick-test.iam.gserviceaccount.com",
  )));
});

test("run.app이 아닌 endpoint는 fail closed한다", () => {
  assert.throws(() => resolveInvocation(
    "development",
    "read",
    () => "https://evil.example",
  ), /canonical/);
});
