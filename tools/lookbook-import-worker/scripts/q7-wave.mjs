import assert from "node:assert/strict";

// 응답 대기와 접수 시작 시각을 분리한다. 오류 후에도 이미 시작한 요청은 모두 정리한다.
export async function runQ7Wave(items, execute, {intervalMs = 100,
  now = Date.now, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  name = "wave"} = {}) {
  if (!items.length || items.length > 10 || intervalMs !== 100) throw new Error("Q7_WAVE_CONTRACT_INVALID");
  const origin = now(), pending = [];
  let failure = null;
  for (let index = 0; index < items.length; index++) {
    const scheduledAt = origin + index * intervalMs;
    const delay = Math.max(0, scheduledAt - now());
    if (delay) await sleep(delay);
    if (failure) break;
    const timing = {name, index, scheduledAt, invokedAt: now(), intervalMs};
    // 즉시 rejection handler를 연결해 전송 중 오류도 유실하지 않는다.
    pending.push((async () => execute(items[index], timing))().then(
      (value) => ({value, timing}), (error) => { failure ??= error; return {error, timing}; }));
  }
  const settled = await Promise.all(pending);
  if (failure) throw failure;
  if (settled.length !== items.length) throw new Error("Q7_WAVE_INCOMPLETE");
  return settled;
}

// 서버 접수 순번이 실제 FIFO 기준이다. 클라이언트 기록을 서버 도착 시각으로 해석하지 않는다.
export function assertQ7WaveEvidence(requests, batches, waves) {
  return ["discovery", "imports"].map((name) => {
    const wave = waves?.find((entry) => entry.name === name);
    const selected = requests.filter((entry) => entry.wave?.name === name)
      .sort((a, b) => a.wave.index - b.wave.index);
    assert.equal(wave?.timings.length, 10, "Q7_WAVE_TIMINGS_MISSING");
    assert.equal(selected.length, 10, "Q7_WAVE_REQUESTS_MISSING");
    const rows = selected.map((request, index) => {
      assert.equal(request.wave.index, index);
      assert.deepEqual(request.wave, wave.timings[index]);
      assert.equal(request.wave.intervalMs, 100);
      assert.equal(request.wave.scheduledAt, selected[0].wave.scheduledAt + index * 100);
      assert.ok(request.wave.invokedAt >= request.wave.scheduledAt);
      assert.equal(request.state, "accepted");
      assert.ok(Number.isSafeInteger(request.httpIntentRecordedAt) &&
        request.httpIntentRecordedAt >= request.wave.invokedAt, "Q7_HTTP_INTENT_MISSING");
      const batch = batches.find((entry) => entry.id === request.response?.batchID);
      assert.ok(batch && batch.requestID === request.requestID, "Q7_WAVE_RECEIPT_CHANGED");
      assert.equal(batch.kind, name === "discovery" ? "discoverSeasons" : "importSeasons");
      assert.ok(Number.isSafeInteger(batch.createdAt));
      assert.ok(Number.isSafeInteger(batch.sequence));
      assert.ok(batch.runs?.length > 0);
      return {requestID: request.requestID, index, batchID: batch.id, brandID: batch.brandID,
        scheduledAt: request.wave.scheduledAt, invokedAt: request.wave.invokedAt,
        httpIntentRecordedAt: request.httpIntentRecordedAt, serverCreatedAt: batch.createdAt,
        sequence: batch.sequence, startedAt: Math.min(...batch.runs.map((run) => run.startedAt)),
        finishedAt: Math.max(...batch.runs.map((run) => run.finishedAt))};
    });
    assert.equal(new Set(rows.map((row) => row.batchID)).size, 10);
    assert.equal(new Set(rows.map((row) => row.brandID)).size, 10);
    const ordered = [...rows].sort((a, b) => a.sequence - b.sequence);
    const waitingPairs = [];
    for (let head = 0; head < ordered.length; head++) {
      for (let next = head + 1; next < ordered.length; next++) {
        const a = ordered[head], b = ordered[next];
        if (b.serverCreatedAt < a.finishedAt) {
          assert.ok(b.startedAt >= a.finishedAt, "Q7_WAVE_PROCESSING_OVERLAP");
          waitingPairs.push({headBatchID: a.batchID, waitingBatchID: b.batchID,
            admittedDuringHeadRun: b.serverCreatedAt >= a.startedAt});
        }
      }
    }
    assert.ok(waitingPairs.length > 0, "Q7_WAVE_WAITING_NOT_OBSERVED");
    return {name, rows, serverOrder: ordered.map((row) => row.index), waitingPairs,
      maxInvocationDelayMs: Math.max(...rows.map((row) => row.invokedAt - row.scheduledAt)),
      httpIntentSpanMs: rows.at(-1).httpIntentRecordedAt - rows[0].httpIntentRecordedAt,
      serverAdmissionSpanMs: Math.max(...rows.map((row) => row.serverCreatedAt)) -
        Math.min(...rows.map((row) => row.serverCreatedAt))};
  });
}
