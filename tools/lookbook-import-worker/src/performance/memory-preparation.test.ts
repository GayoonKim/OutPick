import assert from "node:assert/strict";
import {mkdtemp, readFile, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";
import {cpuSetCount, OperationEvents, readResourceReading, ResourceFeed,
  type ResourceReading} from "./resource-feed.js";
import {preparationCorpus, preparationHash, preparationPlans,
  validatePreparationPlan, validatePreparationResult,
  type PreparationResult} from "./memory-preparation.js";
import {preparationVerdict, runPreparationCampaign, runPreparationContainer,
  type PreparationCommand} from "./memory-preparation-host.js";

const source = {sourceRevision: "a".repeat(40), sourceDigest: "b".repeat(64),
  imageID: `sha256:${"c".repeat(64)}`};
const plans = preparationPlans(source);
function reader(values: Record<string, string>) {
  return (path: string) => {
    assert.ok(path in values, `파일 없음: ${path}`);
    return values[path];
  };
}
const v2 = () => ({"/proc/self/cgroup": "0::/",
  "/sys/fs/cgroup/memory.current": "1000000",
  "/sys/fs/cgroup/memory.max": String(2 * 2**30),
  "/sys/fs/cgroup/cpu.stat": "usage_usec 1000\nthrottled_usec 200",
  "/sys/fs/cgroup/cpu.max": "100000 100000",
  "/sys/fs/cgroup/cpuset.cpus.effective": "0-3,6-7"});
function raw(atMs: number): ResourceReading {
  return {...readResourceReading(reader(v2())),
    usageMicros: atMs * 1000, throttledMicros: atMs * 10};
}
function fixture(plan = plans[0]): PreparationResult {
  const feed = new ResourceFeed(0);
  const samples = Array.from({length: 32}, (_, i) => {
    const at = i * 100;
    return {...feed.consume(at, raw(at)), rssBytes: 1000000, logicalBytes: 0,
      sharp: {queue: 0, process: 0}, marker: new Map([
        [0, "startup"], [2100, "before-input"], [2200, "input-ready"],
        [2500, "outputs-held"], [2600, "released"], [3100, "settled"],
      ]).get(at) ?? "tick"};
  });
  const item = preparationCorpus().find((c) => c.id === plan.caseID);
  assert.ok(item);
  const operations = Array.from({length: plan.overlap ? 4 : 2}, (_, i) => {
    const expected = [...item.golden]
      .sort((a, b) => a.maxPixel - b.maxPixel)[i % 2];
    return {id: `transform-${i}`, queuedAt: 2100, startedAt: 2200,
      endedAt: 2400, units: expected.width * expected.height,
      outcome: "succeeded"};
  });
  return {version: 1, plan, status: "succeeded", reason: null,
    baselineAtMs: 2100, endedAtMs: 2500, feed: feed.snapshot(), samples,
    operations, events: structuredClone(operations),
    files: operations.map((o, i) => {
      const expected = [...item.golden]
        .sort((a, b) => a.maxPixel - b.maxPixel)[i % 2];
      return {id: o.id, sha256: expected.sha256, bytes: expected.bytes};
    }), logicalBytesAfter: 0, elapsedMs: 3100,
    runtime: {node: "v24", arch: "arm64", platform: "linux",
      concurrency: 1, cache: {}, sharp: {}}} as PreparationResult;
}

test("AR01 cgroup 단위 quota cpuset과 실제 Linux 제한을 확인한다", () => {
  const two = readResourceReading(reader(v2()));
  assert.equal(two.cpuCapacity, 1);
  assert.equal(two.cpusetCPU, 6);
  assert.equal(two.usageMicros, 1000);
  assert.equal(two.peakBytes, null);
  const one = readResourceReading(reader({
    "/proc/self/cgroup": "1:cpu,cpuacct:/\n2:memory:/\n3:cpuset:/",
    "/sys/fs/cgroup/memory/memory.usage_in_bytes": "1000000",
    "/sys/fs/cgroup/memory/memory.limit_in_bytes": String(2 * 2**30),
    "/sys/fs/cgroup/cpuacct/cpuacct.usage": "1000000",
    "/sys/fs/cgroup/cpu/cpu.stat": "throttled_time 200000",
    "/sys/fs/cgroup/cpu/cpu.cfs_quota_us": "100000",
    "/sys/fs/cgroup/cpu/cpu.cfs_period_us": "100000",
    "/sys/fs/cgroup/cpuset/cpuset.cpus": "0-3,6-7",
  }));
  assert.equal(one.usageMicros, two.usageMicros);
  assert.equal(one.throttledMicros, two.throttledMicros);
  assert.equal(one.cpuCapacity, 1);
  for (const text of ["", "0-2,2-4", "4-2", "a"]) {
    assert.throws(() => cpuSetCount(text));
  }
  for (const change of [{"/sys/fs/cgroup/cpu.max": "max 100000"},
    {"/proc/self/cgroup": "0::/hidden"},
    {"/sys/fs/cgroup/cpu.stat": "usage_usec 1"}]) {
    assert.throws(() => readResourceReading(reader({...v2(), ...change})));
  }
  // Mac은 순수 parser, 승인된 Linux 게이트는 실제 컨테이너도 확인한다.
  if (process.platform === "linux") {
    const actual = readResourceReading();
    assert.equal(actual.cpuCapacity, 1);
    assert.equal(actual.memory.limitBytes, 2 * 2**30);
  }
});

test("AR02 공통 표본은 CPU 준비 역행 누락과 메모리 중단을 구분한다", () => {
  const feed = new ResourceFeed(0);
  assert.equal(feed.consume(0, raw(0)).cpuRatio, null);
  let ratio: number | null = null;
  for (let at = 100; at <= 2000; at += 100) {
    ratio = feed.consume(at, raw(at)).cpuRatio;
  }
  assert.equal(ratio, 1);
  assert.equal(feed.snapshot().memory.samples, 21);
  assert.throws(() => feed.consume(2100, raw(100)));
  assert.throws(() => feed.consume(2200, raw(2200)));
  const missing = new ResourceFeed(0);
  missing.consume(0, raw(0));
  assert.throws(() => missing.checkTime(501), /sample-gap/);
  const quota = new ResourceFeed(0);
  quota.consume(0, raw(0));
  assert.throws(() => quota.consume(100, {...raw(100), cpuCapacity: 0.5}));
  const high = new ResourceFeed(0);
  for (let at = 0; at < 1000; at += 100) {
    const reading = raw(at);
    reading.memory.usedBytes = Math.ceil(2 * 2**30 * 0.85);
    high.consume(at, reading);
  }
  const last = raw(1000);
  last.memory.usedBytes = Math.ceil(2 * 2**30 * 0.85);
  assert.throws(() => high.consume(1000, last), /sustained-high/);
});

test("AR03 완료 이벤트는 대기 실행 시간을 보존하며 중복 전달하지 않는다", () => {
  const events = new OperationEvents();
  events.queue("one", 1);
  events.start("one", 10);
  events.finish("one", 25, 400, "succeeded");
  const batch = events.drain();
  assert.equal(batch[0].startedAt! - batch[0].queuedAt, 9);
  assert.equal(batch[0].endedAt! - batch[0].startedAt!, 15);
  assert.equal(events.drain().length, 0);
  batch[0].units = 0;
  assert.equal(events.snapshot()[0].units, 400);
  assert.throws(() => events.finish("one", 26, 400, "succeeded"));
  assert.throws(() => events.queue("one", 30));
  events.queue("two", 30);
  assert.throws(() => events.finish("two", 40, 0, "failed"));
  assert.throws(() => events.start("two", 20));
  events.start("two", 40);
  events.finish("two", 41, 0, "failed");
  assert.equal(events.drain()[0].outcome, "failed");
});

test("AR04 준비 계획은 고정 원본 다섯 종류와 열여덟 회를 검증한다",
  async () => {
    const corpus = preparationCorpus();
    assert.equal(corpus.length, 5);
    assert.equal(plans.length, 18);
    assert.equal(new Set(plans.map((p) => p.id)).size, 18);
    assert.equal(plans.reduce((n, p) => n + (p.overlap ? 4 : 2), 0), 42);
    for (const p of plans) validatePreparationPlan(p);
    assert.throws(() => validatePreparationPlan({...plans[0], repeat: 99}));
    const metadata = JSON.parse(await readFile(new URL(
      "../../fixtures/performance-memory-preparation.json", import.meta.url),
    "utf8"));
    assert.equal(metadata.cases[1].image.width, 4050);
    assert.equal(metadata.cases[3].image.channels, 4);
    assert.equal(metadata.cases[4].image.kind, "cover");
    const bytes = await readFile(new URL(
      "../../fixtures/performance-memory-preparation.json", import.meta.url));
    assert.equal(preparationHash(bytes), plans[0].corpusDigest);
    for (const c of corpus) {
      assert.equal(c.golden.length, 2);
      assert.ok(c.golden.every((g) => g.width > 0 && g.height > 0));
    }
  });

test("AR05 timeout OOM 종료 미확인과 미수행 회차를 보존한다", async () => {
  const parent = await mkdtemp(join(tmpdir(), "ad2-preparation-"));
  try {
    for (const kind of ["ok", "timeout", "oom", "missing", "unknown"] as
      const) {
      const root = join(parent, kind);
      await (await import("node:fs/promises")).mkdir(root);
      const calls: string[][] = [];
      const command: PreparationCommand = async (args) => {
        calls.push(args);
        if (args[0] === "create") return "d".repeat(64);
        if (args[0] === "inspect" && args.at(-1) ===
          "{{json .HostConfig}}") {
          return JSON.stringify({NanoCpus: 1e9,
            Memory: 2 * 2**30, MemorySwap: 2 * 2**30, NetworkMode: "none"});
        }
        if (args[0] === "wait") {
          if (kind === "timeout") throw new Error("timeout");
          if (kind === "ok") {
            await writeFile(
              join(root, plans[0].id, "result.json"),
              JSON.stringify(fixture()));
          }
          return "0";
        }
        if (args[0] === "inspect") {
          return JSON.stringify({
            Running: kind === "unknown", Status: kind === "unknown" ?
              "running" : "exited", OOMKilled: kind === "oom", ExitCode: 0});
        }
        return "";
      };
      const result = await runPreparationContainer(plans[0], {
        inputDirectory: parent, outputDirectory: root, timeoutMs: 120000,
        command});
      assert.equal(result.verdict, {ok: "succeeded", timeout: "aborted",
        oom: "aborted", missing: "failed", unknown: "unavailable"}[kind]);
      assert.equal(calls.some((c) => c[0] === "rm"), kind !== "unknown");
      assert.equal(calls.some((c) => c[0] === "kill"), kind === "timeout");
      const create = calls.find((c) => c[0] === "create");
      assert.ok(create?.includes("--network=none"));
      assert.ok(create?.includes("--memory-swap=2g"));
    }
    const summary = await runPreparationCampaign(source, parent,
      join(parent, "campaign"), {preflight: async () => undefined,
        command: async (args) => {
          if (args[0] === "image") return `${source.imageID} arm64 linux`;
          throw new Error("환경 실패");
        }});
    assert.equal(summary.results.length, 18);
    assert.equal(summary.results.filter((r) => r.verdict === "not-run").length,
      17);
    assert.equal(summary.verdict, "incomplete");
  } finally {
    await rm(parent, {recursive: true, force: true});
  }
});

test("AR06 결과 위조 누락과 원본 정책 변경을 성공으로 처리하지 않는다", () => {
  for (const plan of plans) validatePreparationResult(plan, fixture(plan));
  for (const change of [
    (r: PreparationResult) => {
      r.plan = {...r.plan, sourceDigest: "0"};
    },
    (r: PreparationResult) => {
      r.files[0].sha256 = "bad";
    },
    (r: PreparationResult) => {
      r.samples[24].cpuRatio = 0;
    },
    (r: PreparationResult) => {
      r.events.pop();
    },
    (r: PreparationResult) => {
      r.logicalBytesAfter = 1;
    },
    (r: PreparationResult) => {
      r.samples.pop();
    },
    (r: PreparationResult) => {
      r.samples[0].reading.quotaCPU = 0;
    },
    (r: PreparationResult) => {
      r.baselineAtMs = -1;
    },
  ]) {
    const result = fixture();
    change(result);
    assert.throws(() => validatePreparationResult(plans[0], result));
    assert.equal(preparationVerdict(plans[0], {Status: "exited",
      Running: false, OOMKilled: false, ExitCode: 0}, result, false), "failed");
  }
});
