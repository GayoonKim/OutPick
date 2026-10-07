import assert from "node:assert/strict";
import {remoteInputs, remoteInputForPlan} from "./remote-input.js";
import {remotePlans, outputRoot, remoteRunKey, validateCampaign,
  type RemoteCampaign, type RemotePlan} from "./remote-contract.js";
import {readRemoteSample, remoteStatistics, type RemoteSample}
  from "./remote-report.js";
import type {ConnectedInput} from "./reuse-input.js";

export const REMOTE_WINDOW_MS = 2 * 60 * 60 * 1000;
export const REMOTE_COST_LIMIT_USD = 10;
export type RemoteExecution = {
  campaign: RemoteCampaign; targetURL: string; revision: string;
  imageDigest: string; externalCostUSD: number;
};
export function validateRemoteExecution(value: RemoteExecution) {
  validateCampaign(value.campaign);
  assert.deepEqual(Object.keys(value).sort(), ["campaign", "targetURL",
    "revision", "imageDigest", "externalCostUSD"].sort());
  assert.match(value.targetURL, new RegExp("^https://[a-z][a-z0-9-]+---" +
    "lookbook-import-worker-development-xyenspjiwa-du\\.a\\.run\\.app$"));
  assert.match(value.revision,
    /^lookbook-import-worker-development-[a-z0-9-]+$/);
  assert.match(value.imageDigest, /^sha256:[a-f0-9]{64}$/);
  assert.ok(Number.isFinite(value.externalCostUSD) &&
    value.externalCostUSD >= 0 &&
    value.externalCostUSD < REMOTE_COST_LIMIT_USD);
}

// 무료 차감 전 계획 단가. 실제 청구/RPC 측정치가 아닌 보수적인 작업 비용 추정이다.
export function remoteRunCost(counts: Record<string, number>,
  elapsedMs: number) {
  for (const n of [...Object.values(counts), elapsedMs]) {
    assert.ok(Number.isFinite(n) && n >= 0);
  }
  for (const key of ["uploadedBytes", "uploadCalls", "objectReads",
    "documentReads", "documentWrites"]) {
    assert.ok(Object.hasOwn(counts, key));
  }
  const bytes = counts.uploadedBytes + 8 * 2**20;
  return (elapsedMs / 1000) * 0.0000406 +
    (counts.uploadCalls + 1) * 0.005 / 1000 +
    (counts.objectReads + 1) * 0.0004 / 1000 +
    (counts.documentReads + 30) * 0.038 / 100000 +
    (counts.documentWrites + 6) * 0.115 / 100000 +
    bytes / 2**30 * 720 * 0.000031507 +
    8 / 1024 * 0.12;
}
function projectedRunCost(input: ConnectedInput, plan: RemotePlan,
  campaign: RemoteCampaign) {
  const mapped = remoteInputForPlan(input, plan);
  const golden = remoteInputs(plan).map((item) =>
    mapped.golden.find((g) => g.seasonID === item.id)!);
  const files = golden.reduce((n, g) => n + g.uploadFiles, 0);
  const bytes = golden.reduce((n, g) => n + g.uploadBytes, 0);
  // 시즌 5회와 이미 존재하는 객체 검사를 포함한다. 실제 결제 상한은 아니다.
  return remoteRunCost({uploadCalls: files * 5, uploadedBytes: bytes * 5,
    objectReads: files * 6, documentReads: files * 5,
    documentWrites: files * 5}, campaign.runTimeoutMs + 60000);
}
export type RemoteJournal = {
  version: 5; execution: RemoteExecution; startedAtMs: number;
  state: "ready" | "requesting" | "completed" | "halted";
  activeRun: string | null; reason: string | null;
  estimatedUSD: number; unconfirmed: string[]; samples: RemoteSample[];
  summary: ReturnType<typeof remoteStatistics>;
};
export type CampaignPorts = {
  now: () => number;
  call: (plan: RemotePlan, signal: AbortSignal) => Promise<unknown>;
  evidence: (path: string, signal: AbortSignal) => Promise<unknown>;
  checkpoint: (journal: RemoteJournal) => Promise<void>;
};

export async function runRemoteCampaign(execution: RemoteExecution,
  input: ConnectedInput, ports: CampaignPorts,
  cancellation?: AbortSignal): Promise<RemoteJournal> {
  validateRemoteExecution(execution);
  const campaign = execution.campaign;
  const journal: RemoteJournal = {version: 5, execution,
    startedAtMs: ports.now(), state: "ready", activeRun: null, reason: null,
    estimatedUSD: execution.externalCostUSD, unconfirmed: [], samples: [],
    summary: remoteStatistics([])};
  const checkpoint = async () => {
    journal.summary = remoteStatistics(journal.samples, journal.unconfirmed);
    await ports.checkpoint(structuredClone(journal));
  };
  await checkpoint();
  for (const plan of remotePlans()) {
    const remaining = Math.min(campaign.expiresAtMs,
      journal.startedAtMs + REMOTE_WINDOW_MS) - ports.now();
    const projected = projectedRunCost(input, plan, campaign);
    if (cancellation?.aborted || remaining <= 0 ||
      journal.estimatedUSD + projected >= REMOTE_COST_LIMIT_USD) {
      journal.state = "halted";
      journal.reason = cancellation?.aborted ? "cancelled" :
        remaining <= 0 ? "time-limit" : "estimated-cost-limit";
      await checkpoint(); return journal;
    }
    journal.activeRun = plan.id; journal.state = "requesting";
    // 요청 전 증거 저장 실패 시 HTTP를 보내지 않는다. 재시작 자동 인계도 없다.
    await checkpoint();
    const signal = AbortSignal.any([
      AbortSignal.timeout(Math.max(1, Math.floor(Math.min(remaining,
        campaign.runTimeoutMs + 60000)))),
      ...(cancellation ? [cancellation] : []),
    ]);
    const started = ports.now();
    try {
      const response = await ports.call(plan, signal) as
        {key?: unknown; evidencePath?: unknown; status?: unknown};
      assert.equal(response.key, remoteRunKey(campaign, plan));
      const path = `${outputRoot(campaign, plan)}result.json`;
      assert.equal(response.evidencePath, path);
      const sample = readRemoteSample(campaign, input,
        await ports.evidence(path, signal));
      assert.equal(sample.id, plan.id);
      assert.equal(response.status, sample.status);
      assert.equal(sample.runtime.revision, execution.revision);
      assert.equal(sample.runtime.platform, "linux");
      assert.equal(sample.runtime.arch, "x64");
      journal.samples.push(sample);
      journal.estimatedUSD += remoteRunCost(sample.counts,
        Math.max(sample.elapsedMs, ports.now() - started));
      journal.activeRun = null;
      if (sample.status !== "succeeded") {
        journal.state = "halted"; journal.reason = `run-${sample.status}`;
      } else if (journal.estimatedUSD >= REMOTE_COST_LIMIT_USD) {
        journal.state = "halted"; journal.reason = "estimated-cost-limit";
      }
    } catch (error) {
      // 응답 유실·잘못된 증거는 이미 실행했을 수 있다. 재호출하지 않는다.
      journal.state = "halted"; journal.reason = String(error);
      journal.unconfirmed.push(plan.id);
      journal.estimatedUSD += projected;
    }
    if (journal.state === "halted") {
      await checkpoint(); return journal;
    }
    journal.state = "ready"; await checkpoint();
  }
  journal.state = "completed"; await checkpoint();
  return journal;
}
