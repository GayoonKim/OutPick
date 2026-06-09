export interface WorkerConfig {
  projectID: string;
  storageBucket: string;
  port: number;
  assetSyncConcurrency: number;
}

export function loadConfig(env: NodeJS.ProcessEnv): WorkerConfig {
  const projectID = requiredEnv(env, "OUTPICK_FIREBASE_PROJECT_ID");
  const storageBucket =
    optionalEnv(env, "OUTPICK_FIREBASE_STORAGE_BUCKET") ??
    `${projectID}.appspot.com`;
  const port = parsePort(env.PORT);
  const assetSyncConcurrency = parseBoundedInteger(
    env.OUTPICK_IMPORT_ASSET_SYNC_CONCURRENCY,
    "OUTPICK_IMPORT_ASSET_SYNC_CONCURRENCY",
    3,
    1,
    8,
  );

  return {
    projectID,
    storageBucket,
    port,
    assetSyncConcurrency,
  };
}

function requiredEnv(env: NodeJS.ProcessEnv, key: string): string {
  const value = env[key]?.trim();
  if (!value) {
    throw new Error(`${key} 환경 변수가 필요합니다.`);
  }
  return value;
}

function optionalEnv(env: NodeJS.ProcessEnv, key: string): string | null {
  const value = env[key]?.trim();
  return value && value.length > 0 ? value : null;
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
