import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import {spawnSync} from "node:child_process";
import {chmod, mkdir, readFile, rm, writeFile} from "node:fs/promises";
import {join, resolve} from "node:path";
import test from "node:test";
import {createWorkerDeploySnapshot, computeGateSourceIdentity}
  from "./create-lookbook-import-worker-deploy-snapshot.mjs";

const projectRoot = resolve(new URL("../..", import.meta.url).pathname);
const gateConfigPath = join(projectRoot, "verification/lookbook-import.json");
const gateConfig = JSON.parse(await readFile(gateConfigPath, "utf8"));
const deployScript = join(projectRoot, "scripts/ai/deploy-lookbook-import-worker.sh");

async function passedGateSummary() {
  const identity = computeGateSourceIdentity(projectRoot, gateConfigPath,
    gateConfig.inputs);
  const runID = "deploy-contract-" + randomUUID();
  const directory = join(projectRoot, "output/verification", runID);
  await mkdir(directory, {recursive: true});
  const summaryPath = join(directory, "summary.json");
  await writeFile(summaryPath, JSON.stringify({
    configPath: gateConfigPath,
    verdict: "passed",
    source: identity,
    failures: [],
    blockers: [],
    checks: [
      {id: "worker-lint", exitCode: 0, failures: [], blockers: []},
      {id: "worker-test", exitCode: 0, executedTests: 1, failures: [], blockers: []},
      {id: "worker-fixtures", exitCode: 0, failures: [], blockers: []},
      {id: "worker-deploy-contract", exitCode: 0, failures: [], blockers: []},
    ],
  }, null, 2));
  return {runID, directory, summaryPath, identity};
}

test("Development 배포 snapshot은 통과한 gate digest의 Worker 파일만 고정한다", async () => {
  const summary = await passedGateSummary();
  const snapshotDirectory = join(projectRoot,
    "output/lookbook-import-performance/worker-deploy-snapshots/test-" +
    randomUUID());
  try {
    const manifest = await createWorkerDeploySnapshot({projectRoot,
      gateSummaryPath: summary.summaryPath, snapshotDirectory});
    assert.equal(manifest.verification.sourceDigest, summary.identity.digest);
    assert.equal(manifest.verification.sourceFileCount, summary.identity.fileCount);
    assert.ok(manifest.workerSnapshot.fileCount > 0);
    assert.ok(manifest.workerSnapshot.files.some((file) => file.path === "Dockerfile"));
    assert.ok(manifest.workerSnapshot.files.some((file) => file.path === "package-lock.json"));
    assert.ok(manifest.workerSnapshot.files.some((file) => file.path === "src/server.ts"));
    assert.equal(manifest.workerSnapshot.files.some((file) => file.path.startsWith("node_modules/")),
      false);
  } finally {
    await rm(snapshotDirectory, {recursive: true, force: true});
    await rm(snapshotDirectory + ".manifest.json", {force: true});
    await rm(summary.directory, {recursive: true, force: true});
  }
});

test("Development 배포는 gate 실패·source digest 불일치·Production snapshot을 거부한다", async () => {
  const summary = await passedGateSummary();
  const raw = JSON.parse(await readFile(summary.summaryPath, "utf8"));
  const snapshotDirectory = join(projectRoot,
    "output/lookbook-import-performance/worker-deploy-snapshots/reject-" +
    randomUUID());
  try {
    raw.verdict = "failed";
    await writeFile(summary.summaryPath, JSON.stringify(raw));
    await assert.rejects(createWorkerDeploySnapshot({projectRoot,
      gateSummaryPath: summary.summaryPath, snapshotDirectory}), /WORKER_GATE_NOT_PASSED/);
    raw.verdict = "passed";
    raw.source.digest = "0".repeat(64);
    await writeFile(summary.summaryPath, JSON.stringify(raw));
    await assert.rejects(createWorkerDeploySnapshot({projectRoot,
      gateSummaryPath: summary.summaryPath, snapshotDirectory}), /WORKER_GATE_SOURCE_CHANGED/);

    raw.source.digest = summary.identity.digest;
    raw.checks[0].id = raw.checks[1].id;
    await writeFile(summary.summaryPath, JSON.stringify(raw));
    await assert.rejects(createWorkerDeploySnapshot({projectRoot,
      gateSummaryPath: summary.summaryPath, snapshotDirectory}), /WORKER_GATE_CONFIG_INVALID/);

    const result = spawnSync(deployScript, ["production", "--deploy-candidate",
      "--gate-summary", summary.summaryPath], {cwd: projectRoot, encoding: "utf8"});
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Development candidate/);
  } finally {
    await rm(snapshotDirectory, {recursive: true, force: true});
    await rm(snapshotDirectory + ".manifest.json", {force: true});
    await rm(summary.directory, {recursive: true, force: true});
  }
});

