import assert from "node:assert/strict";
import {createHash, randomUUID} from "node:crypto";
import {readFile} from "node:fs/promises";
import test from "node:test";
import sharp from "sharp";
import {jpegBytes} from "../processor.js";
import {mapScheduled} from "../pipeline/scheduling.js";
import {SourceBufferStore} from "../pipeline/source-buffer-store.js";
import {BufferInventory} from "./buffer-inventory.js";
import {comparisonInputs} from "./comparison.js";
import {makeLargePlan, makeLargeControlPlan, makeLargeConfirmationPlan,
  summarizeLarge,
  pressureEstablished}
  from "./large-comparison.js";
import {deriveLargeInput, assertLargeInput, assertLargeContract,
  largeSeasons, largeTraceProfile, LARGE_INPUT_DIGEST, metadataDigest}
  from "./large-input.js";
import {contractForSeasons, inspectContractTrace, PRESSURE_INPUT}
  from "./reuse-contract.js";
import {runReuse, validateReusePlan, validateReusePayload, type ReusePlan}
  from "./reuse-comparison.js";
import {connectedExecutor} from "./reuse-input.js";
import {ReuseTrace, analyzeReuseTrace, assertTraceCapacity, traceEventLimit}
  from "./reuse-trace.js";
import {submissionPolicy, inspectSubmissionTrace}
  from "./submission-comparison.js";
import {SubmissionRuntime} from "./submission-runtime.js";
import {largeStatistics, type LargeSample} from "./large-statistics.js";

const source = {sourceRevision: "a".repeat(40), sourceDigest: "b".repeat(64),
  inputDigest: LARGE_INPUT_DIGEST};
const plans = makeLargePlan(source);

test("P4 다섯 쌍 계획은 세 예산 열다섯 회 순서와 준비 표본 격리를 고정한다",
  () => {
    const plans = makeLargeConfirmationPlan(source);
    assert.equal(plans.length, 15);
    assert.equal(new Set(plans.map((p) => p.id)).size, 15);
    const orders = [["off", "128", "256"], ["128", "256", "off"],
      ["256", "off", "128"], ["off", "256", "128"], ["128", "off", "256"]];
    for (let i = 0; i < 5; i++) {
      assert.deepEqual(plans.filter((p) => p.repeat === i + 1)
        .map((p) => p.budget), orders[i]);
    }
    plans.forEach(validateReusePlan);
    assert.ok(plans.every((p) => p.arm === "prepared" &&
      p.submissionArm === "P4" && !p.largeControl));
    for (const change of [{repeat: 6}, {budget: "512"}, {arm: "off"},
      {largeConfirmation: undefined}, {largeControl: "p4-off-prepared-v1"},
      {id: makeLargeControlPlan(source)[0].id}, {submissionArm: "U"},
      {inputDigest: PRESSURE_INPUT}]) {
      assert.throws(() => validateReusePlan({...plans[0], ...change} as
        ReusePlan));
    }
  });

