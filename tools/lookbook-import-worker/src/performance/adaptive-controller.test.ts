import assert from "node:assert/strict";
import {AsyncLocalStorage} from "node:async_hooks";
import test from "node:test";
import {PipelineRuntime, Slots} from "../pipeline/resources.js";
import {ADAPTIVE_AXES, ADAPTIVE_POLICY, AdaptiveController,
  type AdaptiveAxis, type AdaptiveSample} from "./adaptive-controller.js";
import {remotePlans, remotePolicy} from "./remote-contract.js";
import {ReuseTrace} from "./reuse-trace.js";
import {ReadySeasonQueue, SubmissionRuntime} from "./submission-runtime.js";

const turn = () => new Promise<void>((resolve) => setImmediate(resolve));
function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return {promise, resolve};
}
function sample(atMs: number): AdaptiveSample {
  return {atMs, memory: {source: "cgroup-v2", limitBytes: 1000,
    usedBytes: 500}, cpuRatio: 0.5, cpuThrottled: false, sharpQueued: 0,
  demands: Object.fromEntries(ADAPTIVE_AXES.map((axis) => [axis,
    {active: 1, queued: 10, remaining: 100, canAdmit: true,
      downstreamGrowing: false}])) as AdaptiveSample["demands"],
  completed: {download: [], transform: [], upload: [], images: []},
  transientFailures: {download: 0, upload: 0}};
}
function feed(controller: AdaptiveController, from: number, to: number,
  change: (s: AdaptiveSample) => void = () => undefined) {
  for (let at = from; at <= to; at += 100) {
    const s = sample(at);
    for (const axis of ADAPTIVE_AXES) {
      s.completed[axis].push({units: 100, durationMs: 10});
    }
    change(s);
    controller.observe(s);
  }
  return controller.snapshot();
}
function only(s: AdaptiveSample, axis: AdaptiveAxis) {
  for (const item of ADAPTIVE_AXES) {
    if (item !== axis) s.demands[item].queued = 0;
  }
}

test("AP01 제어기는 초기 범위와 미지원 역행 지연 표본을 구분한다", () => {
  const controller = new AdaptiveController();
  assert.deepEqual(controller.snapshot().targets,
    {download: 4, transform: 1, upload: 4, images: 4});
  assert.deepEqual(controller.snapshot().limits,
    {download: 0, transform: 0, upload: 0, images: 0});
  assert.deepEqual(ADAPTIVE_POLICY.maximum,
    {download: 16, transform: 4, upload: 16, images: 24});
  assert.throws(() => {
    (ADAPTIVE_POLICY.initial as {download: number}).download = 99;
  });
  for (const change of [
    (s: AdaptiveSample) => {
      s.cpuRatio = null;
    },
    (s: AdaptiveSample) => {
      s.cpuRatio = NaN;
    },
    (s: AdaptiveSample) => {
      s.memory = null;
    },
    (s: AdaptiveSample) => {
      s.atMs = -1;
    },
    (s: AdaptiveSample) => {
      s.demands.upload.active = -1;
    },
  ]) {
    const c = new AdaptiveController();
    const s = sample(100);
    change(s);
    assert.ok(c.observe(s).stopped);
    assert.equal(c.observe(sample(200)).limits.upload, 0);
  }
  controller.observe(sample(100));
  assert.equal(controller.checkTime(601).stopped, "sample-gap");
  const duplicate = new AdaptiveController();
  duplicate.observe(sample(100));
  assert.equal(duplicate.observe(sample(100)).stopped, "invalid-sample");
  const changed = new AdaptiveController();
  changed.observe(sample(100));
  const s = sample(200);
  s.memory!.limitBytes = 2000;
  assert.equal(changed.observe(s).stopped, "container-changed");
});

