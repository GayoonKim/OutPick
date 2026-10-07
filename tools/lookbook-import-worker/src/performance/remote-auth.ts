import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {fetch} from "undici";
import {REMOTE_AUDIENCE, REMOTE_CALLER} from "./remote-target.js";

const exec = promisify(execFile);
type TokenPorts = {
  accessToken: (signal: AbortSignal) => Promise<string>;
  request: (url: string, init: {method: "POST";
    headers: Record<string, string>; body: string; redirect: "error";
    signal: AbortSignal}) => Promise<{ok: boolean;
      json: () => Promise<unknown>;
      body: {cancel: () => Promise<unknown>} | null}>;
};
const defaults: TokenPorts = {
  accessToken: async (signal) => (await exec("gcloud",
    ["auth", "print-access-token"],
    {timeout: 20000, maxBuffer: 65536, signal})).stdout.trim(),
  request: fetch,
};

// 기존 OpenIdTokenCreator 권한만 사용한다. 서비스 계정 access token은 만들지 않는다.
export async function remoteIdentityToken(cancellation: AbortSignal,
  ports: TokenPorts = defaults): Promise<string> {
  const signal = AbortSignal.any([cancellation, AbortSignal.timeout(30000)]);
  try {
    signal.throwIfAborted();
    const accessToken = await ports.accessToken(signal);
    if (!accessToken || /\s/.test(accessToken)) throw new Error();
    signal.throwIfAborted();
    const response = await ports.request(
      "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/" +
      `${REMOTE_CALLER}:generateIdToken`, {
        method: "POST", redirect: "error", signal,
        headers: {"authorization": `Bearer ${accessToken}`,
          "content-type": "application/json"},
        body: JSON.stringify({audience: REMOTE_AUDIENCE, includeEmail: true}),
      });
    if (!response.ok) {
      await response.body?.cancel();
      throw new Error();
    }
    const body = await response.json() as {token?: unknown};
    signal.throwIfAborted();
    if (typeof body?.token !== "string" || !body.token ||
      body.token.length > 65536 || /\s/.test(body.token)) throw new Error();
    return body.token;
  } catch {
    // 명령·HTTP 오류에 포함될 수 있는 인증값과 응답 본문을 기록하지 않는다.
    throw new Error("지정 OIDC 호출자 토큰 준비 실패");
  }
}