test("P4 다섯 쌍 통계는 반복 악화와 속도 기준 및 중단 쌍의 미판정을 구분한다",
  () => {
    const samples: LargeSample[] = makeLargeConfirmationPlan(source).map(
      (plan) => {
        const wall = plan.budget === "off" ? 100 : plan.budget === "128" ?
          [110, 110, 110, 99, 99][plan.repeat - 1] : 80;
        return {budget: plan.budget, repeat: plan.repeat,
          verdict: "succeeded", wallMs: wall, firstMs: 20,
          seasonMs: Object.fromEntries(largeSeasons().map((s) => [s.id, 20])),
          readBytes: plan.budget === "off" ? 100 : 80,
          memoryMaxRatio: 0.7, pressure: plan.budget !== "off"};
      });
    const summary = largeStatistics(samples);
    assert.equal(summary.regressions[0].wall?.slowerPairs, 3);
    assert.equal(summary.regressions[0].wall?.withholdAdoption, true);
    assert.equal(summary.regressions[0].meetsLocalSpeedTarget, false);
    assert.equal(summary.regressions[1].meetsLocalSpeedTarget, true);
    assert.ok(summary.comparisons.every((g) => g.complete &&
      g.counts.succeeded === 5 && g.failureOrAbortRate === 0));
    const interrupted = samples.map((s) => s.budget === "128" &&
      s.repeat === 1 ? {...s, verdict: "aborted", wallMs: null, firstMs: null,
        seasonMs: {}, readBytes: null, pressure: null} : s);
    const partial = largeStatistics(interrupted);
    assert.equal(partial.regressions[0].pairs, 4);
    assert.equal(partial.regressions[0].wall, null);
    assert.equal(partial.regressions[0].meetsLocalSpeedTarget, null);
    assert.equal(partial.comparisons[1].counts.aborted, 1);
    assert.equal(partial.comparisons[1].medianMs, null);
    assert.equal(partial.comparisons[1].failureOrAbortRate, 0.2);
    const firstSlow = samples.map((s) => s.budget === "256" ?
      {...s, firstMs: 23} : s);
    assert.equal(largeStatistics(firstSlow).regressions[1]
      .meetsLocalSpeedTarget, false);
    assert.throws(() => largeStatistics([...samples, samples[0]]));
  });
type Input = Parameters<typeof deriveLargeInput>[0];
async function metadataInput() {
  const metadata = JSON.parse(await readFile(
    "fixtures/performance-large-base.json", "utf8"));
  return {...metadata,
    readImage: async () => assert.fail("메타데이터 검사")} as Input;
}

test("대용량 입력은 독립 여섯 시즌과 원본 순서 출력 계약 및 새 식별자를 고정한다",
  async () => {
    const base = await metadataInput();
    const before = metadataDigest(base);
    const large = deriveLargeInput(base, PRESSURE_INPUT);
    assertLargeInput(large);
    assert.equal(metadataDigest(base), before);
    assert.equal(large.inputDigest, LARGE_INPUT_DIGEST);
    assert.equal(new Set(large.connectedInput.seasons.map((s) =>
      s.sourceURL)).size, 6);
    assert.ok(large.contract.every((s) => s.hashReads === 132 &&
      s.targets.length === 132 && s.uploadFiles === 264));
    assert.equal(large.contract.reduce((n, s) => n + s.uploadBytes, 0),
      250182505);
    assert.equal(large.contract.flatMap((s) => s.targets).filter((t) =>
      t.kind === "post").reduce((n, t) => n + t.bytes, 0), 666170412);
    const changed = deriveLargeInput(base, PRESSURE_INPUT);
    changed.manifest.mapping[0].coverSeason = "2024SS";
    assert.throws(() => assertLargeInput(changed));
    const mutated = deriveLargeInput(base, PRESSURE_INPUT);
    mutated.connectedInput.seasons[0].images[0].bytes++;
    assert.throws(() => assertLargeInput(mutated));
    assert.throws(() => deriveLargeInput({...base,
      seasons: [...base.seasons].reverse()}, PRESSURE_INPUT));
    const contract = structuredClone(large.contract);
    contract[0].targets.reverse();
    assert.throws(() => assertLargeContract(contract));
    assert.throws(() => deriveLargeInput(base, "0".repeat(64)));
  });

test("대용량 준비 계획은 일곱 조건 순서와 단일 반복 및 기존 계획 격리를 지킨다",
  () => {
    assert.deepEqual(plans.map((p) => `${p.submissionArm}/${p.budget}`),
      ["U/off", "P4/128", "U/128", "U/256", "P4/256", "P4/512", "U/512"]);
    plans.forEach(validateReusePlan);
    for (const change of [{repeat: 2}, {submission: "submission-v1"},
      {largeInput: undefined}, {budget: "all"}, {submissionArm: "B4"},
      {inputDigest: PRESSURE_INPUT}, {load: "six"}]) {
      assert.throws(() => validateReusePlan({...plans[0], ...change} as
        ReusePlan));
    }
  });

