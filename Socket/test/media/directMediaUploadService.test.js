import assert from "node:assert/strict";
import test from "node:test";
import {createDirectMediaUploadService, validateDirectSources} from "../../src/media/directMediaUploadService.js";

const sources = count => Array.from({length: count * 2}, (_, index) => ({index,
  attachmentIndex: Math.floor(index / 2), role: index % 2 ? "thumbnail" : "display",
  contentType: "image/jpeg", sizeBytes: index % 2 ? 10 : 100, width: 4032, height: 3024,
  duration: 0, isAnimated: false}));
function fixture() {
  let now = 1000, tail = Promise.resolve(), active = 0, peak = 0, calls = 0;
  const documents = new Map([
    ["Rooms/r", {seq: 5}], ["Rooms/r/members/u", {}],
    ["moderationAccounts/u", {accountStatus: "active", moderationStatus: "active", moderationPrincipalID: "p"}],
    ["userPublicProfiles/u", {nickname: "QA"}]
  ]);
  const objects = new Map();
  const ref = path => ({path, id: path.split("/").at(-1), collection: name => col(`${path}/${name}`),
    get: async () => snap(path)});
  const snap = path => ({exists: documents.has(path), data: () => documents.get(path)});
  const col = path => ({doc: id => ref(`${path}/${id}`)});
  const db = {collection: col, runTransaction: action => {
    const run = tail.then(async () => {
      const writes = [];
      const tx = {get: async r => snap(r.path),
        create: (r, value) => writes.push(() => {assert.equal(documents.has(r.path), false); documents.set(r.path, value);}),
        set: (r, value, option) => writes.push(() => documents.set(r.path, option?.merge ? {...documents.get(r.path), ...value} : value)),
        update: (r, value) => writes.push(() => documents.set(r.path, {...documents.get(r.path), ...value}))};
      const result = await action(tx);
      writes.forEach(w => w());
      return result;
    });
    tail = run.catch(() => {});
    return run;
  }};
  const stamp = n => ({toMillis: () => n, toDate: () => new Date(n)});
  const bucket = {name: "qa", file: path => ({delete: async options => {
    assert.equal(options.ifGenerationMatch, objects.get(path)?.generation);
    objects.delete(path);
  }, getSignedUrl: async options => {
    assert.equal(options.extensionHeaders["x-goog-if-generation-match"], "0");
    return [`https://upload.invalid/${path}`];
  }, getMetadata: async () => {
    calls++; active++; peak = Math.max(peak, active);
    await new Promise(resolve => setImmediate(resolve));
    active--;
    if (!objects.has(path)) throw Object.assign(new Error("missing"), {code: 404});
    return [objects.get(path)];
  }})};
  const service = createDirectMediaUploadService({db, admin: {firestore: {Timestamp: {fromMillis: stamp}}},
    clock: {nowMillis: () => now}, bucket, metadataConcurrency: 4, logger: {info() {}}});
  const args = {roomID: "r", uploadID: "m", senderUID: "u", moderationPrincipalID: "p", clientMutationID: "mutation",
    kind: "images", contract: {attachmentCount: 3}, sources: sources(3)};
  const fill = reservation => reservation.uploads.forEach(t => objects.set(t.path,
    {size: t.sizeBytes, contentType: t.contentType, generation: "1"}));
  return {service, args, documents, objects, fill, setNow: n => {now = n;}, metrics: () => ({calls, peak})};
}

test("30장은 60개 role이며 본 파일만300MB 합산한다", () => {
  assert.equal(validateDirectSources("images", {attachmentCount: 30}, sources(30)).ok, true);
  const files = sources(30).map(f => ({...f, sizeBytes: f.role === "display" ? 10_000_000 : 300_000_000}));
  assert.equal(validateDirectSources("images", {attachmentCount: 30}, files).ok, true);
  files[1].role = "display";
  assert.equal(validateDirectSources("images", {attachmentCount: 30}, files).ok, false);
});

