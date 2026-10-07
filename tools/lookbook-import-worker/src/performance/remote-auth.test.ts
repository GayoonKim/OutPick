import assert from "node:assert/strict";
import test from "node:test";
import {remoteIdentityToken} from "./remote-auth.js";
import {REMOTE_AUDIENCE, REMOTE_CALLER} from "./remote-target.js";

test("RN11 인증은 기존 사용자 자격으로 지정 OIDC 토큰만 요청한다", async () => {
  let calls = 0;
  const token = await remoteIdentityToken(new AbortController().signal, {
    accessToken: async () => "user-access-token",
    request: async (url, init) => {
      calls++;
      assert.equal(url, "https://iamcredentials.googleapis.com/v1/projects/" +
        `-/serviceAccounts/${REMOTE_CALLER}:generateIdToken`);
      assert.equal(init.method, "POST"); assert.equal(init.redirect, "error");
      assert.equal(init.headers.authorization, "Bearer user-access-token");
      assert.deepEqual(JSON.parse(init.body),
        {audience: REMOTE_AUDIENCE, includeEmail: true});
      assert.equal(init.signal.aborted, false);
      return {ok: true, json: async () => ({token: "oidc-token"}), body: null};
    },
  });
  assert.equal(token, "oidc-token"); assert.equal(calls, 1);
});

test("RN12 인증 실패 취소와 잘못된 응답은 재요청이나 인증값 노출이 없다",
  async () => {
    for (const mode of ["cancel", "access", "http", "body", "late"]) {
      const controller = new AbortController();
      let calls = 0; let cancelled = 0;
      if (mode === "cancel") controller.abort();
      await assert.rejects(remoteIdentityToken(controller.signal, {
        accessToken: async () => {
          if (mode === "access") throw new Error("secret-access-token");
          return "secret-access-token";
        },
        request: async () => {
          calls++;
          if (mode === "late") controller.abort();
          return {ok: mode !== "http", json: async () =>
            mode === "body" ? {token: "invalid token"} : {token: "secret"},
          body: {cancel: async () => {
            cancelled++;
          }}};
        },
      }), (error: Error) => {
        assert.equal(error.message, "지정 OIDC 호출자 토큰 준비 실패");
        return true;
      });
      assert.equal(calls, mode === "cancel" || mode === "access" ? 0 : 1);
      assert.equal(cancelled, mode === "http" ? 1 : 0);
    }
  });
