import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {comparisonInputs} from "./comparison.js";
import type {loadFrozenInput} from "./frozen-input.js";
import {contractForSeasons, PRESSURE_INPUT, type InputContract}
  from "./reuse-contract.js";
import type {TraceProfile} from "./reuse-trace.js";

type Input = Awaited<ReturnType<typeof loadFrozenInput>>["connectedInput"];
export const metadataDigest = (value: unknown) =>
  createHash("sha256").update(JSON.stringify(value)).digest("hex");
export const LARGE_INPUT_DIGEST =
  "920ce1c766e9fdfb6ff0e6b4ec2c211f5b1454353a93316d8348a2035f51948e";
export const LARGE_CONTRACT_DIGEST =
  "60d3d318d6309b2df6b2bde8fe5491c7e1b3c1d2976eb0c9e0bfe1c5135da8b8";
export const largeSeasons = () => Array.from({length: 6}, (_, i) => {
  const id = `synthetic-large-${String(i + 1).padStart(2, "0")}`;
  return {id, seasonID: id, brandID: "synthetic-local-large"};
});
export const largeTraceProfile = (contract: InputContract): TraceProfile =>
  ({kind: "large-input-v1", attempts: 5, contract});

// 원본 픽셀과 읽기 함수를 유지하고 독립 job의 메타데이터만 구성한다.
export function deriveLargeInput(input: Input, baseDigest: string) {
  assert.equal(baseDigest, PRESSURE_INPUT);
  const original = comparisonInputs("six").map((s) => s.seasonID);
  assert.deepEqual(input.seasons.map((s) => s.seasonID), original);
  assert.deepEqual(input.covers.map((s) => s.seasonID), original);
  assert.deepEqual(input.golden.map((s) => s.seasonID), original);
  const mapping = largeSeasons().map((s, i) => ({...s,
    sourceSeasons: original, coverSeason: original[i]}));
  const seasons = mapping.map((s) => ({seasonID: s.seasonID,
    sourceURL: `https://synthetic.invalid/local/${s.seasonID}`,
    htmlSha256: metadataDigest(input.seasons.map((v) => v.htmlSha256)),
    images: input.seasons.flatMap((v) => v.images.map((image) => ({...image}))),
  }));
  const covers = mapping.map((s, i) => ({...input.covers[i],
    seasonID: s.seasonID}));
  const golden = mapping.map((s, i) => {
    const outputs = [...input.golden.flatMap((g) => g.outputs.filter((o) =>
      o.kind === "post")), ...input.golden[i].outputs.filter((o) =>
      o.kind === "cover")].map((o) => ({...o}));
    const uniqueImages = new Set(seasons[i].images.map((v) => v.sha256)).size;
    assert.equal(uniqueImages, input.golden.reduce((n, g) =>
      n + g.uniqueImages, 0), "원본 시즌 사이 중복이면 새 입력 설계 필요");
    assert.equal(outputs.length, (uniqueImages + 1) * 2);
    return {seasonID: s.seasonID, uniqueImages, outputs,
      uploadFiles: outputs.length, assetTargets: uniqueImages + 1,
      uploadBytes: outputs.reduce((n, o) => n + o.bytes, 0)};
  });
  const manifest = {profile: "large-input-v1", baseDigest, mapping,
    seasons, covers, golden,
    variants: {post: [[768, 82], [1920, 90]], cover: [[512, 75], [1600, 88]]}};
  const connectedInput = {seasons, covers, golden, readImage: input.readImage};
  const contract = contractForSeasons(connectedInput, largeSeasons());
  return {manifest, inputDigest: metadataDigest(manifest), contract,
    connectedInput};
}

export function assertLargeContract(value: unknown):
  asserts value is InputContract {
  assert.equal(metadataDigest(value), LARGE_CONTRACT_DIGEST);
}

export function assertLargeInput(value: ReturnType<typeof deriveLargeInput>) {
  assert.equal(value.inputDigest, LARGE_INPUT_DIGEST);
  assert.equal(metadataDigest(value.manifest), LARGE_INPUT_DIGEST);
  assertLargeContract(value.contract);
  assert.deepEqual(contractForSeasons(value.connectedInput, largeSeasons()),
    value.contract);
  assert.deepEqual(value.connectedInput.seasons, value.manifest.seasons);
  assert.deepEqual(value.connectedInput.covers, value.manifest.covers);
  assert.deepEqual(value.connectedInput.golden, value.manifest.golden);
}
