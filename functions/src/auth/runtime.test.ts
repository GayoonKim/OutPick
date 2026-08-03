import assert from "node:assert/strict";
import test from "node:test";
import {
  AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL_PATTERN,
  authFunctionsServiceAccountEmail,
} from "./runtime.js";

const developmentServiceAccount =
  "outpick-auth-functions-dev@outpick-test.iam.gserviceaccount.com";
const productionServiceAccount =
  "outpick-auth-functions-prod@outpick-664ae.iam.gserviceaccount.com";

test("인증 Function parameter 이름을 고정한다", () => {
  assert.equal(
    authFunctionsServiceAccountEmail.name,
    "OUTPICK_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL"
  );
});

test("Development와 Production 전용 인증 계정만 허용한다", () => {
  assert.match(
    developmentServiceAccount,
    AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL_PATTERN
  );
  assert.match(
    productionServiceAccount,
    AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL_PATTERN
  );
});

test("형식만 맞거나 환경이 교차된 인증 계정은 거부한다", () => {
  assert.doesNotMatch(
    "outpick-auth-functions-dev@outpick-664ae.iam.gserviceaccount.com",
    AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL_PATTERN
  );
  assert.doesNotMatch(
    "other-auth-functions@outpick-test.iam.gserviceaccount.com",
    AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL_PATTERN
  );
  assert.doesNotMatch(
    "not-an-email",
    AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL_PATTERN
  );
});
