export interface WorkerConfig {
  projectID: string;
  port: number;
}

export function loadConfig(env: NodeJS.ProcessEnv): WorkerConfig {
  const projectID = requiredEnv(env, "OUTPICK_FIREBASE_PROJECT_ID");
  const port = parsePort(env.PORT);

  return {
    projectID,
    port,
  };
}

function requiredEnv(env: NodeJS.ProcessEnv, key: string): string {
  const value = env[key]?.trim();
  if (!value) {
    throw new Error(`${key} 환경 변수가 필요합니다.`);
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
