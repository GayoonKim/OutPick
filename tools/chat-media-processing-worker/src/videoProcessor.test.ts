import assert from "node:assert/strict";
import test from "node:test";

import {MediaProcessingError} from "./contracts.js";
import {parseVideoProbe} from "./videoProcessor.js";

test("MP4 H.264/AAC probe와 제거 대상 metadata를 해석한다", () => {
  const probe = parseVideoProbe({
    streams: [
      {codec_type: "video", codec_name: "h264", width: 1280, height: 720},
      {codec_type: "audio", codec_name: "aac"},
      {codec_type: "data", codec_name: "bin_data"},
    ],
    format: {
      format_name: "mov,mp4,m4a,3gp,3g2,mj2",
      duration: "3600.25",
      size: "1048576",
      tags: {title: "private", "com.apple.quicktime.location.ISO6709": "+37.0+127.0/"},
    },
  });

  assert.equal(probe.videoCodec, "h264");
  assert.equal(probe.audioCodec, "aac");
  assert.equal(probe.durationSeconds, 3600.25);
  assert.equal(probe.sourceStreamCount, 3);
  assert.deepEqual(probe.removableMetadataKeys, ["com.apple.quicktime.location.ISO6709", "title"]);
});

test("duration 자체에는 상한을 적용하지 않는다", () => {
  const probe = parseVideoProbe({
    streams: [{codec_type: "video", codec_name: "h264", width: 1280, height: 720}],
    format: {format_name: "mp4", duration: `${7 * 24 * 60 * 60}`, size: "1000"},
  });

  assert.equal(probe.durationSeconds, 604800);
});

test("지원하지 않는 video codec은 unsupportedMedia로 거부한다", () => {
  assert.throws(
    () => parseVideoProbe({
      streams: [{codec_type: "video", codec_name: "vp9", width: 1280, height: 720}],
      format: {format_name: "mp4", duration: "10", size: "1000"},
    }),
    (error: unknown) => error instanceof MediaProcessingError && error.code === "unsupportedMedia",
  );
});