async function tinyInput() {
  const bytes = await Promise.all(Array.from({length: 6}, (_, i) =>
    sharp({create: {width: 8, height: 8, channels: 3,
      background: {r: i * 30, g: 90, b: 10}}}).png().toBuffer()));
  const hash = (b: Buffer) => createHash("sha256").update(b).digest("hex");
  const seasons = comparisonInputs("six").map((s, i) => {
    const image = {sourceURL: `https://example.com/${i}`, path: String(i),
      bytes: bytes[i].length, sha256: hash(bytes[i])};
    return {seasonID: s.seasonID, sourceURL: `https://example.com/s/${i}`,
      htmlSha256: "0".repeat(64), images: [image, {...image,
        sourceURL: `${image.sourceURL}-duplicate`}]};
  });
  const covers = seasons.map((s) => ({...s.images[0], seasonID: s.seasonID,
    sourceURL: `${s.images[0].sourceURL}-cover`}));
  const golden = await Promise.all(seasons.map(async (s, i) => {
    const outputs = [];
    for (const kind of ["post", "cover"]) {
      for (const [maxPixel, quality] of kind === "post" ?
        [[768, 82], [1920, 90]] : [[512, 75], [1600, 88]]) {
        const jpeg = await jpegBytes(bytes[i], maxPixel, quality);
        outputs.push({kind, sourceHash: hash(bytes[i]), maxPixel,
          sha256: hash(jpeg), bytes: jpeg.length});
      }
    }
    return {seasonID: s.seasonID, uniqueImages: 1, assetTargets: 2,
      uploadFiles: 4, uploadBytes: outputs.reduce((n, o) => n + o.bytes, 0),
      outputs};
  }));
  const buffers = new Set<Buffer>();
  let readBytes = 0;
  const base: Input = {seasons, covers, golden, readImage: async (image) => {
    const b = Buffer.from(bytes[Number(image.path)]);
    assert.ok(!buffers.has(b));
    buffers.add(b);
    readBytes += b.length;
    return b;
  }};
  return {base, buffers, readBytes: () => readBytes,
    budget: bytes[0].length};
}

test("합성 시즌은 실제 JPEG와 새 버퍼 독립 중복 제거 혼합 재사용 및 경로를 지킨다",
  async () => {
    for (const arm of ["U", "P4"] as const) {
      const tiny = await tinyInput();
      const input = deriveLargeInput(tiny.base, PRESSURE_INPUT);
      const trace = new ReuseTrace();
      const inventory = new BufferInventory();
      const pipeline = new SubmissionRuntime({...submissionPolicy("128", arm),
        sourceBufferBudgetBytes: tiny.budget}, trace, arm === "P4");
      await inventory.run(() => Promise.all(largeSeasons().map((s, i) =>
        pipeline.withSeason(i, () => connectedExecutor(input.connectedInput,
          trace, true)(s, pipeline, new AbortController().signal)))));
      const counts = inspectContractTrace(input.contract, trace.snapshot());
      assert.equal(counts.files, 84);
      assert.equal(counts.posts, 36);
      assert.equal(counts.trace.assets, 42);
      assert.ok(counts.trace.reused > 0 && counts.trace.reused < 36);
      assert.equal(counts.reads, tiny.buffers.size);
      assert.equal(counts.readBytes, tiny.readBytes());
      assert.equal(pipeline.sourceBuffers?.snapshot().retainedBytes, 0);
      assert.equal(pipeline.sourceBuffers?.snapshot().openScopes, 0);
      assert.equal(inventory.snapshot().objects, 0);
    }
  });

test("보관 예산은 정확한 경계 초과 독립 scope와 조기 반환 및 중복 거절을 구분한다",
  () => {
    const store = new SourceBufferStore(4);
    const one = store.openScope();
    const two = store.openScope();
    assert.equal(one.retain("url", "one", Buffer.alloc(4)), true);
    assert.equal(two.acquire("url", "two"), null);
    assert.equal(two.retain("url", "two", Buffer.alloc(4)), false);
    one.close();
    assert.equal(two.retain("url", "two", Buffer.alloc(4)), true);
    two.close();
    const three = store.openScope();
    assert.equal(three.retain("large", "three", Buffer.alloc(5)), false);
    assert.equal(three.retain("url", "three", Buffer.alloc(4)), true);
    assert.equal(three.retain("duplicate", "three", Buffer.alloc(4)), false);
    three.retainOnly(new Set(["url"]), "three");
    const lease = three.acquire("url", "three");
    assert.ok(lease);
    lease.release();
    three.close();
    assert.equal(store.snapshot().retainedBytes, 0);
    assert.equal(store.snapshot().openScopes, 0);
    assert.equal(store.snapshot().peakRetainedBytes, 4);
    assert.equal(store.snapshot().rejectedByBudget, 3);
    assert.equal(store.snapshot().misses, 1);
  });

