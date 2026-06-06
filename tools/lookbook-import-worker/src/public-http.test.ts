import assert from "node:assert/strict";
import test from "node:test";

import {
  assertPublicHTTPURL,
  isPublicIPAddress,
  retryableStatusError,
} from "./public-http.js";
import {RetryableImportError} from "./import-error.js";

test("공개 IP만 허용한다", () => {
  assert.equal(isPublicIPAddress("8.8.8.8"), true);
  assert.equal(isPublicIPAddress("10.0.0.1"), false);
  assert.equal(isPublicIPAddress("127.0.0.1"), false);
  assert.equal(isPublicIPAddress("169.254.169.254"), false);
  assert.equal(isPublicIPAddress("192.0.2.1"), false);
  assert.equal(isPublicIPAddress("198.51.100.1"), false);
  assert.equal(isPublicIPAddress("203.0.113.1"), false);
  assert.equal(isPublicIPAddress("::1"), false);
  assert.equal(isPublicIPAddress("fc00::1"), false);
});

test("localhost와 내부 DNS 결과를 차단한다", async () => {
  await assert.rejects(
    assertPublicHTTPURL("http://localhost/path"),
    /내부 네트워크/,
  );
  await assert.rejects(
    assertPublicHTTPURL("https://brand.example/lookbook", {
      lookupAll: async () => [{address: "192.168.0.10", family: 4}],
    }),
    /내부 네트워크/,
  );
});

test("공개 DNS 결과를 허용한다", async () => {
  const result = await assertPublicHTTPURL(
    "https://brand.example/lookbook",
    {
      lookupAll: async () => [{address: "8.8.8.8", family: 4}],
    },
  );
  assert.equal(result.hostname, "brand.example");
});

test("429와 5xx만 retryable HTTP 오류다", () => {
  assert.ok(
    retryableStatusError(429, "rate limit") instanceof RetryableImportError,
  );
  assert.ok(
    retryableStatusError(503, "unavailable") instanceof RetryableImportError,
  );
  assert.equal(
    retryableStatusError(404, "not found") instanceof RetryableImportError,
    false,
  );
});
