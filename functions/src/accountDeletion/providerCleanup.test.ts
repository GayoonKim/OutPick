import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {unlinkKakaoAccount} from "./providerCleanup.js";

test("Kakao unlink는 관리자 키와 provider user ID를 전송한다", async () => {
  const requests: Array<{url: string; init?: RequestInit}> = [];
  await unlinkKakaoAccount("1234", "admin-key", async (url, init) => {
    requests.push({url: String(url), init});
    return new Response(JSON.stringify({id: 1234}), {status: 200});
  });
  const request = requests[0];
  assert.equal(request?.url, "https://kapi.kakao.com/v1/user/unlink");
  assert.equal(
    (request?.init?.headers as Record<string, string>).Authorization,
    "KakaoAK admin-key",
  );
  assert.match(String(request?.init?.body), /target_id=1234/);
});

test("Kakao unlink는 미설정 secret과 인증 실패를 구분한다", async () => {
  await assert.rejects(
    unlinkKakaoAccount(
      "1234",
      "",
      async () => new Response(null, {status: 200}),
    ),
    (error) =>
      error instanceof HttpsError && error.code === "failed-precondition",
  );
  await assert.rejects(
    unlinkKakaoAccount(
      "1234",
      "bad-key",
      async () => new Response(null, {status: 401}),
    ),
    /kakao_unlink_failed:401/,
  );
});

test("Kakao의 이미 해제된 사용자 400 응답은 멱등 성공으로 처리한다", async () => {
  await assert.doesNotReject(unlinkKakaoAccount(
    "1234",
    "admin-key",
    async () => new Response(null, {status: 400}),
  ));
});
