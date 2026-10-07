import assert from "node:assert/strict";
import test from "node:test";
import {Response} from "undici";
import {Readable} from "node:stream";
import type {FirebaseClients} from "../firebase.js";
import {remoteFirebasePorts, configureRemoteFirestore}
  from "./remote-firebase.js";
import {PipelineRuntime} from "../pipeline/resources.js";
import {connectedExecutor} from "./reuse-input.js";
import {comparisonInputs} from "./comparison.js";
import {remoteInputs, remoteInputForPlan} from "./remote-input.js";
import {remoteFixture, testCampaign} from "./remote-fixture.js";
import {remotePlans, validateCampaign, requestedPlan, loadRemoteCorpus,
  assertRemoteEnvironment, remotePolicy, remoteRunKey, outputRoot}
  from "./remote-contract.js";
import {RemoteIO} from "./remote-io.js";
import {runRemote} from "./remote-runner.js";
import {brandTestMemory} from "./brand-fixture.js";

test("RC01 고정 8회와 원격 입력 요청량을 독립 검증한다", async () => {
  const plans = remotePlans();
  assert.equal(plans.length, 8);
  assert.equal(new Set(plans.map((p) => p.id)).size, 8);
  const input = await loadRemoteCorpus();
  let files = 0;
  let bytes = 0;
  let reads = 0;
  for (const plan of plans) {
    assert.deepEqual(requestedPlan({runID: plan.id}), plan);
    const mapped = remoteInputForPlan(input, plan);
    for (const item of remoteInputs(plan)) {
      const golden = mapped.golden.find((s) => s.seasonID === item.id)!;
      const source = mapped.seasons.find((s) => s.seasonID === item.id)!;
      files += golden.uploadFiles; bytes += golden.uploadBytes;
      reads += source.images.length + golden.assetTargets;
    }
  }
  assert.deepEqual({files, bytes, reads},
    {files: 5816, bytes: 889805586, reads: 5710});
  for (const body of [{runID: "../P"}, {runID: plans[0].id, url: "http://x"}]) {
    assert.throws(() => requestedPlan(body));
  }
  assert.throws(() => validateCampaign({...testCampaign(),
    campaignID: "../x"}));
  assert.throws(() => validateCampaign({...testCampaign(),
    runTimeoutMs: 900000}));
  assert.throws(() => assertRemoteEnvironment("outpick-664ae",
    "outpick-test.firebasestorage.app"));
});

test("RC02 원본 변동은 저장 전에 거부하고 취소 신호를 전달한다", async () => {
  const f = await remoteFixture();
  const plan = remotePlans()[0];
  const campaign = testCampaign();
  const io = new RemoteIO(f.input, outputRoot(campaign, plan),
    `lookbookImportPerformanceRuns/${remoteRunKey(campaign, plan)}`, f.ports);
  f.ports.fetch = async (_url, init) => {
    assert.ok(init.signal);
    return new Response(Buffer.from("changed"));
  };
  const image = f.input.covers[0];
  await assert.rejects(() => io.readImage(image, new AbortController().signal),
    /원본 크기 변경/);
  assert.equal(io.counts.imageGET, 1);
  assert.equal(f.objects.size, 0);
  await assert.rejects(() => io.readImage(image, AbortSignal.abort()));
  assert.equal(io.counts.imageGET, 1);
});

