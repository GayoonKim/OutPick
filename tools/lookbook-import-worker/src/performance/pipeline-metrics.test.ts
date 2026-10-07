import assert from "node:assert/strict";
import test from "node:test";
import sharp from "sharp";
import type {Storage} from "firebase-admin/storage";
import {Response} from "undici";
import {jpegBytes, uploadJPEG} from "../processor.js";
import {resolveContentHashDedupe} from "../extraction/dedupe.js";
import {responseBytes} from "../public-http.js";
import {MetricsRecorder, measured, recordBytes} from "./metrics.js";

const identity = {
  sourceRevision: "a".repeat(40), instanceID: "test",
  mode: "local-assets" as const,
};

test("실제 JPEG 변환은 계측 on off의 출력 바이트와 규격이 같다", async () => {
  const input = await sharp({create: {
    width: 32, height: 48, channels: 3, background: "#2b3853",
  }}).png().toBuffer();
  const expected = await jpegBytes(input, 16, 82);
  const recorder = new MetricsRecorder(identity);
  const actual = await recorder.run(() => jpegBytes(input, 16, 82));
  assert.deepEqual(actual, expected);
  const metadata = await sharp(actual).metadata();
  assert.equal(metadata.format, "jpeg");
  assert.equal(metadata.height, 16);
  const report = recorder.finish("returned");
  assert.equal(report.stages["image.transform"].succeeded, 1);
  assert.equal(report.stages["image.transform"].completedBytes, actual.length);
});

test("실제 업로드 함수는 제출량과 성공량을 분리하고 원래 SDK 옵션을 유지한다", async () => {
  let release!: () => void;
  const released = new Promise<void>((done) => {
    release = done;
  });
  const calls: Array<{path: string; bytes: Buffer; options: unknown}> = [];
  const storage = {bucket: () => ({file: (path: string) => ({
    save: async (bytes: Buffer, options: unknown) => {
      calls.push({path, bytes, options});
      await released;
      if (path === "failure") throw new Error("SDK failure");
    },
  })})} as unknown as Storage;
  const recorder = new MetricsRecorder(identity);
  const work = recorder.run(() => Promise.allSettled([
    uploadJPEG(storage, "success", Buffer.alloc(4)),
    uploadJPEG(storage, "failure", Buffer.alloc(7)),
  ]));
  release();
  await work;
  const report = recorder.finish("returned");
  assert.equal(report.stages["file.upload"].peakActive, 2);
  assert.equal(report.stages["file.upload"].failed, 1);
  assert.equal(report.stages["file.upload"].submittedBytes, 11);
  assert.equal(report.stages["file.upload"].completedBytes, 4);
  assert.deepEqual(calls[0].options, {resumable: false, metadata: {
    contentType: "image/jpeg", cacheControl: "public,max-age=3600",
  }});
});

test("실행별 업로드는 객체 생성 조건과 응답 generation을 보존한다", async () => {
  let options: Record<string, unknown> | null = null;
  const storage = {bucket: () => ({file: () => ({
    metadata: {generation: "108"},
    save: async (_bytes: Buffer, value: Record<string, unknown>) => {
      options = value;
    },
  })})} as unknown as Storage;
  const generation = await uploadJPEG(storage, "unique/write/detail.jpg",
    Buffer.alloc(8), true);
  assert.equal(generation, "108");
  assert.deepEqual(options, {resumable: false,
    preconditionOpts: {ifGenerationMatch: 0}, metadata: {
      contentType: "image/jpeg", cacheControl: "public,max-age=3600",
    }});
});

test("해시 계측 후에도 중복 순서와 다운로드 실패 후보 보존 계약을 유지한다", async () => {
  const candidates = [1, 2, 3].map((n) => ({sourceURL: `https://brand.example/${n}`}));
  const recorder = new MetricsRecorder({...identity, mode: "local-extraction"});
  const result = await recorder.run(() => resolveContentHashDedupe({
    candidates,
    loadBytes: async (candidate) => {
      if (candidate === candidates[2]) throw new Error("download failure");
      return Buffer.from("same bytes");
    },
  }));
  assert.deepEqual(result.candidates, [candidates[0], candidates[2]]);
  assert.equal(result.failureCount, 1);
  assert.equal(result.complete, false);
  assert.equal(recorder.finish("returned").stages["image.hash"].succeeded, 2);
});

test("응답 크기 제한 실패에도 읽은 바이트는 기록한다", async () => {
  const recorder = new MetricsRecorder(identity);
  await assert.rejects(recorder.run(() => measured("image.download", () =>
    responseBytes(new Response("abc"), 2, "image", (n) =>
      recordBytes("image.download", "receivedBytes", n)),
  )));
  const report = recorder.finish("threw");
  assert.equal(report.stages["image.download"].receivedBytes, 3);
  assert.equal(report.stages["image.download"].failed, 1);
});
