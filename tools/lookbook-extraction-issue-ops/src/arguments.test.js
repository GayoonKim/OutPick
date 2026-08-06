import assert from "node:assert/strict";
import test from "node:test";

import {parseArguments} from "./arguments.js";

test("environment는 필수이고 arbitrary URL flag는 거부된다", () => {
  assert.throws(() => parseArguments(["list"]), /environment/);
  assert.throws(() => parseArguments([
    "list", "--environment", "development", "--url", "https://evil.example",
  ]), /허용되지 않은 flag/);
});

test("list와 batch의 bounded 입력을 구성한다", () => {
  assert.deepEqual(parseArguments([
    "list", "--environment", "development", "--limit", "20",
    "--status", "open", "--recurrence-only",
  ]).payload, {
    limit: 20,
    statuses: ["open"],
    recurrenceOnly: true,
  });
  assert.throws(() => parseArguments([
    "show-batch", "--environment", "development",
    ...Array.from({length: 21}, () => ["--fingerprint", "a".repeat(40)]).flat(),
  ]), /1~20개/);
});

test("Production write는 정확한 project 확인값을 요구한다", () => {
  const base = [
    "start", "--environment", "production",
    "--fingerprint", "a".repeat(40),
    "--expected-state-version", "1",
  ];
  assert.throws(() => parseArguments(base), /confirm-production/);
  assert.equal(parseArguments([
    ...base, "--confirm-production", "outpick-664ae",
  ]).action, "startProcessing");
});

test("verify-fix는 양 환경을 지원하고 Production만 확인값을 요구한다", () => {
  const flags = [
    "--fingerprint", "a".repeat(40),
    "--expected-state-version", "2",
    "--stage", "seasonImageImport",
    "--target-runtime-version", "extractor:1.3.0",
    "--worker-revision", "lookbook-import-worker-00025-test",
    "--worker-source-revision", "b".repeat(40),
  ];
  const development = parseArguments([
    "verify-fix", "--environment", "development", ...flags,
  ]);
  assert.equal(development.environment, "development");
  assert.throws(() => parseArguments([
    "verify-fix", "--environment", "production", ...flags,
  ]), /확인값/);
  const parsed = parseArguments([
    "verify-fix", "--environment", "production", ...flags,
    "--confirm-production", "outpick-664ae",
  ]);
  assert.equal(parsed.endpoint, "release");
  assert.equal(parsed.action, "verifyFix");
});
