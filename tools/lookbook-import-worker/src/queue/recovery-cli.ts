import {isRecoveryDecisionID, parseRecoveryTarget} from "./recovery.js";

export type RecoveryCLICommand = {
  mode: "inspect" | "resume" | "settle-correction";
  baseURL: string;
  audience: string;
  serviceAccountEmail: string;
  target: ReturnType<typeof parseRecoveryTarget>;
  reportDigest?: string;
  expectedStateRevision?: number;
  decisionID?: string;
};

export function parseRecoveryCLICommand(
  argv: readonly string[], env: NodeJS.ProcessEnv,
): RecoveryCLICommand {
  const mode = argv[0];
  if (mode !== "inspect" && mode !== "resume" && mode !== "settle-correction") {
    throw new Error("RECOVERY_CLI_MODE_REQUIRED");
  }
  const values: Record<string, string> = {};
  for (const argument of argv.slice(1)) {
    const match = argument.match(/^--([a-z-]+)=(.+)$/);
    if (!match) throw new Error("RECOVERY_CLI_ARGUMENT_INVALID");
    const [, key, value] = match;
    if (values[key] !== undefined) {
      throw new Error("RECOVERY_CLI_ARGUMENT_DUPLICATE");
    }
    values[key] = value;
  }
  const allowed = ["project", "service", "revision", "batch", "epoch",
    "report-digest", "state-revision", "decision-id"];
  if (Object.keys(values).some((key) => !allowed.includes(key))) {
    throw new Error("RECOVERY_CLI_ARGUMENT_UNKNOWN");
  }
  const baseURL = requiredEnv(env, "OUTPICK_IMPORT_RECOVERY_URL");
  const audience = requiredEnv(env, "OUTPICK_IMPORT_RECOVERY_AUDIENCE");
  const serviceAccountEmail = requiredEnv(env,
    "OUTPICK_IMPORT_RECOVERY_SERVICE_ACCOUNT_EMAIL");
  let url: URL;
  try {
    url = new URL(baseURL);
  } catch {
    throw new Error("RECOVERY_CLI_URL_INVALID");
  }
  if (url.protocol !== "https:" || url.origin !== baseURL ||
      url.search || url.hash) {
    throw new Error("RECOVERY_CLI_URL_INVALID");
  }
  const projectID = values.project;
  const serviceName = values.service;
  const revision = values.revision;
  const batchID = values.batch;
  const epoch = Number(values.epoch);
  const target = parseRecoveryTarget({projectID, serviceName, revision,
    batchID, expectedEpoch: epoch});
  const expectedAccount = new RegExp(
    `^[a-z0-9-]+@${target.projectID}\\.iam\\.gserviceaccount\\.com$`);
  if (!expectedAccount.test(serviceAccountEmail.toLowerCase())) {
    throw new Error("RECOVERY_CLI_ACCOUNT_PROJECT_MISMATCH");
  }
  if (mode === "inspect") {
    if (values["report-digest"] || values["state-revision"] ||
        values["decision-id"]) throw new Error("RECOVERY_CLI_ARGUMENT_INVALID");
    return {mode, baseURL, audience, serviceAccountEmail, target};
  }
  const reportDigest = values["report-digest"];
  const stateRevision = Number(values["state-revision"]);
  const decisionID = values["decision-id"];
  if (!reportDigest || !/^[a-f0-9]{64}$/.test(reportDigest) ||
      !Number.isSafeInteger(stateRevision) || stateRevision < 0 ||
      !isRecoveryDecisionID(decisionID)) {
    throw new Error("RECOVERY_CLI_DECISION_CONFIRMATION_REQUIRED");
  }
  return {mode, baseURL, audience, serviceAccountEmail, target,
    reportDigest, expectedStateRevision: stateRevision, decisionID};
}

function requiredEnv(env: NodeJS.ProcessEnv, key: string): string {
  const value = env[key]?.trim();
  if (!value) throw new Error(`${key} is required`);
  return value;
}
