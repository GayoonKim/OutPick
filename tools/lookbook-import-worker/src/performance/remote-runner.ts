import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import {remoteInputs, remoteInputForPlan} from "./remote-input.js";
import {connectedExecutor, type ConnectedInput} from "./reuse-input.js";
import {RemoteIO, retryableRemote, type RemotePorts} from "./remote-io.js";
import {BufferInventory} from "./buffer-inventory.js";
import {superviseMemory} from "./memory-supervisor.js";
import {readContainerMemory} from "./resources.js";
import {ReuseTrace} from "./reuse-trace.js";
import {SubmissionRuntime} from "./submission-runtime.js";
import {withMeasurement} from "./session.js";
import {type SeasonEvent} from "./season-runner.js";
import {runArrivingSeasons, BRAND_ARRIVAL_INTERVAL_MS}
  from "./arrival-runner.js";
import {remoteArrivalMetrics} from "./remote-arrivals.js";
import {remotePolicy, remoteSeasonPolicy, outputRoot, requestedPlan,
  sha256, REMOTE_RETRY,
  type RemoteCampaign} from "./remote-contract.js";
import type {RemoteRunStore} from "./remote-store.js";
import {REMOTE_GOLDEN_PROFILE, remoteEncoderVersions}
  from "./remote-golden-profile.js";

