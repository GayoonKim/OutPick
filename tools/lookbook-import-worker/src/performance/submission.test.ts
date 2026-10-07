import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {readFile} from "node:fs/promises";
import test from "node:test";
import sharp from "sharp";
import {jpegBytes} from "../processor.js";
import {mapScheduled} from "../pipeline/scheduling.js";
import {BufferInventory} from "./buffer-inventory.js";
import {comparisonInputs} from "./comparison.js";
import {contractFor, inspectContractTrace, PRESSURE_INPUT,
  type InputContract} from "./reuse-contract.js";
import {runReuse, summarizeReuse, validateReusePayload, validateReusePlan,
  type ReusePlan} from "./reuse-comparison.js";
import {connectedExecutor} from "./reuse-input.js";
import {ReuseTrace} from "./reuse-trace.js";
import {inspectSubmissionTrace, makeSubmissionPlan, submissionPolicy,
  SUBMISSION_ARMS} from "./submission-comparison.js";
import {ReadySeasonQueue, SubmissionRuntime} from "./submission-runtime.js";

const source = {sourceRevision: "a".repeat(40), sourceDigest: "b".repeat(64),
  inputDigest: PRESSURE_INPUT};
const plans = makeSubmissionPlan(source);
const turn = () => new Promise<void>((resolve) => setImmediate(resolve));
const deferred = () => {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return {promise, resolve};
};

test("제출 순서 계획은 네 구조 두 예산과 공유 off 다섯 회를 고정한다", () => {
  assert.equal(plans.length, 45);
  assert.equal(new Set(plans.map((p) => p.id)).size, 45);
  assert.equal(plans.filter((p) => p.budget === "off").length, 5);
  const order = plans.slice(0, 9).map((p) => `${p.submissionArm}/${p.budget}`);
  for (let repeat = 1; repeat <= 5; repeat++) {
    assert.deepEqual(plans.filter((p) => p.repeat === repeat).map((p) =>
      `${p.submissionArm}/${p.budget}`), order.map((_, i) =>
      order[(i + repeat - 1) % 9]));
  }
  plans.forEach(validateReusePlan);
  for (const change of [{submissionArm: "P4"}, {submission: undefined},
    {budget: "32"}, {load: "single"}, {repeat: 6}, {arm: "prepared"},
    {loadPressure: "load-pressure-v1"}, {inputDigest: "c".repeat(64)}]) {
    assert.throws(() => validateReusePlan({...plans[0], ...change} as
      ReusePlan));
  }
});

test("제출 폭 네 개는 빈자리 보충과 묶음 종료 및 취소를 구분한다",
  async () => {
    for (const arm of ["R4", "B4"] as const) {
      const waits = Array.from({length: 6}, deferred);
      const started: number[] = [];
      const controller = new AbortController();
      const pending = mapScheduled(waits, submissionPolicy("16", arm).assets,
        async (item, i) => {
          started.push(i);
          await item.promise;
        }, controller.signal);
      assert.deepEqual(started, [0, 1, 2, 3]);
      waits[1].resolve();
      await turn();
      assert.deepEqual(started, arm === "R4" ? [0, 1, 2, 3, 4] :
        [0, 1, 2, 3]);
      controller.abort();
      const rejected = assert.rejects(pending);
      waits.forEach((w) => w.resolve());
      await rejected;
      assert.equal(started.includes(5), false);
    }
  });

test("준비된 시즌 큐는 입력 우선 동순위 FIFO 비선점과 빈 슬롯 실행을 지킨다",
  async () => {
    const queue = new ReadySeasonQueue();
    const first = deferred();
    const order: string[] = [];
    const run = (rank: number, label: string, wait?: Promise<void>) =>
      queue.run(rank, async () => {
        order.push(label);
        await wait;
      });
    const one = run(5, "실행중", first.promise);
    assert.deepEqual(order, ["실행중"]);
    const two = run(4, "뒤시즌");
    const three = run(0, "앞시즌1");
    const four = run(0, "앞시즌2");
    assert.equal(queue.snapshot().queued, 3);
    first.resolve();
    await Promise.all([one, two, three, four]);
    assert.deepEqual(order, ["실행중", "앞시즌1", "앞시즌2", "뒤시즌"]);
    assert.equal(queue.snapshot().peakActive, 1);
    assert.equal(queue.snapshot().active, 0);
    assert.equal(queue.snapshot().queued, 0);
  });

