/* eslint-disable require-jsdoc, max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {
  assertExpectedProductionCounts,
  buildBackfillCounts,
  parseBackfillArguments,
  PRODUCTION_CONFIRMATION,
  resolveBackfillIdentity,
} from "./backfill.js";

function fetcherReturning(
  response: Response,
  inspect?: (input: URL | RequestInfo, init?: RequestInit) => void,
): typeof fetch {
  return (async (input: URL | RequestInfo, init?: RequestInit) => {
    inspect?.(input, init);
    return response;
  }) as typeof fetch;
}

const kakaoUser = {
  uid: "kakao:12345",
  providerData: [],
};

test("Kakao UID 후보를 Admin API 응답 ID와 대조한다", async () => {
  let requested = false;
  const result = await resolveBackfillIdentity(
    kakaoUser,
    "admin-secret",
    fetcherReturning(
      new Response(JSON.stringify({id: 12345}), {status: 200}),
      (input, init) => {
        requested = true;
        const url = new URL(String(input));
        assert.equal(url.origin + url.pathname, "https://kapi.kakao.com/v2/user/me");
        assert.equal(url.searchParams.get("target_id_type"), "user_id");
        assert.equal(url.searchParams.get("target_id"), "12345");
        assert.equal(init?.method, "GET");
        assert.deepEqual(init?.headers, {
          "Authorization": "KakaoAK admin-secret",
          "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
        });
      },
    ),
  );
  assert.equal(requested, true);
  assert.deepEqual(result, {
    identity: {provider: "kakao", subject: "12345"},
    unresolvedReason: null,
  });
});

test("Kakao UID와 API 응답 ID가 다르면 unresolved로 분류한다", async () => {
  const result = await resolveBackfillIdentity(
    kakaoUser,
    "admin-secret",
    fetcherReturning(new Response(JSON.stringify({id: 99999}), {status: 200})),
  );
  assert.deepEqual(result, {
    identity: null,
    unresolvedReason: "kakao-identity-mismatch",
  });
});

test("Kakao 미연결 응답은 unresolved로 분류한다", async () => {
  const result = await resolveBackfillIdentity(
    kakaoUser,
    "admin-secret",
    fetcherReturning(new Response("not linked", {status: 400})),
  );
  assert.equal(result.unresolvedReason, "kakao-unlinked");
});

test("Kakao HTTP 실패는 응답 본문 없이 unresolved로 분류한다", async () => {
  const sensitiveBody = "provider-id-and-secret";
  const result = await resolveBackfillIdentity(
    kakaoUser,
    "admin-secret",
    fetcherReturning(new Response(sensitiveBody, {status: 500})),
  );
  assert.equal(result.unresolvedReason, "kakao-http-failure");
  assert.equal(JSON.stringify(result).includes(sensitiveBody), false);
});

test("비숫자 Kakao UID는 Admin API를 호출하지 않는다", async () => {
  let requested = false;
  const result = await resolveBackfillIdentity(
    {uid: "kakao:not-a-number", providerData: []},
    "admin-secret",
    fetcherReturning(new Response(null, {status: 200}), () => {
      requested = true;
    }),
  );
  assert.equal(requested, false);
  assert.equal(result.unresolvedReason, "kakao-invalid-uid");
});

test("Google providerData는 Kakao Admin API 없이 resolve한다", async () => {
  const result = await resolveBackfillIdentity({
    uid: "firebase-uid",
    providerData: [{providerId: "google.com", uid: "google-subject"}],
  }, null);
  assert.deepEqual(result, {
    identity: {provider: "google", subject: "google-subject"},
    unresolvedReason: null,
  });
});

test("backfill summary는 계정 식별자를 포함하지 않는다", () => {
  const summary = buildBackfillCounts([
    {
      identity: {provider: "google", subject: "private-google-subject"},
      unresolvedReason: null,
    },
    {identity: null, unresolvedReason: "kakao-unlinked"},
  ]);
  const output = JSON.stringify(summary);
  assert.equal(output.includes("private-google-subject"), false);
  assert.deepEqual(summary, {
    authUserCount: 2,
    resolvedCount: 1,
    unresolvedCount: 1,
    providerCounts: {google: 1, apple: 0, kakao: 0},
    unresolvedReasonCounts: {"kakao-unlinked": 1},
  });
});

test("Production dry-run은 apply 확인값 없이 허용한다", () => {
  const options = parseBackfillArguments(["--project", "outpick-664ae"]);
  assert.equal(options.apply, false);
  assert.equal(options.expectedTotal, null);
});

test("Production apply는 exact 확인 문자열과 예상 건수를 모두 요구한다", () => {
  assert.throws(
    () => parseBackfillArguments([
      "--project", "outpick-664ae", "--apply",
      "--confirm-production", "wrong",
      "--expected-total", "2",
      "--expected-google", "1",
      "--expected-kakao", "1",
    ]),
    /확인 문자열/,
  );
  assert.throws(
    () => parseBackfillArguments([
      "--project", "outpick-664ae", "--apply",
      "--confirm-production", PRODUCTION_CONFIRMATION,
    ]),
    /예상 계정 수/,
  );
  assert.throws(
    () => parseBackfillArguments([
      "--project", "outpick-664ae", "--apply",
      "--confirm-production", PRODUCTION_CONFIRMATION,
      "--expected-total", "3",
      "--expected-google", "1",
      "--expected-kakao", "1",
    ]),
    /provider별 합계/,
  );
  assert.throws(
    () => parseBackfillArguments([
      "--project", "outpick-664ae", "--apply",
      "--confirm-production", PRODUCTION_CONFIRMATION,
      "--expected-total", "2",
      "--expected-google", "1",
      "--expected-kakao", "1",
      "--secret-name", "wrong-secret",
    ]),
    /canonical Secret/,
  );
});

test("Production apply는 실제 계정 수가 예상과 다르면 쓰기 전에 차단한다", () => {
  const options = parseBackfillArguments([
    "--project", "outpick-664ae", "--apply",
    "--confirm-production", PRODUCTION_CONFIRMATION,
    "--expected-total", "2",
    "--expected-google", "1",
    "--expected-kakao", "1",
  ]);
  assert.doesNotThrow(() => assertExpectedProductionCounts(options, {
    authUserCount: 2,
    resolvedCount: 2,
    unresolvedCount: 0,
    providerCounts: {google: 1, apple: 0, kakao: 1},
    unresolvedReasonCounts: {},
  }));
  assert.throws(() => assertExpectedProductionCounts(options, {
    authUserCount: 3,
    resolvedCount: 3,
    unresolvedCount: 0,
    providerCounts: {google: 2, apple: 0, kakao: 1},
    unresolvedReasonCounts: {},
  }), /예상 계정 수/);
});
