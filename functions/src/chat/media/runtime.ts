/* eslint-disable max-len, require-jsdoc */
export const DEVELOPMENT_PROJECT_ID = "outpick-test";
export const PRODUCTION_PROJECT_ID = "outpick-664ae";

export type ChatMediaRuntimeIdentity = "orchestrator" | "cleanup";

const SERVICE_ACCOUNTS: Record<string, Record<ChatMediaRuntimeIdentity, string>> = {
  [DEVELOPMENT_PROJECT_ID]: {
    orchestrator: "outpick-chat-media-orch-dev@outpick-test.iam.gserviceaccount.com",
    cleanup: "outpick-chat-media-cleanup-dev@outpick-test.iam.gserviceaccount.com",
  },
  [PRODUCTION_PROJECT_ID]: {
    orchestrator: "outpick-chat-media-orchestrator@outpick-664ae.iam.gserviceaccount.com",
    cleanup: "outpick-chat-media-cleanup@outpick-664ae.iam.gserviceaccount.com",
  },
};

export function chatMediaServiceAccountEmailForProject(
  projectID: string,
  identity: ChatMediaRuntimeIdentity
): string {
  const account = SERVICE_ACCOUNTS[projectID]?.[identity];
  if (!account) throw new Error(`지원하지 않는 Firebase project입니다: ${projectID}`);
  return account;
}

export function chatMediaServiceAccountEmailForEnvironment(
  environment: NodeJS.ProcessEnv,
  identity: ChatMediaRuntimeIdentity
): string {
  const projectID = environment.GCLOUD_PROJECT?.trim() ||
    environment.GOOGLE_CLOUD_PROJECT?.trim() ||
    environment.GCP_PROJECT?.trim();
  if (!projectID) throw new Error("Google Cloud project ID 환경 변수가 필요합니다.");
  return chatMediaServiceAccountEmailForProject(projectID, identity);
}