test("Development candidate는 고정 snapshot·gate digest를 mock Cloud Run에만 전달한다", async () => {
  const summary = await passedGateSummary();
  const temporaryDirectory = join(projectRoot,
    "output/verification/deploy-mock-" + randomUUID());
  const mockBin = join(temporaryDirectory, "bin");
  const mockLog = join(temporaryDirectory, "gcloud.log");
  let snapshotDirectory = "";
  let manifestPath = "";
  try {
    await mkdir(mockBin, {recursive: true});
    const mockGcloud = join(mockBin, "gcloud");
    await writeFile(mockGcloud, `#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$OUTPICK_GCLOUD_MOCK_LOG"
printf '\\n' >>"$OUTPICK_GCLOUD_MOCK_LOG"
if [[ "$*" == *"json(status.traffic)"* ]]; then
  printf '%s\\n' '{"status":{"traffic":[{"revisionName":"lookbook-import-worker-development-00012-fih","percent":100}]}}'
elif [[ "$*" == *"latestCreatedRevisionName"* ]]; then
  printf '%s\\n' 'lookbook-import-worker-development-candidate'
elif [[ "$*" == *"run deploy"* ]]; then
  :
else
  echo "unexpected mock gcloud call" >&2
  exit 1
fi
`);
    await chmod(mockGcloud, 0o755);
    const result = spawnSync(deployScript, ["development", "--deploy-candidate",
      "--gate-summary", summary.summaryPath], {cwd: projectRoot, encoding: "utf8",
      env: {...process.env, PATH: mockBin + ":" + process.env.PATH,
        OUTPICK_GCLOUD_MOCK_LOG: mockLog}});
    assert.equal(result.status, 0, result.stderr + result.stdout);
    assert.match(result.stdout, new RegExp(`verification_digest=${summary.identity.digest}`));
    assert.match(result.stdout, /previous_revision=lookbook-import-worker-development-00012-fih/);
    assert.match(result.stdout, /candidate_tag=q7-20261006/);
    assert.match(result.stdout, /candidate_revision=lookbook-import-worker-development-candidate/);
    manifestPath = result.stdout.match(/^snapshot_manifest=(.+)$/m)?.[1] ?? "";
    snapshotDirectory = result.stdout.match(/^deployment_source=(.+)$/m)?.[1] ?? "";
    assert.ok(manifestPath && snapshotDirectory);
    const gcloudLog = await readFile(mockLog, "utf8");
    assert.match(gcloudLog, /--no-traffic/);
    assert.match(gcloudLog, /--tag q7-20261006/);
    assert.match(gcloudLog, /OUTPICK_IMPORT_PERFORMANCE_ENABLED=true/);
    assert.match(gcloudLog, /OUTPICK_IMPORT_RECOVERY_SERVICE_ACCOUNT_EMAIL=lookbook-import-recovery@outpick-test\.iam\.gserviceaccount\.com/);
    assert.ok(gcloudLog.includes("--source " + snapshotDirectory));
    assert.match(gcloudLog, new RegExp(`--source ${snapshotDirectory.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
    assert.match(gcloudLog, new RegExp(`OUTPICK_WORKER_VERIFICATION_DIGEST=${summary.identity.digest}`));
    assert.doesNotMatch(gcloudLog, /outpick-664ae/);
  } finally {
    if (snapshotDirectory) await rm(snapshotDirectory, {recursive: true, force: true});
    if (manifestPath) await rm(manifestPath, {force: true});
    await rm(summary.directory, {recursive: true, force: true});
    await rm(temporaryDirectory, {recursive: true, force: true});
  }
});
