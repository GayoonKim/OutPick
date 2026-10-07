import assert from "node:assert/strict";
import sharp from "sharp";

export const ARM_CORPUS_DIGEST =
  "307bdf7d1b90c04fbcc8ed16307aa7e2ed559cc008207eed8fd487cece676a10";
export const REMOTE_GOLDEN_PROFILE = Object.freeze({
  id: "linux-amd64-sharp0345-vips8173-mozjpeg0826579",
  platform: "linux", arch: "x64", sharp: "0.34.5", vips: "8.17.3",
  mozjpeg: "0826579", sourceCorpusDigest: ARM_CORPUS_DIGEST,
});
export const remoteEncoderVersions = () => ({sharp: sharp.versions.sharp,
  vips: sharp.versions.vips, mozjpeg: sharp.versions.mozjpeg});

// 로컬 호스트는 기준 파일을 읽을 수 있지만 원격 실행 프로세스는 AMD64만 허용한다.
export function assertRemoteGoldenRuntime(value: unknown = {
  platform: process.platform, arch: process.arch,
  encoder: remoteEncoderVersions(),
}) {
  assert.deepEqual(value, {platform: REMOTE_GOLDEN_PROFILE.platform,
    arch: REMOTE_GOLDEN_PROFILE.arch, encoder: {
      sharp: REMOTE_GOLDEN_PROFILE.sharp, vips: REMOTE_GOLDEN_PROFILE.vips,
      mozjpeg: REMOTE_GOLDEN_PROFILE.mozjpeg,
    }}, "AMD64 golden 실행 환경 불일치");
}
