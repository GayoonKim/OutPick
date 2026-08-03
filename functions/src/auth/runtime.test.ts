import assert from "node:assert/strict";
import test from "node:test";
import {
  DEVELOPMENT_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL,
  DEVELOPMENT_PROJECT_ID,
  PRODUCTION_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL,
  PRODUCTION_PROJECT_ID,
  authFunctionsServiceAccountEmailForEnvironment,
  authFunctionsServiceAccountEmailForProject,
} from "./runtime.js";

test("Firebase project별 인증 Function 계정을 정확히 선택한다", () => {
  assert.equal(
    authFunctionsServiceAccountEmailForProject(DEVELOPMENT_PROJECT_ID),
    DEVELOPMENT_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL
  );
  assert.equal(
    authFunctionsServiceAccountEmailForProject(PRODUCTION_PROJECT_ID),
    PRODUCTION_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL
  );
});

test("지원하지 않는 project는 인증 Function 계정을 선택하지 않는다", () => {
  assert.throws(
    () => authFunctionsServiceAccountEmailForProject("other-project"),
    /지원하지 않는 Firebase project/
  );
});

test("배포 환경은 Firebase CLI가 제공한 project로 계정을 선택한다", () => {
  assert.equal(
    authFunctionsServiceAccountEmailForEnvironment({
      GCLOUD_PROJECT: DEVELOPMENT_PROJECT_ID,
    }),
    DEVELOPMENT_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL
  );
  assert.equal(
    authFunctionsServiceAccountEmailForEnvironment({
      GOOGLE_CLOUD_PROJECT: PRODUCTION_PROJECT_ID,
    }),
    PRODUCTION_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL
  );
});

test("배포 project가 누락되거나 미지원이면 fail closed한다", () => {
  assert.throws(
    () => authFunctionsServiceAccountEmailForEnvironment({}),
    /Google Cloud project ID/
  );
  assert.throws(
    () => authFunctionsServiceAccountEmailForEnvironment({
      GCLOUD_PROJECT: "other-project",
    }),
    /지원하지 않는 Firebase project/
  );
});