test("RC03 부분 업로드 실패는 형제 종료를 기다리고 경로를 쓰지 않는다", async () => {
  const f = await remoteFixture();
  const campaign = testCampaign(); const plan = remotePlans()[0];
  const io = new RemoteIO(f.input, outputRoot(campaign, plan),
    `lookbookImportPerformanceRuns/${remoteRunKey(campaign, plan)}`, f.ports);
  let release!: () => void;
  const blocked = new Promise<void>((resolve) => {
    release = resolve;
  });
  let started!: () => void;
  const ready = new Promise<void>((resolve) => {
    started = resolve;
  });
  f.ports.put = async (path) => {
    if (path.endsWith("thumb.jpg")) throw new Error("업로드 실패");
    started(); await blocked;
  };
  const runtime = new PipelineRuntime({...remotePolicy()});
  let ended = false;
  const result = connectedExecutor(f.input, undefined, true, io)(
    comparisonInputs("single")[0], runtime, new AbortController().signal)
    .then(() => {
      ended = true; return null;
    }, (e: unknown) => {
      ended = true; return e;
    });
  await ready;
  assert.equal(ended, false);
  assert.equal(io.saved.size, 0);
  release();
  assert.match(String(await result), /업로드 실패/);
  assert.equal(io.saved.size, 0);
  assert.equal(runtime.sourceBuffers?.snapshot().openScopes, 0);
  assert.ok(Object.values(runtime.snapshot()).every((slot) =>
    slot.active === 0 && slot.queued === 0));
});

test("RC04 응답 유실 재업로드는 실제 객체를 검사하며 손상은 거부한다", async () => {
  const f = await remoteFixture();
  const plan = remotePlans()[0]; const campaign = testCampaign();
  const io = new RemoteIO(f.input, outputRoot(campaign, plan),
    `lookbookImportPerformanceRuns/${remoteRunKey(campaign, plan)}`, f.ports);
  const item = comparisonInputs("single")[0];
  const target = {...f.input.seasons.find((s) => s.seasonID === item.id)!
    .images[0], seasonID: item.id, kind: "post"};
  const signal = new AbortController().signal;
  await io.upload(item, 0, target, "thumb", f.bytes, signal);
  await io.upload(item, 0, target, "thumb", f.bytes, signal);
  assert.equal(f.objects.size, 1);
  assert.equal(io.counts.objectReads, 1);
  f.objects.set([...f.objects.keys()][0], Buffer.from("corrupt"));
  await assert.rejects(() =>
    io.upload(item, 0, target, "thumb", f.bytes, signal));
  assert.equal(io.saved.size, 0);
});

test("RC05 두 구조는 실제 adapter 계약을 지나 정리와 재조회까지 완료한다", async () => {
  for (const arm of ["PP", "SP"] as const) {
    const f = await remoteFixture(); const campaign = testCampaign();
    const plan = remotePlans().find((p) =>
      p.arm === arm && p.load === "ten-brands")!;
    let finished = false;
    const result = await runRemote({runID: plan.id}, {campaign, input: f.input,
      ports: f.ports, instanceID: "unit-test", revision: "unit-test",
      readMemory: brandTestMemory.readMemory,
      store: {claim: async () => remoteRunKey(campaign, plan),
        finish: async (_campaign, _plan, _owner, result) => {
          assert.equal(result.continueAllowed, true); finished = true;
        }}});
    assert.equal(result.status, "succeeded");
    assert.equal(finished, true);
    const evidence = JSON.parse(f.objects.get(result.evidencePath)!.toString());
    assert.equal(evidence.buffers.objects, 0);
    assert.equal(evidence.cache.openScopes, 0);
    assert.equal(evidence.cache.retainedBytes, 0);
    assert.equal(evidence.files.length, 72);
    assert.equal(evidence.paths.length, 36);
    assert.equal(evidence.counts.objectReads, 72);
    // 같은 URL이어도18개 독립 작업이 후보2개와 커버1개씩 다운로드한다.
    assert.equal(evidence.counts.imageGET, 54);
    assert.equal(evidence.counts.receivedBytes, f.bytes.length * 54);
    assert.equal(new Set(evidence.files.map((entry: [string, unknown]) =>
      entry[0])).size, 72);
    const events = evidence.measurement.events as Array<{
      event: string; brandID: string; atMs: number}>;
    if (arm === "SP") {
      const brands = [..."ABCDEFGHIJ"].map((b) => `virtual-${b}`);
      for (let i = 1; i < brands.length; i++) {
        const start = events.find((e) =>
          e.event === "brand-start" && e.brandID === brands[i])!;
        const end = events.find((e) =>
          e.event === "brand-end" && e.brandID === brands[i - 1])!;
        assert.ok(start.atMs >= end.atMs);
      }
    }
  }
});

