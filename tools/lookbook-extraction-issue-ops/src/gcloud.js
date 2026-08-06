import {execFileSync} from "node:child_process";

import {ENDPOINT_FUNCTIONS, environmentConfig} from "./config.js";

export async function resolveInvocation(
  environment,
  endpoint,
  execute = execFileSync,
  fetchImplementation = fetch,
) {
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
  const accessToken = run(execute, [
    "auth", "print-access-token",
    `--account=${config.callerEmail}`,
  ]);
  const response = await fetchImplementation(
    `https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${config.operatorEmail}:generateIdToken`,
    {
      method: "POST",
      headers: {
        "authorization": `Bearer ${accessToken}`,
        "content-type": "application/json; charset=utf-8",
      },
      body: JSON.stringify({audience: uri, includeEmail: true}),
    },
  );
  if (!response.ok) {
    throw new Error(`operator ID token 발급이 거부됐습니다. HTTP ${response.status}`);
  }
  const body = await response.json();
  const token = typeof body?.token === "string" ? body.token.trim() : "";
  if (!token) throw new Error("operator ID token을 발급하지 못했습니다.");
  return {uri, token, config};
}

function run(execute, args) {
  return String(execute("gcloud", args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  })).trim();
}
