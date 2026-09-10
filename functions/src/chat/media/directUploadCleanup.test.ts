/* eslint-disable require-jsdoc, max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp, type Firestore, type DocumentReference} from "firebase-admin/firestore";
import {cleanupDirectUpload} from "./directUploadCleanup.js";

function fixture(status = "uploading", hasMessage = false) {
  let data: Record<string, unknown> = {contractVersion: 3, roomID: "r", uploadID: "u",
    processingStatus: status, bucket: "qa", cleanupAfter: Timestamp.fromMillis(100),
    targets: [{path: "rooms/r/messages/u/attachments/a/display"}, {path: "unrelated/file"}]};
  const messageRef = {id: "u"};
  const ref = {id: "u", parent: {parent: {collection: () => ({doc: () => messageRef})}}} as unknown as DocumentReference;
  const firestore = {runTransaction: async (operation: (tx: unknown) => unknown) => operation({
    get: async (target: unknown) => target === ref ? {data: () => data} : {exists: hasMessage},
    update: (_: unknown, fields: Record<string, unknown>) => {
      data = {...data, ...fields};
    },
  })} as unknown as Firestore;
  const deleted: string[] = [];
  const run = (nowMillis: number) => cleanupDirectUpload({firestore, ref, nowMillis,
    remove: async (bucket, path) => {
      deleted.push(`${bucket}/${path}`);
    }});
  return {run, deleted, data: () => data};
}

test("URL 만료 전에는 지우지 않고 만료 뒤 자기 manifest만 정리한다", async () => {
  const f = fixture();
  await f.run(99);
  assert.equal(f.deleted.length, 0);
  await f.run(100);
  assert.equal(f.data().processingStatus, "expired");
  assert.deepEqual(f.deleted, ["qa/rooms/r/messages/u/attachments/a/display"]);
  await f.run(101);
  assert.equal(f.deleted.length, 1);
  await f.run(100 + 15 * 60_000);
  assert.equal(f.deleted.length, 2);
});

test("ready 또는 이미 존재하는 정상 메시지는 정리하지 않는다", async () => {
  for (const f of [fixture("ready"), fixture("canceled", true)]) {
    await f.run(1000);
    assert.equal(f.deleted.length, 0);
  }
});