test("시즌 우선 큐의 대기 취소와 실행 실패는 형제 실행 및 반환을 보존한다",
  async () => {
    const queue = new ReadySeasonQueue();
    const blocker = deferred();
    const controller = new AbortController();
    const first = queue.run(3, async () => {
      await blocker.promise;
      throw new Error("변환 실패");
    });
    const firstFailure = assert.rejects(first);
    const cancelled = queue.run(0, async () => assert.fail("취소 후 시작"),
      controller.signal);
    const cancelledFailure = assert.rejects(cancelled);
    const last = queue.run(2, async () => "완료");
    controller.abort();
    await cancelledFailure;
    assert.equal(queue.snapshot().queued, 1);
    blocker.resolve();
    await firstFailure;
    assert.equal(await last, "완료");
    assert.equal(queue.snapshot().failed, 1);
    assert.equal(queue.snapshot().active, 0);
    assert.equal(queue.snapshot().queued, 0);
    assert.throws(() => queue.run(0, async () => undefined,
      controller.signal));
  });

async function tinyInput() {
  const buffers = await Promise.all(Array.from({length: 5}, (_, i) =>
    sharp({create: {width: 8, height: 8, channels: 3,
      background: {r: 20 + i * 40, g: 70, b: 120}}}).png().toBuffer()));
  const hash = (b: Buffer) => createHash("sha256").update(b).digest("hex");
  const images = buffers.map((b, i) => ({sourceURL: `https://example.com/${i}`,
    path: String(i), sha256: hash(b), bytes: b.length}));
  const cover = {...images[0], seasonID: "2026SS",
    sourceURL: "https://example.com/cover"};
  const outputs = [];
  for (const [kind, image] of [...images.map((i) => ["post", i] as const),
    ["cover", cover] as const]) {
    for (const [maxPixel, quality] of kind === "post" ?
      [[768, 82], [1920, 90]] : [[512, 75], [1600, 88]]) {
      const jpeg = await jpegBytes(buffers[Number(image.path)], maxPixel,
        quality);
      outputs.push({kind, maxPixel, sourceHash: image.sha256,
        sha256: hash(jpeg), bytes: jpeg.length});
    }
  }
  const calls = new Map<string, number>();
  const input = {seasons: [{seasonID: "2026SS",
    sourceURL: "https://example.com/season", htmlSha256: "0".repeat(64),
    images}], covers: [cover], golden: [{seasonID: "2026SS", uniqueImages: 5,
    uploadFiles: 12, assetTargets: 6, outputs,
    uploadBytes: outputs.reduce((n, o) => n + o.bytes, 0)}],
  readImage: async (image: typeof images[number]) => {
    calls.set(image.sourceURL, (calls.get(image.sourceURL) ?? 0) + 1);
    return Buffer.from(buffers[Number(image.path)]);
  }};
  return {input, calls, budget: buffers[0].length};
}

test("네 제출 구조는 실제 JPEG 혼합 재사용과 커버 마지막 대상 및 정리를 지킨다",
  async () => {
    const tiny = await tinyInput();
    for (const arm of SUBMISSION_ARMS) {
      const trace = new ReuseTrace();
      const inventory = new BufferInventory();
      const pipeline = new SubmissionRuntime({...submissionPolicy("16", arm),
        hashes: {kind: "refill", concurrency: 1},
        sourceBufferBudgetBytes: tiny.budget}, trace, arm === "P4");
      await inventory.run(() => pipeline.withSeason(0, () =>
        connectedExecutor(tiny.input, trace, true)(
          comparisonInputs("single")[0], pipeline,
          new AbortController().signal)));
      const contract = contractFor(tiny.input, "single");
      const counts = inspectContractTrace(contract, trace.snapshot());
      const admission = inspectSubmissionTrace(trace.snapshot(), contract,
        arm);
      assert.equal(counts.trace.reused, 1);
      assert.equal(counts.trace.prepared, 1);
      assert.equal(counts.reads, 10);
      assert.equal(counts.files, 12);
      assert.ok(arm === "U" || admission.peakAssets["2026SS"] <= 4);
      assert.equal(pipeline.sourceBuffers?.snapshot().retainedBytes, 0);
      assert.equal(inventory.snapshot().objects, 0);
      assert.ok(Object.values(pipeline.snapshot()).every((s) =>
        s.active === 0 && s.queued === 0));
      const bad = trace.snapshot().filter((e) => e.event !== "asset-end");
      assert.throws(() => inspectSubmissionTrace(bad, contract, arm));
    }
    assert.equal(tiny.calls.get("https://example.com/cover"), 4);
  });

