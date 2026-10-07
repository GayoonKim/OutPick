import assert from "node:assert/strict";
import test from "node:test";
import {readFile} from "node:fs/promises";
import sharp from "sharp";
import {jpegBytes} from "../processor.js";
import {loadRemoteCorpus, sha256, validateCampaign, CORPUS_DIGEST}
  from "./remote-contract.js";
import {ARM_CORPUS_DIGEST, REMOTE_GOLDEN_PROFILE, assertRemoteGoldenRuntime}
  from "./remote-golden-profile.js";
import {testCampaign} from "./remote-fixture.js";

test("RN13 AMD64 기준은 ARM 입력과 정책을 보존하고 이전 계약을 거부한다",
  async () => {
    const oldBytes = await readFile(new URL(
      "../../fixtures/performance-remote-input.json", import.meta.url));
    assert.equal(sha256(oldBytes), ARM_CORPUS_DIGEST);
    const old = JSON.parse(oldBytes.toString());
    const bytes = await readFile(new URL(
      "../../fixtures/performance-remote-input-amd64.json", import.meta.url));
    assert.equal(sha256(bytes), CORPUS_DIGEST);
    const next = JSON.parse(bytes.toString());
    assert.deepEqual(next.goldenProfile, REMOTE_GOLDEN_PROFILE);
    const restored = structuredClone(next); delete restored.goldenProfile;
    let changed = 0; let files = 0;
    for (const [i, season] of restored.golden.entries()) {
      assert.equal(season.uploadBytes, season.outputs.reduce(
        (n: number, o: {bytes: number}) => n + o.bytes, 0));
      assert.equal(season.uploadFiles, season.outputs.length);
      season.uploadBytes = old.golden[i].uploadBytes;
      for (const [j, output] of season.outputs.entries()) {
        const previous = old.golden[i].outputs[j]; files++;
        if (output.sha256 !== previous.sha256) changed++;
        output.sha256 = previous.sha256; output.bytes = previous.bytes;
      }
    }
    assert.deepEqual(restored, old);
    assert.equal(files, 274); assert.equal(changed, 152);
    assert.deepEqual((await loadRemoteCorpus()).golden, next.golden);
    assert.throws(() => validateCampaign({...testCampaign(),
      corpusDigest: ARM_CORPUS_DIGEST}));
  });

test("RN14 원격 golden은 플랫폼과 인코더 버전 불일치를 거부한다", () => {
  const valid = {platform: "linux", arch: "x64",
    encoder: {sharp: "0.34.5", vips: "8.17.3", mozjpeg: "0826579"}};
  assertRemoteGoldenRuntime(valid);
  for (const invalid of [{...valid, arch: "arm64"},
    {...valid, platform: "darwin"}, {...valid, encoder: {}},
    {...valid, encoder: {...valid.encoder, mozjpeg: "changed"}}]) {
    assert.throws(() => assertRemoteGoldenRuntime(invalid));
  }
});

test("RN15 실제 JPEG 변환은 EXIF 여덟 방향의 회전 반전과 치수를 지킨다",
  async () => {
    const colors = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]];
    const raw = Buffer.alloc(80 * 60 * 3);
    for (let y = 0; y < 60; y++) {
      for (let x = 0; x < 80; x++) {
        const color = colors[(y >= 30 ? 2 : 0) + (x >= 40 ? 1 : 0)];
        color.forEach((v, c) => {
          raw[(y * 80 + x) * 3 + c] = v;
        });
      }
    }
    const quadrants = [[0, 1, 2, 3], [1, 0, 3, 2], [3, 2, 1, 0],
      [2, 3, 0, 1], [0, 2, 1, 3], [2, 0, 3, 1], [3, 1, 2, 0], [1, 3, 0, 2]];
    for (let orientation = 1; orientation <= 8; orientation++) {
      const input = await sharp(raw,
        {raw: {width: 80, height: 60, channels: 3}})
        .withMetadata({orientation}).jpeg({quality: 100}).toBuffer();
      const bytes = await jpegBytes(input, 1920, 90);
      const metadata = await sharp(bytes).metadata();
      assert.equal(metadata.format, "jpeg");
      assert.equal(metadata.orientation, undefined);
      const {data, info} = await sharp(bytes).raw()
        .toBuffer({resolveWithObject: true});
      assert.equal(info.width, orientation >= 5 ? 60 : 80);
      assert.equal(info.height, orientation >= 5 ? 80 : 60);
      const actual = [0, 1, 2, 3].map((q) => {
        const x = Math.floor(info.width * (q % 2 ? 0.75 : 0.25));
        const y = Math.floor(info.height * (q >= 2 ? 0.75 : 0.25));
        const pixel = data.subarray((y * info.width + x) * 3,
          (y * info.width + x) * 3 + 3);
        const distance = colors.map((color) => color.reduce((sum, v, c) =>
          sum + (pixel[c] - v) ** 2, 0));
        return distance.indexOf(Math.min(...distance));
      });
      assert.deepEqual(actual, quadrants[orientation - 1]);
    }
  });
