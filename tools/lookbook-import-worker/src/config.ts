export interface WorkerConfig {
  projectID: string;
  storageBucket: string;
  port: number;
  assetSyncConcurrency: number;
  oidcAudience: string;
  taskServiceAccountEmail: string;
  functionsServiceAccountEmail: string;
  workerRevision: string;
  workerSourceRevision: string;
  seasonDiscoveryContractRevision: number;
  seasonDiscoveryExtractorVersion: string;
}

type WorkerEnvironmentContract = Pick<
  WorkerConfig,
  | "storageBucket"
  | "oidcAudience"
  | "taskServiceAccountEmail"
  | "functionsServiceAccountEmail"
>;

const workerEnvironmentContracts: Record<string, WorkerEnvironmentContract> = {
  "outpick-test": {
    storageBucket: "outpick-test.firebasestorage.app",
    oidcAudience:
      "https://lookbook-import-worker-development-xyenspjiwa-du.a.run.app",
    taskServiceAccountEmail:
      "outpick-lookbook-task-dev@outpick-test.iam.gserviceaccount.com",
    functionsServiceAccountEmail:
      "86635107099-compute@developer.gserviceaccount.com",
  },
  "outpick-664ae": {
    storageBucket: "outpick-664ae.appspot.com",
    oidcAudience:
      "https://lookbook-import-worker-715386497547.asia-northeast3.run.app",
    taskServiceAccountEmail:
      "lookbook-import-task-invoker@outpick-664ae.iam.gserviceaccount.com",
    functionsServiceAccountEmail:
      "715386497547-compute@developer.gserviceaccount.com",
  },
};

export function loadConfig(env: NodeJS.ProcessEnv): WorkerConfig {
  const projectID = requiredEnv(env, "OUTPICK_FIREBASE_PROJECT_ID");
  const environmentContract = requiredEnvironmentContract(projectID);
  const storageBucket = requiredExactValue(
    requiredEnv(env, "OUTPICK_FIREBASE_STORAGE_BUCKET"),
    environmentContract.storageBucket,
    "OUTPICK_FIREBASE_STORAGE_BUCKET",
  );
  const port = parsePort(env.PORT);
  const assetSyncConcurrency = parseBoundedInteger(
    env.OUTPICK_IMPORT_ASSET_SYNC_CONCURRENCY,
    "OUTPICK_IMPORT_ASSET_SYNC_CONCURRENCY",
    3,
    1,
    8,
  );
  const oidcAudience = requiredExactValue(
    requiredURL(env, "OUTPICK_IMPORT_OIDC_AUDIENCE"),
    environmentContract.oidcAudience,
    "OUTPICK_IMPORT_OIDC_AUDIENCE",
  );
  const taskServiceAccountEmail = requiredExactValue(
    requiredServiceAccountEmail(
      env,
      "OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL",
    ),
    environmentContract.taskServiceAccountEmail,
    "OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL",
  );
  const functionsServiceAccountEmail = requiredExactValue(
    requiredServiceAccountEmail(
      env,
      "OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL",
    ),
    environmentContract.functionsServiceAccountEmail,
    "OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL",
  );
  const workerRevision = requiredEnv(env, "K_REVISION");
  const workerSourceRevision = requiredRevision(
    env, "OUTPICK_WORKER_SOURCE_REVISION",
  );
  const seasonDiscoveryContractRevision = parseBoundedInteger(
    env.OUTPICK_SEASON_DISCOVERY_CONTRACT_REVISION,
    "OUTPICK_SEASON_DISCOVERY_CONTRACT_REVISION",
    1,
    1,
    Number.MAX_SAFE_INTEGER,
  );
  const seasonDiscoveryExtractorVersion = requiredEnv(
    env, "OUTPICK_SEASON_DISCOVERY_EXTRACTOR_VERSION",
  );

  return {
    projectID,
    storageBucket,
    port,
    assetSyncConcurrency,
    oidcAudience,
    taskServiceAccountEmail,
    functionsServiceAccountEmail,
    workerRevision,
    workerSourceRevision,
    seasonDiscoveryContractRevision,
    seasonDiscoveryExtractorVersion,
  };
}

function requiredRevision(env: NodeJS.ProcessEnv, key: string): string {
  const value = requiredEnv(env, key).toLowerCase();
  if (!/^[a-f0-9]{7,40}$/.test(value)) {
    throw new Error(`${key} 환경 변수는 git revision이어야 합니다.`);
  }
  return value;
}

function requiredEnvironmentContract(
  projectID: string,
): WorkerEnvironmentContract {
  const contract = workerEnvironmentContracts[projectID];
  if (!contract) {
    throw new Error(
      `지원하지 않는 OUTPICK_FIREBASE_PROJECT_ID입니다: ${projectID}`,
    );
  }
  return contract;
}

function requiredExactValue(
  value: string,
  expectedValue: string,
  key: string,
): string {
  if (value !== expectedValue) {
    throw new Error(`${key} 환경 변수가 Firebase project와 일치하지 않습니다.`);
  }
  return value;
}

function requiredEnv(env: NodeJS.ProcessEnv, key: string): string {
  const value = env[key]?.trim();
  if (!value) {
    throw new Error(`${key} 환경 변수가 필요합니다.`);
  }
  return value;
}

function requiredURL(env: NodeJS.ProcessEnv, key: string): string {
  const value = requiredEnv(env, key).replace(/\/+$/, "");
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error(`${key} 환경 변수가 올바른 URL이 아닙니다.`);
  }
  if (url.protocol !== "https:" || url.origin !== value) {
    throw new Error(`${key} 환경 변수는 HTTPS origin이어야 합니다.`);
  }
  return value;
}

function requiredServiceAccountEmail(
  env: NodeJS.ProcessEnv,
  key: string,
): string {
  const value = requiredEnv(env, key).toLowerCase();
  const serviceAccountPattern =
    /^[a-z0-9-]+@(?:[a-z0-9-]+\.iam|developer)\.gserviceaccount\.com$/;
  if (!serviceAccountPattern.test(value)) {
    throw new Error(`${key} 환경 변수가 서비스 계정 email 형식이 아닙니다.`);
  }
  return value;
}

function parsePort(rawPort: string | undefined): number {
  if (!rawPort) {
    return 8080;
  }

  const port = Number(rawPort);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("PORT 환경 변수가 올바르지 않습니다.");
  }
  return port;
}

function parseBoundedInteger(
  rawValue: string | undefined,
  key: string,
  defaultValue: number,
  minValue: number,
  maxValue: number,
): number {
  if (rawValue === undefined || rawValue.trim().length === 0) {
    return defaultValue;
  }

  const value = Number(rawValue.trim());
  if (
    !Number.isInteger(value) ||
    value < minValue ||
    value > maxValue
  ) {
    throw new Error(
      `${key} 환경 변수는 ${minValue} 이상 ${maxValue} 이하의 정수여야 합니다.`,
    );
  }
  return value;
}
