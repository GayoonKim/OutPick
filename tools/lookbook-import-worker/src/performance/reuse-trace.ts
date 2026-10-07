import assert from "node:assert/strict";
import {AsyncLocalStorage} from "node:async_hooks";
import {PipelineRuntime, type ResourceStage}
  from "../pipeline/resources.js";

type Target = {season: string; target: string; kind: "post" | "cover"};
export type TraceProfile = {
  kind: "large-input-v1" | "remote-input-v1"; attempts: 5;
  contract: Array<{seasonID: string; targets: Array<{id: string;
    kind: string}>}>};
export function traceEventLimit(profile?: TraceProfile): number {
  if (!profile) return 9999;
  assert.ok(["large-input-v1", "remote-input-v1"].includes(profile.kind));
  assert.equal(profile.attempts, 5);
  const assets = profile.contract.reduce((n, s) => n + s.targets.length, 0);
  assert.ok(assets > 0 && Number.isSafeInteger(assets));
  return (21 * assets + 4 * profile.contract.length) * profile.attempts;
}
export function assertTraceCapacity(count: number, profile?: TraceProfile) {
  assert.ok(Number.isSafeInteger(count) && count >= 0 &&
    count <= traceEventLimit(profile), "진단 이벤트 한도 초과");
}
export type TraceEvent = Partial<Target> & {atMs: number;
  event: "asset-start" | "asset-end" | "source-ready" | "season-end" |
    "prepare-start" | "prepare-end" | "submit" | "start" | "end";
  stage?: ResourceStage; operation?: number; success?: boolean;
  reused?: boolean; prepared?: boolean};

// 로컬 진단 전용이다. URL/이미지 바이트 없이 순서와 단조 시각만 보관한다.
export class ReuseTrace {
  private readonly origin = performance.now();
  private readonly context = new AsyncLocalStorage<Target>();
  private readonly events: TraceEvent[] = [];
  private operation = 0;
  constructor(private readonly profile?: TraceProfile) {}
  record(event: Omit<TraceEvent, "atMs">): void {
    assertTraceCapacity(this.events.length + 1, this.profile);
    this.events.push({...this.context.getStore(), ...event,
      atMs: performance.now() - this.origin});
  }
  async target<T>(target: Target, work: () => Promise<T>): Promise<T> {
    return this.lifecycle(target, "asset", work);
  }
  async prepare<T>(target: Target, work: () => Promise<T>): Promise<T> {
    assert.equal(target.kind, "cover");
    return this.lifecycle(target, "prepare", work);
  }
  private async lifecycle<T>(target: Target, phase: "asset" | "prepare",
    work: () => Promise<T>): Promise<T> {
    return this.context.run(target, async () => {
      this.record({event: `${phase}-start`});
      let success = false;
      try {
        const result = await work();
        success = true;
        return result;
      } finally {
        this.record({event: `${phase}-end`, success});
      }
    });
  }
  stage<T>(stage: ResourceStage,
    run: (work: () => Promise<T>) => Promise<T>,
    work: () => Promise<T>): Promise<T> {
    if (!this.context.getStore()) return run(work);
    const operation = ++this.operation;
    this.record({event: "submit", stage, operation});
    return run(async () => {
      this.record({event: "start", stage, operation});
      let success = false;
      try {
        const result = await work();
        success = true;
        return result;
      } finally {
        this.record({event: "end", stage, operation, success});
      }
    });
  }
  snapshot() {
    return this.events.map((event) => ({...event}));
  }
}

export class TracedPipeline extends PipelineRuntime {
  constructor(config: ConstructorParameters<typeof PipelineRuntime>[0],
    private readonly trace: ReuseTrace) {
    super(config);
  }
  override run<T>(stage: ResourceStage, work: () => Promise<T>,
    signal?: AbortSignal): Promise<T> {
    return this.trace.stage(stage,
      (operation) => super.run(stage, operation, signal), work);
  }
}

