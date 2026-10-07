import assert from "node:assert/strict";
import {mkdtemp, readFile, rename, rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";
import {runQ7Wave, assertQ7WaveEvidence} from "./q7-wave.mjs";
import {openQ7Journal} from "./q7-journal.mjs";
import {createQ7Callable} from "./q7-callable.mjs";

test("QV08 100ms wave는 앞 응답을 기다리지 않고 열 요청을 예약 시각에 시작한다", async () => {
  let time = 1000;
  const started = [], releases = [];
  const running = runQ7Wave(Array.from({length: 10}, (_, index) => index), (item, timing) => {
    started.push({item, at: time, timing});
    return new Promise((resolve) => {
      releases.push(() => resolve(item));
      if (item === 9) for (const release of releases.reverse()) release();
    });
  }, {now: () => time, sleep: async (ms) => { await Promise.resolve(); time += ms; }});
  const result = await running;
  assert.deepEqual(started.map((item) => item.at), Array.from({length: 10}, (_, index) => 1000 + index * 100));
  assert.deepEqual(result.map((item) => item.value), Array.from({length: 10}, (_, index) => index));
  assert.equal(result.at(-1).timing.scheduledAt - result[0].timing.scheduledAt, 900);
});

test("QV08 wave 오류는 신규 접수를 멈추고 시작한 요청 정리를 기다린다", async () => {
  let time = 0, drained = false, release;
  const starts = [];
  const running = runQ7Wave([0, 1, 2], (item) => {
    starts.push(item);
    if (item === 1) throw new Error("intentional-failure");
    return new Promise((resolve) => { release = () => {drained = true; resolve(item);}; });
  }, {now: () => time, sleep: async (ms) => {await Promise.resolve(); time += ms;}});
  // 모든 신규 투입을 판단한 다음에도 최초 요청은 아직 끝나지 않았다.
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(starts, [0, 1]);
  assert.equal(drained, false);
  release();
  await assert.rejects(running, /intentional-failure/);
  assert.equal(drained, true);
});

test("QV08 동시 journal 기록은 모든 전송 상태를 보존하고 저장 오류 후 새 전송을 막는다", async () => {
  const directory = await mkdtemp(join(tmpdir(), "q7-wave-journal-"));
  const journal = await openQ7Journal(directory, "wave-12345678", {});
  try {
    await Promise.all(Array.from({length: 20}, async (_, index) => {
      const requestID = "request-" + index;
      await journal.appendRequest({requestID, callable: "createBrand", payload: {requestID}});
      await journal.updateRequest(requestID, {state: "sent"});
      await journal.updateRequest(requestID, {state: "accepted", response: {requestID}});
    }));
    const saved = JSON.parse(await readFile(journal.path, "utf8"));
    assert.equal(saved.requests.length, 20);
    assert.ok(saved.requests.every((item) => item.state === "accepted"));
    await rename(directory, directory + "-hold");
    await assert.rejects(journal.appendRequest({requestID: "io-failed", payload: {}}), {code: "ENOENT"});
    await rename(directory + "-hold", directory);
    await assert.rejects(journal.appendRequest({requestID: "must-not-send", payload: {}}), {code: "ENOENT"});
    assert.equal(JSON.parse(await readFile(journal.path, "utf8")).requests.length, 20);
  } finally {await journal.close(); await rm(directory, {recursive: true, force: true});}
});

test("QV08 HTTP 직전 기록은 비밀을 전달하지 않고 기록 실패 시 실제 호출을 막는다", async () => {
  let requests = 0;
  const call = createQ7Callable({getToken: async () => ({uid: "uid", idToken: "secret"}),
    onDispatch: async (event) => {
      assert.deepEqual(Object.keys(event).sort(), ["name", "recordedAt", "requestID"]);
      assert.equal(event.requestID, "request");
      assert.doesNotMatch(JSON.stringify(event), /secret/);
      throw new Error("recording-failed");
    }, fetchImpl: async () => {requests++;}});
  await assert.rejects(call("createBrand", {requestID: "request"}), /recording-failed/);
  assert.equal(requests, 0);
});

test("QV08 실제 wave는 서버 순번과 브랜드 대기를 확인하고 누락 또는 중첩을 거부한다", () => {
  const requests = [], batches = [], waves = [];
  for (const [waveIndex, name] of ["discovery", "imports"].entries()) {
    const origin = waveIndex * 10000;
    const timings = [];
    for (let index = 0; index < 10; index++) {
      const timing = {name, index, scheduledAt: origin + index * 100,
        invokedAt: origin + index * 100 + 5, intervalMs: 100};
      timings.push(timing);
      const id = name + index;
      // 응답 순서와 무관한 서버 순번을 검증한다.
      const sequence = index === 1 ? 2 : index === 2 ? 1 : index;
      requests.push({requestID: id, wave: timing, httpIntentRecordedAt: timing.invokedAt + 2,
        state: "accepted", response: {batchID: id}});
      batches.push({id, requestID: id, kind: name === "discovery" ? "discoverSeasons" : "importSeasons",
        brandID: "brand-" + index, createdAt: origin + 1500 + index * 10, sequence,
        runs: [{startedAt: origin + 2000 + sequence * 1000, finishedAt: origin + 3000 + sequence * 1000}]});
    }
    waves.push({name, timings});
  }
  const result = assertQ7WaveEvidence(requests, batches, waves);
  assert.deepEqual(result[0].serverOrder, [0, 2, 1, 3, 4, 5, 6, 7, 8, 9]);
  assert.ok(result.every((entry) => entry.waitingPairs.length > 0));
  const missing = structuredClone(requests); delete missing[0].httpIntentRecordedAt;
  assert.throws(() => assertQ7WaveEvidence(missing, batches, waves), /HTTP_INTENT/);
  const overlap = structuredClone(batches); overlap[1].runs[0].startedAt = 2001;
  assert.throws(() => assertQ7WaveEvidence(requests, overlap, waves), /PROCESSING_OVERLAP/);
  const noWaiting = structuredClone(batches);
  for (const batch of noWaiting) batch.createdAt = batch.runs[0].startedAt;
  assert.throws(() => assertQ7WaveEvidence(requests, noWaiting, waves), /WAITING_NOT_OBSERVED/);
});
