import assert from "node:assert/strict";
import test from "node:test";
import {setImmediate} from "node:timers/promises";
import {remotePlans, remoteSeasonPolicy, remotePlanDigest, validateCampaign,
  requestedPlan, assertRemoteRoots, outputRoot, remoteRunKey, REMOTE_ARMS}
  from "./remote-contract.js";
import {runSeasons} from "./season-runner.js";
import {comparisonInputs} from "./comparison.js";
import {testCampaign} from "./remote-fixture.js";

test("RN01 열 브랜드 여덟 회차는 고정 순서와 정책 해시로 분리한다", () => {
  const plans = remotePlans();
  assert.equal(plans[0].purpose, "smoke");
  assert.equal(plans.filter((p) => p.purpose === "smoke").length, 1);
  assert.equal(plans.length, 8);
  assert.ok(plans.every((p) => p.repeat === 1));
  assert.deepEqual(plans.map((p) => p.variant),
    ["smoke", "S6", "Sall", "P6", "Pall", "D8", "T2", "U8"]);
  assert.throws(() => validateCampaign({...testCampaign(), version: 4}));
  assert.equal(validateCampaign(testCampaign()).planDigest, remotePlanDigest());
  assert.throws(() => validateCampaign({...testCampaign(), version: 1}));
  assert.throws(() => validateCampaign({...testCampaign(), version: 2}));
  assert.throws(() => validateCampaign({...testCampaign(), planDigest:
    "4917b9bf8a57bc0f03636a8d43c8ffaaea870dae51d3e17817ab66e105b9bb7b"}));
  assert.throws(() => validateCampaign({...testCampaign(), planDigest: "0"}));
  for (const runID of ["P-single-1", "PP-single-1", "SS-six-1",
    "smoke-SS-single-1", "PP-synthetic-three-2", "PP-synthetic-three-6"]) {
    assert.throws(() => requestedPlan({runID}));
  }
  assert.throws(() => validateCampaign({...testCampaign(), version: 3}));
  for (const arm of ["PS", "SS"]) {
    assert.throws(() => requestedPlan({runID: `${arm}-synthetic-three-1`}));
  }
  const campaign = testCampaign();
  for (const arm of REMOTE_ARMS) {
    for (let repeat = 2; repeat <= 5; repeat++) {
      assert.throws(() => requestedPlan({runID:
        `${arm}-synthetic-three-${repeat}`}));
    }
  }
  for (const plan of plans) {
    const root = outputRoot(campaign, plan);
    const documents = `lookbookImportPerformanceRuns/${remoteRunKey(campaign,
      plan)}`;
    assertRemoteRoots(root, documents);
    assert.throws(() => assertRemoteRoots(root, `${documents}-different`));
  }
});

test("RN02 네 구조는 실제 시즌 동시 수와 정리 후 전환을 지킨다", async () => {
  for (const [arm, expected] of [["PP", 6], ["SP", 2],
    ["PS", 3], ["SS", 1]] as const) {
    const inputs = comparisonInputs("synthetic-three");
    let active = 0; let peak = 0;
    const started: string[] = [];
    const ended: string[] = [];
    type Release = () => void;
    const releases = new Map<string, Release>();
    const execute = async (item: {id: string}) => {
      active++; peak = Math.max(peak, active); started.push(item.id);
      await new Promise<void>((resolve) => {
        releases.set(item.id, resolve);
      });
      // 업로드/경로 저장을 포함한 execute의 정리 경계까지 끝나야 반환한다.
      await setImmediate();
      active--; ended.push(item.id);
      return {status: "succeeded" as const};
    };
    const pending = runSeasons(inputs, remoteSeasonPolicy(arm), execute,
      {signal: new AbortController().signal});
    await setImmediate();
    assert.equal(started.length, expected, arm);
    assert.equal(active, expected);
    for (let step = 0; step < inputs.length; step++) {
      const next = started.find((id) => !ended.includes(id));
      assert.ok(next); releases.get(next)!();
      await setImmediate(); await setImmediate();
      if (arm === "SP" || arm === "SS") {
        for (const item of inputs.filter((i) => started.includes(i.id))) {
          const brandIndex = inputs.findIndex((i) =>
            i.brandID === item.brandID);
          assert.ok(inputs.slice(0, brandIndex).every((i) =>
            ended.includes(i.id)));
        }
      }
      if (arm === "PS" || arm === "SS") {
        for (const item of inputs.filter((i) => started.includes(i.id))) {
          const previous = inputs.slice(0, inputs.indexOf(item))
            .filter((i) => i.brandID === item.brandID);
          assert.ok(previous.every((i) => ended.includes(i.id)));
        }
      }
    }
    assert.equal(peak, expected);
    assert.ok((await pending).every((r) => r.status === "succeeded"));
  }
});
