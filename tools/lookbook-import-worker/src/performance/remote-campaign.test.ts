import assert from "node:assert/strict";
import test from "node:test";
import {remoteFixture, testCampaign} from "./remote-fixture.js";
import {brandTestMemory} from "./brand-fixture.js";
import {remotePlans, remoteRunKey, REMOTE_ARMS}
  from "./remote-contract.js";
import {runRemote} from "./remote-runner.js";
import {readRemoteSample, remoteStatistics} from "./remote-report.js";
import {runRemoteCampaign, remoteRunCost, validateRemoteExecution,
  type RemoteExecution, type RemoteJournal, type CampaignPorts}
  from "./remote-campaign.js";
import {assertRemoteTarget, REMOTE_AUDIENCE, REMOTE_CALLER,
  REMOTE_SERVICE} from "./remote-target.js";

async function hostFixture() {
  const f = await remoteFixture();
  const execution: RemoteExecution = {campaign: testCampaign(),
    targetURL: `https://test---${REMOTE_SERVICE}-xyenspjiwa-du.a.run.app`,
    revision: `${REMOTE_SERVICE}-test`, imageDigest: `sha256:${"c".repeat(64)}`,
    externalCostUSD: 0.3};
  const calls: string[] = []; const journals: RemoteJournal[] = [];
  const ports: CampaignPorts = {now: Date.now,
    checkpoint: async (journal) => {
      journals.push(structuredClone(journal));
    },
    call: async (plan) => {
      calls.push(plan.id);
      return runRemote({runID: plan.id}, {campaign: execution.campaign,
        input: f.input, ports: f.ports, instanceID: "test-instance",
        revision: execution.revision, readMemory: brandTestMemory.readMemory,
        store: {claim: async () => remoteRunKey(execution.campaign, plan),
          finish: async () => undefined}});
    },
    evidence: async (path) => {
      const value = JSON.parse(f.objects.get(path)!.toString());
      // 호스트 계약 검사만 위한 주입값이다. Cloud Run 실행 증거가 아니다.
      value.runtime.platform = "linux"; value.runtime.arch = "x64";
      return value;
    },
  };
  return {...f, execution, calls, journals, ports};
}

test("RN03 8회 실행은 실제 변환 저장 재검증을 거쳐 smoke를 집계에서 뺀다",
  async () => {
    const f = await hostFixture();
    const result = await runRemoteCampaign(f.execution, f.input, f.ports);
    assert.equal(result.state, "completed", result.reason ?? "");
    assert.deepEqual(f.calls, remotePlans().map((p) => p.id));
    assert.equal(result.samples.length, 8);
    assert.equal(result.summary.smoke, "succeeded");
    assert.equal(result.summary.notRun.length, 0);
    assert.ok(result.summary.groups.every((g) =>
      g.planned === 1 && g.succeeded === 1 && g.recorded === 1));
    assert.ok(result.summary.comparisons.every((c) => c.comparable));
    assert.ok(result.estimatedUSD > f.execution.externalCostUSD);
    assert.equal(f.journals.filter((j) => j.state === "requesting").length, 8);
  });

test("RN04 증거의 해시 경로 정책 정리 상태와 버전 위조는 거부한다",
  async () => {
    const f = await hostFixture();
    const response = await f.ports.call(remotePlans()[0],
      new AbortController().signal) as {evidencePath: string};
    const value = await f.ports.evidence(response.evidencePath,
      new AbortController().signal);
    const valid = () => JSON.parse(JSON.stringify(value));
    const bad = [
      {...valid(), version: 1},
      {...valid(), version: 2},
      {...valid(), version: 3},
      {...valid(), version: 4},
      {...valid(), inputs: []},
      {...valid(), arrivalIntervalMs: 5000},
      {...valid(), policy: {...valid().policy, limits: {transform: 8}}},
      {...valid(), seasonPolicy: {order: "parallel", concurrency: null}},
      {...valid(), goldenProfile: "arm64"},
      {...valid(), runtime: {...valid().runtime, encoder: {sharp: "other"}}},
      {...valid(), campaign: {...f.execution.campaign, planDigest: "x"}},
      {...valid(), files: []}, {...valid(), paths: []},
      {...valid(), buffers: {objects: 1}},
      {...valid(), counts: {...valid().counts, uploadedBytes: -1}},
      {...valid(), memory: {...valid().memory, samples: 0}},
    ];
    const corrupt = valid(); corrupt.files[0][1].sha256 = "0".repeat(64);
    bad.push(corrupt);
    const early = valid();
    early.measurement.arrivals[0].arrivedMs =
      early.measurement.originMs - 1;
    bad.push(early);
    const wrongWait = valid();
    wrongWait.measurement.brands[0].queueWaitMs = -1;
    bad.push(wrongWait);
    for (const item of bad) {
      assert.throws(() =>
        readRemoteSample(f.execution.campaign, f.input, item));
    }
  });

