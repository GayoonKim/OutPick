import assert from "node:assert/strict";
import test from "node:test";
import {createDirectMediaUploadService, validateDirectSources} from "../../src/media/directMediaUploadService.js";

const sources = count => Array.from({length: count * 2}, (_, index) => ({index,
  attachmentIndex: Math.floor(index / 2), role: index % 2 ? "thumbnail" : "display",
  contentType: "image/jpeg", sizeBytes: index % 2 ? 10 : 100, width: 4032, height: 3024,
  duration: 0, isAnimated: false}));
function fixture(hooks = {}) {
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
    await hooks.delete?.(path, options);
    assert.equal(options.ifGenerationMatch, objects.get(path)?.generation);
    objects.delete(path);
  }, getSignedUrl: async options => {
    await hooks.sign?.(path, options);
    assert.equal(options.extensionHeaders["x-goog-if-generation-match"], "0");
    return [`https://upload.invalid/${path}`];
  }, getMetadata: async () => {
    calls++; active++; peak = Math.max(peak, active);
    try {
      await hooks.metadata?.(path);
      await new Promise(resolve => setImmediate(resolve));
    } finally { active--; }
    if (!objects.has(path)) throw Object.assign(new Error("missing"), {code: 404});
    return [objects.get(path)];
  }})};
  const service = createDirectMediaUploadService({db, admin: {firestore: {Timestamp: {fromMillis: stamp}}},
    clock: {nowMillis: () => now}, bucket, logger: {info() {}}});
  const args = {roomID: "r", uploadID: "m", senderUID: "u", moderationPrincipalID: "p", clientMutationID: "mutation",
    kind: "images", contract: {attachmentCount: 3}, sources: sources(3)};
  const fill = reservation => reservation.uploads.forEach(t => objects.set(t.path,
    {size: t.sizeBytes, contentType: t.contentType, generation: "1"}));
  return {service, args, documents, objects, fill, setNow: n => {now = n;}, metrics: () => ({calls, peak})};
}

test("묶음 크기에 맞춰 전체 객체 확인 후 한번만 확정한다", async () => {
  for (const count of [1, 3, 30]) {
    const f = fixture();
    const args = {...f.args, contract: {attachmentCount: count}, sources: sources(count)};
    f.fill(await f.service.preflight(args));
    const before = f.metrics().calls;
    const pending = f.service.finalize(args);
    assert.equal(f.documents.has("Rooms/r/Messages/m"), false);
    assert.equal((await pending).processingStatus, "ready");
    assert.equal(f.metrics().calls - before, count * 2);
    assert.equal(f.metrics().peak, count * 2);
    assert.equal(f.documents.get("Rooms/r/Messages/m").attachments.length, count);
    await f.service.finalize(args);
    assert.equal(f.documents.get("Rooms/r").seq, 6);
    assert.equal(f.metrics().calls - before, count * 2);
  }
});

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
  assert.ok(f.metrics().peak <= 12); // 두 독립 요청 각각 전체6개
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
  assert.equal(f.metrics().peak, 6);
  // fake bucket에는 download/copy/이미지 처리 API 자체가 없다.
});

function gate(count) {
  let started = 0, notify;
  const allStarted = new Promise(resolve => { notify = resolve; });
  const pending = Array.from({length: count}, () => {
    let resolve, reject;
    const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
    return {promise, resolve, reject};
  });
  return {allStarted, pending, enter() {
    const item = pending[started++];
    assert.ok(item, "대상당 작업은 한 번만 시작해야 합니다.");
    if (started === count) notify();
    return item.promise;
  }};
}

test("서명은 전체60개를 시작하고 역순 완료에도 응답 순서를 유지한다", {timeout: 5000}, async () => {
  const signing = gate(60);
  const f = fixture({sign: () => signing.enter()});
  const args = {...f.args, contract: {attachmentCount: 30}, sources: sources(30)};
  const pending = f.service.preflight(args);
  await signing.allStarted;
  signing.pending.toReversed().forEach(item => item.resolve());
  const reservation = await pending;
  assert.deepEqual(reservation.uploads.map(item => item.index), Array.from({length: 60}, (_, i) => i));
  f.fill(reservation);
  const retry = await f.service.preflight(args);
  assert.deepEqual(retry.uploads, []);
});

test("일부 서명 실패도 진행 중 서명이 모두 끝난 후 반환한다", {timeout: 5000}, async () => {
  const signing = gate(6);
  const f = fixture({sign: () => signing.enter()});
  let settled = false;
  const pending = f.service.preflight(f.args).finally(() => { settled = true; });
  const rejected = assert.rejects(pending, /sign failure/);
  await signing.allStarted;
  signing.pending[0].reject(new Error("sign failure"));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(settled, false);
  signing.pending.slice(1).forEach(item => item.resolve());
  await rejected;
  assert.equal(f.documents.has("Rooms/r/Messages/m"), false);
});

test("서명 도중 취소되면 완료된 URL을 새 응답으로 노출하지 않는다", {timeout: 5000}, async () => {
  const signing = gate(6);
  const f = fixture({sign: () => signing.enter()});
  const pending = f.service.preflight(f.args);
  await signing.allStarted;
  assert.equal((await f.service.cancel(f.args)).processingStatus, "canceled");
  signing.pending.forEach(item => item.resolve());
  const response = await pending;
  assert.equal(response.processingStatus, "canceled");
  assert.deepEqual(response.uploads, []);
});

test("비404 조회 실패는 다른 전체 조회 종료 후 반환하고 메시지를 만들지 않는다", {timeout: 5000}, async () => {
  const reading = gate(6);
  const f = fixture({metadata: () => reading.enter()});
  f.fill(await f.service.preflight(f.args));
  let settled = false;
  const pending = f.service.finalize(f.args).finally(() => { settled = true; });
  const rejected = assert.rejects(pending, /read failure/);
  await reading.allStarted;
  reading.pending[0].reject(Object.assign(new Error("read failure"), {code: 503}));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(settled, false);
  reading.pending.slice(1).forEach(item => item.resolve());
  await rejected;
  assert.equal(f.documents.has("Rooms/r/Messages/m"), false);
  assert.equal(f.documents.get("Rooms/r").seq, 5);
});

test("취소는 전체 삭제를 시작하고 일부 실패 후에도 canceled와 지연 정리를 유지한다", {timeout: 5000}, async () => {
  const deleting = gate(6);
  const f = fixture({delete: () => deleting.enter()});
  f.fill(await f.service.preflight(f.args));
  let settled = false;
  const pending = f.service.cancel(f.args).finally(() => { settled = true; });
  await deleting.allStarted;
  assert.equal(f.documents.get("Rooms/r/MediaUploads/m").processingStatus, "canceled");
  deleting.pending[0].reject(new Error("delete failure"));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(settled, false);
  deleting.pending.slice(1).forEach(item => item.resolve());
  assert.equal((await pending).processingStatus, "canceled");
  assert.equal(f.objects.size, 1);
  assert.equal(f.documents.get("Rooms/r/MediaUploads/m").cleanupStatus, "pending");
  assert.equal(f.documents.has("Rooms/r/Messages/m"), false);
});

test("확정된 메시지의 취소는 정상 파일을 삭제하지 않는다", async () => {
  const f = fixture({delete: () => assert.fail("ready 파일 삭제 금지")});
  f.fill(await f.service.preflight(f.args));
  await f.service.finalize(f.args);
  assert.equal((await f.service.cancel(f.args)).processingStatus, "ready");
  assert.equal(f.objects.size, 6);
});
