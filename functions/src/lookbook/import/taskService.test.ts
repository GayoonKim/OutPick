import assert from "node:assert/strict";
import test from "node:test";
import {batchTaskSender} from "./taskService.js";
import type {BatchDispatchIntent} from "./queue/dispatch.js";
import {
  deterministicAssetRetryTaskID,
  deterministicImportTaskID,
  diagnosticCandidateID,
} from "./functions.js";

test("import task ID는 동일 입력에 대해 결정적이다", () => {
  const first = deterministicImportTaskID("brand-1", "job-1", 0);
  const second = deterministicImportTaskID("brand-1", "job-1", 0);
  assert.equal(first, second);
  assert.match(first, /^import-/);
  assert.ok(first.length <= 500);
  assert.notEqual(
    first,
    deterministicImportTaskID("brand-1", "job-1", 1)
  );
});

test("asset retry와 diagnostic candidate ID도 입력 계약을 반영한다", () => {
  const retry = deterministicAssetRetryTaskID(
    "brand-1",
    "season-1",
    "job-1",
    "request-1"
  );
  assert.match(retry, /^asset-retry-/);
  assert.ok(retry.length <= 500);
  assert.equal(
    diagnosticCandidateID("https://example.com/season/1"),
    diagnosticCandidateID("https://example.com/season/1")
  );
});

test("PQ03 묶음 task는 고정 ID와 15분 deadline OIDC를 보존한다", async () => {
  const config = {
    projectID: "demo-lookbook-queue", locationID: "asia-northeast3",
    queueID: "test-queue", workerURL: "https://worker.example",
    audience: "https://worker.example", serviceAccountEmail: "test@example.com",
  };
  const intent: BatchDispatchIntent = {
    taskID: "batch-one-0", endpoint: "/tasks/import-batch",
    dispatchDeadlineSeconds: 900,
    payload: {batchID: "one", dispatchGeneration: 0, queueContractVersion: 1},
  };
  let calls = 0;
  const send = batchTaskSender({createTask: async (request) => {
    calls++;
    assert.equal(request.task.dispatchDeadline.seconds, 900);
    assert.equal(request.task.name.endsWith("/tasks/batch-one-0"), true);
    assert.equal(request.task.httpRequest.url,
      "https://worker.example/tasks/import-batch");
    assert.deepEqual(JSON.parse(request.task.httpRequest.body.toString()),
      intent.payload);
    assert.equal(request.task.httpRequest.oidcToken.audience, config.audience);
    assert.equal(request.task.httpRequest.oidcToken.serviceAccountEmail,
      config.serviceAccountEmail);
    if (calls === 2) throw Object.assign(new Error("exists"), {code: 6});
    if (calls === 3) throw new Error("unavailable");
  }}, config);
  await send(intent);
  await send(intent);
  await assert.rejects(() => send(intent), /unavailable/);
  assert.throws(() => batchTaskSender({createTask: async () => undefined},
    {...config, audience: "https://another.example"}), /INVALID_TASK_CONFIG/);
});

test("PQ03 tagged URL uses the stable OIDC audience", async () => {
  const config = {
    projectID: "outpick-test", locationID: "asia-northeast3",
    queueID: "test-queue",
    workerURL: "https://q7-20261006---" +
      "lookbook-import-worker-development-xyenspjiwa-du.a.run.app",
    audience: "https://lookbook-import-worker-development-" +
      "xyenspjiwa-du.a.run.app",
    serviceAccountEmail:
      "outpick-lookbook-task-dev@outpick-test.iam.gserviceaccount.com",
  };
  const intent: BatchDispatchIntent = {
    taskID: "batch-q7-0", endpoint: "/tasks/import-batch",
    dispatchDeadlineSeconds: 900,
    payload: {batchID: "q7", dispatchGeneration: 0, queueContractVersion: 1},
  };
  let sent: {task: {httpRequest: {url: string;
    oidcToken: {audience: string}}}} | undefined;
  const send = batchTaskSender({
    createTask: async (request) => {
      sent = request;
    },
  }, config);
  await send(intent);
  assert.equal(sent?.task.httpRequest.url,
    config.workerURL + "/tasks/import-batch");
  assert.equal(sent?.task.httpRequest.oidcToken.audience, config.audience);
  assert.throws(() => batchTaskSender({
    createTask: async () => undefined,
  }, {...config, audience: "https://another-service.run.app"}),
  /INVALID_TASK_CONFIG/);
});