test("AP02 가변 슬롯은 감속 중 새 시작을 막고 영 정지 뒤 재개한다",
  async () => {
    const slots = new Slots(3, true);
    const waits = Array.from({length: 5}, deferred);
    const started: number[] = [];
    const works = waits.map((wait, i) => slots.run(async () => {
      started.push(i);
      await wait.promise;
    }));
    await turn();
    assert.deepEqual(started, [0, 1, 2]);
    slots.setLimit(1);
    waits[0].resolve();
    waits[1].resolve();
    await turn();
    assert.deepEqual(started, [0, 1, 2]);
    assert.equal(slots.snapshot().active, 1);
    slots.setLimit(0);
    waits[2].resolve();
    await turn();
    assert.equal(slots.snapshot().active, 0);
    assert.equal(slots.snapshot().queued, 2);
    slots.setLimit(2);
    await turn();
    assert.deepEqual(started, [0, 1, 2, 3, 4]);
    waits.forEach((w) => w.resolve());
    await Promise.all(works);
    assert.equal(slots.snapshot().active, 0);
    assert.equal(slots.snapshot().completed, 5);
    for (const n of [-1, 0.1, NaN, Infinity]) {
      assert.throws(() => slots.setLimit(n));
    }
    assert.throws(() => new Slots(1).setLimit(2));
  });

test("AP03 한 축씩 증속하고 부족한 표본과 악화는 유지 또는 복귀한다", () => {
  const c = new AdaptiveController();
  assert.equal(feed(c, 100, 2000).targets.upload, 5);
  feed(c, 2100, 5900, (s) => {
    s.completed.upload = [{units: 120, durationMs: 10}];
  });
  assert.equal(c.snapshot().probe?.axis, "upload");
  feed(c, 6000, 6000, (s) => {
    s.completed.upload = [{units: 120, durationMs: 10}];
  });
  assert.equal(c.snapshot().probe, null);
  assert.equal(c.decisions().at(-1)?.reason, "probe-kept");
  feed(c, 6100, 10000);
  assert.equal(c.snapshot().probe?.axis, "transform");
  assert.equal(c.snapshot().targets.transform, 2);
  feed(c, 10100, 14000);
  assert.equal(c.snapshot().targets.transform, 1);
  assert.equal(c.decisions().at(-1)?.reason, "probe-reverted");
  feed(c, 14100, 18000);
  assert.equal(c.snapshot().probe?.axis, "download");
  feed(c, 18100, 22000, (s) => {
    s.completed.download = [];
  });
  assert.equal(c.decisions().at(-1)?.reason, "probe-insufficient");
  assert.equal(c.snapshot().probe?.axis, "download");
  const latency = new AdaptiveController();
  feed(latency, 100, 2000);
  feed(latency, 2100, 6000, (s) => {
    s.completed.upload = [{units: 150, durationMs: 12}];
  });
  assert.equal(latency.snapshot().targets.upload, 4);
  const capped = new AdaptiveController();
  feed(capped, 100, 60000, (s) => {
    only(s, "transform");
    s.completed.transform = [{units: 100 + s.atMs, durationMs: 10}];
  });
  assert.equal(capped.snapshot().targets.transform, 4);
  assert.ok(capped.decisions().every((d) => d.targets.transform <= 4));
  for (const axis of ADAPTIVE_AXES) {
    const bounded = new AdaptiveController();
    feed(bounded, 100, 200000, (s) => {
      only(s, axis);
      s.completed[axis] = [{units: 2 ** Math.floor(s.atMs / 4000),
        durationMs: 10}];
    });
    assert.equal(bounded.snapshot().targets[axis],
      ADAPTIVE_POLICY.maximum[axis]);
    assert.ok(bounded.decisions().every((d) =>
      d.targets[axis] <= ADAPTIVE_POLICY.maximum[axis]));
  }
});

