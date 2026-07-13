/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {exchangeKakaoAccessToken} from "./kakaoService.js";

function jsonResponse(value: unknown, ok = true): Response {
  return {ok, json: async () => value} as Response;
}

test("Kakao token info와 me를 순서대로 조회하고 custom token을 만든다", async () => {
  const calls: string[] = [];
  const result = await exchangeKakaoAccessToken("access-token", {
    fetch: (async (input, init) => {
      calls.push(String(input));
      assert.deepEqual(init?.headers, {Authorization: "Bearer access-token"});
      return calls.length === 1 ?
        jsonResponse({id: 123}) :
        jsonResponse({id: 123, kakao_account: {email: " USER@EXAMPLE.COM "}});
    }) as typeof fetch,
    createCustomToken: async (uid, claims) => {
      calls.push(`token:${uid}`);
      assert.deepEqual(claims, {provider: "kakao", providerUserID: "123"});
      return "firebase-token";
    },
  });

  assert.deepEqual(calls, [
    "https://kapi.kakao.com/v1/user/access_token_info",
    "https://kapi.kakao.com/v2/user/me",
    "token:kakao:123",
  ]);
  assert.deepEqual(result, {
    firebaseCustomToken: "firebase-token",
    identityKey: "kakao:123",
    provider: "kakao",
    providerUserID: "123",
    email: "user@example.com",
  });
});

test("Kakao HTTP 실패와 서로 다른 사용자 ID를 거부한다", async () => {
  await assert.rejects(
    exchangeKakaoAccessToken("bad", {
      fetch: (async () => jsonResponse({}, false)) as typeof fetch,
      createCustomToken: async () => "unused",
    }),
    (error: unknown) => error instanceof HttpsError &&
      error.code === "unauthenticated" &&
      error.message === "Kakao 토큰 검증에 실패했습니다."
  );

  let call = 0;
  await assert.rejects(
    exchangeKakaoAccessToken("mismatch", {
      fetch: (async () => jsonResponse({id: ++call})) as typeof fetch,
      createCustomToken: async () => "unused",
    }),
    (error: unknown) => error instanceof HttpsError &&
      error.code === "unauthenticated" &&
      error.message === "Kakao 사용자 식별에 실패했습니다."
  );
});

test("Kakao email은 선택 값이며 token 생성 실패는 그대로 전파한다", async () => {
  await assert.rejects(
    exchangeKakaoAccessToken("token", {
      fetch: (async () => jsonResponse({id: 77})) as typeof fetch,
      createCustomToken: async () => {
        throw new Error("auth unavailable");
      },
    }),
    /auth unavailable/
  );
});
