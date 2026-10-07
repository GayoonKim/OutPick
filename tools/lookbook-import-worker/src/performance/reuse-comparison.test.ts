import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {mkdtemp, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";
import sharp from "sharp";
import {jpegBytes} from "../processor.js";
import {PipelineRuntime} from "../pipeline/resources.js";
import {makeComparisonPlan, comparisonInputs} from "./comparison.js";
import {BufferInventory} from "./buffer-inventory.js";
import {runContainer} from "./container-runner.js";
import {BUDGETS, COVER_ARMS, makeCoverPreparationPlan, makeReusePlan,
  reusePolicy, runReuse,
  summarizeReuse, validateReusePayload, validateReusePlan, type ReusePlan}
  from "./reuse-comparison.js";
import {connectedExecutor} from "./reuse-input.js";
import {ReuseTrace, TracedPipeline} from "./reuse-trace.js";

const source = {sourceRevision: "a".repeat(40), sourceDigest: "b".repeat(64),
  inputDigest: "c".repeat(64)};
const plans = makeReusePlan(source);
const memory = {maxSampleGapMs: 500, readMemory: async () =>
  ({source: "cgroup-v2" as const, usedBytes: 1, limitBytes: 2 * 2**30})};
const imageID = `sha256:${"d".repeat(64)}`;
const evidence = {Status: "exited", Running: false, OOMKilled: false,
  ExitCode: 0};

test("재사용 계획은 15회 회전 순서와 고정 정책만 허용한다", () => {
  assert.equal(plans.length, 15);
  assert.equal(new Set(plans.map((p) => p.id)).size, 15);
  for (const [i, plan] of plans.entries()) {
    validateReusePlan(plan);
    assert.equal(plan.budget, BUDGETS[(Math.floor(i / 5) + i % 5) % 5]);
  }
  for (const change of [{repeat: 4}, {budget: "0"}, {download: 8},
    {experiment: "transform-confirmation-v1"}, {measurementCount: 2}]) {
    assert.throws(() =>
      validateReusePlan({...plans[0], ...change} as ReusePlan));
  }
  assert.throws(() => validateReusePlan(makeComparisonPlan(source)[0] as
    unknown as ReusePlan));
});

async function tinyInput() {
  const bytes = await sharp({create: {width: 8, height: 8, channels: 3,
    background: {r: 35, g: 70, b: 120}}}).png().toBuffer();
  const hash = (value: Buffer) =>
    createHash("sha256").update(value).digest("hex");
  const image = {sourceURL: "https://example.com/a.png", path: "a",
    sha256: hash(bytes), bytes: bytes.length};
  const outputs = [];
  for (const [kind, maxPixel, quality] of [["post", 768, 82],
    ["post", 1920, 90], ["cover", 512, 75], ["cover", 1600, 88]] as const) {
    const jpeg = await jpegBytes(bytes, maxPixel, quality);
    outputs.push({kind, maxPixel, sourceHash: image.sha256,
      sha256: hash(jpeg), bytes: jpeg.length});
  }
  let reads = 0;
  const input = {seasons: [{seasonID: "2026FW",
    sourceURL: "https://example.com/season", htmlSha256: "0".repeat(64),
    images: [image, {...image, sourceURL: "https://example.com/b.png"}]}],
  covers: [{...image, seasonID: "2026FW",
    sourceURL: "https://example.com/cover.png"}],
  golden: [{seasonID: "2026FW", uniqueImages: 1, uploadFiles: 4,
    uploadBytes: outputs.reduce((sum, o) => sum + o.bytes, 0),
    assetTargets: 2, outputs}],
  readImage: async (requested?: {sourceURL: string}) => {
    if (requested) assert.ok(requested.sourceURL.startsWith("https://"));
    reads++;
    return Buffer.from(bytes);
  }};
  return {input, bytes, reads: () => reads};
}

test("실제 JPEG 연결 진단은 본문 hit와 커버 다운로드 및 시즌 종료를 기록한다",
  async () => {
    const tiny = await tinyInput();
    const trace = new ReuseTrace();
    const pipeline = new TracedPipeline(reusePolicy("256"), trace);
    await connectedExecutor(tiny.input, trace)(comparisonInputs("six")[0],
      pipeline, new AbortController().signal);
    const events = trace.snapshot();
    assert.deepEqual(events.filter((e) => e.event === "source-ready")
      .map((e) => [e.kind, e.reused]), [["post", true], ["cover", false]]);
    assert.equal(events.filter((e) => e.event === "submit" &&
      e.stage === "download").length, 1);
    assert.equal(events.filter((e) => e.event === "end" &&
      e.stage === "transform").length, 4);
    assert.equal(events.at(-1)?.event, "season-end");
    assert.equal(tiny.reads(), 3);
    assert.equal(pipeline.sourceBuffers?.snapshot().retainedBytes, 0);
  });

test("재사용 연결은 실제 JPEG를 유지하며 예산 miss 중복 pruning과 실행 격리를 지킨다",
  async () => {
    for (const budget of [undefined, 0, null]) {
      const tiny = await tinyInput();
      const runtime = new PipelineRuntime({...reusePolicy("off"),
        ...(budget === undefined ? {} : {sourceBufferBudgetBytes: budget})});
      const execute = connectedExecutor(tiny.input);
      for (let i = 0; i < 2; i++) {
        await execute(comparisonInputs("six")[0], runtime,
          new AbortController().signal);
        assert.equal(runtime.sourceBuffers?.snapshot().retainedBytes ?? 0, 0);
        assert.equal(runtime.sourceBuffers?.snapshot().openScopes ?? 0, 0);
      }
      assert.equal(tiny.reads(), budget === null ? 6 : 8);
      assert.equal(runtime.sourceBuffers?.snapshot().hits ?? 0,
        budget === null ? 2 : 0);
    }
    const tiny = await tinyInput();
    const runtime = new PipelineRuntime({...reusePolicy("off"),
      sourceBufferBudgetBytes: tiny.bytes.length});
    const execute = connectedExecutor(tiny.input);
    await Promise.all(["one", "two"].map((id) =>
      execute({...comparisonInputs("six")[0], id}, runtime,
        new AbortController().signal)));
    const cache = runtime.sourceBuffers?.snapshot();
    assert.ok(cache && cache.rejectedByBudget > 0);
    assert.ok(cache.peakRetainedBytes <= tiny.bytes.length);
    assert.equal(tiny.reads(), 8 - cache.hits);
    assert.equal(cache.retainedBytes, 0);
    assert.equal(cache.openScopes, 0);
  });

test("재사용 연결 정합성 실패와 취소는 형제 종료 후 scope와 슬롯을 반환한다",
  async () => {
    for (const cancel of [false, true]) {
      const tiny = await tinyInput();
      const controller = new AbortController();
      if (cancel) {
        const read = tiny.input.readImage;
        tiny.input.readImage = async () => {
          const bytes = await read();
          controller.abort();
          return bytes;
        };
      } else tiny.input.golden[0].outputs[0].sha256 = "0".repeat(64);
      const runtime = new PipelineRuntime({...reusePolicy("all"),
        signal: controller.signal});
      await assert.rejects(connectedExecutor(tiny.input)(
        comparisonInputs("six")[0], runtime, controller.signal));
      assert.equal(runtime.sourceBuffers?.snapshot().retainedBytes, 0);
      assert.equal(runtime.sourceBuffers?.snapshot().openScopes, 0);
      assert.ok(Object.values(runtime.snapshot()).every((slot) =>
        slot.active === 0 && slot.queued === 0));
    }
  });

test("커버 선준비 계획은 세 조건 다섯 쌍과 동일 상세 계측을 고정한다", () => {
  const matrix = makeCoverPreparationPlan(source);
  assert.equal(matrix.length, 15);
  for (const [i, plan] of matrix.entries()) {
    validateReusePlan(plan);
    assert.equal(plan.arm, COVER_ARMS[(Math.floor(i / 3) + i % 3) % 3]);
    assert.equal(plan.repeat, Math.floor(i / 3) + 1);
    assert.equal(plan.diagnostic, "asset-timeline-v1");
    assert.equal(plan.budget, plan.arm === "off" ? "off" : "256");
  }
  for (const change of [{arm: "current"}, {repeat: 6},
    {coverComparison: undefined}, {diagnostic: undefined}, {budget: "128"}]) {
    assert.throws(() => validateReusePlan({...matrix[0], ...change} as
      ReusePlan));
  }
});

test("커버 선준비는 실제 JPEG와 읽기 횟수를 유지하고 예산 miss도 정리한다",
  async () => {
    for (const budget of [0, 256 * 2**20]) {
      const tiny = await tinyInput();
      const trace = new ReuseTrace();
      const inventory = new BufferInventory();
      const pipeline = new TracedPipeline({...reusePolicy("256"),
        sourceBufferBudgetBytes: budget}, trace);
      const read = tiny.input.readImage;
      let covers = 0;
      tiny.input.readImage = async (image) => {
        if (image?.sourceURL.endsWith("cover.png")) {
          covers++;
          assert.equal(trace.snapshot().filter((e) =>
            e.stage === "transform").length, 0);
        }
        return read(image);
      };
      await inventory.run(() => connectedExecutor(tiny.input, trace, true)(
        comparisonInputs("six")[0], pipeline, new AbortController().signal));
      const events = trace.snapshot();
      const ready = events.find((e) => e.event === "prepare-end");
      assert.ok(ready?.success);
      assert.ok(events.filter((e) => e.event === "asset-start").every((e) =>
        e.atMs >= ready.atMs));
      assert.equal(events.filter((e) => e.event === "source-ready" &&
        e.prepared && !e.reused).length, 1);
      assert.equal(covers, 1);
      assert.equal(tiny.reads(), budget === 0 ? 4 : 3);
      const cache = pipeline.sourceBuffers?.snapshot();
      assert.equal(cache?.misses, budget === 0 ? 1 : 0);
      assert.equal(cache?.retainedBytes, 0);
      assert.equal(cache?.openScopes, 0);
      assert.equal(inventory.snapshot().objects, 0);
      assert.ok(inventory.snapshot().source.peakBytes >= tiny.bytes.length);
    }
  });

test("커버 준비 실패 취소와 저장 실패는 변환 경계와 보유량 정리를 지킨다",
  async () => {
    for (const failure of ["download", "cancel", "storage"]) {
      const tiny = await tinyInput();
      const trace = new ReuseTrace();
      const inventory = new BufferInventory();
      const controller = new AbortController();
      const pipeline = new TracedPipeline({...reusePolicy("256"),
        signal: controller.signal}, trace);
      const read = tiny.input.readImage;
      tiny.input.readImage = async (image) => {
        const bytes = await read(image);
        if (image?.sourceURL.endsWith("cover.png")) {
          if (failure === "download") throw new Error("커버 읽기 실패");
          if (failure === "cancel") controller.abort();
        }
        return bytes;
      };
      if (failure === "storage") {
        tiny.input.golden[0].outputs[0].sha256 =
        "0".repeat(64);
      }
      await assert.rejects(inventory.run(() =>
        connectedExecutor(tiny.input, trace, true)(comparisonInputs("six")[0],
          pipeline, controller.signal)));
      if (failure !== "storage") {
        assert.equal(trace.snapshot().filter((e) =>
          e.event === "asset-start").length, 0);
      }
      assert.equal(inventory.snapshot().objects, 0);
      assert.equal(pipeline.sourceBuffers?.snapshot().retainedBytes, 0);
      assert.equal(pipeline.sourceBuffers?.snapshot().openScopes, 0);
      assert.ok(Object.values(pipeline.snapshot()).every((s) =>
        s.active === 0 && s.queued === 0));
    }
  });

// 집계기의 필드 변조 검사용 기록이다. 실제 JPEG/읽기는 위에서 검증한다.
async function validPayload(plan: ReusePlan) {
  const trace = plan.diagnostic ? new ReuseTrace() : undefined;
  const value = await runReuse(plan, async (season, pipeline) => {
    if (trace) {
      const posts = season.seasonID === "2024SS" ? 21 : 22;
      const cover = {season: season.seasonID, target: `cover-${posts}`,
        kind: "cover" as const};
      if (plan.arm === "prepared") {
        await trace.prepare(cover, () =>
          pipeline.run("download", async () => undefined));
      }
      await Promise.all(Array.from({length: posts + 1}, (_, i) => {
        const kind = i === posts ? "cover" : "post";
        return trace.target({season: season.seasonID,
          target: `${kind}-${i}`, kind}, async () => {
          const prepared = kind === "cover" && plan.arm === "prepared";
          const reused = kind === "post" && plan.budget !== "off";
          if (!prepared && !reused) {
            await pipeline.run("download",
              async () => undefined);
          }
          trace.record({event: "source-ready", reused,
            ...(prepared ? {prepared: true} : {})});
          await Promise.all([0, 1].map(() => pipeline.run("transform",
            async () => undefined)));
          await Promise.all([0, 1].map(() => pipeline.run("upload",
            async () => undefined)));
          await pipeline.run("paths", async () => undefined);
        });
      }));
      trace.record({event: "season-end", season: season.seasonID});
    }
    return {status: "succeeded"};
  }, memory, trace);
  const report = value.results[0].reports[0] as {measurement: {stages:
    Record<string, Record<string, number>>}};
  const off = plan.budget === "off";
  for (const [stage, count] of Object.entries({
    "image.download": off ? 269 : 138,
    "image.transform": 274, "file.upload": 274, "paths.save": 137})) {
    Object.assign(report.measurement.stages[stage],
      {started: count, succeeded: count, peakActive: 1});
  }
  report.measurement.stages["image.download"].receivedBytes =
    off ? 223800086 : 112771684;
  report.measurement.stages["file.upload"].completedBytes = 42259800;
  if (!off) {
    value.cache = {budgetBytes: plan.budget === "all" ? null :
      Number(plan.budget) * 2**20, retainedBytes: 0, peakRetainedBytes: 100,
    hits: 131, misses: plan.arm === "prepared" ? 0 : 6,
    rejectedByBudget: 0, openScopes: 0};
  }
  assert.equal(validateReusePayload(plan, value), true);
  return value;
}

test("커버 비교는 첫 시즌 다섯 쌍과 실패 분모를 분리하고 다른 기록을 거절한다",
  async () => {
    const matrix = makeCoverPreparationPlan(source);
    const rows = [];
    for (const plan of matrix) {
      const payload = await validPayload(plan);
      payload.results[0].wallMs = 1000;
      (payload.detail as {firstSeasonMs: number}).firstSeasonMs =
        plan.arm === "prepared" ? 600 : 400;
      rows.push({id: plan.id, imageID, verdict: "succeeded", evidence,
        payload});
    }
    const summary = summarizeReuse(matrix, [...rows].reverse());
    assert.equal(summary.valid, true);
    assert.equal(summary.counts.succeeded, 15);
    assert.ok(summary.comparisons.every((g) => g.successes === 5));
    assert.ok(summary.regressions.every((r) => r.complete && r.pairs === 5 &&
      r.first?.withholdAdoption && !r.wall?.withholdAdoption));
    const aborted = summarizeReuse(matrix, rows.map((r, i) =>
      matrix[i].id === "cover-prepared-1" ? {...r, verdict: "aborted"} : r));
    assert.equal(aborted.valid, true);
    assert.equal(aborted.counts.aborted, 1);
    assert.ok(aborted.regressions.every((r) => !r.complete && r.pairs === 4 &&
      r.wall === null && r.first === null));
    for (const changed of [rows.slice(1), [...rows, rows[0]], rows.map((r, i) =>
      i === 0 ? {...r, imageID: `sha256:${"e".repeat(64)}`} : r)]) {
      assert.equal(summarizeReuse(matrix, changed).valid, false);
    }
    assert.equal(summarizeReuse(plans, rows).valid, false);
    const preparedIndex = matrix.findIndex((p) => p.arm === "prepared");
    const bad = structuredClone(rows[preparedIndex].payload);
    assert.ok(bad.cache);
    bad.cache.misses = 6;
    assert.equal(validateReusePayload(matrix[preparedIndex], bad), false);
    const trace = structuredClone(rows[preparedIndex].payload);
    assert.ok(trace.trace);
    const start = trace.trace.find((e) => e.event === "asset-start");
    assert.ok(start);
    start.atMs = 0;
    trace.trace.sort((a, b) => a.atMs - b.atMs);
    assert.equal(validateReusePayload(matrix[preparedIndex], trace), false);
  });

test("재사용 집계는 읽기 정리 오류와 누락 혼입을 거절하고 중단을 보존한다",
  async () => {
    const rows = await Promise.all(plans.map(async (plan) => ({id: plan.id,
      imageID, verdict: "succeeded", evidence,
      payload: await validPayload(plan)})));
    const summary = summarizeReuse(plans, rows);
    assert.equal(summary.valid, true);
    assert.equal(summary.counts.succeeded, 15);
    assert.ok(summary.comparisons.every((g) =>
      g.successes === 3 && g.medianMs));
    const aborted = rows.map((row, i) => i === 0 ?
      {...row, verdict: "aborted"} : row);
    const partial = summarizeReuse(plans, aborted);
    assert.equal(partial.valid, true);
    assert.equal(partial.counts.aborted, 1);
    assert.equal(partial.comparisons[0].medianMs, null);
    for (const changed of [rows.slice(1), [...rows, rows[0]], rows.map((r, i) =>
      i === 0 ? {...r, imageID: `sha256:${"e".repeat(64)}`} : r)]) {
      assert.equal(summarizeReuse(plans, changed).valid, false);
    }
    for (const change of [{cache: null}, {cache: {...rows[1].payload.cache,
      retainedBytes: 1}}, {detail: {firstSeasonMs: NaN}}, {id: "wrong"}]) {
      assert.equal(validateReusePayload(plans[1],
        {...rows[1].payload, ...change}), false);
    }
    const invalid = structuredClone(rows[0].payload);
    const report = invalid.results[0].reports[0] as {measurement: {stages:
      Record<string, Record<string, number>>}};
    report.measurement.stages["image.download"].receivedBytes--;
    assert.equal(validateReusePayload(plans[0], invalid), false);
    const unavailable = await runReuse(plans[0], async () => {
      throw new Error("실행 금지");
    }, {maxSampleGapMs: 500, readMemory: async () => null});
    assert.equal(unavailable.results[0].outcome, "unavailable");
    assert.equal(unavailable.validation.valid, true);
    assert.equal(validateReusePayload(plans[0], unavailable), false);
  });

test("재사용 컨테이너는 전용 진입점과 단일 구간 결과만 인정한다", async () => {
  const root = await mkdtemp(join(tmpdir(), "lookbook-reuse-test-"));
  const plan = plans[0];
  const payload = await validPayload(plan);
  const commands: string[][] = [];
  try {
    await assert.rejects(runContainer(plan, {imageID,
      inputDirectory: root, outputParent: root}));
    const row = await runContainer(plan, {kind: "reuse", imageID,
      inputDirectory: root, outputParent: root, command: async (args) => {
        commands.push(args);
        if (args[0] === "image") return `${imageID} arm64 linux`;
        if (args[0] === "create") return "f".repeat(64);
        if (args[0] === "wait") {
          await writeFile(join(root, plan.id, "result.json"),
            JSON.stringify(payload));
          return "0";
        }
        if (args[0] === "inspect") return JSON.stringify(evidence);
        return "";
      }});
    assert.equal(row.verdict, "succeeded");
    assert.ok(commands.find((a) => a[0] === "create")?.includes(
      "lib/performance/reuse-entry.js"));
    assert.equal(commands.at(-1)?.[0], "rm");
  } finally {
    await rm(root, {recursive: true, force: true});
  }
});
