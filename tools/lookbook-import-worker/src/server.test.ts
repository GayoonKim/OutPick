import assert from "node:assert/strict";
import {once} from "node:events";
import {type AddressInfo} from "node:net";
import test from "node:test";

import {type FirebaseClients} from "./firebase.js";
import {
  type OIDCTokenVerifier,
  type VerifiedOIDCIdentity,
} from "./oidc-auth.js";
import {createServer} from "./server.js";

const taskServiceAccountEmail =
  "outpick-lookbook-task-dev@outpick-test.iam.gserviceaccount.com";
const functionsServiceAccountEmail =
  "86635107099-compute@developer.gserviceaccount.com";

test("보호 route는 Bearer OIDC 토큰이 없으면 401을 반환한다", async () => {
  await withServer(fakeVerifier(taskServiceAccountEmail), async (baseURL) => {
    for (const path of [
      "/wake",
      "/tasks/import-job",
      "/tasks/discover-seasons-diagnostic",
    ]) {
      const response = await post(baseURL, path);
      assert.equal(response.status, 401, path);
    }
  });
});

test("route별 caller가 바뀌면 handler 실행 전에 403을 반환한다", async () => {
  await withServer(
    fakeVerifier(functionsServiceAccountEmail),
    async (baseURL) => {
      const response = await post(
        baseURL,
        "/tasks/import-job",
        "Bearer functions-token",
      );
      assert.equal(response.status, 403);
    },
  );

  await withServer(fakeVerifier(taskServiceAccountEmail), async (baseURL) => {
    for (const path of ["/wake", "/tasks/discover-seasons-diagnostic"]) {
      const response = await post(baseURL, path, "Bearer task-token");
      assert.equal(response.status, 403, path);
    }
  });
});

test("route별 올바른 caller는 인증을 통과해 payload 검증까지 도달한다", async () => {
  await withServer(fakeVerifier(taskServiceAccountEmail), async (baseURL) => {
    const response = await post(
      baseURL,
      "/tasks/import-job",
      "Bearer task-token",
    );
    assert.equal(response.status, 500);
  });

  await withServer(
    fakeVerifier(functionsServiceAccountEmail),
    async (baseURL) => {
      const wakeResponse = await post(
        baseURL,
        "/wake",
        "Bearer functions-token",
      );
      assert.equal(wakeResponse.status, 400);

      const response = await post(
        baseURL,
        "/tasks/discover-seasons-diagnostic",
        "Bearer functions-token",
      );
      assert.equal(response.status, 500);
    },
  );
});

function fakeVerifier(email: string): OIDCTokenVerifier {
  return {
    async verify(): Promise<VerifiedOIDCIdentity> {
      return {email, emailVerified: true};
    },
  };
}

async function withServer(
  verifier: OIDCTokenVerifier,
  operation: (baseURL: string) => Promise<void>,
): Promise<void> {
  const app = createServer({
    projectID: "outpick-test",
    assetSyncConcurrency: 3,
    firebase: {} as FirebaseClients,
    auth: {
      audience:
        "https://lookbook-import-worker-development-xyenspjiwa-du.a.run.app",
      taskServiceAccountEmail,
      functionsServiceAccountEmail,
      verifier,
    },
  });
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address() as AddressInfo;

  try {
    await operation(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => error ? reject(error) : resolve());
    });
  }
}

function post(
  baseURL: string,
  path: string,
  authorization?: string,
): Promise<Response> {
  return fetch(`${baseURL}${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(authorization ? {authorization} : {}),
    },
    body: "{}",
  });
}
