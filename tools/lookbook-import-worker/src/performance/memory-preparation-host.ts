import assert from "node:assert/strict";
import {execFile} from "node:child_process";
import {mkdir, readFile, writeFile} from "node:fs/promises";
import {isAbsolute, join} from "node:path";
import {promisify} from "node:util";
import {preparationCorpus, preparationInput, preparationPlans,
  validatePreparationPlan, validatePreparationResult,
  type PreparationPlan, type PreparationResult, type PreparationSource}
  from "./memory-preparation.js";

type State = {Status: string; Running: boolean; OOMKilled: boolean;
  ExitCode: number};
type Verdict = "succeeded" | "failed" | "aborted" | "unavailable";
export type PreparationCommand = (args: string[], timeout: number) =>
  Promise<string>;
const exec = promisify(execFile);
const docker: PreparationCommand = async (args, timeout) =>
  (await exec("docker", args, {timeout, maxBuffer: 2 * 2**20})).stdout;
const save = (path: string, value: unknown) => writeFile(path,
  JSON.stringify(value, null, 2), {flag: "wx"});

export function preparationVerdict(plan: PreparationPlan, state: State,
  payload: PreparationResult | null, timedOut: boolean): Verdict {
  if (state.Running || state.Status !== "exited") return "unavailable";
  if (state.OOMKilled || timedOut) return "aborted";
  if (payload?.feed?.failure) {
    return payload.feed.failure === "sustained-high" ? "aborted" :
      "unavailable";
  }
  if (state.ExitCode !== 0 || !payload) return "failed";
  try {
    validatePreparationResult(plan, payload);
    return "succeeded";
  } catch {
    return "failed";
  }
}

export async function runPreparationContainer(plan: PreparationPlan, options: {
  inputDirectory: string; outputDirectory: string;
  timeoutMs: number; command?: PreparationCommand;
}) {
  validatePreparationPlan(plan);
  assert.ok(options.timeoutMs > 0 && options.timeoutMs <= 120000);
  for (const path of [options.inputDirectory, options.outputDirectory]) {
    assert.ok(isAbsolute(path) && !/[,\n\r]/.test(path));
  }
  const directory = join(options.outputDirectory, plan.id);
  await mkdir(directory);
  await save(join(directory, "plan.json"), plan);
  const command = options.command ?? docker;
  let containerID: string | null = null;
  let state: State | null = null;
  let payload: PreparationResult | null = null;
  let verdict: Verdict = "unavailable";
  let stage = "create";
  let timedOut = false;
  let waitExit: number | null = null;
  let cleanup = false;
  const startedAt = new Date().toISOString();
  try {
    containerID = (await command(["create", "--cpus=1", "--memory=2g",
      "--memory-swap=2g", "--network=none", "--mount",
      `type=bind,src=${options.inputDirectory},dst=/input,readonly`,
      "--mount", `type=bind,src=${directory},dst=/output`, plan.imageID,
      "node", "lib/performance/memory-preparation-entry.js",
      "/input", "/output/plan.json", "/output/result.json"], 15000)).trim();
    assert.match(containerID, /^[a-f0-9]{64}$/);
    await save(join(directory, "container.json"), {containerID, startedAt});
    stage = "settings";
    const config = JSON.parse(await command(["inspect", containerID,
      "--format", "{{json .HostConfig}}"], 15000));
    assert.equal(config.NanoCpus, 1e9);
    assert.equal(config.Memory, 2 * 2**30);
    assert.equal(config.MemorySwap, 2 * 2**30);
    assert.equal(config.NetworkMode, "none");
    await save(join(directory, "host-config.json"), config);
    stage = "start";
    await command(["start", containerID], 15000);
    stage = "wait";
    try {
      const exit = (await command(["wait", containerID],
        options.timeoutMs)).trim();
      assert.match(exit, /^\d+$/);
      waitExit = Number(exit);
    } catch {
      timedOut = true;
      // 이 실행기가 방금 만든 컨테이너만 중단한다. 전역 prune은 사용하지 않는다.
      await command(["kill", containerID], 15000);
    }
    stage = "inspect";
    state = JSON.parse(await command(["inspect", containerID,
      "--format", "{{json .State}}"], 15000));
    assert.ok(state && typeof state.OOMKilled === "boolean" &&
      Number.isSafeInteger(state.ExitCode));
    if (waitExit !== null) assert.equal(waitExit, state.ExitCode);
    try {
      payload = JSON.parse(await readFile(join(directory, "result.json"),
        "utf8"));
    } catch {
      // OOM/timeout으로 결과가 없을 때도 컨테이너 종료 증거를 보존한다.
    }
    verdict = preparationVerdict(plan, state, payload, timedOut);
    const logs = await command(["logs", containerID], 15000);
    await writeFile(join(directory, "container.log"), logs, {flag: "wx"});
    if (!state.Running && state.Status === "exited") {
      stage = "cleanup";
      await command(["rm", containerID], 15000);
      cleanup = true;
    }
  } catch {
    verdict = "unavailable";
  }
  const result = {id: plan.id, verdict, stage, startedAt,
    endedAt: new Date().toISOString(), containerID, timedOut, cleanup, state,
    payload};
  await save(join(directory, "finished.json"), result);
  return result;
}

export async function runPreparationCampaign(source: PreparationSource,
  inputDirectory: string, outputDirectory: string,
  options: {command?: PreparationCommand; now?: () => number;
    preflight?: () => Promise<void>} = {}) {
  const plans = preparationPlans(source);
  const command = options.command ?? docker;
  const now = options.now ?? (() => performance.now());
  const started = now();
  await mkdir(outputDirectory);
  await save(join(outputDirectory, "manifest.json"), {version: 1, source,
    plans, campaignTimeoutMs: 1800000, runTimeoutMs: 120000,
    startedAt: new Date().toISOString()});
  const results: Array<Awaited<ReturnType<typeof runPreparationContainer>> |
    {id: string; verdict: "not-run"; reason: string}> = [];
  let halted: string | null = null;
  try {
    const image = (await command(["image", "inspect", source.imageID,
      "--format", "{{.Id}} {{.Architecture}} {{.Os}}"], 15000)).trim();
    assert.equal(image, `${source.imageID} arm64 linux`);
    if (options.preflight) await options.preflight();
    else {
      for (const item of preparationCorpus()) {
        await preparationInput(inputDirectory, item);
      }
    }
  } catch {
    halted = "preflight";
  }
  for (const plan of plans) {
    const remaining = 1800000 - (now() - started);
    if (remaining <= 0) halted ??= "campaign-timeout";
    if (halted) {
      results.push({id: plan.id, verdict: "not-run", reason: halted});
      continue;
    }
    const result = await runPreparationContainer(plan, {command,
      inputDirectory, outputDirectory,
      timeoutMs: Math.min(120000, remaining)});
    results.push(result);
    if (result.verdict !== "succeeded" || !result.cleanup) {
      halted = result.id;
    }
  }
  const summary = {version: 1, source, expectedRuns: 18,
    expectedTransforms: 42, halted, elapsedMs: now() - started, results,
    verdict: halted ? "incomplete" : "passed"};
  await save(join(outputDirectory, "summary.json"), summary);
  return summary;
}