test("RC06 환경 미검증과 증거 저장 실패는 다음 회차를 허용하지 않는다", async () => {
  const f = await remoteFixture(); const campaign = testCampaign();
  const plan = remotePlans()[0];
  let finished = 0;
  const deps = {campaign, input: f.input, ports: f.ports,
    instanceID: "unit-test", revision: "unit-test",
    readMemory: async () => null,
    store: {claim: async () => remoteRunKey(campaign, plan),
      finish: async (_c: unknown, _p: unknown, _o: unknown,
        value: {continueAllowed: boolean}) => {
        assert.equal(value.continueAllowed, false); finished++;
      }}};
  const result = await runRemote({runID: plan.id}, deps);
  assert.equal(result.status, "unavailable");
  assert.equal(finished, 1); assert.equal(result.counts.imageGET, 0);
  f.ports.put = async () => {
    throw new Error("증거 저장 실패");
  };
  await assert.rejects(() => runRemote({runID: plan.id}, deps), /증거 저장 실패/);
  assert.equal(finished, 1);
});

test("RC07 다운로드 내부 세 번과 시즌 총 다섯 시도의 분모를 보존한다", async () => {
  const f = await remoteFixture(); const campaign = testCampaign();
  const plan = remotePlans()[0];
  f.ports.fetch = async () => new Response("busy", {status: 503});
  const result = await runRemote({runID: plan.id}, {campaign, input: f.input,
    ports: f.ports, instanceID: "unit-test", revision: "unit-test",
    readMemory: brandTestMemory.readMemory,
    store: {claim: async () => remoteRunKey(campaign, plan),
      finish: async (_c, _p, _o, result) => {
        assert.equal(result.continueAllowed, false);
      }}});
  const evidence = JSON.parse(f.objects.get(result.evidencePath)!.toString());
  assert.equal(result.status, "failed");
  assert.equal(result.counts.imageGET, 2 * 3 * 5);
  assert.equal(evidence.measurement.seasons[0].attempts.length, 5);
  assert.equal(evidence.attemptErrors.length, 5);
  assert.equal(f.delays.filter((ms) => ms === 1000).length, 4);
  assert.equal(evidence.paths.length, 0);
});

test("RC08 경로 저장 실패와 저장물 손상을 성공으로 처리하지 않는다", async () => {
  const f = await remoteFixture(); const campaign = testCampaign();
  const plan = remotePlans()[0];
  const io = new RemoteIO(f.input, outputRoot(campaign, plan),
    `lookbookImportPerformanceRuns/${remoteRunKey(campaign, plan)}`, f.ports);
  const items = comparisonInputs("single");
  const signal = new AbortController().signal;
  await io.prepare(items, signal);
  const save = f.ports.set;
  f.ports.set = async () => {
    throw new Error("경로 기록 실패");
  };
  const runtime = new PipelineRuntime(remotePolicy());
  await assert.rejects(() => connectedExecutor(f.input, undefined, true, io)(
    items[0], runtime, signal), /경로 기록 실패/);
  assert.equal(io.saved.size, 0);
  f.ports.set = save;
  await connectedExecutor(f.input, undefined, true, io)(
    items[0], runtime, signal);
  await io.verify(signal, 4);
  f.objects.set([...f.objects.keys()][0], Buffer.from("bad"));
  await assert.rejects(() => io.verify(signal, 4));
});

