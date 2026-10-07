import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {readFile} from "node:fs/promises";
import {resolve} from "node:path";
import test from "node:test";
import sharp from "sharp";
import {jpegBytes} from "../processor.js";
import {BufferInventory} from "./buffer-inventory.js";
import {comparisonInputs} from "./comparison.js";
import {assertApprovedContract, contractFor, inspectContractTrace,
  PRESSURE_INPUT, type InputContract} from "./reuse-contract.js";
import {makeLoadPressurePlan, reusePolicy, runReuse, summarizeReuse,
  validateReusePayload, validateReusePlan, type ReusePlan}
  from "./reuse-comparison.js";
import {connectedExecutor} from "./reuse-input.js";
import {ReuseTrace, TracedPipeline, analyzeReuseTrace} from "./reuse-trace.js";

const fixture = JSON.parse(await readFile(resolve(
  "fixtures/performance-input-contract.json"), "utf8")) as
  {inputDigest: string; contracts: {single: InputContract; six: InputContract}};
const source = {sourceRevision: "a".repeat(40), sourceDigest: "b".repeat(64),
  inputDigest: PRESSURE_INPUT};
const plans = makeLoadPressurePlan(source);
const memory = {maxSampleGapMs: 500, readMemory: async () =>
  ({source: "cgroup-v2" as const, usedBytes: 1, limitBytes: 2 * 2**30})};

test("부하 압박 계획은 승인 입력과 20회 확인 25회 압박을 분리한다", () => {
  assert.equal(plans.length, 45);
  assert.equal(new Set(plans.map((p) => p.id)).size, 45);
  assert.equal(plans.filter((p) => p.phase === "confirmation").length, 20);
  assert.equal(plans.filter((p) => p.phase === "pressure").length, 25);
  plans.forEach(validateReusePlan);
  for (const [index, load] of ["single", "synthetic-three"].entries()) {
    for (let repeat = 1; repeat <= 5; repeat++) {
      assert.deepEqual(plans.filter((p) => p.phase === "confirmation" &&
        p.load === load && p.repeat === repeat).map((p) => p.budget),
      (repeat + index) % 2 === 1 ? ["off", "256"] : ["256", "off"]);
    }
  }
  for (let repeat = 1; repeat <= 5; repeat++) {
    const budgets = ["off", "16", "32", "64", "128"];
    assert.deepEqual(plans.filter((p) => p.phase === "pressure" &&
      p.repeat === repeat).map((p) => p.budget),
    budgets.map((_, i) => budgets[(repeat - 1 + i) % budgets.length]));
  }
  for (const phase of ["confirmation", "pressure"]) {
    const groups = new Map<string, number>();
    for (const p of plans.filter((p) => p.phase === phase)) {
      const key = `${p.load}/${p.budget}`;
      groups.set(key, (groups.get(key) ?? 0) + 1);
    }
    assert.ok([...groups.values()].every((n) => n === 5));
  }
  for (const changed of [{phase: "pressure"}, {load: "six"}, {budget: "16"},
    {repeat: 6}, {inputDigest: "c".repeat(64)}, {arm: "current"},
    {diagnostic: undefined}, {loadPressure: undefined}]) {
    assert.throws(() => validateReusePlan({...plans[0], ...changed} as
      ReusePlan));
  }
});

test("고정 입력 계약은 시즌 대상 크기와 출력 바이트 변조를 거절한다", () => {
  assert.equal(fixture.inputDigest, PRESSURE_INPUT);
  assertApprovedContract(fixture.contracts.single, "single");
  assertApprovedContract(fixture.contracts.six, "six");
  assertApprovedContract(fixture.contracts.six, "synthetic-three");
  assert.equal(fixture.contracts.single[0].targets.length, 31);
  assert.equal(fixture.contracts.six.reduce((n, s) => n + s.targets.length,
    0), 137);
  for (const mutate of [
    (c: InputContract) => c.pop(),
    (c: InputContract) => c[0].targets[0].bytes++,
    (c: InputContract) => c[0].uploadBytes++,
  ]) {
    const bad = structuredClone(fixture.contracts.six);
    mutate(bad);
    assert.throws(() => assertApprovedContract(bad, "six"));
  }
});

