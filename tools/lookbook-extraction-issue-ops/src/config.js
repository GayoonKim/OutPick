export const ENVIRONMENTS = Object.freeze({
  development: Object.freeze({
    projectID: "outpick-test",
    region: "asia-northeast3",
    callerEmail: "gayunkim.1@gmail.com",
    operatorEmail:
      "outpick-extraction-ops-dev@outpick-test.iam.gserviceaccount.com",
  }),
  production: Object.freeze({
    projectID: "outpick-664ae",
    region: "asia-northeast3",
    callerEmail: "gayunkim.1@gmail.com",
    operatorEmail:
      "outpick-extraction-ops-prod@outpick-664ae.iam.gserviceaccount.com",
  }),
});

export const ENDPOINT_FUNCTIONS = Object.freeze({
  read: "lookbookExtractionIssueOpsRead",
  write: "lookbookExtractionIssueOpsWrite",
  release: "verifyLookbookExtractionFix",
});

export function environmentConfig(environment) {
  const config = ENVIRONMENTS[environment];
  if (!config) throw new Error("--environment 값이 필요합니다.");
  return config;
}
