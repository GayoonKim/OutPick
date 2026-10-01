/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import {EventEmitter} from "node:events";
import test, {mock} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getAppCheck} from "firebase-admin/app-check";

process.env.GCLOUD_PROJECT ??= "outpick-test";
// eslint-disable-next-line @typescript-eslint/no-var-requires
const {issueChatMediaURL} = require("./videoPlaybackFunctions.js") as
  typeof import("./videoPlaybackFunctions.js");

class CallableResponse extends EventEmitter {
  statusCode = 200;
  body?: {error?: {status: string}};
  private headers = new Map<string, unknown>();
  setHeader(name: string, value: unknown) {
    this.headers.set(name.toLowerCase(), value);
    return this;
  }
  getHeader(name: string) {
    return this.headers.get(name.toLowerCase());
  }
  status(code: number) {
    this.statusCode = code;
    return this;
  }
  send(body: CallableResponse["body"]) {
    this.body = body;
    this.emit("finish");
    return this;
  }
}

test("공통 callable은 AppCheck 누락·오류를 거절하고 " +
  "검증 성공 뒤에만 입력을 처리한다", async (t) => {
  const auth = getAuth();
  const appCheck = getAppCheck();
  let authChecks = 0;
  let appChecks = 0;
  const authMock = mock.method(auth, "verifyIdToken", async () => {
    authChecks += 1;
    return {uid: "qa-viewer"} as Awaited<ReturnType<typeof auth.verifyIdToken>>;
  });
  const verifyAppToken = async (token: string) => {
    appChecks += 1;
    if (token === "invalid") throw new Error("synthetic-invalid-app-check");
    return {appId: "qa-app", token: {}} as
      Awaited<ReturnType<typeof appCheck.verifyToken>>;
  };
  const appMock = mock.method(appCheck, "verifyToken", verifyAppToken);
  t.after(() => {
    authMock.mock.restore();
    appMock.mock.restore();
  });

  for (const [token, expectedStatus, expectedError] of [
    [undefined, 401, "UNAUTHENTICATED"],
    ["invalid", 401, "UNAUTHENTICATED"],
    ["valid", 400, "INVALID_ARGUMENT"],
  ] as const) {
    const headers: Record<string, string> = {
      "content-type": "application/json", "authorization": "Bearer qa-auth",
    };
    if (token) headers["x-firebase-appcheck"] = token;
    const request = {
      method: "POST", headers,
      // 정상 토큰이면 handler의 입력 검사까지 도달하지만 Firestore는 호출하지 않는다.
      body: {data: {variant: "invalid"}},
      header: (name: string) => headers[name.toLowerCase()],
    } as unknown as Parameters<typeof issueChatMediaURL>[0];
    const response = new CallableResponse();
    await issueChatMediaURL(request,
      response as unknown as Parameters<typeof issueChatMediaURL>[1]);
    assert.equal(response.statusCode, expectedStatus);
    assert.equal(response.body?.error?.status, expectedError);
  }
  assert.equal(authChecks, 3);
  assert.equal(appChecks, 2);
});