test("RN05 약식 집계는 단일 관측만 비교하고 채택과 반복 악화를 판정하지 않는다",
  async () => {
    const f = await hostFixture();
    const result = await runRemoteCampaign(f.execution, f.input, f.ports);
    assert.equal(result.state, "completed");
    const samples = result.samples.map((s) => ({...s, wallMs: 100,
      firstSeasonMs: 50, firstBrandMs: 80}));
    for (const s of samples) {
      if (s.plan.variant === "Sall") {
        s.wallMs = 120; s.firstSeasonMs = 60; s.firstBrandMs = 96;
      }
    }
    samples[0].wallMs = 99999;
    const summary = remoteStatistics(samples);
    assert.equal(summary.mode, "screening");
    assert.equal(summary.adoption, "not-assessed");
    assert.equal(summary.repeatedRegression, "not-assessed");
    assert.equal(summary.failureRateImprovement, "not-assessed");
    assert.equal(summary.groups[0].observed!.wallMs, 100);
    const slower = summary.comparisons.find((c) => c.variant === "Sall")!;
    assert.equal(slower.wall!.baselineMs, 100);
    assert.equal(slower.wall!.candidateMs, 120);
    assert.ok(Math.abs(slower.wall!.changePercent! - 20) < 1e-10);
    assert.equal(summary.comparisons.length, 6);
    assert.ok(!Object.hasOwn(slower, "speedCandidate"));
    assert.ok(!Object.hasOwn(slower.wall!, "withholdAdoption"));
    assert.ok(summary.groups.every((g) => !Object.hasOwn(g, "medianMs")));
    assert.throws(() => remoteStatistics([...samples, samples[0]]));
    const incomplete = remoteStatistics(samples.slice(0, -1));
    assert.equal(incomplete.comparisons[5].comparable, false);
    const unknown = remoteStatistics(samples.slice(0, -1),
      [samples.at(-1)!.id]);
    assert.equal(unknown.groups.find((g) => g.variant === "U8")!.notRun, 0);
    assert.equal(unknown.groups.find((g) => g.variant === "U8")!.succeeded, 0);
    const missing = unknown.groups.find((g) => g.variant === "U8")!;
    assert.equal(missing.unconfirmed.length, 1);
    assert.throws(() => remoteStatistics(samples, [samples[0].id]));
    const failed = structuredClone(samples);
    failed.find((s) => s.plan.variant === "Sall")!.status = "failed";
    assert.equal(remoteStatistics(failed).groups[1].observed, null);
    assert.equal(remoteStatistics(failed).comparisons[0].wall, null);
    const mismatched = structuredClone(samples);
    mismatched.find((s) => s.plan.variant === "Sall")!.runtime.arch = "arm64";
    assert.equal(remoteStatistics(mismatched).comparisons
      .find((c) => c.variant === "Sall")!.comparable, false);
  });

test("RN06 응답 유실과 잘못된 증거는 재호출하지 않고 종료 미확인으로 남긴다",
  async () => {
    for (const failure of ["response", "evidence"] as const) {
      const f = await hostFixture();
      const call = f.ports.call;
      f.ports.call = async (...args) => {
        const response = await call(...args);
        if (failure === "response") throw new Error("응답 유실");
        return response;
      };
      if (failure === "evidence") f.ports.evidence = async () => ({version: 1});
      const result = await runRemoteCampaign(f.execution, f.input, f.ports);
      assert.equal(result.state, "halted");
      assert.equal(f.calls.length, 1);
      assert.deepEqual(result.unconfirmed, [remotePlans()[0].id]);
      assert.equal(result.summary.smoke, "unconfirmed");
      assert.equal(result.summary.notRun.length, 7);
    }
  });