test("AP04 CPU 포화는 네트워크를 축소하지 않고 변환 증속만 보류한다", () => {
  const c = new AdaptiveController();
  feed(c, 100, 2000, (s) => {
    s.cpuRatio = 1.05;
  });
  assert.equal(c.snapshot().targets.upload, 5);
  assert.equal(c.snapshot().targets.download, 4);
  for (const condition of ["cpu", "throttle", "sharp"] as const) {
    const transform = new AdaptiveController();
    feed(transform, 100, 4000, (s) => {
      only(s, "transform");
      s.cpuRatio = condition === "cpu" ? 0.9 : 0.5;
      s.cpuThrottled = condition === "throttle";
      s.sharpQueued = condition === "sharp" ? 1 : 0;
    });
    assert.equal(transform.snapshot().targets.transform, 1);
    assert.equal(transform.snapshot().probe, null);
    feed(transform, 4100, 6000, (s) => only(s, "transform"));
    assert.equal(transform.snapshot().targets.transform, 2);
    feed(transform, 6100, 6200, (s) => {
      s.cpuRatio = 1;
    });
    assert.equal(transform.snapshot().targets.transform, 2);
  }
  const failure = sample(2100);
  failure.transientFailures.upload = 1;
  c.observe(failure);
  assert.equal(c.snapshot().targets.upload, 2);
  assert.equal(c.snapshot().targets.download, 4);
  assert.equal(c.snapshot().probe, null);
  feed(c, 2200, 3000, (s) => {
    s.transientFailures.upload = 1;
  });
  assert.equal(c.snapshot().targets.upload, 1);
});

test("AP05 메모리 제동은 하류 정리를 허용하고 예약 거절과 중단을 지킨다",
  async () => {
    const c = new AdaptiveController();
    const runtime = new PipelineRuntime({...remotePolicy(),
      adjustableLimits: true});
    const images = new Slots(4, true);
    const pressure = sample(100);
    pressure.memory!.usedBytes = 750;
    const state = c.observe(pressure);
    assert.equal(state.paused, true);
    for (const stage of ["download", "transform", "upload"] as const) {
      runtime.setStageLimit(stage, state.limits[stage]);
    }
    images.setLimit(state.limits.images);
    const abort = new AbortController();
    const entered: string[] = [];
    const download = runtime.run("download", async () => {
      entered.push("download");
    }, abort.signal);
    const image = images.run(async () => {
      entered.push("image");
    }, abort.signal);
    await runtime.run("upload", async () => {
      entered.push("upload");
    });
    await runtime.run("paths", async () => {
      entered.push("paths");
    });
    assert.deepEqual(entered, ["upload", "paths"]);
    const rejected = Promise.all([assert.rejects(download),
      assert.rejects(image)]);
    abort.abort();
    await rejected;
    feed(c, 200, 1100);
    assert.equal(c.snapshot().paused, true);
    feed(c, 1200, 1200);
    assert.equal(c.snapshot().paused, false);
    const denied = sample(1300);
    denied.demands.transform.canAdmit = false;
    assert.equal(c.observe(denied).limits.transform, 0);
    const high = new AdaptiveController();
    feed(high, 100, 1000, (s) => {
      s.memory!.usedBytes = 850;
    });
    assert.equal(high.snapshot().stopped, null);
    feed(high, 1100, 1100, (s) => {
      s.memory!.usedBytes = 850;
    });
    assert.equal(high.snapshot().stopped, "sustained-high");
    assert.equal(high.snapshot().limits.upload, 0);
    const backlog = new AdaptiveController();
    feed(backlog, 100, 10000, (s) => {
      for (const axis of ADAPTIVE_AXES) {
        s.demands[axis].downstreamGrowing = true;
      }
    });
    assert.equal(backlog.snapshot().probe, null);
  });

test("AP06 가변 슬롯 취소 실패와 늦은 완료는 실행 중 허용량을 누수하지 않는다",
  async () => {
    const slots = new Slots(1, true);
    const blocker = deferred();
    const abort = new AbortController();
    const first = slots.run(async () => {
      await blocker.promise;
      throw new Error("실행 실패");
    });
    const one = assert.rejects(first, /실행 실패/);
    const second = slots.run(async () => {
      assert.fail("대기 취소됨");
    }, abort.signal);
    const two = assert.rejects(second);
    await turn();
    slots.setLimit(0);
    abort.abort();
    await two;
    assert.equal(slots.snapshot().active, 1);
    assert.equal(slots.snapshot().queued, 0);
    blocker.resolve();
    await one;
    assert.equal(slots.snapshot().active, 0);
    slots.setLimit(1);
    assert.equal(await slots.run(async () => 42), 42);
    assert.equal(slots.snapshot().failed, 1);
    assert.equal(slots.snapshot().completed, 1);
    const aborted = new AbortController();
    aborted.abort();
    await assert.rejects(slots.run(async () => 1, aborted.signal));
    assert.equal(slots.snapshot().active, 0);
  });

