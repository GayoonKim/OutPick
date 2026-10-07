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
import type {PerformanceOptions} from "./performance/session.js";

const taskServiceAccountEmail =
  "outpick-lookbook-task-dev@outpick-test.iam.gserviceaccount.com";
const functionsServiceAccountEmail =
  "86635107099-compute@developer.gserviceaccount.com";

test("보호 route는 Bearer OIDC 토큰이 없으면 401을 반환한다", async () => {
  await withServer(fakeVerifier(taskServiceAccountEmail), async (baseURL) => {
    for (const path of [
      "/wake",
      "/tasks/import-batch",
      "/tasks/import-job",
      "/tasks/discover-seasons",
      "/tasks/discover-seasons-diagnostic",
      "/smoke/extraction",
      "/recovery/inspect",
      "/recovery/resume",
      "/recovery/settle-correction",
    ]) {
      const response = await post(baseURL, path);
      assert.equal(response.status, 401, path);
    }
    assert.equal((await fetch(`${baseURL}/runtime-contract`)).status, 401);
  });
});

test("route별 caller가 바뀌면 handler 실행 전에 403을 반환한다", async () => {
  await withServer(
    fakeVerifier(functionsServiceAccountEmail),
    async (baseURL) => {
      for (const path of [
        "/tasks/import-batch", "/tasks/import-job", "/tasks/discover-seasons",
      ]) {
        const response = await post(baseURL, path, "Bearer functions-token");
        assert.equal(response.status, 403, path);
      }
    },
  );

  await withServer(fakeVerifier(taskServiceAccountEmail), async (baseURL) => {
    for (const path of [
      "/wake", "/tasks/discover-seasons-diagnostic", "/smoke/extraction",
      "/recovery/inspect", "/recovery/resume", "/recovery/settle-correction",
    ]) {
      const response = await post(baseURL, path, "Bearer task-token");
      assert.equal(response.status, 403, path);
    }
  });
});

test("복구 route는 별도 계정에서만 입력 검증 단계로 진입한다", async () => {
  const recoveryServiceAccountEmail =
    "lookbook-import-recovery@outpick-test.iam.gserviceaccount.com";
  const app = createServer({
    projectID: "outpick-test", assetSyncConcurrency: 3,
    firebase: {} as FirebaseClients,
    auth: {
      audience: "https://lookbook-import-worker-development-xyenspjiwa-du.a.run.app",
      taskServiceAccountEmail, functionsServiceAccountEmail,
      recoveryServiceAccountEmail,
      verifier: fakeVerifier(recoveryServiceAccountEmail),
    },
    runtime: runtimeContract,
    recovery: {serviceName: "lookbook-import-worker-development",
      evidenceProvider: {async findTerminatedInstance() {
        return null;
      }}},
  });
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address() as AddressInfo;
  const baseURL = `http://127.0.0.1:${address.port}`;
  try {
    assert.equal((await post(baseURL, "/recovery/inspect")).status, 401);
    assert.equal((await post(baseURL, "/recovery/inspect",
      "Bearer recovery-token")).status, 400);
    assert.equal((await post(baseURL, "/recovery/settle-correction",
      "Bearer recovery-token")).status, 400);
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => error ? reject(error) : resolve());
    });
  }
  const wrongCaller = createServer({
    projectID: "outpick-test", assetSyncConcurrency: 3,
    firebase: {} as FirebaseClients,
    auth: {audience: runtimeContract.workerRevision,
      taskServiceAccountEmail, functionsServiceAccountEmail,
      recoveryServiceAccountEmail,
      verifier: fakeVerifier(functionsServiceAccountEmail)},
    runtime: runtimeContract,
    recovery: {serviceName: "lookbook-import-worker-development",
      evidenceProvider: {async findTerminatedInstance() {
        return null;
      }}},
  });
  const wrongServer = wrongCaller.listen(0, "127.0.0.1");
  await once(wrongServer, "listening");
  const wrongAddress = wrongServer.address() as AddressInfo;
  try {
    assert.equal((await post(`http://127.0.0.1:${wrongAddress.port}`,
      "/recovery/inspect", "Bearer functions-token")).status, 403);
  } finally {
    await new Promise<void>((resolve, reject) => {
      wrongServer.close((error) => error ? reject(error) : resolve());
    });
  }
});