test("네 제출 구조의 fallback 변환 업로드 실패와 취소는 모든 보유량을 반환한다",
  async () => {
    for (const arm of SUBMISSION_ARMS) {
      for (const fault of ["fallback", "transform", "upload", "cancel"]) {
        const tiny = await tinyInput();
        const controller = new AbortController();
        const read = tiny.input.readImage;
        tiny.input.readImage = async (image) => {
          const bytes = await read(image);
          if (image.path === "1" && tiny.calls.get(image.sourceURL) === 2) {
            if (fault === "fallback") throw new Error("fallback 실패");
            if (fault === "cancel") controller.abort();
          }
          return bytes;
        };
        const trace = new ReuseTrace();
        const inventory = new BufferInventory();
        class FaultRuntime extends SubmissionRuntime {
          override run<T>(stage: Parameters<SubmissionRuntime["run"]>[0],
            work: () => Promise<T>, signal?: AbortSignal): Promise<T> {
            return super.run(stage, stage === fault ? async () => {
              throw new Error(`${stage} 실패`);
            } : work, signal);
          }
        }
        const runtime = new FaultRuntime({...submissionPolicy("16", arm),
          hashes: {kind: "refill", concurrency: 1},
          sourceBufferBudgetBytes: tiny.budget, signal: controller.signal},
        trace, arm === "P4");
        await assert.rejects(inventory.run(() => runtime.withSeason(0, () =>
          connectedExecutor(tiny.input, trace, true)(
            comparisonInputs("single")[0], runtime, controller.signal))));
        assert.equal(inventory.snapshot().objects, 0);
        assert.equal(runtime.sourceBuffers?.snapshot().retainedBytes, 0);
        assert.equal(runtime.sourceBuffers?.snapshot().openScopes, 0);
        assert.ok(Object.values(runtime.snapshot()).every((s) =>
          s.active === 0 && s.queued === 0));
      }
    }
  });

// 집계 전용 합성 기록이다. 실제 JPEG 정합성은 위 연결 검사에서 확인한다.
async function fakePayload(plan: ReusePlan) {
  const fixture = JSON.parse(await readFile(
    "fixtures/performance-input-contract.json", "utf8")) as
    {contracts: {six: InputContract}};
  const contract = fixture.contracts.six;
  const off = plan.budget === "off";
  const partial = plan.budget === "16";
  const trace = new ReuseTrace();
  const value = await runReuse(plan, async (season, pipeline) => {
    const expected = contract.find((s) => s.seasonID === season.seasonID);
    assert.ok(expected);
    const cover = expected.targets.at(-1);
    assert.ok(cover);
    if (!off) {
      await trace.prepare({season: season.seasonID, target: cover.id,
        kind: "cover"}, () => pipeline.run("download", async () => undefined));
    }
    await mapScheduled(expected.targets, pipeline.assets, (target) =>
      trace.target({season: season.seasonID, target: target.id,
        kind: target.kind}, async () => {
        const prepared = !off && target.kind === "cover";
        const reused = !off && target.kind === "post" && (!partial ||
          (season.seasonID === contract[0].seasonID && target.id === "post-0"));
        if (!prepared && !reused) {
          await pipeline.run("download", async () => undefined);
        }
        trace.record({event: "source-ready", reused,
          ...(prepared ? {prepared: true} : {})});
        await Promise.all([0, 1].map(() => pipeline.run("transform",
          async () => undefined)));
        await Promise.all([0, 1].map(() => pipeline.run("upload",
          async () => undefined)));
        await pipeline.run("paths", async () => undefined);
      }));
    trace.record({event: "season-end", season: season.seasonID});
    return {status: "succeeded"};
  }, {maxSampleGapMs: 500, readMemory: async () =>
    ({source: "cgroup-v2", usedBytes: 1, limitBytes: 2 * 2**30})}, trace);
  const c = inspectContractTrace(contract, trace.snapshot());
  const stages = (value.results[0].reports[0] as {measurement: {stages:
    Record<string, Record<string, number>>}}).measurement.stages;
  for (const [stage, count] of Object.entries({"image.download": c.reads,
    "image.hash": c.hashReads, "image.transform": c.files,
    "file.upload": c.files, "paths.save": c.trace.assets})) {
    Object.assign(stages[stage], {started: count, succeeded: count,
      peakActive: 1});
  }
  stages["image.download"].receivedBytes = c.readBytes;
  stages["file.upload"].completedBytes = c.uploadBytes;
  if (!off) {
    value.cache = {budgetBytes: Number(plan.budget) * 2**20,
      retainedBytes: 0, openScopes: 0, hits: c.trace.reused,
      misses: c.posts - c.trace.reused,
      rejectedByBudget: c.posts - c.trace.reused,
      peakRetainedBytes: partial ? contract[0].targets[0].bytes :
        contract.reduce((n, s) => n + s.hashBytes, 0),
    };
  }
  const payload = {...value, inputContract: contract};
  assert.equal(validateReusePayload(plan, payload), true, plan.id);
  return payload;
}

