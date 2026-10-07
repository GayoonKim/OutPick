import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {fetch} from "undici";

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

// 복구 전용 계정의 ID token만 발급하며 서비스 계정 access token은 만들지 않는다.
export async function recoveryIdentityToken(input: {
  serviceAccountEmail: string; audience: string;
}, cancellation: AbortSignal, ports: TokenPorts = defaults): Promise<string> {
  const signal = AbortSignal.any([cancellation, AbortSignal.timeout(30000)]);
  try {
    signal.throwIfAborted();
    if (!/^[a-z0-9-]+@[a-z0-9-]+\.iam\.gserviceaccount\.com$/
      .test(input.serviceAccountEmail)) throw new Error();
    const audience = new URL(input.audience);
    if (audience.protocol !== "https:" || audience.origin !== input.audience) {
      throw new Error();
    }
    const accessToken = await ports.accessToken(signal);
    if (!accessToken || /\s/.test(accessToken)) throw new Error();
    signal.throwIfAborted();
    const response = await ports.request(
      "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/" +
      `${input.serviceAccountEmail}:generateIdToken`, {
        method: "POST", redirect: "error", signal,
        headers: {"authorization": `Bearer ${accessToken}`,
          "content-type": "application/json"},
        body: JSON.stringify({audience: input.audience, includeEmail: true}),
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
    // 명령·HTTP 오류 본문의 인증값은 출력하지 않는다.
    throw new Error("RECOVERY_IDENTITY_TOKEN_UNAVAILABLE");
  }
}