test("route별 올바른 caller는 인증을 통과해 payload 검증까지 도달한다", async () => {
  await withServer(fakeVerifier(taskServiceAccountEmail), async (baseURL) => {
    for (const path of ["/tasks/import-job", "/tasks/discover-seasons"]) {
      const response = await post(baseURL, path, "Bearer task-token");
      assert.equal(response.status, 500, path);
    }
    assert.equal((await post(baseURL, "/tasks/import-batch",
      "Bearer task-token")).status, 400);
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
      const smoke = await post(
        baseURL,
        "/smoke/extraction",
        "Bearer functions-token",
      );
      assert.equal(smoke.status, 400);
      const runtime = await fetch(`${baseURL}/runtime-contract`, {
        headers: {authorization: "Bearer functions-token"},
      });
      assert.equal(runtime.status, 200);
      assert.deepEqual(await runtime.json(), runtimeContract);
    },
  );
});

test("성능 계측은 인증 뒤 실행하고 실패한 요청 결과를 보존한다", async () => {
  const reports: unknown[] = [];
  await withServer(fakeVerifier(taskServiceAccountEmail), async (baseURL) => {
    assert.equal((await post(baseURL, "/tasks/import-job")).status, 401);
    assert.equal(reports.length, 0);
    const response = await post(baseURL, "/tasks/import-job", "Bearer token");
    assert.equal(response.status, 500);
    assert.equal(reports.length, 1);
    assert.match(JSON.stringify(reports[0]), /"operationOutcome":"threw"/);
    assert.doesNotMatch(JSON.stringify(reports[0]), /Bearer|private-instance/);
  }, {
    enabled: true, sourceRevision: "a".repeat(40),
    instanceID: "private-instance", emit: (report) => reports.push(report),
  });
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
  performance?: PerformanceOptions,
  remoteExperiment?: (body: unknown, signal: AbortSignal) => Promise<unknown>,
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
    runtime: runtimeContract,
    performance,
    queueOwner: "unit-worker",
    bootID: "unit-worker",
    remoteExperiment,
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

test("RC09 실험 route의 기본 폐쇄 인증 제품 격리를 강제한다", async () => {
  let calls = 0;
  const handler = async (_body: unknown, signal: AbortSignal) => {
    signal.throwIfAborted(); calls++; return {ok: true};
  };
  await withServer(fakeVerifier(functionsServiceAccountEmail), async (url) => {
    assert.equal((await post(url, "/experiments/lookbook-transfer",
      "Bearer allowed")).status, 404);
  });
  await withServer(fakeVerifier(taskServiceAccountEmail), async (url) => {
    assert.equal((await post(url, "/experiments/lookbook-transfer",
      "Bearer task")).status, 403);
  }, undefined, handler);
  await withServer(fakeVerifier(functionsServiceAccountEmail), async (url) => {
    assert.equal((await post(url,
      "/experiments/lookbook-transfer")).status, 401);
    assert.equal((await post(url, "/experiments/lookbook-transfer",
      "Bearer allowed")).status, 200);
    for (const path of ["/wake", "/tasks/import-batch", "/tasks/import-job",
      "/tasks/discover-seasons",
      "/tasks/discover-seasons-diagnostic", "/smoke/extraction"]) {
      assert.equal((await post(url, path, "Bearer allowed")).status, 404);
    }
  }, undefined, handler);
  assert.equal(calls, 1);
});

const runtimeContract = {
  schemaVersion: 1 as const,
  projectID: "outpick-test",
  workerRevision: "lookbook-import-worker-development-00001-test",
  workerSourceRevision: "a".repeat(40),
  seasonDiscoveryContractRevision: 1,
  seasonDiscoveryExtractorVersion: "season-discovery-v1",
  imageExtractorVersion: "1.2.3",
  adapterVersions: {cafe24: "1.0.0"},
};

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
