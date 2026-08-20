import assert from "node:assert/strict";
import {mkdtemp, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import path from "node:path";
import test from "node:test";

import {cloudJobEnvironment, readyObjectPath, sha256File} from "./cloudJob.js";

test("Cloud Run Job 환경 계약을 읽는다", () => {
  assert.deepEqual(cloudJobEnvironment({
    CHAT_MEDIA_UPLOAD_PATH: "Rooms/room-1/MediaUploads/upload-1",
    CHAT_MEDIA_LEASE_TOKEN: "lease-1",
    CHAT_MEDIA_KIND: "images",
    CHAT_MEDIA_READY_BUCKET: "ready-bucket",
  }), {
    uploadPath: "Rooms/room-1/MediaUploads/upload-1",
    leaseToken: "lease-1",
    kind: "images",
    readyBucket: "ready-bucket",
  });
});

test("Cloud Run Job 환경이 없으면 로컬 CLI mode를 유지한다", () => {
  assert.equal(cloudJobEnvironment({}), null);
});

test("ready object path는 attachment별 display와 thumbnail로 결정된다", () => {
  assert.equal(
    readyObjectPath("room-1", "upload-1", "attachment-1", "display"),
    "rooms/room-1/messages/upload-1/attachments/attachment-1/display",
  );
  assert.equal(
    readyObjectPath("room-1", "upload-1", "attachment-1", "thumbnail"),
    "rooms/room-1/messages/upload-1/attachments/attachment-1/thumbnail",
  );
});

test("worker는 큰 source를 메모리에 올리지 않고 SHA-256을 검증한다", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "chat-media-sha-"));
  const filePath = path.join(directory, "source");
  try {
    await writeFile(filePath, "OutPick");
    assert.equal(
      await sha256File(filePath),
      "d3c8b2a421d45d656eeec4ed884c38e710742fc2eccf64a953dac556a7c4d690",
    );
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});