test("합성 해시 경로 실패와 중단은 독립 형제 scope와 슬롯을 반환한다",
  async () => {
    for (const fault of ["hash", "paths", "cancel"]) {
      const tiny = await tinyInput();
      const controller = new AbortController();
      const baseRead = tiny.base.readImage;
      tiny.base.readImage = async (image) => {
        if (fault === "hash") throw new Error("해시 읽기 실패");
        if (fault === "cancel") controller.abort();
        return baseRead(image);
      };
      const input = deriveLargeInput(tiny.base, PRESSURE_INPUT);
      const trace = new ReuseTrace();
      class FaultRuntime extends SubmissionRuntime {
        override run<T>(stage: Parameters<SubmissionRuntime["run"]>[0],
          work: () => Promise<T>, signal?: AbortSignal): Promise<T> {
          return super.run(stage, stage === fault ? async () => {
            throw new Error("경로 저장 실패");
          } : work, signal);
        }
      }
      const pipeline = new FaultRuntime({...submissionPolicy("128", "P4"),
        sourceBufferBudgetBytes: tiny.budget, signal: controller.signal},
      trace, true);
      const inventory = new BufferInventory();
      const outcomes = await inventory.run(() => Promise.allSettled(
        largeSeasons().map((s, i) => pipeline.withSeason(i, () =>
          connectedExecutor(input.connectedInput, trace, true)(s, pipeline,
            controller.signal)))));
      assert.ok(outcomes.every((o) => o.status === "rejected"));
      assert.equal(pipeline.sourceBuffers?.snapshot().retainedBytes, 0);
      assert.equal(pipeline.sourceBuffers?.snapshot().openScopes, 0);
      assert.equal(inventory.snapshot().objects, 0);
      assert.ok(Object.values(pipeline.snapshot()).every((s) =>
        s.active === 0 && s.queued === 0));
    }
  });

