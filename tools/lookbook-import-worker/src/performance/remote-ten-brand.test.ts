import assert from "node:assert/strict";
import test from "node:test";
import {setImmediate} from "node:timers/promises";
import {remotePlans, remotePolicy, remoteSeasonPolicy, loadRemoteCorpus}
  from "./remote-contract.js";
import {remoteInputs, remoteInputForPlan} from "./remote-input.js";
import {SubmissionRuntime} from "./submission-runtime.js";
import {ReuseTrace} from "./reuse-trace.js";
import type {PipelineRuntime} from "../pipeline/resources.js";

test("TB07 열 브랜드 입력은 원본을 세 번 배정하고 가상 작업과 golden을 격리한다",
  async () => {
    const base = await loadRemoteCorpus();
    const plan = remotePlans()[1];
    const items = remoteInputs(plan);
    const mapped = remoteInputForPlan(base, plan);
    assert.equal(items.length, 18);
    assert.equal(new Set(items.map((i) => i.id)).size, 18);
    assert.deepEqual([..."ABCDEFGHIJ"].map((b) =>
      items.filter((i) => i.brandID === `virtual-${b}`).length),
    [8, 2, 1, 1, 1, 1, 1, 1, 1, 1]);
    for (const source of base.seasons) {
      assert.equal(items.filter((i) =>
        i.sourceSeasonID === source.seasonID).length, 3);
    }
    for (const [index, item] of items.entries()) {
      const source = base.seasons.find((s) =>
        s.seasonID === item.sourceSeasonID);
      assert.ok(source);
      assert.deepEqual(mapped.seasons[index], {...source, seasonID: item.id});
      const golden = base.golden.find((g) =>
        g.seasonID === item.sourceSeasonID);
      assert.ok(golden);
      assert.deepEqual(mapped.golden[index], {...golden, seasonID: item.id});
    }
    const url = mapped.seasons[6].images[0].sourceURL;
    mapped.seasons[0].images[0].sourceURL = "changed";
    assert.equal(mapped.seasons[6].images[0].sourceURL, url);
    assert.equal(base.seasons[0].images[0].sourceURL, url);
    assert.throws(() => remoteInputForPlan({...base, covers: []}, plan));
    assert.deepEqual(remoteInputs(remotePlans()[0]).map((i) => i.id),
      ["2026SS"]);
    assert.deepEqual(remotePlans().map((p) => remoteSeasonPolicy(p)), [
      {order: "serial-brands", concurrency: 6},
      {order: "serial-brands", concurrency: 6},
      {order: "serial-brands", concurrency: null},
      {order: "parallel", concurrency: 6},
      {order: "parallel", concurrency: null},
      ...Array.from({length: 3}, () =>
        ({order: "serial-brands", concurrency: 6})),
    ]);
  });

test("TB08 고정 증량 설정은 실제 공용 슬롯에 적용되고 동적 변경은 거부한다",
  async () => {
    for (const [variant, stage, limit] of [["D8", "download", 8],
      ["T2", "transform", 2], ["U8", "upload", 8]] as const) {
      const plan = remotePlans().find((p) => p.variant === variant);
      assert.ok(plan);
      const runtime = new SubmissionRuntime(remotePolicy(plan),
        new ReuseTrace(), true);
      assert.throws(() => runtime.setStageLimit(stage, limit + 1));
      let release!: () => void;
      const blocked = new Promise<void>((resolve) => {
        release = resolve;
      });
      let active = 0;
      const work = Promise.all(Array.from({length: 18}, (_, rank) =>
        runtime.withSeason(rank, () => runtime.run(stage, async () => {
          active++; await blocked; active--;
        }))));
      try {
        await setImmediate();
        assert.equal(active, limit);
      } finally {
        release(); await work;
      }
      const slots = runtime.snapshot() as
        ReturnType<PipelineRuntime["snapshot"]>;
      const snapshot = slots[stage];
      assert.equal(snapshot.limit, limit);
      assert.equal(snapshot.peakActive, limit);
      assert.equal(snapshot.completed, 18);
      assert.equal(snapshot.active, 0);
      assert.equal(snapshot.queued, 0);
    }
  });
