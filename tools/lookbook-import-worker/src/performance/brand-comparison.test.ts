import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import {mkdtemp, rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {setImmediate} from "node:timers/promises";
import test from "node:test";
import {brandInputs, brandInputDigest, makeBrandPlan}
  from "./brand-comparison.js";
import {brandMetrics} from "./brand-metrics.js";
import {BrandProgress} from "./brand-progress.js";
import {summarizeBrand} from "./brand-report.js";
import {brandStatistics, type BrandSample} from "./brand-statistics.js";
import {brandMetadata, fakeBrandPayload, tinyBrandInput, brandTestMemory}
  from "./brand-fixture.js";
import {deriveLargeInput, metadataDigest} from "./large-input.js";
import {contractFor, PRESSURE_INPUT} from "./reuse-contract.js";
import {runReuse, validateReusePlan, validateReusePayload, type ReusePlan}
  from "./reuse-comparison.js";
import {connectedExecutor} from "./reuse-input.js";
import {ReuseTrace} from "./reuse-trace.js";
import {runSeasons, type SeasonEvent} from "./season-runner.js";
import {runContainer} from "./container-runner.js";

const source = {sourceRevision: "a".repeat(40), sourceDigest: "b".repeat(64)};
const plans = makeBrandPlan(source);
const evidence = {Status: "exited", Running: false,
  OOMKilled: false, ExitCode: 0};
const imageID = `sha256:${"d".repeat(64)}`;

test("BF07 브랜드 입력은 세 브랜드 두 시즌과 기존 원본 출력 계약을 보존한다", async () => {
  const base = await brandMetadata();
  const before = JSON.stringify(base);
  const large = deriveLargeInput(base, PRESSURE_INPUT);
  for (const load of ["standard", "large"] as const) {
    const inputs = brandInputs(load);
    assert.equal(new Set(inputs.map((s) => s.brandID)).size, 3);
    for (const id of new Set(inputs.map((s) => s.brandID))) {
      assert.equal(inputs.filter((s) => s.brandID === id).length, 2);
    }
    const contract = load === "large" ? large.contract :
      contractFor(base, "synthetic-three");
    assert.deepEqual(inputs.map((s) => s.id), contract.map((s) => s.seasonID));
    assert.equal(contract.reduce((n, s) => n + s.uploadFiles, 0),
      load === "large" ? 1584 : 274);
    assert.notEqual(brandInputDigest(load),
      load === "large" ? large.inputDigest : PRESSURE_INPUT);
  }
  assert.equal(JSON.stringify(base), before);
});

test("BF08 브랜드 스무 회 집계는 고정 순서 동일 이미지와 고유 표본만 허용한다", async () => {
  assert.equal(plans.length, 20);
  assert.deepEqual(plans.slice(0, 4).map((p) => [p.brandLoad, p.brandOrder]),
    [["standard", "parallel"], ["standard", "serial-brands"],
      ["large", "serial-brands"], ["large", "parallel"]]);
  for (const plan of plans) validateReusePlan(plan);
  for (const change of [{budget: "off"}, {brandOrder: "serial-per-brand"},
    {inputDigest: PRESSURE_INPUT}, {repeat: 6}, {brandComparison: undefined}]) {
    assert.throws(() =>
      validateReusePlan({...plans[0], ...change} as ReusePlan));
  }
  const fixtures = new Map<string,
    Awaited<ReturnType<typeof fakeBrandPayload>>>();
  for (const plan of plans.slice(0, 4)) {
    const payload = await fakeBrandPayload(plan);
    assert.equal(validateReusePayload(plan, payload), true);
    fixtures.set(`${plan.brandLoad}/${plan.brandOrder}`, payload);
  }
  const rows = plans.map((plan) => {
    const fixture = fixtures.get(`${plan.brandLoad}/${plan.brandOrder}`);
    assert.ok(fixture);
    const payload = structuredClone(fixture);
    payload.id = plan.id;
    Object.assign(payload.results[0], plan);
    const report = payload.results[0].reports[0] as {
      measurement: {runID: string; instanceKey: string}};
    report.measurement.runID = randomUUID();
    report.measurement.instanceKey = metadataDigest(plan.id).slice(0, 24);
    return {id: plan.id, imageID, verdict: "succeeded",
      reason: "none", evidence, payload};
  });
  const summary = summarizeBrand(plans, rows);
  assert.equal(summary.valid, true, summary.issues.join(","));
  assert.equal(summary.counts.succeeded, 20);
  assert.ok(summary.comparisons?.every((c) => c.complete && c.pairs === 5));
  const interrupted = rows.map((r, i) => i === 0 ? {...r, verdict: "aborted",
    reason: "memory", payload: null,
    evidence: {...evidence, OOMKilled: true, ExitCode: 137}} : r);
  const partial = summarizeBrand(plans, interrupted);
  assert.equal(partial.valid, true);
  assert.equal(partial.comparisons?.[0].pairs, 4);
  assert.equal(partial.comparisons?.[0].wall, null);
  assert.equal(summarizeBrand(plans, rows.map((r, i) => i ? r :
    {...r, imageID: `sha256:${"e".repeat(64)}`})).valid, false);
  const copied = structuredClone(rows);
  copied[1].payload.results[0].reports = copied[0].payload.results[0].reports;
  assert.equal(summarizeBrand(plans, copied).valid, false);
  assert.equal(summarizeBrand(plans, rows.slice(1)).valid, false);
});

test("BF09 첫 브랜드 시간은 등록 순서와 대기를 반영하고 review를 성공으로 바꾸지 않는다", async () => {
  for (const review of [false, true]) {
    let time = 0;
    let release!: () => void;
    const gate = new Promise<void>((r) => {
      release = r;
    });
    const events: SeasonEvent[] = [];
    const inputs = [{id: "a", brandID: "first"}, {id: "b", brandID: "second"}];
    const work = runSeasons(inputs, {order: "parallel", concurrency: 6},
      async ({id}) => {
        if (id === "a") await gate;
        return {status: review && id === "a" ? "needs-review" : "succeeded"};
      }, {signal: new AbortController().signal, now: () => ++time,
        onEvent: async (e) => {
          events.push(e);
        }});
    await setImmediate();
    release();
    const records = await work;
    const m = brandMetrics(inputs, records, events, 0, false);
    assert.ok(m.brands[0].releasedMs! > m.brands[1].releasedMs!);
    assert.equal(m.firstBrandMs, review ? null : m.brands[0].completedMs);
    assert.equal(m.brands[0].queueWaitMs, m.brands[0].admittedMs);
    assert.throws(() => brandMetrics(inputs, records, events, 0, true));
  }
});

test("BF10 브랜드 집계는 반복 악화 불완전 쌍과 중단 분모를 구분한다", () => {
  const samples: BrandSample[] = plans.map((p) => {
    const ms = p.brandOrder === "parallel" ? 100 :
      [110, 110, 110, 99, 99][p.repeat - 1];
    return {id: p.id, load: p.brandLoad!, order: p.brandOrder!,
      repeat: p.repeat,
      verdict: "succeeded", wallMs: ms, firstSeasonMs: ms, firstBrandMs: ms / 2,
      memoryMaxRatio: 0.5, readBytes: 10,
      brands: [{brandID: "a", completedMs: ms / 2,
        queueWaitMs: 0, serviceMs: ms / 2},
      {brandID: "b", completedMs: ms,
        queueWaitMs: ms / 2, serviceMs: ms / 2}]};
  });
  const full = brandStatistics(samples);
  assert.equal(full.comparisons[0].wall?.withholdAdoption, true);
  assert.equal(full.groups[1].brands?.[1].queueWaitMedianMs, 55);
  const partial = brandStatistics(samples.map((s, i) => i ? s :
    {...s, verdict: "aborted", wallMs: null, firstBrandMs: null}));
  assert.equal(partial.comparisons[0].wall, null);
  assert.equal(partial.groups[0].failureOrAbortRate, 0.2);
  assert.throws(() => brandStatistics([...samples, samples[0]]));
});

test("BF11 두 브랜드 구조는 실제 JPEG와 원본 재사용 및 정리를 보존한다", async () => {
  for (const plan of plans.slice(0, 2)) {
    const tiny = await tinyBrandInput();
    const trace = new ReuseTrace();
    const result = await runReuse(plan,
      connectedExecutor(tiny.input, trace, true),
      brandTestMemory, trace);
    assert.equal(result.results[0].outcome, "succeeded");
    assert.equal(tiny.reads(), 18);
    assert.equal(result.cache?.hits, 6);
    assert.equal(result.cache?.retainedBytes, 0);
    assert.equal(result.cache?.openScopes, 0);
    assert.equal(result.buffers.objects, 0);
    const events = trace.snapshot();
    assert.equal(events.filter((e) => e.event === "end" &&
      e.stage === "upload").length, 24);
    assert.equal(events.filter((e) => e.event === "end" &&
      e.stage === "paths").length, 12);
    assert.ok(Object.values(result.slots!)
      .every((s) => !s.active && !s.queued));
  }
});

test("BF12 진행 증거는 순서 한도 출력 실패와 OOM 결과 누락을 보존한다", async () => {
  const lines: string[] = [];
  const progress = new BrandProgress("sample", async (line) => {
    lines.push(line);
  });
  await Promise.all([progress.emit({event: "preflight-start"}),
    progress.emit({event: "measurement-start"})]);
  assert.deepEqual(lines.map((l) => JSON.parse(l).sequence), [1, 2]);
  const limited = new BrandProgress("sample", async () => undefined, 1);
  await assert.rejects(limited.emit({event: "preflight-start"}),
    /evidence-limit/);
  assert.equal(limited.controller.signal.aborted, true);
  const broken = new BrandProgress("sample", async () => {
    throw new Error("disk");
  });
  await assert.rejects(broken.emit({event: "preflight-start"}),
    /evidence-write/);
  await broken.drain();
  assert.equal(broken.errorCode, "evidence-write");
  let executed = 0;
  const disrupted = new BrandProgress(plans[0].id, async (line) => {
    if (JSON.parse(line).event === "attempt-start") throw new Error("disk");
  });
  const failure = await runReuse(plans[0], async () => {
    executed++; return {status: "succeeded"};
  }, brandTestMemory, new ReuseTrace(), disrupted);
  assert.equal(failure.evidenceError, "evidence-write");
  assert.equal(executed, 0);
  assert.equal(failure.buffers.objects, 0);
  assert.equal(failure.cache?.openScopes, 0);
  const root = await mkdtemp(join(tmpdir(), "brand-oom-"));
  let removed = false;
  try {
    const row = await runContainer(plans[0], {kind: "reuse", imageID,
      inputDirectory: root, outputParent: root, command: async (args) => {
        if (args[0] === "image") return `${imageID} arm64 linux`;
        if (args[0] === "create") return "c".repeat(64);
        if (args[0] === "wait") return "137";
        if (args[0] === "inspect") {
          return JSON.stringify({...evidence, OOMKilled: true, ExitCode: 137});
        }
        if (args[0] === "rm") removed = true;
        return "";
      }});
    assert.equal(row.verdict, "aborted");
    assert.equal(row.reason, "memory");
    assert.equal(row.payload, null);
    assert.equal(removed, true);
    assert.equal(lines.length, 2);
  } finally {
    await rm(root, {recursive: true, force: true});
  }
});
