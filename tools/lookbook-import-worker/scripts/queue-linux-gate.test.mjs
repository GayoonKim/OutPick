import assert from "node:assert/strict";
import {spawn} from "node:child_process";
import {after, before, test} from "node:test";
import {setTimeout as delay} from "node:timers/promises";
import {fileURLToPath} from "node:url";
import {dirname, resolve} from "node:path";

const workerDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const imageTag = `outpick/lookbook-queue-linux:${process.pid}-${Date.now()}`;

before(async () => {
  const result = await run("docker", ["build", "--platform=linux/amd64",
    "--target", "runtime", "--tag", imageTag, "."], 700000);
  assert.equal(result.code, 0, summarize(result));
});

after(async () => {
  await run("docker", ["image", "rm", "--force", imageTag], 30000);
});

test("PQ06 Linux 1 CPU 2 GiB에서 Chromium·공유 자원·표본 경계를 검증한다",
  {timeout: 180000}, async (context) => {
    const result = await run("docker", ["run", "--rm", "--platform=linux/amd64",
      "--cpus=1", "--memory=2g", "--memory-swap=2g", "--pids-limit=256",
      "--entrypoint", "node", imageTag, "--expose-gc",
      "scripts/queue-linux-smoke.mjs"],
    150000);
    assert.equal(result.code, 0, summarize(result));
    const report = JSON.parse(result.stdout.trim().split("\n").at(-1));
    assert.equal(report.platform, "linux");
    assert.equal(report.architecture, "x64");
    assert.ok(report.sample.count >= 8);
    assert.ok(report.sample.maxGapMs <= 500);
    assert.equal(report.sigterm.browserPIDExited, true);
    assert.equal(report.sigterm.exitCode, 0);
    assert.match(report.memoryPressure.memoryStop, /memory:sustained-high/);
    assert.ok(report.memoryPressure.maxRatio >= 0.85);
    assert.ok(report.memoryPressure.maxRatio < 0.92);
    context.diagnostic(JSON.stringify(report));
  });

test("PQ09 제한된 Linux container의 실제 OOM 종료를 관측하고 runner는 생존한다",
  {timeout: 90000}, async (context) => {
    const name = `outpick-q3-oom-${process.pid}-${Date.now()}`;
    const allocator = "import('./lib/queue/development-retry-fault.js').then(({forceQ7OOM})=>forceQ7OOM())";
    try {
      const created = await run("docker", ["create", "--platform=linux/amd64",
        "--cpus=1", "--memory=192m", "--memory-swap=192m", "--name", name,
        "--entrypoint", "node", imageTag, "-e", allocator], 30000);
      assert.equal(created.code, 0, summarize(created));
      const started = await run("docker", ["start", "--attach", name], 60000);
      assert.ok(started.code === 137 || started.signal === "SIGKILL",
        summarize(started));
      const inspected = await run("docker", ["inspect", "--format",
        "{{json .State}}", name], 10000);
      assert.equal(inspected.code, 0, summarize(inspected));
      const state = JSON.parse(inspected.stdout.trim());
      assert.equal(state.OOMKilled, true, JSON.stringify(state));
      assert.equal(state.ExitCode, 137, JSON.stringify(state));
      context.diagnostic(JSON.stringify({oomKilled: state.OOMKilled,
        exitCode: state.ExitCode, memoryLimit: "192m", swapLimit: "192m"}));
    } finally {
      await run("docker", ["rm", "--force", name], 10000);
    }
  });

async function run(command, args, timeoutMs) {
  return await new Promise((resolveResult, rejectResult) => {
    const child = spawn(command, args, {cwd: workerDirectory,
      stdio: ["ignore", "pipe", "pipe"]});
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
      setTimeout(() => child.kill("SIGKILL"), 2000).unref();
    }, timeoutMs);
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { stdout = tail(stdout + chunk); });
    child.stderr.on("data", (chunk) => { stderr = tail(stderr + chunk); });
    child.once("error", rejectResult);
    child.once("close", (code, signal) => {
      clearTimeout(timer);
      resolveResult({code, signal, stdout, stderr, timedOut});
    });
  });
}

function tail(value) {
  return value.length > 20000 ? value.slice(-20000) : value;
}

function summarize(result) {
  return JSON.stringify({code: result.code, signal: result.signal,
    timedOut: result.timedOut, stdout: tail(result.stdout),
    stderr: tail(result.stderr)});
}