test("RC11 실행 중 HTTP 취소는 fetch까지 전달하고 재시도하지 않는다", async () => {
  const f = await remoteFixture(); const campaign = testCampaign();
  const plan = remotePlans()[0];
  const io = new RemoteIO(f.input, outputRoot(campaign, plan),
    `lookbookImportPerformanceRuns/${remoteRunKey(campaign, plan)}`, f.ports);
  let entered!: () => void;
  const started = new Promise<void>((resolve) => {
    entered = resolve;
  });
  f.ports.fetch = async (_url, {signal}) => {
    assert.ok(signal); entered();
    return new Promise((_resolve, reject) => {
      signal.addEventListener("abort", () => reject(signal.reason),
        {once: true});
    });
  };
  const controller = new AbortController();
  const result = io.readImage(f.input.covers[0], controller.signal);
  const rejected = assert.rejects(result);
  await started;
  controller.abort(new Error("회차 중단"));
  await rejected;
  assert.equal(io.counts.imageGET, 1);
  assert.equal(f.delays.length, 0);
});

test("RC12 Firebase adapter는 객체 조건과 범위를 지키며 재시도를 고정한다", async () => {
  const campaign = testCampaign(); const plan = remotePlans()[0];
  const root = outputRoot(campaign, plan);
  const documents =
    `lookbookImportPerformanceRuns/${remoteRunKey(campaign, plan)}`;
  let options: Record<string, unknown> = {};
  let settings: Record<string, unknown> = {};
  let writes = 0;
  const retryOptions = {autoRetry: true, maxRetries: 3};
  const firebase = {app: {options: {projectId: "outpick-test"}},
    storage: {bucket: () => ({name: "outpick-test.firebasestorage.app",
      storage: {retryOptions}, file: () => ({
        save: async (_bytes: Buffer, opts: Record<string, unknown>) => {
          options = opts; writes++;
        }, createReadStream: () => Readable.from([Buffer.from("jpeg")]),
      })})}, firestore: {
      settings: (value: Record<string, unknown>) => {
        settings = value;
      },
      doc: () => ({set: async () => {
        writes++;
      }}),
    }} as unknown as FirebaseClients;
  configureRemoteFirestore(firebase);
  assert.ok(settings.clientConfig);
  const ports = remoteFirebasePorts(firebase, root, documents);
  await ports.put(`${root}test.jpg`, Buffer.from("jpeg"));
  assert.deepEqual(options.preconditionOpts, {ifGenerationMatch: 0});
  assert.equal(options.timeout, 20000);
  assert.deepEqual(retryOptions, {autoRetry: false, maxRetries: 0});
  assert.equal((await ports.get(`${root}test.jpg`)).toString(), "jpeg");
  await assert.rejects(() =>
    ports.put("brands/real/cover.jpg", Buffer.from("x")));
  await assert.rejects(() => ports.set("brands/real/seasons/real", {}));
  assert.equal(writes, 1);
});

test("RC13 원본 변동은 현재 형제를 정리하고 다음 브랜드 시작을 막는다", async () => {
  const f = await remoteFixture(); const campaign = testCampaign();
  const plan = remotePlans().find((p) =>
    p.arm === "SP" && p.load === "ten-brands")!;
  f.ports.fetch = async () => new Response("changed");
  const result = await runRemote({runID: plan.id}, {campaign, input: f.input,
    ports: f.ports, instanceID: "unit-test", revision: "unit-test",
    readMemory: brandTestMemory.readMemory,
    store: {claim: async () => remoteRunKey(campaign, plan),
      finish: async (_c, _p, _o, value) => {
        assert.equal(value.continueAllowed, false);
      }}});
  const evidence = JSON.parse(f.objects.get(result.evidencePath)!.toString());
  assert.equal(result.status, "failed");
  assert.match(evidence.fatalError, /원본 크기 변경/);
  assert.deepEqual(evidence.measurement.events.filter((e: {event: string}) =>
    e.event === "brand-start").map((e: {brandID: string}) => e.brandID),
  ["virtual-A"]);
  assert.equal(evidence.paths.length, 0);
  assert.equal(evidence.buffers.objects, 0);
  assert.equal(evidence.cache.openScopes, 0);
  // A의 최초 실행 가능6시즌마다 후보2개이며 다음 브랜드는 시작하지 않는다.
  assert.ok(result.counts.imageGET <= 6 * 2);
});
