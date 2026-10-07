import assert from "node:assert/strict";
import test from "node:test";
import {recoveryIdentityToken} from "./recovery-auth.js";

const input = {
  serviceAccountEmail:
    "lookbook-import-recovery@outpick-test.iam.gserviceaccount.com",
  audience: "https://worker.example.com",
};

test("PQ14 복구 인증은 사용자 자격으로 전용 계정 ID 토큰만 발급한다",
  async () => {
    let calls = 0;
    const token = await recoveryIdentityToken(input,
      new AbortController().signal, {
        accessToken: async () => "user-token",
        request: async (url, init) => {
          calls++;
          assert.equal(url,
            "https://iamcredentials.googleapis.com/v1/projects/" +
            `-/serviceAccounts/${input.serviceAccountEmail}:generateIdToken`);
          assert.equal(init.method, "POST");
          assert.equal(init.redirect, "error");
          assert.equal(init.headers.authorization, "Bearer user-token");
          assert.deepEqual(JSON.parse(init.body),
            {audience: input.audience, includeEmail: true});
          return {ok: true, json: async () => ({token: "id-token"}),
            body: null};
        },
      });
    assert.equal(token, "id-token");
    assert.equal(calls, 1);
  });

test("PQ14 복구 인증 오류와 취소는 재요청과 비밀정보 노출 없이 거절한다",
  async () => {
    for (const mode of ["cancel", "access", "http", "body", "late",
      "account", "audience"]) {
      const controller = new AbortController();
      if (mode === "cancel") controller.abort();
      let calls = 0;
      let cancelled = 0;
      await assert.rejects(recoveryIdentityToken({
        serviceAccountEmail: mode === "account" ? "invalid/secret" :
          input.serviceAccountEmail,
        audience: mode === "audience" ? "http://insecure.example.com" :
          input.audience,
      }, controller.signal, {
        accessToken: async () => {
          if (mode === "access") throw new Error("secret-access-token");
          return "secret-access-token";
        },
        request: async () => {
          calls++;
          if (mode === "late") controller.abort();
          return {ok: mode !== "http", json: async () =>
            ({token: mode === "body" ? "invalid token" : "secret-id-token"}),
          body: {cancel: async () => {
            cancelled++;
          }}};
        },
      }), (error: Error) =>
        error.message === "RECOVERY_IDENTITY_TOKEN_UNAVAILABLE");
      assert.equal(calls,
        ["cancel", "access", "account", "audience"].includes(mode) ? 0 : 1);
      assert.equal(cancelled, mode === "http" ? 1 : 0);
    }
  });