export async function runRemote(body: unknown, dependencies: {
  campaign: RemoteCampaign; input: ConnectedInput; ports: RemotePorts;
  store: Pick<RemoteRunStore, "claim" | "finish">;
  instanceID: string; revision: string;
  signal?: AbortSignal;
  readMemory?: typeof readContainerMemory;
}) {
  const {campaign, ports, store} = dependencies;
  dependencies.signal?.throwIfAborted();
  const plan = requestedPlan(body);
  const input = remoteInputForPlan(dependencies.input, plan);
  const owner = randomUUID();
  const key = await store.claim(campaign, plan, owner);
  const root = outputRoot(campaign, plan);
  const io = new RemoteIO(input, root,
    `lookbookImportPerformanceRuns/${key}`, ports);
  const timeout = new AbortController();
  const fatal = new AbortController();
  const remaining = Math.min(campaign.runTimeoutMs,
    campaign.expiresAtMs - Date.now());
  const timer = setTimeout(() => timeout.abort(new Error("실험 시간 제한")),
    Math.max(1, remaining));
  const buffers = new BufferInventory();
  const items = remoteInputs(plan);
  const trace = new ReuseTrace({kind: "remote-input-v1", attempts: 5,
    contract: items.map((item) => ({seasonID: item.id,
      targets: Array.from({length: input.golden.find((s) =>
        s.seasonID === item.id)!.assetTargets}, (_, index) =>
        ({id: String(index), kind: "asset"}))}))});
  const attemptErrors: Array<Record<string, unknown>> = [];
  let runtime: SubmissionRuntime | undefined;
  let measurement: Record<string, unknown> | null = null;
  const reports: unknown[] = [];
  const stages = {prepareMs: 0, verifyMs: 0};
  const startedAt = Date.now();
  const supervised = await superviseMemory(async (memorySignal) => {
    const signal = AbortSignal.any([memorySignal, timeout.signal, fatal.signal,
      ...(dependencies.signal ? [dependencies.signal] : [])]);
    signal.throwIfAborted();
    const prepareStart = performance.now();
    await io.prepare(items, signal);
    stages.prepareMs = performance.now() - prepareStart;
    runtime = new SubmissionRuntime({...remotePolicy(plan), signal},
      trace, true);
    const pipeline = runtime;
    const execute = connectedExecutor(input, trace, true, io);
    const events: SeasonEvent[] = [];
    const execution = await buffers.run(() => withMeasurement({enabled: true,
      sourceRevision: campaign.sourceRevision,
      instanceID: dependencies.instanceID, inputDigest: campaign.corpusDigest,
      settingsDigest: sha256(JSON.stringify({plan,
        policy: remotePolicy(plan)})),
      emit: (report) => reports.push(report)}, "remote-connected", () =>
      runArrivingSeasons(items,
        remoteSeasonPolicy(plan), async (item, {attempt}) => {
          io.clearDownloadError(item.id);
          try {
            return await pipeline.withSeason(items.findIndex((s) =>
              s.id === item.id), () => execute(item, pipeline, signal));
          } catch (error) {
            if (signal.aborted) throw error;
            const cause = io.downloadError(item.id) ?? error;
            attemptErrors.push({seasonID: item.id, attempt,
              error: String(cause)});
            if (retryableRemote(cause)) {
              return {status: "retryable",
                retryAfterMs: REMOTE_RETRY.seasonBackoffMs};
            }
            // 입력/출력 불일치 등 비재시도 오류는 비교 회차 전체를 무효화한다.
            fatal.abort(cause);
            throw cause;
          }
        }, {signal, retryWait: ports.wait, onEvent: async (event) => {
          events.push(event);
        }})));
    const {originMs: origin, seasons, arrivals} = execution;
    const wallMs = performance.now() - origin;
    measurement = {wallMs, originMs: origin, seasons, events, arrivals,
      firstSeasonMs: seasons[0].attempts.at(-1)?.endedMs === undefined ?
        null : seasons[0].attempts.at(-1)!.endedMs - origin,
      ...remoteArrivalMetrics(items, seasons, events, origin,
        remoteSeasonPolicy(plan).order === "serial-brands", arrivals,
        remoteSeasonPolicy(plan).concurrency)};
    assert.equal(reports.length, 1, "계측 보고 누락");
    assert.equal(buffers.snapshot().objects, 0);
    assert.equal(pipeline.sourceBuffers?.snapshot().openScopes, 0);
    assert.equal(pipeline.sourceBuffers?.snapshot().retainedBytes, 0);
    assert.ok(seasons.every((season) => season.status === "succeeded"),
      "일부 시즌 처리 실패");
    const expectedFiles = items.reduce((n, item) => n +
      input.golden.find((s) => s.seasonID === item.id)!.uploadFiles, 0);
    const verifyStart = performance.now();
    await io.verify(signal, expectedFiles);
    stages.verifyMs = performance.now() - verifyStart;
  }, {maxSampleGapMs: 500, readMemory: async () => {
    const memory = await (dependencies.readMemory ?? readContainerMemory)();
    return memory?.limitBytes === 2 * 2**30 ? memory : null;
  }}).finally(() => clearTimeout(timer));
  const status = supervised.status === "completed" ? "succeeded" :
    timeout.signal.aborted ? "aborted" : supervised.status;
  const error = "error" in supervised ? String(supervised.error) : null;
  const result = {version: 5, scope: "development-connected-experiment",
    policy: remotePolicy(plan), seasonPolicy: remoteSeasonPolicy(plan),
    inputs: items, arrivalIntervalMs: BRAND_ARRIVAL_INTERVAL_MS,
    goldenProfile: REMOTE_GOLDEN_PROFILE.id,
    campaign, plan, key, status, error, startedAt, endedAt: Date.now(),
    revision: dependencies.revision, instanceID: dependencies.instanceID,
    retry: REMOTE_RETRY, attemptErrors,
    fatalError: fatal.signal.aborted ? String(fatal.signal.reason) : null,
    runtime: {node: process.version, platform: process.platform,
      processUptimeSeconds: process.uptime(),
      arch: process.arch, encoder: remoteEncoderVersions()},
    measurement, stages, reports,
    counts: {...io.counts}, memory: supervised.memory,
    cache: runtime?.sourceBuffers?.snapshot() ?? null,
    slots: runtime?.snapshot() ?? null, buffers: buffers.snapshot(),
    trace: trace.snapshot(), files: [...io.expected], paths: [...io.saved],
    attemptedFiles: [...io.submitted],
    // SDK의 내부 RPC 수와 논리 호출 수를 혼동하지 않는다.
    countScope: "adapter-calls-and-observed-http-body-bytes"};
  const evidence = Buffer.from(JSON.stringify(result));
  assert.ok(evidence.length <= 8 * 2**20, "증거 크기 제한");
  const evidencePath = `${root}result.json`;
  // 증거 저장이나 최종 상태 반영에 실패하면 실행권을 해제하지 않는다.
  await ports.put(evidencePath, evidence);
  await store.finish(campaign, plan, owner, {status, evidencePath,
    continueAllowed: status === "succeeded"});
  return {key, status, evidencePath, counts: result.counts};
}
