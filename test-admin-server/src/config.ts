export interface ServerConfig {
  readonly host: string;
  readonly port: number;
  readonly firebaseProjectID: string;
  readonly serviceAccountPath: string;
  readonly testUserPassword?: string;
}

const defaultHost = "127.0.0.1";
const defaultPort = 45731;
const defaultFirebaseProjectID = "outpick-test";

export function loadConfig(env: NodeJS.ProcessEnv = process.env): ServerConfig {
  return {
    host: env.TEST_ADMIN_HOST ?? defaultHost,
    port: parsePort(env.TEST_ADMIN_PORT),
    firebaseProjectID: env.TEST_FIREBASE_PROJECT_ID ?? defaultFirebaseProjectID,
    serviceAccountPath: parseRequiredString(
      env.TEST_FIREBASE_SERVICE_ACCOUNT_PATH,
      "TEST_FIREBASE_SERVICE_ACCOUNT_PATH"
    ),
    testUserPassword: optionalString(env.TEST_FIREBASE_TEST_USER_PASSWORD)
  };
}

export function validateProjectID(projectID: string): void {
  if (projectID !== defaultFirebaseProjectID) {
    throw new Error(
      `테스트 서버는 ${defaultFirebaseProjectID} project에서만 실행할 수 있습니다: ${projectID}`
    );
  }
}

function parsePort(rawPort: string | undefined): number {
  if (rawPort === undefined || rawPort.trim().length === 0) {
    return defaultPort;
  }

  const port = Number(rawPort);
  if (Number.isInteger(port) === false || port < 1 || port > 65535) {
    throw new Error(`TEST_ADMIN_PORT가 유효하지 않습니다: ${rawPort}`);
  }

  return port;
}

function parseRequiredString(
  value: string | undefined,
  key: string
): string {
  const trimmed = value?.trim() ?? "";
  if (trimmed.length === 0) {
    throw new Error(`${key} 환경 변수가 필요합니다.`);
  }

  return trimmed;
}

function optionalString(value: string | undefined): string | undefined {
  const trimmed = value?.trim() ?? "";
  return trimmed.length > 0 ? trimmed : undefined;
}