test("사진 본 파일과 썸네일은 각각300MB 경계이며 합산은 본 파일만 검사한다", () => {
  for (const role of ["display", "thumbnail"]) {
    const files = sources(1).map(f => ({...f, sizeBytes: 300_000_000}));
    assert.equal(validateDirectSources("images", {attachmentCount: 1}, files).ok, true);
    files.find(f => f.role === role).sizeBytes++;
    assert.equal(validateDirectSources("images", {attachmentCount: 1}, files).ok, false);
  }
  const files = sources(2).map(f => ({...f, sizeBytes: f.role === "display" ? 150_000_000 : 300_000_000}));
  assert.equal(validateDirectSources("images", {attachmentCount: 2}, files).ok, true);
  files[2].sizeBytes++;
  assert.equal(validateDirectSources("images", {attachmentCount: 2}, files).error, "media_aggregate_too_large");
});

test("영상은 기존350MiB 본 파일과4MiB 썸네일 제한을 유지한다", () => {
  const files = sources(1);
  files[0].contentType = "video/mp4";
  files[0].sizeBytes = 350 * 1024 ** 2;
  files[1].sizeBytes = 4 * 1024 ** 2;
  assert.equal(validateDirectSources("video", {attachmentCount: 1}, files).ok, true);
  files[1].sizeBytes++;
  assert.equal(validateDirectSources("video", {attachmentCount: 1}, files).ok, false);
});

test("누락 썸네일만 복구하고 두 finalize는 하나의 메시지·seq만 생성한다", async () => {
  const f = fixture(), {service, args} = f;
  const reservation = await service.preflight(args);
  assert.equal(reservation.uploads.length, 6);
  f.fill(reservation);
  f.objects.delete(reservation.uploads[1].path);
  const incomplete = await service.finalize(args);
  assert.equal(incomplete.error, "media_upload_incomplete");
  assert.deepEqual(incomplete.missing, [{attachmentID: reservation.uploads[1].attachmentID, role: "thumbnail"}]);
  const retry = await service.preflight(args);
  assert.equal(retry.uploads.length, 1);
  f.fill(retry);
  const results = await Promise.all([service.finalize(args), service.finalize(args)]);
  assert.deepEqual(results.map(r => r.seq), [6, 6]);
  assert.equal(f.documents.get("Rooms/r").seq, 6);
  assert.equal(f.documents.get("Rooms/r/Messages/m").attachments.length, 3);
  const before = f.metrics().calls;
  assert.equal((await service.finalize(args)).processingStatus, "ready");
  assert.equal(f.metrics().calls, before);
  assert.ok(f.metrics().peak <= 8); // 두 독립 요청 각각 최대4
  assert.equal((await service.cancel(args)).processingStatus, "ready");
});

test("파일이 올라와도 최종 권한 철회 또는 취소 뒤 메시지를 만들지 않는다", async () => {
  for (const change of ["ban", "account", "cancel"]) {
    const f = fixture(); f.fill(await f.service.preflight(f.args));
    if (change === "ban") f.documents.set("Rooms/r/bans/p", {isActive: true});
    if (change === "account") f.documents.set("moderationAccounts/u", {accountStatus: "active", moderationStatus: "suspended", moderationPrincipalID: "p"});
    if (change === "cancel") await f.service.cancel(f.args);
    assert.equal((await f.service.finalize(f.args)).ok, false);
    assert.equal(f.documents.has("Rooms/r/Messages/m"), false);
  }
});

test("취소 tombstone은 늦은 예약을 막고 metadata 불일치는 확정하지 않는다", async () => {
  const a = fixture();
  assert.equal((await a.service.cancel(a.args)).processingStatus, "canceled");
  assert.equal((await a.service.preflight(a.args)).ok, false);
  const b = fixture(); const r = await b.service.preflight(b.args); b.fill(r);
  b.objects.get(r.uploads[0].path).size = 99;
  assert.equal((await b.service.finalize(b.args)).error, "media_object_metadata_mismatch");
  assert.equal(b.documents.has("Rooms/r/Messages/m"), false);
});

test("권한 검사 전 정상 픽셀 여부를 서버가 다운로드하거나 재가공하지 않는다", async () => {
  const f = fixture(); f.fill(await f.service.preflight(f.args));
  const result = await f.service.finalize(f.args);
  assert.equal(result.processingStatus, "ready");
  assert.equal(f.metrics().peak, 4);
  // fake bucket에는 download/copy/이미지 처리 API 자체가 없다.
});
