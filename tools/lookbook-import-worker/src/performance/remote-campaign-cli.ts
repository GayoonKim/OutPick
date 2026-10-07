import assert from "node:assert/strict";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {readFile, writeFile, mkdir, rename} from "node:fs/promises";
import {resolve, join} from "node:path";
import {initializeApp, deleteApp} from "firebase-admin/app";
import {getStorage} from "firebase-admin/storage";
import {fetch} from "undici";
import {loadRemoteCorpus, remotePlans, remotePlanDigest, REMOTE_PROJECT,
  REMOTE_BUCKET, CORPUS_DIGEST} from "./remote-contract.js";
import {runRemoteCampaign, validateRemoteExecution, type RemoteExecution}
  from "./remote-campaign.js";
import {assertRemoteTarget, REMOTE_REGION, REMOTE_SERVICE,
} from "./remote-target.js";
import {remoteIdentityToken} from "./remote-auth.js";

const exec = promisify(execFile);
async function cloudJSON(args: string[]) {
  const result = await exec("gcloud", [...args, "--project", REMOTE_PROJECT,
    "--region", REMOTE_REGION, "--format=json"],
  {timeout: 30000, maxBuffer: 2 * 2**20});
  return JSON.parse(result.stdout);
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === "plan") {
    console.log(JSON.stringify({version: 5, corpusDigest: CORPUS_DIGEST,
      planDigest: remotePlanDigest(), plans: remotePlans()}, null, 2));
    return;
  }
  assert.ok(args.length === 4 && args[0] === "run" && args[3] === "--execute",
    "사용: plan 또는 run <승인된 실행 manifest.json> <새 증거 폴더> --execute");
  const execution: RemoteExecution = JSON.parse(
    await readFile(args[1], "utf8"));
  validateRemoteExecution(execution);
  assert.ok(execution.campaign.expiresAtMs > Date.now());
  const input = await loadRemoteCorpus();
  // 기존 증거 폴더의 이어 실행을 금지한다. 중단 회차의 수동 확인이 먼저다.
  const directory = resolve(args[2]);
  await mkdir(directory);
  await writeFile(join(directory, "execution.json"),
    JSON.stringify(execution, null, 2), {flag: "wx"});
  const service = await cloudJSON([
    "run", "services", "describe", REMOTE_SERVICE]);
  const revision = await cloudJSON(["run", "revisions", "describe",
    execution.revision]);
  assertRemoteTarget(execution, service, revision);
  await writeFile(join(directory, "target-checked.json"), JSON.stringify({
    checkedAt: new Date().toISOString(), revision: execution.revision,
    imageDigest: execution.imageDigest, targetURL: execution.targetURL,
    cpu: 1, memoryGiB: 2, revisionMaxInstances: 1, defaultTrafficPercent: 0,
  }, null, 2), {flag: "wx"});
  const app = initializeApp({projectId: REMOTE_PROJECT,
    storageBucket: REMOTE_BUCKET}, `remote-host-${Date.now()}`);
  const bucket = getStorage(app).bucket();
  bucket.storage.retryOptions.autoRetry = false;
  bucket.storage.retryOptions.maxRetries = 0;
  const controller = new AbortController();
  const stop = () => controller.abort(new Error("로컬 실행 중단"));
  process.once("SIGINT", stop); process.once("SIGTERM", stop);
  try {
    const journal = await runRemoteCampaign(execution, input, {
      now: Date.now,
      call: async (plan, signal) => {
        // 토큰을 파일/로그에 쓰지 않으며 HTTP 자동 재호출도 하지 않는다.
        const token = await remoteIdentityToken(signal);
        signal.throwIfAborted();
        const response = await fetch(
          `${execution.targetURL}/experiments/lookbook-transfer`, {
            method: "POST", redirect: "error", signal,
            headers: {"authorization": `Bearer ${token}`,
              "content-type": "application/json"},
            body: JSON.stringify({runID: plan.id}),
          });
        if (!response.ok) {
          await response.body?.cancel();
          throw new Error(`실험 HTTP ${response.status}; 재호출 금지`);
        }
        return response.json();
      },
      evidence: async (path, signal) => {
        const plan = remotePlans().find((p) => path ===
          `lookbook-import-performance/${execution.campaign.campaignID}/` +
          `${p.id}/result.json`);
        assert.ok(plan);
        const stream = bucket.file(path).createReadStream();
        const abort = () => stream.destroy(new Error("증거 읽기 취소"));
        const timeout = setTimeout(abort, 20000);
        signal.addEventListener("abort", abort, {once: true});
        const chunks: Buffer[] = []; let size = 0;
        try {
          signal.throwIfAborted();
          for await (const chunk of stream) {
            size += chunk.length; assert.ok(size <= 8 * 2**20);
            chunks.push(Buffer.from(chunk));
          }
          const bytes = Buffer.concat(chunks);
          await writeFile(join(directory, `${plan.id}.json`), bytes,
            {flag: "wx"});
          return JSON.parse(bytes.toString());
        } finally {
          clearTimeout(timeout); signal.removeEventListener("abort", abort);
          stream.destroy();
        }
      },
      checkpoint: async (journal) => {
        const temporary = join(directory, "journal.tmp");
        await writeFile(temporary, JSON.stringify(journal, null, 2));
        await rename(temporary, join(directory, "journal.json"));
      },
    }, controller.signal);
    console.log(JSON.stringify({state: journal.state, reason: journal.reason,
      estimatedUSD: journal.estimatedUSD, recorded: journal.samples.length}));
    if (journal.state !== "completed") process.exitCode = 1;
  } finally {
    process.removeListener("SIGINT", stop);
    process.removeListener("SIGTERM", stop);
    await deleteApp(app);
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