// 집계용 합성 사건이며 실제 픽셀/업로드 결과의 실측을 의미하지 않는다.
async function fakePayload(plan: ReusePlan) {
  const large = deriveLargeInput(await metadataInput(), PRESSURE_INPUT);
  const contract = large.contract;
  const profile = largeTraceProfile(contract);
  const trace = new ReuseTrace(profile);
  const off = plan.budget === "off";
  const value = await runReuse(plan, async (season, pipeline) => {
    const expected = contract.find((s) => s.seasonID === season.seasonID);
    assert.ok(expected);
    const cover = expected.targets.at(-1);
    assert.ok(cover);
    if (plan.arm === "prepared") {
      await trace.prepare({season: season.seasonID, target: cover.id,
        kind: "cover"}, () => pipeline.run("download", async () => undefined));
    }
    await mapScheduled(expected.targets, pipeline.assets, (target) =>
      trace.target({season: season.seasonID, target: target.id,
        kind: target.kind}, async () => {
        const prepared = plan.arm === "prepared" && target.kind === "cover";
        const reused = !off && target.id === "post-0";
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
  const counts = inspectContractTrace(contract, trace.snapshot(), profile);
  const stages = (value.results[0].reports[0] as {measurement: {stages:
    Record<string, Record<string, number>>}}).measurement.stages;
  for (const [name, count] of Object.entries({"image.download": counts.reads,
    "image.hash": counts.hashReads, "image.transform": counts.files,
    "file.upload": counts.files, "paths.save": counts.trace.assets})) {
    Object.assign(stages[name], {started: count, succeeded: count,
      peakActive: 1});
  }
  stages["image.download"].receivedBytes = counts.readBytes;
  stages["file.upload"].completedBytes = counts.uploadBytes;
  if (!off) {
    value.cache = {budgetBytes: Number(plan.budget) * 2**20,
      retainedBytes: 0, openScopes: 0, hits: counts.trace.reused,
      misses: counts.posts - counts.trace.reused,
      rejectedByBudget: counts.posts - counts.trace.reused,
      peakRetainedBytes: contract[0].targets[0].bytes * 6};
  }
  return {...value, inputContract: contract};
}

test("P4 열다섯 회 집계는 동일 이미지와 고유 측정 및 실패 분모를 검증한다",
  async () => {
    const plans = makeLargeConfirmationPlan(source);
    const fixtures = new Map<string, Awaited<ReturnType<typeof fakePayload>>>();
    for (const plan of plans.slice(0, 3)) {
      fixtures.set(plan.budget, await fakePayload(plan));
    }
    // 집계 전용 가짜 자료다. 실제 파일 출력은 별도 JPEG 연결 검사로 확인한다.
    const rows = plans.map((plan) => {
      const payload = structuredClone(fixtures.get(plan.budget));
      assert.ok(payload);
      payload.id = plan.id;
      Object.assign(payload.results[0], plan);
      const report = payload.results[0].reports[0] as {measurement: {
        runID: string; instanceKey: string}};
      report.measurement.runID = randomUUID();
      report.measurement.instanceKey = metadataDigest(plan.id).slice(0, 24);
      return {id: plan.id, imageID: `sha256:${"d".repeat(64)}`,
        verdict: "succeeded", reason: "none", payload,
        evidence: {Status: "exited", Running: false, OOMKilled: false,
          ExitCode: 0}};
    });
    const summary = summarizeLarge(plans, rows);
    assert.equal(summary.valid, true);
    assert.equal(summary.counts.succeeded, 15);
    assert.equal(summary.comparisons?.length, 3);
    assert.equal(summary.regressions.length, 2);
    assert.ok(summary.regressions.every((r) => r.complete && r.pairs === 5));
    const interrupted = rows.map((r, i) => i === 0 ? {...r,
      verdict: "aborted", reason: "memory", payload: null,
      evidence: {...r.evidence, OOMKilled: true, ExitCode: 137}} : r);
    const partial = summarizeLarge(plans, interrupted);
    assert.equal(partial.valid, true);
    assert.equal(partial.counts.aborted, 1);
    assert.ok(partial.regressions.every((r) => !r.complete &&
      r.pairs === 4 && r.wall === null));
    const mixed = rows.map((r, i) => i === 0 ?
      {...r, imageID: `sha256:${"e".repeat(64)}`} : r);
    assert.equal(summarizeLarge(plans, mixed).valid, false);
    const copied = structuredClone(rows);
    const measurement = (r: typeof rows[number]) =>
      (r.payload.results[0].reports[0] as {measurement: {runID: string}})
        .measurement;
    measurement(copied[1]).runID = measurement(copied[0]).runID;
    assert.ok(summarizeLarge(plans, copied).issues
      .includes("result.reused-measurement"));
    assert.equal(validateReusePayload(plans[0], {
      ...rows[0].payload, id: makeLargeControlPlan(source)[0].id}), false);
  });

test("P4 비재사용 대조 계획은 커버 선준비와 단일 회차 및 기존 행렬 격리를 지킨다",
  () => {
    const control = makeLargeControlPlan(source);
    assert.equal(control.length, 1);
    const plan = control[0];
    validateReusePlan(plan);
    assert.equal(plan.submissionArm, "P4");
    assert.equal(plan.budget, "off");
    assert.equal(plan.arm, "prepared");
    assert.equal(plan.repeat, 1);
    assert.ok(!makeLargePlan(source).some((p) => p.id === plan.id));
    for (const change of [{arm: "off"}, {budget: "128"}, {repeat: 2},
      {submissionArm: "U"}, {largeControl: undefined}, {largeInput: undefined},
      {id: plans[0].id}, {settingsDigest: plans[0].settingsDigest}]) {
      assert.throws(() => validateReusePlan({...plan, ...change} as ReusePlan));
    }
    for (const old of plans) {
      assert.throws(() => validateReusePlan({...old,
        largeControl: "p4-off-prepared-v1"}));
    }
  });

test("P4 비재사용 실제 JPEG는 본문 재다운로드와 커버 선준비 및 자원 반환을 지킨다",
  async () => {
    const tiny = await tinyInput();
    const large = deriveLargeInput(tiny.base, PRESSURE_INPUT);
    const trace = new ReuseTrace();
    const pipeline = new SubmissionRuntime(submissionPolicy("off", "P4"),
      trace, true);
    const inventory = new BufferInventory();
    await inventory.run(() => Promise.all(largeSeasons().map((season, i) =>
      pipeline.withSeason(i, () => connectedExecutor(large.connectedInput,
        trace, true)(season, pipeline, new AbortController().signal)))));
    const counts = inspectContractTrace(large.contract, trace.snapshot());
    assert.equal(counts.trace.prepared, 6);
    assert.equal(counts.trace.reused, 0);
    assert.equal(counts.reads, 114);
    assert.equal(counts.files, 84);
    assert.equal(counts.reads, tiny.buffers.size);
    assert.equal(counts.readBytes, tiny.readBytes());
    assert.equal(pipeline.sourceBuffers, undefined);
    const admission = inspectSubmissionTrace(trace.snapshot(),
      large.contract, "P4");
    assert.ok(Object.values(admission.peakAssets).every((n) => n <= 4));
    assert.equal(inventory.snapshot().objects, 0);
    assert.ok(Object.values(pipeline.snapshot()).every((s) =>
      s.active === 0 && s.queued === 0));
  });

test("P4 비재사용 대조 집계는 단일 결과와 메모리 중단 및 기존 표본 혼입을 구분한다",
  async () => {
    const control = makeLargeControlPlan(source);
    const payload = await fakePayload(control[0]);
    assert.equal(validateReusePayload(control[0], payload), true);
    assert.equal(payload.cache, null);
    const counts = inspectContractTrace(payload.inputContract,
      payload.trace ?? [], largeTraceProfile(payload.inputContract));
    assert.equal(counts.reads, 1584);
    assert.equal(counts.readBytes, 1338062791);
    assert.equal(counts.trace.prepared, 6);
    assert.equal(counts.trace.reused, 0);
    const row = {id: control[0].id, imageID: `sha256:${"d".repeat(64)}`,
      verdict: "succeeded", reason: "none", payload,
      evidence: {Status: "exited", Running: false, OOMKilled: false,
        ExitCode: 0}};
    const summary = summarizeLarge(control, [row]);
    assert.equal(summary.valid, true);
    assert.equal(summary.planned, 1);
    assert.equal(summary.conditions[0].pressureEstablished, false);
    assert.equal(summary.scope,
      "large-p4-off-control-qualification-not-adoption");
    assert.deepEqual(summary.regressions, []);
    assert.equal(summarizeLarge(control, []).valid, false);
    assert.equal(summarizeLarge(control, [row, row]).valid, false);
    assert.equal(summarizeLarge(plans, [row]).valid, false);
    assert.equal(summarizeLarge(control, [{...row, id: plans[0].id}]).valid,
      false);
    const aborted = {...row, verdict: "aborted", reason: "memory",
      payload: null, evidence: {...row.evidence, OOMKilled: true,
        ExitCode: 137}};
    assert.equal(summarizeLarge(control, [aborted]).counts.aborted, 1);
    assert.equal(summarizeLarge(control, [aborted]).valid, true);
    assert.equal(summarizeLarge(control, [{...aborted,
      evidence: row.evidence}]).valid, false);
    const bad = structuredClone(payload);
    const prepared = bad.trace?.find((e) => e.prepared);
    assert.ok(prepared);
    delete prepared.prepared;
    assert.equal(validateReusePayload(control[0], bad), false);
  });

test("대용량 사건은 만 건 초과와 산출 상한을 허용하고 누락 변조 혼입을 거절한다",
  async () => {
    const payload = await fakePayload(plans[1]);
    assert.equal(validateReusePayload(plans[1], payload), true);
    assert.ok(payload.trace && payload.trace.length > 10000);
    const profile = largeTraceProfile(payload.inputContract);
    assert.equal(traceEventLimit(profile), 16656 * 5);
    const recorder = new ReuseTrace(profile);
    for (let i = 0; i < traceEventLimit(profile); i++) {
      recorder.record({event: "season-end"});
    }
    assertTraceCapacity(recorder.snapshot().length, profile);
    assert.throws(() => recorder.record({event: "season-end"}));
    assert.throws(() => assertTraceCapacity(traceEventLimit(profile) + 1,
      profile));
    assert.throws(() => analyzeReuseTrace(payload.trace ?? [],
      payload.inputContract));
    for (const mutation of ["missing", "contract", "bytes", "time"]) {
      const bad = structuredClone(payload);
      if (mutation === "missing") bad.trace?.pop();
      if (mutation === "contract") bad.inputContract[0].targets[0].bytes++;
      if (mutation === "bytes") {
        const report = bad.results[0].reports[0] as {measurement: {stages:
          Record<string, {receivedBytes: number}>}};
        report.measurement.stages["image.download"].receivedBytes++;
      }
      if (mutation === "time") {
        (bad.detail as {seasonCompletedMs: Array<{elapsedMs: number}>})
          .seasonCompletedMs[1].elapsedMs = 0;
      }
      assert.equal(validateReusePayload(plans[1], bad), false, mutation);
    }
    assert.throws(() => analyzeReuseTrace(payload.trace ?? [],
      payload.inputContract, {...profile,
        contract: [...payload.inputContract].reverse()}));
  });

test("대용량 준비 집계는 일곱 회 분모 압박 미성립 중단과 원본 불일치를 보존한다",
  async () => {
    const rows = [];
    for (const plan of plans) {
      rows.push({id: plan.id,
        imageID: `sha256:${"d".repeat(64)}`, verdict: "succeeded",
        reason: "none",
        evidence: {Status: "exited", Running: false, OOMKilled: false,
          ExitCode: 0}, payload: await fakePayload(plan)});
    }
    const summary = summarizeLarge(plans, rows);
    assert.equal(summary.valid, true);
    assert.equal(summary.counts.succeeded, 7);
    assert.equal(summary.conditions[0].pressureEstablished, false);
    assert.ok(summary.conditions.slice(1).every((c) => c.pressureEstablished));
    assert.deepEqual(summary.regressions, []);
    assert.equal(pressureEstablished({rejectedByBudget: 1, misses: 0}), false);
    assert.equal(pressureEstablished({rejectedByBudget: 0, misses: 0}), false);
    const abort = rows.map((r, i) => i === 0 ? {...r, verdict: "aborted",
      reason: "memory", payload: null,
      evidence: {...r.evidence, OOMKilled: true, ExitCode: 137}} : r);
    assert.equal(summarizeLarge(plans, abort).counts.aborted, 1);
    assert.equal(summarizeLarge(plans, abort).valid, true);
    const stopped = rows.map((r, i) => i === 0 ? {...r, verdict: "failed",
      reason: "operation", payload: null} : {...r, verdict: "notRun",
      reason: "prior-condition-halted", payload: null, evidence: null});
    assert.equal(summarizeLarge(plans, stopped).valid, true);
    assert.equal(summarizeLarge(plans, stopped).counts.notRun, 6);
    for (const bad of [rows.slice(1), [...rows, rows[0]], rows.map((r, i) =>
      i === 0 ? {...r, imageID: `sha256:${"e".repeat(64)}`} : r)]) {
      assert.equal(summarizeLarge(plans, bad).valid, false);
    }
    const wrong = structuredClone(rows);
    wrong[1].payload.results[0].inputDigest = PRESSURE_INPUT;
    assert.equal(summarizeLarge(plans, wrong).valid, false);
    assert.equal(contractForSeasons((await metadataInput()),
      comparisonInputs("six")).length, 6);
  });
