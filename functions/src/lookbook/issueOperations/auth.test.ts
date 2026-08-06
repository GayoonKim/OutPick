/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";

import {
  authenticateOperator,
  IssueOperationsAuthError,
  operatorAuthConfig,
  type OperatorTokenVerifier,
} from "./auth.js";

const config = {
  environment: "development" as const,
  projectID: "outpick-test",
  audience: "https://issue-ops-read.example.run.app",
  operatorEmail:
    "outpick-extraction-ops-dev@outpick-test.iam.gserviceaccount.com",
};

test("project별 canonical operator와 endpoint audience가 필요하다", () => {
  assert.deepEqual(operatorAuthConfig("outpick-test", "read", {
    OUTPICK_EXTRACTION_OPS_READ_AUDIENCE: config.audience,
  }), config);
  assert.throws(
    () => operatorAuthConfig("unknown", "read", {}),
    isAuthError(503),
  );
  assert.throws(
    () => operatorAuthConfig("outpick-test", "read", {}),
    isAuthError(503),
  );
});

test("환경 교차와 미검증 email은 서버에서 거부한다", async () => {
  await assert.rejects(authenticateOperator({
    authorizationHeader: "Bearer token",
    requestedEnvironment: "production",
    config,
    verifier: fakeVerifier(config.operatorEmail),
  }), isAuthError(403));
  await assert.rejects(authenticateOperator({
    authorizationHeader: "Bearer token",
    requestedEnvironment: "development",
    config,
    verifier: fakeVerifier("attacker@example.com"),
  }), isAuthError(403));
});

test("정확한 audience 검증과 허용 operator만 통과한다", async () => {
  let verifiedAudience = "";
  const verifier: OperatorTokenVerifier = {
    async verify(_token, audience) {
      verifiedAudience = audience;
      return {email: config.operatorEmail, emailVerified: true};
    },
  };
  const identity = await authenticateOperator({
    authorizationHeader: "Bearer token",
    requestedEnvironment: "development",
    config,
    verifier,
  });
  assert.equal(verifiedAudience, config.audience);
  assert.equal(identity.email, config.operatorEmail);
});

function fakeVerifier(email: string): OperatorTokenVerifier {
  return {
    async verify() {
      return {email, emailVerified: true};
    },
  };
}

function isAuthError(statusCode: 401 | 403 | 503) {
  return (error: unknown): boolean =>
    error instanceof IssueOperationsAuthError &&
    error.statusCode === statusCode;
}