async function mixedInput() {
  const bytes = await Promise.all([30, 170].map((r) => sharp({create: {
    width: 8, height: 8, channels: 3, background: {r, g: 70, b: 120},
  }}).png().toBuffer()));
  const hash = (b: Buffer) => createHash("sha256").update(b).digest("hex");
  const images = bytes.map((b, i) => ({sourceURL: `https://example.com/${i}`,
    path: String(i), sha256: hash(b), bytes: b.length}));
  const cover = {...images[0], seasonID: "2026SS",
    sourceURL: "https://example.com/cover"};
  const outputs = [];
  for (const [kind, image, b] of [["post", images[0], bytes[0]],
    ["post", images[1], bytes[1]], ["cover", cover, bytes[0]]] as const) {
    for (const [maxPixel, quality] of kind === "post" ?
      [[768, 82], [1920, 90]] : [[512, 75], [1600, 88]]) {
      const jpeg = await jpegBytes(b, maxPixel, quality);
      outputs.push({kind, sourceHash: image.sha256, maxPixel,
        sha256: hash(jpeg), bytes: jpeg.length});
    }
  }
  const calls = new Map<string, number>();
  const input = {seasons: [{seasonID: "2026SS",
    sourceURL: "https://example.com/season", htmlSha256: "0".repeat(64),
    images: [...images, {...images[1], sourceURL: "https://example.com/dup"}]}],
  covers: [cover], golden: [{seasonID: "2026SS", uniqueImages: 2,
    uploadFiles: 6, assetTargets: 3, outputs,
    uploadBytes: outputs.reduce((n, o) => n + o.bytes, 0)}],
  readImage: async (image: typeof images[number]) => {
    calls.set(image.sourceURL, (calls.get(image.sourceURL) ?? 0) + 1);
    return Buffer.from(bytes[Number(image.path)]);
  }};
  return {input, calls, budget: bytes[0].length};
}

test("혼합 재사용은 실제 JPEG와 읽기 바이트 및 커버 준비 계약을 지킨다",
  async () => {
    const tiny = await mixedInput();
    const trace = new ReuseTrace();
    const inventory = new BufferInventory();
    const runtime = new TracedPipeline({...reusePolicy("16"),
      hashes: {kind: "refill", concurrency: 1},
      sourceBufferBudgetBytes: tiny.budget}, trace);
    await inventory.run(() => connectedExecutor(tiny.input, trace, true)(
      comparisonInputs("single")[0], runtime, new AbortController().signal));
    const contract = contractFor(tiny.input, "single");
    const counts = inspectContractTrace(contract, trace.snapshot());
    assert.equal(counts.trace.assets, 3);
    assert.equal(counts.trace.prepared, 1);
    assert.equal(counts.trace.reused, 1);
    assert.equal(counts.reads, 5);
    assert.equal(counts.reads, [...tiny.calls.values()].reduce((a, b) => a+b));
    assert.equal(counts.readBytes, contract[0].hashBytes +
      contract[0].targets[1].bytes + contract[0].targets[2].bytes);
    assert.equal(tiny.calls.get("https://example.com/cover"), 1);
    assert.equal(runtime.sourceBuffers?.snapshot().misses, 1);
    assert.equal(runtime.sourceBuffers?.snapshot().rejectedByBudget, 2);
    assert.equal(runtime.sourceBuffers?.snapshot().retainedBytes, 0);
    assert.equal(inventory.snapshot().objects, 0);
    const altered = trace.snapshot().map((e) => e.target === "post-1" ?
      {...e, target: "post-9"} : e);
    assert.throws(() => analyzeReuseTrace(altered, contract));
  });

test("압박 fallback 실패와 취소도 준비 커버 및 cache scope를 반환한다",
  async () => {
    for (const cancel of [false, true]) {
      const tiny = await mixedInput();
      const trace = new ReuseTrace();
      const inventory = new BufferInventory();
      const controller = new AbortController();
      const read = tiny.input.readImage;
      tiny.input.readImage = async (image) => {
        const bytes = await read(image);
        if (image.sourceURL === "https://example.com/1" &&
          tiny.calls.get(image.sourceURL) === 2) {
          if (cancel) controller.abort();
          else throw new Error("fallback 읽기 실패");
        }
        return bytes;
      };
      const runtime = new TracedPipeline({...reusePolicy("16"),
        hashes: {kind: "refill", concurrency: 1},
        sourceBufferBudgetBytes: tiny.budget, signal: controller.signal},
      trace);
      await assert.rejects(inventory.run(() =>
        connectedExecutor(tiny.input, trace, true)(
          comparisonInputs("single")[0], runtime, controller.signal)));
      assert.equal(inventory.snapshot().objects, 0);
      assert.equal(runtime.sourceBuffers?.snapshot().retainedBytes, 0);
      assert.equal(runtime.sourceBuffers?.snapshot().openScopes, 0);
      assert.ok(Object.values(runtime.snapshot()).every((s) =>
        s.active === 0 && s.queued === 0));
    }
  });

