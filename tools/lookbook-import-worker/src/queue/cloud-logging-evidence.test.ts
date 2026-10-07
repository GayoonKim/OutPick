/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {CloudLoggingRecoveryEvidenceProvider, isCloudRunTerminationMessage} from "./cloud-logging-evidence.js";

test("KR18 플랫폼 종료는 컨테이너 종료·메모리 초과 시스템 원문만 인정하고 요청 timeout·종료 준비를 제외한다", () => {
  for (const message of ["Container terminated with signal 9.",
    "While handling this request, the container instance was found to be using too much memory and was terminated.",
    "Memory limit of 2048 MiB exceeded with 2130 MiB used.", "Memory limit exceeded.", "OOMKilled"]) {
    assert.equal(isCloudRunTerminationMessage(message), true, message);
  }
  for (const message of ["The request was terminated because it reached timeout.",
    "Initiating instance shutdown.", "OOM monitoring enabled", "memory limit not exceeded", "Starting new instance"]) {
    assert.equal(isCloudRunTerminationMessage(message), false, message);
  }
});

test("KR20 플랫폼 종료 조회는 URL 인코딩된 정확한 시스템 logName과 이전 run revision·instance를 사용한다", async () => {
  const provider = new CloudLoggingRecoveryEvidenceProvider();
  const projectID = "outpick-test";
  const revision = "lookbook-import-worker-development-00025-nog";
  const traceID = "a".repeat(32);
  const startedAt = 1791346170000;
  const filters: string[] = [];
  Reflect.set(provider, "listEntries", async (_project: string, filter: string) => {
    assert.equal(_project, projectID); filters.push(filter);
    if (filters.length === 1) return [{labels: {instanceId: "exact-instance"}}];
    assert.ok(filter.includes("logName=\"projects/outpick-test/logs/run.googleapis.com%2Fvarlog%2Fsystem\""));
    assert.ok(filter.includes(`revision_name="${revision}"`));
    assert.ok(filter.includes("labels.instanceId=\"exact-instance\""));
    assert.ok(filter.includes(new Date(startedAt).toISOString()));
    return [{insertId: "exact-termination", timestamp: new Date(startedAt + 1000).toISOString(),
      textPayload: "Memory limit of 2048 MiB exceeded with 2248 MiB used."}];
  });
  const result = await provider.findTerminatedInstance({projectID,
    serviceName: "lookbook-import-worker-development", revision, traceID, startedAt});
  assert.equal(filters.length, 2);
  assert.equal(result?.revision, revision); assert.equal(result?.instanceID, "exact-instance");
  assert.equal(result?.insertID, "exact-termination"); assert.equal(result?.traceID, traceID);
});
