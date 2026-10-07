import assert from "node:assert/strict";
import test from "node:test";
import {comparisonInputs} from "./comparison.js";
import {makeReuseDiagnosticPlan, makeReusePlan, reusePolicy,
  validateReusePlan} from "./reuse-comparison.js";
import {ReuseTrace, TracedPipeline, analyzeReuseTrace} from "./reuse-trace.js";

test("재사용 진단 계획은 off와 256 두 회차를 기존 성능 표본과 분리한다", () => {
  const source = {sourceRevision: "a".repeat(40), sourceDigest: "b".repeat(64),
    inputDigest: "c".repeat(64)};
  const plans = makeReuseDiagnosticPlan(source);
  assert.deepEqual(plans.map((p) => p.budget), ["off", "256"]);
  plans.forEach(validateReusePlan);
  assert.notEqual(plans[0].settingsDigest, makeReusePlan(source)[0]
    .settingsDigest);
  for (const change of [{repeat: 2}, {budget: "128"},
    {diagnostic: undefined}, {diagnostic: "unknown"}]) {
    assert.throws(() => validateReusePlan({...plans[0], ...change} as
      typeof plans[number]));
  }
});

test("진단 계측은 병렬 대상 맥락과 슬롯 대기 실패 순서를 보존한다", async () => {
  const trace = new ReuseTrace();
  const pipeline = new TracedPipeline(reusePolicy("off"), trace);
  let release!: () => void;
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  const target = (id: string, work: () => Promise<void>) => trace.target(
    {season: "2026FW", target: id, kind: "post"}, work);
  const first = target("one", () => pipeline.run("transform", () => gate));
  const second = target("two", () => pipeline.run("transform", async () => {
    throw new Error("변환 실패");
  }));
  const secondDone = assert.rejects(second);
  await Promise.resolve();
  assert.equal(trace.snapshot().filter((e) => e.event === "start").length, 1);
  release();
  await Promise.all([first, secondDone]);
  const events = trace.snapshot();
  const starts = events.filter((e) => e.event === "start");
  assert.deepEqual(starts.map((e) => e.target), ["one", "two"]);
  const failed = events.find((e) => e.event === "end" && e.target === "two");
  assert.equal(failed?.success, false);
  assert.equal(events.find((e) => e.event === "asset-end" &&
    e.target === "two")?.success, false);
  assert.equal(pipeline.snapshot().transform.active, 0);
});

test("진단 집계는 전체 대상 단계와 커버 대기를 확인하고 불완전 기록을 거절한다",
  async () => {
    for (const reuse of [false, true]) {
      const trace = new ReuseTrace();
      const pipeline = new TracedPipeline(reusePolicy("off"), trace);
      await Promise.all(comparisonInputs("six").map(async (season, index) => {
        const posts = index === 5 ? 21 : 22;
        await Promise.all(Array.from({length: posts + 1}, (_, i) => {
          const kind = i === posts ? "cover" : "post";
          return trace.target({season: season.id, target: `${kind}-${i}`, kind},
            async () => {
              if (!reuse || kind === "cover") {
                await pipeline.run("download", async () => undefined);
              }
              trace.record({event: "source-ready",
                reused: reuse && kind === "post"});
              await Promise.all([0, 1].map(() =>
                pipeline.run("transform", async () => undefined)));
              await Promise.all([0, 1].map(() =>
                pipeline.run("upload", async () => undefined)));
              await pipeline.run("paths", async () => undefined);
            });
        }));
        trace.record({event: "season-end", season: season.id});
      }));
      const events = trace.snapshot();
      const summary = analyzeReuseTrace(events);
      assert.equal(summary.assets, 137);
      assert.equal(summary.reused, reuse ? 131 : 0);
      assert.equal(summary.details.length, 6);
      assert.ok(summary.details.every((s) => s.coverTransforms.length === 2));
      assert.throws(() => analyzeReuseTrace(events.slice(1)));
      const last = events.at(-1);
      assert.ok(last);
      assert.throws(() => analyzeReuseTrace([...events, last]));
      const invalid = structuredClone(events);
      invalid[2].atMs = -1;
      assert.throws(() => analyzeReuseTrace(invalid));
    }
  });
