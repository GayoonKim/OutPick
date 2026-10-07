import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {comparisonInputs} from "./comparison.js";
import type {loadFrozenInput} from "./frozen-input.js";
import type {ReusePlan} from "./reuse-comparison.js";
import {analyzeReuseTrace, type TraceEvent} from "./reuse-trace.js";
import {assertLargeContract, largeTraceProfile} from "./large-input.js";

export const PRESSURE_INPUT =
  "a3885d467d8430ca9d40e28b36e163bbb2f1303fb1cad4c37187a79e0b48c05b";
// 승인한 고정 manifest/golden에서 산출한 계약이다. 원본 변경은 새 실험이다.
const CONTRACT_DIGESTS = {
  single: "e2de9aa6d8d7d2fe694e8d50a66df09a6e4359d79a91cc9d97c40776fab5bd62",
  six: "09e31f46a48d76483bcde13c2abdd57d79eff8f20a1e7ba67f3cef40d4323e66",
};
export type ReuseLoad = "single" | "six" | "synthetic-three";
export type InputContract = Array<{seasonID: string;
  hashReads: number; hashBytes: number;
  uploadFiles: number; uploadBytes: number;
  targets: Array<{id: string; kind: "post" | "cover";
    sha256: string; bytes: number}>}>;

type Input = Awaited<ReturnType<typeof loadFrozenInput>>["connectedInput"];
export function contractFor(input: Input, load: ReuseLoad): InputContract {
  return contractForSeasons(input, comparisonInputs(load));
}

export function contractForSeasons(input: Input,
  seasons: Array<{seasonID: string}>): InputContract {
  return seasons.map(({seasonID}) => {
    const season = input.seasons.find((s) => s.seasonID === seasonID);
    const cover = input.covers.find((s) => s.seasonID === seasonID);
    const golden = input.golden.find((s) => s.seasonID === seasonID);
    assert.ok(season && cover && golden);
    const seen = new Set<string>();
    const posts = season.images.filter((i) => {
      if (seen.has(i.sha256)) return false;
      seen.add(i.sha256);
      return true;
    });
    const targets = [...posts.map((p, i) => ({id: `post-${i}`,
      kind: "post" as const, sha256: p.sha256, bytes: p.bytes})),
    {id: `cover-${posts.length}`, kind: "cover" as const,
      sha256: cover.sha256, bytes: cover.bytes}];
    assert.equal(posts.length, golden.uniqueImages);
    assert.equal(targets.length, golden.assetTargets);
    assert.equal(targets.length * 2, golden.uploadFiles);
    return {seasonID, hashReads: season.images.length,
      hashBytes: season.images.reduce((n, i) => n + i.bytes, 0),
      uploadFiles: golden.uploadFiles,
      uploadBytes: golden.uploadBytes, targets};
  });
}

export function assertApprovedContract(value: unknown, load: ReuseLoad):
  asserts value is InputContract {
  assert.equal(createHash("sha256").update(JSON.stringify(value)).digest("hex"),
    CONTRACT_DIGESTS[load === "single" ? "single" : "six"]);
}

export function inspectContractTrace(contract: InputContract,
  events: TraceEvent[], profile?: Parameters<typeof analyzeReuseTrace>[2]) {
  const trace = analyzeReuseTrace(events, contract, profile);
  let reads = 0;
  let readBytes = 0;
  let posts = 0;
  let files = 0;
  let uploadBytes = 0;
  let hashReads = 0;
  let minimumPeakBytes = 0;
  for (const season of contract) {
    let retainedForSeason = 0;
    reads += season.hashReads;
    hashReads += season.hashReads;
    readBytes += season.hashBytes;
    files += season.uploadFiles;
    uploadBytes += season.uploadBytes;
    for (const target of season.targets) {
      if (target.kind === "post") posts++;
      const source = events.find((e) => e.event === "source-ready" &&
        e.season === season.seasonID && e.target === target.id);
      assert.ok(source);
      if (!source.reused) {
        reads++;
        readBytes += target.bytes;
      } else retainedForSeason += target.bytes;
    }
    minimumPeakBytes = Math.max(minimumPeakBytes, retainedForSeason);
  }
  return {trace, reads, readBytes, posts, files, uploadBytes, hashReads,
    minimumPeakBytes};
}

export function validatePressureMetrics(plan: ReusePlan,
  value: Record<string, unknown>, stages: Record<string,
    {succeeded: number; receivedBytes: number; completedBytes: number}>) {
  if (plan.largeInput) assertLargeContract(value.inputContract);
  else {
    assert.ok(plan.load);
    assertApprovedContract(value.inputContract, plan.load);
  }
  const contract = value.inputContract;
  const counts = inspectContractTrace(contract, value.trace as TraceEvent[],
    plan.largeInput ? largeTraceProfile(contract) : undefined);
  const off = plan.budget === "off";
  assert.equal(counts.trace.prepared,
    plan.arm === "prepared" ? contract.length : 0);
  assert.equal(stages["image.download"].succeeded, counts.reads);
  assert.equal(stages["image.download"].receivedBytes, counts.readBytes);
  assert.equal(stages["image.hash"].succeeded, counts.hashReads);
  assert.equal(stages["image.transform"].succeeded, counts.files);
  assert.equal(stages["file.upload"].succeeded, counts.files);
  assert.equal(stages["file.upload"].completedBytes, counts.uploadBytes);
  assert.equal(stages["paths.save"].succeeded, counts.trace.assets);
  if (off) {
    assert.equal(value.cache, null);
    assert.equal(counts.trace.reused, 0);
    return;
  }
  const cache = value.cache as Record<string, number>;
  assert.ok(cache && typeof cache === "object");
  assert.equal(cache.budgetBytes, Number(plan.budget) * 2**20);
  assert.equal(cache.retainedBytes, 0);
  assert.equal(cache.openScopes, 0);
  assert.equal(cache.hits, counts.trace.reused);
  assert.equal(cache.misses, counts.posts - cache.hits);
  assert.ok(Number.isSafeInteger(cache.rejectedByBudget) &&
    cache.rejectedByBudget >= cache.misses &&
    cache.rejectedByBudget <= counts.hashReads);
  assert.ok(Number.isSafeInteger(cache.peakRetainedBytes) &&
    cache.peakRetainedBytes >= counts.minimumPeakBytes &&
    cache.peakRetainedBytes <= cache.budgetBytes &&
    cache.peakRetainedBytes <= contract.reduce((n, s) => n + s.hashBytes, 0));
  if (!plan.largeInput && ["128", "256"].includes(plan.budget)) {
    assert.equal(cache.hits, counts.posts);
    assert.equal(cache.rejectedByBudget, 0);
  }
}