export function analyzeReuseTrace(events: TraceEvent[], expected?:
  Array<{seasonID: string; targets: Array<{id: string; kind: string}>}>,
profile?: TraceProfile) {
  assert.ok(Array.isArray(events) && events.length > 0);
  assertTraceCapacity(events.length, profile);
  if (profile) assert.deepEqual(expected, profile.contract);
  let last = 0;
  for (const event of events) {
    assert.ok(Number.isFinite(event.atMs) && event.atMs >= last);
    last = event.atMs;
  }
  const starts = events.filter((e) => e.event === "asset-start");
  const assets = expected?.reduce((n, s) => n + s.targets.length, 0) ?? 137;
  const seasons = expected?.map((s) => s.seasonID) ??
    ["2026FW", "2026SS", "2025FW", "2025SS", "2024FW", "2024SS"];
  assert.ok(assets > 0 && seasons.length > 0 &&
    new Set(seasons).size === seasons.length);
  assert.equal(starts.length, assets);
  assert.equal(new Set(starts.map((e) => `${e.season}/${e.target}`)).size,
    assets);
  if (expected) {
    assert.deepEqual(starts.map((e) => `${e.season}/${e.target}/${e.kind}`)
      .sort(), expected.flatMap((s) => s.targets.map((t) =>
      `${s.seasonID}/${t.id}/${t.kind}`)).sort());
  }
  const operations: Array<{season: string; target: string; kind: string;
    stage: string; submitted: number; started: number; ended: number}> = [];
  for (const submit of events.filter((e) => e.event === "submit")) {
    const match = events.filter((e) => e.operation === submit.operation);
    assert.deepEqual(match.map((e) => e.event), ["submit", "start", "end"]);
    assert.ok(match.every((e) => e.season === submit.season &&
      e.target === submit.target && e.kind === submit.kind &&
      e.stage === submit.stage));
    assert.equal(match[2].success, true);
    operations.push({season: String(submit.season),
      target: String(submit.target), kind: String(submit.kind),
      stage: String(submit.stage), submitted: submit.atMs,
      started: match[1].atMs, ended: match[2].atMs});
  }
  const targets = starts.map((start) => {
    assert.ok(start.season && start.target &&
      ["post", "cover"].includes(String(start.kind)));
    const own = events.filter((e) => e.season === start.season &&
      e.target === start.target);
    const end = own.filter((e) => e.event === "asset-end");
    const source = own.filter((e) => e.event === "source-ready");
    assert.equal(end.length, 1);
    assert.equal(end[0].success, true);
    assert.equal(source.length, 1);
    assert.equal(typeof source[0].reused, "boolean");
    const prepared = source[0].prepared === true;
    assert.ok(source[0].prepared === undefined || prepared);
    const preparation = own.filter((e) => e.event === "prepare-start" ||
      e.event === "prepare-end");
    assert.equal(preparation.length, prepared ? 2 : 0);
    if (prepared) {
      assert.equal(start.kind, "cover");
      assert.equal(source[0].reused, false);
      assert.deepEqual(preparation.map((e) => e.event),
        ["prepare-start", "prepare-end"]);
      assert.equal(preparation[1].success, true);
      assert.ok(preparation[1].atMs <= start.atMs);
    }
    const ops = operations.filter((o) => o.season === start.season &&
      o.target === start.target);
    for (const [stage, count] of Object.entries({transform: 2, upload: 2,
      paths: 1, download: source[0].reused ? 0 : 1})) {
      assert.equal(ops.filter((o) => o.stage === stage).length, count);
    }
    assert.ok(start.atMs <= source[0].atMs && ops.every((o) =>
      prepared && o.stage === "download" ?
        o.submitted >= preparation[0].atMs &&
          o.ended <= preparation[1].atMs :
        o.submitted >= start.atMs && o.ended <= end[0].atMs));
    const transforms = ops.filter((o) => o.stage === "transform");
    const uploads = ops.filter((o) => o.stage === "upload");
    assert.ok(transforms.every((o) => o.submitted >= source[0].atMs));
    assert.ok(uploads.every((o) => o.submitted >=
      Math.max(...transforms.map((t) => t.ended))));
    assert.ok(ops.filter((o) => o.stage === "paths").every((o) =>
      o.submitted >= Math.max(...uploads.map((u) => u.ended))));
    assert.ok(ops.filter((o) => o.stage === "download").every((o) =>
      o.ended <= source[0].atMs));
    return {...start, ended: end[0].atMs, reused: source[0].reused,
      prepared, preparedAt: prepared ? preparation[1].atMs : null, ops};
  });
  assert.equal(events.filter((e) => e.event === "start").length,
    operations.length);
  assert.equal(events.filter((e) => e.event === "end").length,
    operations.length);
  const prepared = targets.filter((t) => t.prepared).length;
  assert.equal(events.length, assets * 3 + operations.length * 3 +
    seasons.length +
    prepared * 2);
  assert.deepEqual([...new Set(targets.map((t) => t.season))].sort(),
    [...seasons].sort());
  const details = seasons.map((season) => {
    const own = targets.filter((t) => t.season === season);
    const covers = own.filter((t) => t.kind === "cover");
    assert.equal(covers.length, 1);
    const cover = covers[0];
    const end = events.filter((e) => e.season === season &&
      e.event === "season-end");
    assert.equal(end.length, 1);
    assert.ok(end[0].atMs >= Math.max(...own.map((t) => t.ended)));
    const download = cover.ops.find((o) => o.stage === "download");
    assert.ok(download && !cover.reused);
    if (cover.preparedAt !== null) {
      assert.ok(own.every((t) => t.atMs >= Number(cover.preparedAt)));
    }
    const transforms = cover.ops.filter((o) => o.stage === "transform");
    const first = transforms[0];
    return {season, bodyEndMs: Math.max(...own.filter((t) => t.kind === "post")
      .map((t) => t.ended)), coverEndMs: cover.ended,
    seasonEndMs: end[0].atMs, coverDownload: download,
    coverPreparedAtMs: cover.preparedAt,
    coverTransforms: transforms,
    otherSeasonPostTransformsAhead: operations.filter((o) =>
      o.kind === "post" && o.season !== season && o.stage === "transform" &&
      o.submitted < first.submitted && o.ended > first.submitted).length};
  });
  return {assets: targets.length,
    prepared,
    reused: targets.filter((t) => t.reused).length,
    details};
}
