import {execFileSync} from "node:child_process";

import {ENDPOINT_FUNCTIONS, environmentConfig} from "./config.js";

export function resolveInvocation(environment, endpoint, execute = execFileSync) {
  const config = environmentConfig(environment);
  const functionName = ENDPOINT_FUNCTIONS[endpoint];
  const uri = run(execute, [
    "functions", "describe", functionName,
    "--v2",
    `--region=${config.region}`,
    `--project=${config.projectID}`,
    "--format=value(serviceConfig.uri)",
  ]);
  if (!/^https:\/\/[a-z0-9.-]+\.run\.app$/.test(uri)) {
    throw new Error("배포된 canonical run.app endpoint를 확인할 수 없습니다.");
  }
  const token = run(execute, [
    "auth", "print-identity-token",
    `--impersonate-service-account=${config.operatorEmail}`,
    `--audiences=${uri}`,
    "--include-email",
  ]);
  if (!token) throw new Error("operator ID token을 발급하지 못했습니다.");
  return {uri, token, config};
}

function run(execute, args) {
  return String(execute("gcloud", args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  })).trim();
}