test("AP07 가변 변환 큐는 우선순위 맥락과 유한 입력의 완료를 보존한다",
  async () => {
    const queue = new ReadySeasonQueue(true);
    const context = new AsyncLocalStorage<string>();
    const waits = Array.from({length: 4}, deferred);
    const started: string[] = [];
    queue.setLimit(0);
    const pending = [3, 0, 0, 2].map((rank, i) => context.run(String(i), () =>
      queue.run(rank, async () => {
        started.push(`${rank}/${context.getStore()}`);
        await waits[i].promise;
        assert.equal(context.getStore(), String(i));
      })));
    queue.setLimit(2);
    assert.deepEqual(started, ["0/1", "0/2"]);
    queue.setLimit(1);
    waits[1].resolve();
    await turn();
    assert.equal(started.length, 2);
    waits[2].resolve();
    await turn();
    assert.deepEqual(started, ["0/1", "0/2", "2/3"]);
    waits[3].resolve();
    await turn();
    assert.equal(started.at(-1), "3/0");
    waits[0].resolve();
    await Promise.all(pending);
    assert.equal(queue.snapshot().peakActive, 2);
    assert.equal(queue.snapshot().active, 0);
    assert.throws(() => new ReadySeasonQueue().setLimit(2));
    assert.throws(() => queue.setLimit(-1));
    const trace = new ReuseTrace();
    const runtime = new SubmissionRuntime({...remotePolicy(),
      adjustableLimits: true}, trace, true);
    runtime.setStageLimit("transform", 0);
    const work = runtime.withSeason(0, () => trace.target({season: "one",
      target: "post-0", kind: "post"}, () => runtime.run("transform",
      async () => "JPEG")));
    assert.equal(runtime.snapshot().transform?.queued, 1);
    runtime.setStageLimit("transform", 2);
    assert.equal(await work, "JPEG");
    assert.equal(runtime.snapshot().transform?.limit, 2);
    assert.equal(trace.snapshot().find((e) => e.event === "start")?.season,
      "one");
  });

test("AP08 제어 결정 증거는 독립 복사이며 기존 P와 S 계약을 바꾸지 않는다",
  async () => {
    const c = new AdaptiveController();
    feed(c, 100, 2000);
    const records = c.decisions().filter((d) => d.reason === "probe-start");
    assert.equal(records[0].reason, "probe-start");
    assert.equal(records[0].axis, "upload");
    assert.equal(records[0].rates?.upload.count, 20);
    records[0].targets.upload = 999;
    assert.equal(c.decisions().find((d) =>
      d.reason === "probe-start")?.targets.upload, 5);
    const snapshot = c.snapshot();
    snapshot.targets.upload = 999;
    assert.equal(c.snapshot().targets.upload, 5);
    c.stop("cancelled");
    assert.equal(c.observe(sample(2100)).stopped, "cancelled");
    assert.equal(c.decisions().at(-1)?.reason, "stopped");
    assert.equal(c.decisions().at(-1)?.stopped, "cancelled");
    assert.equal(remotePlans().length, 8);
    assert.deepEqual([...new Set(remotePlans().map((p) => p.arm))].sort(),
      ["PP", "SP"]);
    assert.deepEqual(remotePolicy().limits,
      {download: 4, transform: 1, upload: 4, paths: null});
    for (const prioritized of [false, true]) {
      const fixed = new SubmissionRuntime(remotePolicy(), new ReuseTrace(),
        prioritized);
      assert.throws(() => fixed.setStageLimit("transform", 2));
      assert.throws(() => fixed.setStageLimit("download", 0));
      await fixed.withSeason(0, () => fixed.run("transform", async () => 1));
      assert.equal(fixed.snapshot().transform?.limit, 1);
      assert.equal(fixed.snapshot().transform?.completed, 1);
      assert.equal(fixed.snapshot().transform?.active, 0);
    }
  });