test("RN07 시간 비용 취소 기록 실패는 다음 요청 전에 차단한다",
  async () => {
    const reasons = ["expired", "cost", "cancelled", "checkpoint"] as const;
    for (const reason of reasons) {
      const f = await hostFixture();
      if (reason === "expired") f.execution.campaign.expiresAtMs = 1;
      if (reason === "cost") f.execution.externalCostUSD = 9.99999;
      if (reason === "checkpoint") {
        f.ports.checkpoint = async () => {
          throw new Error("증거 기록 실패");
        };
      }
      const operation = runRemoteCampaign(f.execution, f.input, f.ports,
        reason === "cancelled" ? AbortSignal.abort() : undefined);
      if (reason === "checkpoint") await assert.rejects(operation);
      else assert.equal((await operation).state, "halted");
      assert.equal(f.calls.length, 0);
    }
    const f = await hostFixture();
    let now = Date.now(); f.ports.now = () => now;
    const call = f.ports.call;
    f.ports.call = async (...args) => {
      const result = await call(...args); now += 7200001; return result;
    };
    const result = await runRemoteCampaign(f.execution, f.input, f.ports);
    assert.equal(result.state, "halted"); assert.equal(f.calls.length, 1);
    assert.equal(result.reason, "time-limit");
  });

test("RN08 실패한 smoke와 리비전 불일치는 본 비교를 시작하지 않는다",
  async () => {
    for (const mode of ["failed", "revision"] as const) {
      const f = await hostFixture();
      const evidence = f.ports.evidence;
      const call = f.ports.call;
      if (mode === "failed") {
        f.ports.call = async (...args) => ({...await call(...args) as object,
          status: "failed"});
      }
      f.ports.evidence = async (...args) => {
        const value = await evidence(...args) as Record<string, unknown>;
        if (mode === "failed") value.status = "failed";
        else value.revision = "another-revision";
        return value;
      };
      const result = await runRemoteCampaign(f.execution, f.input, f.ports);
      assert.equal(result.state, "halted"); assert.equal(f.calls.length, 1);
      assert.equal(result.summary.groups.reduce((n, g) =>
        n + g.recorded, 0), 0);
    }
  });

test("RN09 대상 검증은 기본 트래픽과 다른 자원 이미지를 거부한다",
  async () => {
    const f = await hostFixture(); const e = f.execution;
    const service = {metadata: {name: REMOTE_SERVICE}, status: {traffic: [
      {revisionName: "existing", percent: 100},
      {revisionName: e.revision, tag: "test", url: e.targetURL}]}};
    const revision = {metadata: {name: e.revision,
      annotations: {"autoscaling.knative.dev/maxScale": "1"}},
    spec: {containerConcurrency: 2, timeoutSeconds: 900,
      serviceAccountName:
        "outpick-lookbook-worker-dev@outpick-test.iam.gserviceaccount.com",
      containers: [{image: `image@${e.imageDigest}`,
        resources: {limits: {cpu: "1", memory: "2Gi"}},
        env: Object.entries({OUTPICK_FIREBASE_PROJECT_ID: "outpick-test",
          OUTPICK_FIREBASE_STORAGE_BUCKET: "outpick-test.firebasestorage.app",
          OUTPICK_IMPORT_OIDC_AUDIENCE: REMOTE_AUDIENCE,
          OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL: REMOTE_CALLER,
          OUTPICK_IMPORT_REMOTE_CAMPAIGN: JSON.stringify(e.campaign)})
          .map(([name, value]) => ({name, value}))}]}};
    assertRemoteTarget(e, service, revision);
    assert.throws(() => validateRemoteExecution({...e,
      targetURL: REMOTE_AUDIENCE}));
    assert.throws(() => assertRemoteTarget(e, service, {...revision,
      spec: {...revision.spec, containerConcurrency: 3}}));
    assert.throws(() => assertRemoteTarget(e, service, {...revision,
      metadata: {...revision.metadata, annotations: {
        "autoscaling.knative.dev/maxScale": "20"}}}));
    assert.throws(() => assertRemoteTarget({...e,
      imageDigest: `sha256:${"0".repeat(64)}`}, service, revision));
    assert.throws(() => assertRemoteTarget(e, {...service, status: {traffic: [
      {...service.status.traffic[1], percent: 100}]}}, revision));
    assert.equal(REMOTE_ARMS.length, 4);
  });

test("RN10 비용은 무료 차감 없이 준비 저장 검증과 제어 여유를 합산한다", () => {
  const actual = remoteRunCost({uploadCalls: 274, uploadedBytes: 42259800,
    objectReads: 274, documentReads: 268, documentWrites: 274}, 60000);
  const expected = 60 * 0.0000406 + 275 * 0.005 / 1000 +
    275 * 0.0004 / 1000 + 298 * 0.038 / 100000 + 280 * 0.115 / 100000 +
    (42259800 + 8 * 2**20) / 2**30 * 720 * 0.000031507 + 8 / 1024 * 0.12;
  assert.equal(actual, expected);
  assert.throws(() => remoteRunCost({uploadCalls: -1}, 10));
});