// 집계/변조 검증용 합성 기록이며 실제 JPEG의 증거는 위 별도 검사다.
async function fakePayload(plan: ReusePlan) {
  const contract = fixture.contracts[plan.load === "single" ? "single" :
    "six"];
  const trace = new ReuseTrace();
  const off = plan.budget === "off";
  const partial = ["16", "32", "64"].includes(plan.budget);
  const value = await runReuse(plan, async (season, pipeline) => {
    const expected = contract.find((s) => s.seasonID === season.seasonID);
    assert.ok(expected);
    const cover = expected.targets.at(-1);
    assert.ok(cover);
    if (!off) {
      await trace.prepare({season: season.seasonID,
        target: cover.id, kind: "cover"}, () =>
        pipeline.run("download", async () => undefined));
    }
    await Promise.all(expected.targets.map((target) => trace.target({
      season: season.seasonID, target: target.id, kind: target.kind},
    async () => {
      const prepared = !off && target.kind === "cover";
      const reused = !off && target.kind === "post" && (!partial ||
        (season.seasonID === contract[0].seasonID && target.id === "post-0"));
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
    })));
    trace.record({event: "season-end", season: season.seasonID});
    return {status: "succeeded"};
  }, memory, trace);
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
        contract.reduce((n, s) => n + s.hashBytes, 0)};
  }
  value.results[0].wallMs = 1000;
  (value.detail as {firstSeasonMs: number}).firstSeasonMs = off ? 400 : 600;
  const payload = {...value, inputContract: contract};
  assert.equal(validateReusePayload(plan, payload), true);
  return payload;
}

test("압박 결과는 cache 통계와 trace 및 원본 읽기 바이트를 교차 검사한다",
  async () => {
    const plan = plans.find((p) => p.budget === "16");
    assert.ok(plan);
    const good = await fakePayload(plan);
    for (const mutate of [
      (p: typeof good) => {
        if (p.cache) p.cache.hits++;
      },
      (p: typeof good) => {
        if (p.cache) p.cache.peakRetainedBytes = 2**30;
      },
      (p: typeof good) => {
        if (p.cache) p.cache.peakRetainedBytes = 0;
      },
      (p: typeof good) => p.inputContract[0].hashBytes++,
      (p: typeof good) => p.trace?.pop(),
      (p: typeof good) => {
        const r = p.results[0].reports[0] as {measurement: {stages:
          Record<string, Record<string, number>>}};
        r.measurement.stages["image.download"].receivedBytes++;
      },
    ]) {
      const bad = structuredClone(good);
      mutate(bad);
      assert.equal(validateReusePayload(plan, bad), false);
    }
  });

test("45회 집계는 부하별 다섯 쌍과 압박 성립 및 중단 분모를 보존한다",
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
    assert.ok(summary.regressions.every((r) => r.complete && r.pairs === 5 &&
      r.first?.withholdAdoption && !r.wall?.withholdAdoption));
    const groups = summary.comparisons as Array<{pressureExpected: boolean;
      pressureEstablished: boolean}>;
    assert.equal(groups.filter((g) => g.pressureExpected &&
      g.pressureEstablished).length, 3);
    const index = plans.findIndex((p) => p.budget === "16");
    const incomplete = summarizeReuse(plans, rows.map((r, i) => i === index ?
      {...r, verdict: "aborted"} : r));
    assert.equal(incomplete.valid, true);
    assert.equal(incomplete.counts.aborted, 1);
    assert.ok(incomplete.regressions.some((r) => r.pairs === 4 &&
      !r.complete && r.first === null));
    for (const bad of [rows.slice(1), [...rows, rows[0]], rows.map((r, i) =>
      i === 0 ? {...r, imageID: `sha256:${"e".repeat(64)}`} : r)]) {
      assert.equal(summarizeReuse(plans, bad).valid, false);
    }
  });
