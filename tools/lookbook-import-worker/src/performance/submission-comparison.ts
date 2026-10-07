import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import type {LaunchPolicy} from "../pipeline/scheduling.js";
import {comparisonInputs} from "./comparison.js";
import {PRESSURE_INPUT, type InputContract} from "./reuse-contract.js";
import {makeReusePlan, reusePolicy, type ReusePlan}
  from "./reuse-comparison.js";
import type {TraceEvent} from "./reuse-trace.js";

export const SUBMISSION_ARMS = ["U", "R4", "B4", "P4"] as const;
export type SubmissionArm = typeof SUBMISSION_ARMS[number];

export function submissionPolicy(budget: ReusePlan["budget"],
  arm: SubmissionArm) {
  assert.ok(SUBMISSION_ARMS.includes(arm));
  const assets: LaunchPolicy = arm === "U" ?
    {kind: "refill", concurrency: null} : arm === "B4" ?
      {kind: "batch", size: 4, concurrency: null} :
      {kind: "refill", concurrency: 4};
  return {...reusePolicy(budget), assets};
}

export function makeSubmissionPlan(source: Parameters<typeof makeReusePlan>[0]):
  ReusePlan[] {
  const base = makeReusePlan(source)[0];
  assert.equal(source.inputDigest, PRESSURE_INPUT);
  const conditions: Array<{budget: ReusePlan["budget"];
    submissionArm: SubmissionArm}> = [{budget: "off", submissionArm: "U"}];
  for (const budget of ["16", "128"] as const) {
    for (const submissionArm of SUBMISSION_ARMS) {
      conditions.push({budget, submissionArm});
    }
  }
  return Array.from({length: 5}, (_, index) => conditions.map((_, offset) => {
    const setting = conditions[(index + offset) % conditions.length];
    const settings = {...setting, submission: "submission-v1" as const,
      load: "six" as const, diagnostic: "asset-timeline-v1" as const,
      arm: setting.budget === "off" ? "off" as const : "prepared" as const};
    return {...base, ...settings, repeat: index + 1,
      id: `submission-${setting.submissionArm}-${setting.budget}-${index+1}`,
      settingsDigest: createHash("sha256").update(JSON.stringify({
        ...settings, policy: submissionPolicy(setting.budget,
          setting.submissionArm), inputs: comparisonInputs("six"),
        concurrency: 6, inputDigest: PRESSURE_INPUT})).digest("hex")};
  })).flat();
}

// 성공 trace에서 미완료 폭/묶음 경계와 당시 준비된 변환의 선택을 검사한다.
export function inspectSubmissionTrace(events: TraceEvent[],
  contract: InputContract, arm: SubmissionArm) {
  const active = new Map<string, Set<string>>();
  const ended = new Map<string, Set<string>>();
  const cursors = new Map<string, number>();
  const peak = new Map<string, number>();
  const queued = new Map<number, {rank: number; sequence: number}>();
  let running: number | undefined;
  const completions: Array<{season: string; atMs: number}> = [];
  for (const event of events) {
    const rank = contract.findIndex((s) => s.seasonID === event.season);
    assert.ok(rank >= 0);
    const season = contract[rank];
    const open = active.get(season.seasonID) ?? new Set<string>();
    const done = ended.get(season.seasonID) ?? new Set<string>();
    active.set(season.seasonID, open);
    ended.set(season.seasonID, done);
    if (event.event === "asset-start") {
      const cursor = cursors.get(season.seasonID) ?? 0;
      assert.equal(event.target, season.targets[cursor]?.id);
      if (arm === "B4") {
        for (let i = 0; i < Math.floor(cursor / 4) * 4; i++) {
          assert.ok(done.has(season.targets[i].id));
        }
      }
      open.add(String(event.target));
      cursors.set(season.seasonID, cursor + 1);
      assert.ok(arm === "U" || open.size <= 4);
      peak.set(season.seasonID, Math.max(peak.get(season.seasonID) ?? 0,
        open.size));
    }
    if (event.event === "asset-end") {
      assert.ok(open.delete(String(event.target)));
      assert.equal(event.success, true);
      done.add(String(event.target));
    }
    if (event.stage === "transform") {
      assert.ok(Number.isSafeInteger(event.operation));
      const id = Number(event.operation);
      if (event.event === "submit") {
        assert.ok(!queued.has(id));
        queued.set(id, {rank, sequence: id});
      } else if (event.event === "start") {
        assert.equal(running, undefined);
        assert.ok(queued.has(id));
        if (arm === "P4") {
          const chosen = [...queued.entries()].sort((a, b) =>
            a[1].rank - b[1].rank || a[1].sequence - b[1].sequence)[0];
          assert.equal(id, chosen[0]);
        }
        queued.delete(id);
        running = id;
      } else if (event.event === "end") {
        assert.equal(running, id);
        running = undefined;
      }
    }
    if (event.event === "season-end") {
      assert.equal(open.size, 0);
      assert.equal(done.size, season.targets.length);
      completions.push({season: season.seasonID, atMs: event.atMs});
    }
  }
  assert.equal(running, undefined);
  assert.equal(queued.size, 0);
  assert.equal(completions.length, contract.length);
  assert.equal(new Set(completions.map((s) => s.season)).size, contract.length);
  return {peakAssets: Object.fromEntries(peak), completions};
}
