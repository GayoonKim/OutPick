import assert from "node:assert/strict";
import test from "node:test";

import {resolveInvocation} from "./gcloud.js";

test("좁은 OIDC 권한으로 고정 endpoint와 operator token을 조회한다", async () => {
  const calls = [];
  const execute = (_command, args) => {
    calls.push(args);
    return args[0] === "functions" ?
      "https://issue-read-abc-du.a.run.app\n" : "user-access-token\n";
  };
  const fetchCalls = [];
  const result = await resolveInvocation(
    "development",
    "read",
    execute,
    async (url, options) => {
      fetchCalls.push({url, options});
      return {ok: true, json: async () => ({token: "secret-token"})};
    },
  );
  assert.equal(result.uri, "https://issue-read-abc-du.a.run.app");
  assert.equal(result.token, "secret-token");
  assert.ok(calls[0].includes("--project=outpick-test"));
  assert.deepEqual(calls[1], [
    "auth", "print-access-token", "--account=gayunkim.1@gmail.com",
  ]);
  assert.equal(fetchCalls[0].url,
    "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/" +
    "outpick-extraction-ops-dev@outpick-test.iam.gserviceaccount.com:" +
    "generateIdToken",
  );
  assert.equal(fetchCalls[0].options.headers.authorization,
    "Bearer user-access-token");
  assert.deepEqual(JSON.parse(fetchCalls[0].options.body), {
    audience: "https://issue-read-abc-du.a.run.app",
    includeEmail: true,
  });
  assert.equal(calls.flat().some((value) =>
    value.includes("--impersonate-service-account")), false);
});

test("run.app이 아닌 endpoint는 fail closed한다", async () => {
  await assert.rejects(resolveInvocation(
    "development",
    "read",
    () => "https://evil.example",
  ), /canonical/);
});

test("IAM Credentials 실패와 빈 token은 fail closed한다", async () => {
  const execute = (_command, args) => args[0] === "functions" ?
    "https://issue-read-abc-du.a.run.app" : "user-access-token";
  await assert.rejects(resolveInvocation(
    "development", "read", execute,
    async () => ({ok: false, status: 403}),
  ), /HTTP 403/);
  await assert.rejects(resolveInvocation(
    "development", "read", execute,
    async () => ({ok: true, json: async () => ({})}),
  ), /발급하지 못했습니다/);
});
