import assert from "node:assert/strict";
import test from "node:test";

import {
  allowedEmailForCaller,
  authenticateOIDCRequest,
  OIDCAuthenticationError,
  type OIDCTokenVerifier,
  type WorkerAuthConfig,
} from "./oidc-auth.js";

const config: WorkerAuthConfig = {
  audience: "https://lookbook-import-worker.example.run.app",
  taskServiceAccountEmail:
    "outpick-lookbook-task-dev@outpick-test.iam.gserviceaccount.com",
  functionsServiceAccountEmail:
    "86635107099-compute@developer.gserviceaccount.com",
};

test("경로 caller별 task와 Functions 계정을 분리한다", () => {
  assert.equal(
    allowedEmailForCaller("task", config),
    config.taskServiceAccountEmail,
  );
  assert.equal(
    allowedEmailForCaller("functions", config),
    config.functionsServiceAccountEmail,
  );
});

test("Bearer 토큰이 없거나 형식이 잘못되면 401이다", async () => {
  const verifier = fakeVerifier(config.taskServiceAccountEmail);
  await assert.rejects(
    authenticateOIDCRequest(undefined, "task", config, verifier),
    isAuthError(401),
  );
  await assert.rejects(
    authenticateOIDCRequest("Basic token", "task", config, verifier),
    isAuthError(401),
  );
});

test("서명 또는 audience 검증 실패는 401이다", async () => {
  const verifier: OIDCTokenVerifier = {
    async verify() {
      throw new Error("invalid token");
    },
  };
  await assert.rejects(
    authenticateOIDCRequest("Bearer token", "task", config, verifier),
    isAuthError(401),
  );
});

test("email 미검증 또는 다른 호출 계정은 403이다", async () => {
  await assert.rejects(
    authenticateOIDCRequest(
      "Bearer token",
      "task",
      config,
      fakeVerifier(config.taskServiceAccountEmail, false),
    ),
    isAuthError(403),
  );
  await assert.rejects(
    authenticateOIDCRequest(
      "Bearer token",
      "task",
      config,
      fakeVerifier(config.functionsServiceAccountEmail),
    ),
    isAuthError(403),
  );
});

test("caller에 맞는 검증된 계정만 허용한다", async () => {
  const taskIdentity = await authenticateOIDCRequest(
    "Bearer task-token",
    "task",
    config,
    fakeVerifier(config.taskServiceAccountEmail),
  );
  const functionsIdentity = await authenticateOIDCRequest(
    "Bearer functions-token",
    "functions",
    config,
    fakeVerifier(config.functionsServiceAccountEmail),
  );

  assert.equal(taskIdentity.email, config.taskServiceAccountEmail);
  assert.equal(functionsIdentity.email, config.functionsServiceAccountEmail);
});

function fakeVerifier(
  email: string,
  emailVerified = true,
): OIDCTokenVerifier {
  return {
    async verify() {
      return {email, emailVerified};
    },
  };
}

function isAuthError(statusCode: 401 | 403) {
  return (error: unknown): boolean =>
    error instanceof OIDCAuthenticationError &&
    error.statusCode === statusCode;
}
