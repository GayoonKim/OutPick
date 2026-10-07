import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {readFile} from "node:fs/promises";
import {comparisonInputs} from "./comparison.js";
import {remoteInputs} from "./remote-input.js";
import {BRAND_ARRIVAL_INTERVAL_MS} from "./arrival-runner.js";
import type {ConnectedInput} from "./reuse-input.js";
import type {SeasonExecutionPolicy} from "./season-runner.js";
import {REMOTE_GOLDEN_PROFILE} from "./remote-golden-profile.js";

export const REMOTE_PROJECT = "outpick-test";
export const REMOTE_BUCKET = "outpick-test.firebasestorage.app";
export const CORPUS_DIGEST =
  "49671fbcd756f733e034bc079cc6911fa6ef18184e9e6206f3c1d0d475fa8f15";
export const REMOTE_RETRY = {seasonAttempts: 5, seasonBackoffMs: 1000,
  imageAttempts: 3, imageBackoffStepMs: 400, imageTimeoutMs: 20000,
  storageAutoRetry: false, storageTimeoutMs: 20000,
  firestoreRPCMs: 20000, firestoreTransactionAttempts: 5};
export const sha256 = (bytes: string | Buffer) =>
  createHash("sha256").update(bytes).digest("hex");
export const remotePolicy = (plan?: RemotePlan) => ({
  assets: {kind: "refill" as const, concurrency: 4},
  hashes: {kind: "refill" as const, concurrency: null},
  limits: {download: plan?.variant === "D8" ? 8 : 4,
    transform: plan?.variant === "T2" ? 2 : 1,
    upload: plan?.variant === "U8" ? 8 : 4, paths: null},
  sourceBufferBudgetBytes: 128 * 2**20,
});
export const REMOTE_ARMS = ["PP", "SP", "PS", "SS"] as const;
export const REMOTE_VARIANTS =
  ["S6", "Sall", "P6", "Pall", "D8", "T2", "U8"] as const;
export type RemoteArm = typeof REMOTE_ARMS[number];
export type RemotePlan = {id: string; arm: RemoteArm;
  variant: "smoke" | typeof REMOTE_VARIANTS[number];
  load: "single" | "ten-brands"; repeat: number;
  purpose: "smoke" | "comparison"};
export function remotePlans(): RemotePlan[] {
  const plans: RemotePlan[] = [{id: "smoke-SP-single-1", arm: "SP",
    variant: "smoke",
    load: "single", repeat: 1, purpose: "smoke"}];
  for (const variant of REMOTE_VARIANTS) {
    plans.push({id: `${variant}-ten-brands-1`, variant,
      arm: variant.startsWith("P") ? "PP" : "SP",
      load: "ten-brands", repeat: 1, purpose: "comparison"});
  }
  return plans;
}
export function remoteSeasonPolicy(value: RemoteArm | RemotePlan):
SeasonExecutionPolicy {
  const arm = typeof value === "string" ? value : value.arm;
  assert.ok(REMOTE_ARMS.includes(arm));
  if (typeof value !== "string" && value.variant.endsWith("all")) {
    return {order: arm === "PP" ? "parallel" : "serial-brands",
      concurrency: null};
  }
  return arm === "PP" ? {order: "parallel", concurrency: 6} :
    arm === "PS" ? {order: "serial-per-brand", concurrency: 6} :
      {order: "serial-brands", concurrency: arm === "SS" ? 1 : 6};
}
export function remotePlanDigest(): string {
  return sha256(JSON.stringify({version: 5, plans: remotePlans(),
    arrivalIntervalMs: BRAND_ARRIVAL_INTERVAL_MS, retry: REMOTE_RETRY,
    inputs: remotePlans().map(remoteInputs),
    policies: remotePlans().map(remotePolicy),
    seasons: remotePlans().map(remoteSeasonPolicy)}));
}
export type RemoteCampaign = {
  version: 5; campaignID: string; corpusDigest: string; planDigest: string;
  sourceRevision: string; sourceDigest: string;
  expiresAtMs: number; runTimeoutMs: number;
};
export function validateCampaign(value: unknown): RemoteCampaign {
  const v = value as RemoteCampaign;
  assert.ok(v && typeof v === "object");
  assert.deepEqual(Object.keys(v).sort(), ["version", "campaignID",
    "corpusDigest", "sourceRevision", "sourceDigest", "expiresAtMs",
    "runTimeoutMs", "planDigest"].sort());
  assert.equal(v.version, 5);
  assert.equal(v.planDigest, remotePlanDigest());
  assert.match(v.campaignID, /^[a-z][a-z0-9-]{7,63}$/);
  assert.equal(v.corpusDigest, CORPUS_DIGEST);
  assert.match(v.sourceRevision, /^[a-f0-9]{40}$/);
  assert.match(v.sourceDigest, /^[a-f0-9]{64}$/);
  assert.ok(Number.isSafeInteger(v.expiresAtMs) && v.expiresAtMs > 0);
  // 실제 시간값은 D4 실행 manifest에서 정한다. 현재 서비스 900초보다 짧게 둔다.
  assert.ok(Number.isSafeInteger(v.runTimeoutMs) &&
    v.runTimeoutMs >= 1000 && v.runTimeoutMs <= 840000);
  return Object.freeze({...v});
}
export function requestedPlan(body: unknown): RemotePlan {
  assert.ok(body && typeof body === "object");
  assert.deepEqual(Object.keys(body), ["runID"]);
  const plan = remotePlans().find((p) =>
    p.id === (body as {runID: unknown}).runID);
  assert.ok(plan, "고정된 열 브랜드 비교 7회와 smoke 1회 이외의 요청입니다.");
  return plan;
}
export function assertRemoteEnvironment(project: string, bucket: string) {
  assert.equal(project, REMOTE_PROJECT);
  assert.equal(bucket, REMOTE_BUCKET);
}
export function remoteRunKey(campaign: RemoteCampaign, plan: RemotePlan) {
  validateCampaign(campaign);
  assert.deepEqual(plan, requestedPlan({runID: plan.id}));
  return `${campaign.campaignID}_${plan.id}`;
}
export function outputRoot(campaign: RemoteCampaign, plan: RemotePlan) {
  remoteRunKey(campaign, plan);
  return `lookbook-import-performance/${campaign.campaignID}/${plan.id}/`;
}
export function assertRemoteRoots(root: string, documents: string) {
  const pattern = "^lookbook-import-performance/" +
    "([a-z][a-z0-9-]{7,63})/([^/]+)/$";
  const match = new RegExp(pattern).exec(root);
  assert.ok(match, "실험 저장 경로가 유효하지 않습니다.");
  requestedPlan({runID: match[2]});
  assert.equal(documents,
    `lookbookImportPerformanceRuns/${match[1]}_${match[2]}`);
}
export async function loadRemoteCorpus(): Promise<ConnectedInput> {
  const bytes = await readFile(new URL(
    "../../fixtures/performance-remote-input-amd64.json", import.meta.url));
  assert.equal(sha256(bytes), CORPUS_DIGEST);
  const value = JSON.parse(bytes.toString()) as ConnectedInput &
    {goldenProfile: unknown};
  assert.deepEqual(value.goldenProfile, REMOTE_GOLDEN_PROFILE);
  assert.deepEqual(value.seasons.map((s) => s.seasonID),
    comparisonInputs("six").map((s) => s.seasonID));
  return {...value, readImage: async () => {
    throw new Error("원격 실험에서 로컬 원본 읽기는 금지됩니다.");
  }};
}
