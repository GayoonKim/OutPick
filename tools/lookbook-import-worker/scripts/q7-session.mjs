import {createServer} from "node:http";
import {randomBytes, randomUUID} from "node:crypto";
import {readFile} from "node:fs/promises";
import {initializeApp, deleteApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";

const MAX_BODY = 32 * 1024;

export async function startQ7Session({firebaseConfigPath, port = 0}) {
  if (!firebaseConfigPath) throw new Error("Q7_FIREBASE_CONFIG_REQUIRED");
  const config = JSON.parse(await readFile(firebaseConfigPath, "utf8"));
  if (config.projectId !== "outpick-test" || !config.apiKey ||
      !config.authDomain || !config.appId) throw new Error("Q7_FIREBASE_CONFIG_INVALID");
  const nonce = randomUUID();
  const cspNonce = randomBytes(18).toString("base64url");
  const app = initializeApp({projectId: "outpick-test"}, "q7-session-" + nonce);
  const auth = getAuth(app);
  const page = await readFile(new URL("./q7-login.html", import.meta.url), "utf8");
  let token = null;
  let identity = null;
  let resolveLogin;
  const login = new Promise((resolve) => { resolveLogin = resolve; });
  const server = createServer(async (request, response) => {
    const host = request.headers.host;
    const expectedOrigin = "http://localhost:" + server.address().port;
    if (host !== "localhost:" + server.address().port &&
        host !== "127.0.0.1:" + server.address().port) {
      return send(response, 421, "잘못된 호스트입니다.");
    }
    if (request.method === "GET" && request.url === "/") {
      response.writeHead(200, {"content-type": "text/html; charset=utf-8",
        "cache-control": "no-store",
        "content-security-policy": "default-src 'none'; script-src 'nonce-" +
          cspNonce + "' 'self' https://www.gstatic.com https://apis.google.com; " +
          "style-src 'unsafe-inline'; connect-src 'self' https://identitytoolkit.googleapis.com " +
          "https://securetoken.googleapis.com https://www.googleapis.com https://accounts.google.com; " +
          "frame-src https://outpick-test.firebaseapp.com https://accounts.google.com; " +
          "base-uri 'none'; form-action 'none'"});
      return response.end(page.replace("__Q7_CONFIG__", JSON.stringify(config)
        .replaceAll("<", "\\u003c"))
        .replace("__Q7_NONCE__", nonce).replace("__Q7_CSP_NONCE__", cspNonce));
    }
    if (request.method === "GET" && request.url === "/q7-login.js") {
      response.writeHead(200, {"content-type": "text/javascript; charset=utf-8",
        "cache-control": "no-store", "x-content-type-options": "nosniff"});
      return response.end(await readFile(new URL("./q7-login.js", import.meta.url)));
    }
    if (request.method === "GET" && request.url === "/q7/state") {
      return sendJSON(response, 200, {connected: Boolean(identity), uid: identity?.uid ?? null});
    }
    if (request.method === "POST" && request.url === "/q7/auth") {
      if (request.headers.origin !== expectedOrigin) return send(response, 403, "origin 거부");
      let body;
      try { body = await readBody(request); } catch {
        return send(response, 413, "요청 크기가 제한을 넘었습니다.");
      }
      let input;
      try { input = JSON.parse(body); } catch { return send(response, 400, "잘못된 요청"); }
      if (input.nonce !== nonce || typeof input.idToken !== "string" ||
          input.idToken.length > 16_384) return send(response, 403, "인증 정보 거부");
      try {
        const decoded = await auth.verifyIdToken(input.idToken, true);
        if (decoded.aud !== "outpick-test" ||
            decoded.iss !== "https://securetoken.google.com/outpick-test") {
          return send(response, 403, "프로젝트 불일치");
        }
        token = input.idToken;
        identity = {uid: decoded.uid};
        resolveLogin(identity);
        return sendJSON(response, 200, {connected: true, uid: decoded.uid});
      } catch {
        token = null;
        identity = null;
        return send(response, 401, "Firebase ID token 확인에 실패했습니다.");
      }
    }
    if (request.method === "POST" && request.url === "/q7/logout") {
      if (request.headers.origin !== expectedOrigin) return send(response, 403, "origin 거부");
      token = null;
      identity = null;
      return sendJSON(response, 200, {connected: false});
    }
    return send(response, 404, "찾을 수 없습니다.");
  });
  server.requestTimeout = 5_000;
  server.headersTimeout = 5_000;
  server.maxHeadersCount = 32;
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, "localhost", resolve);
  });
  const url = "http://localhost:" + server.address().port + "/";
  return {
    url, login,
    identity: () => identity,
    getToken: async () => {
      if (!token || !identity) throw new Error("Q7_LOGIN_REQUIRED");
      const checked = await auth.verifyIdToken(token, true);
      if (checked.uid !== identity.uid) throw new Error("Q7_UID_CHANGED");
      return {uid: identity.uid, idToken: token};
    },
    close: async () => {
      token = null;
      identity = null;
      await new Promise((resolve) => server.close(resolve));
      await deleteApp(app);
    },
  };
}

function send(response, status, message) {
  response.writeHead(status, {"content-type": "text/plain; charset=utf-8",
    "cache-control": "no-store", "x-content-type-options": "nosniff"});
  response.end(message);
}
function sendJSON(response, status, value) {
  response.writeHead(status, {"content-type": "application/json; charset=utf-8",
    "cache-control": "no-store", "x-content-type-options": "nosniff"});
  response.end(JSON.stringify(value));
}
async function readBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY) throw new Error("Q7_BODY_TOO_LARGE");
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}
