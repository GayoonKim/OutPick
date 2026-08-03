/* eslint-disable max-len, require-jsdoc */
export const DEVELOPMENT_PROJECT_ID = "outpick-test";
export const PRODUCTION_PROJECT_ID = "outpick-664ae";
export const DEVELOPMENT_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL =
  "outpick-auth-functions-dev@outpick-test.iam.gserviceaccount.com";
export const PRODUCTION_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL =
  "outpick-auth-functions-prod@outpick-664ae.iam.gserviceaccount.com";
export function authFunctionsServiceAccountEmailForProject(
  value: string
): string {
  switch (value) {
  case DEVELOPMENT_PROJECT_ID:
    return DEVELOPMENT_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL;
  case PRODUCTION_PROJECT_ID:
    return PRODUCTION_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL;
  default:
    throw new Error(`지원하지 않는 Firebase project입니다: ${value}`);
  }
}

export function authFunctionsServiceAccountEmailForEnvironment(
  env: NodeJS.ProcessEnv
): string {
  const projectID =
    env.GCLOUD_PROJECT?.trim() ||
    env.GOOGLE_CLOUD_PROJECT?.trim() ||
    env.GCP_PROJECT?.trim();
  if (!projectID) {
    throw new Error("Google Cloud project ID 환경 변수가 필요합니다.");
  }
  return authFunctionsServiceAccountEmailForProject(projectID);
}