test("제출 결과는 동시 폭 우선순위와 시즌 완료 기록 변조를 거절한다",
  async () => {
    const plan = plans.find((p) => p.submissionArm === "P4");
    assert.ok(plan);
    const good = await fakePayload(plan);
    assert.ok(good.trace);
    const events = good.trace;
    assert.throws(() => inspectSubmissionTrace(events,
      [...good.inputContract].reverse(), "P4"));
    const times = structuredClone(good);
    const detail = times.detail as {seasonCompletedMs: Array<{
      elapsedMs: number}>};
    detail.seasonCompletedMs[1].elapsedMs = 0;
    assert.equal(validateReusePayload(plan, times), false);
    const bad = structuredClone(good);
    const start = bad.trace?.find((e) => e.event === "start" &&
      e.stage === "transform");
    assert.ok(start);
    start.operation = 999999;
    assert.equal(validateReusePayload(plan, bad), false);
    const wrong = structuredClone(good);
    const asset = wrong.trace?.find((e) => e.event === "asset-start");
    assert.ok(asset);
    asset.target = "post-99";
    assert.equal(validateReusePayload(plan, wrong), false);
  });

test("제출 비교 집계는 공유 대조군과 동일 예산 및 실패 분모를 유지한다",
  async () => {
    const rows = [];
    for (const plan of plans) {
      rows.push({id: plan.id,
        imageID: `sha256:${"d".repeat(64)}`, verdict: "succeeded",
        evidence: {Status: "exited", Running: false, OOMKilled: false,
          ExitCode: 0}, payload: await fakePayload(plan)});
    }
    const summary = summarizeReuse(plans, [...rows].reverse());
    assert.equal(summary.valid, true);
    assert.equal(summary.counts.succeeded, 45);
    assert.equal(summary.comparisons.length, 9);
    assert.equal(summary.regressions.length, 18);
    assert.ok(summary.regressions.every((r) => r.complete && r.pairs === 5));
    assert.ok(summary.regressions.some((r) => r.baseline === "R4/16" &&
      r.candidate === "P4/16"));
    const incomplete = summarizeReuse(plans, rows.map((r, i) => i === 0 ?
      {...r, verdict: "aborted"} : r));
    assert.equal(incomplete.valid, true);
    assert.equal(incomplete.counts.aborted, 1);
    assert.equal(incomplete.regressions.filter((r) => !r.complete &&
      r.pairs === 4 && r.first === null).length, 8);
    for (const bad of [rows.slice(1), [...rows, rows[0]], rows.map((r, i) =>
      i === 0 ? {...r, imageID: `sha256:${"e".repeat(64)}`} : r)]) {
      assert.equal(summarizeReuse(plans, bad).valid, false);
    }
  });
