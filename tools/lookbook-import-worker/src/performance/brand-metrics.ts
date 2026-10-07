import assert from "node:assert/strict";
import type {SeasonEvent, SeasonInput, SeasonRecord} from "./season-runner.js";

export function brandMetrics(inputs: SeasonInput[], records: SeasonRecord[],
  events: SeasonEvent[], originMs: number, serial: boolean) {
  assert.ok(Number.isFinite(originMs));
  assert.deepEqual(records.map((r) => [r.id, r.brandID]),
    inputs.map((r) => [r.id, r.brandID]));
  const ids = [...new Set(inputs.map((i) => i.brandID))];
  let previous = originMs;
  for (const event of events) {
    assert.ok(ids.includes(event.brandID));
    assert.ok(Number.isFinite(event.atMs) && event.atMs >= previous);
    previous = event.atMs;
    assert.ok(["brand-start", "brand-end", "attempt-start", "attempt-end"]
      .includes(event.event));
  }
  const brands = ids.map((brandID) => {
    const own = records.filter((r) => r.brandID === brandID);
    const started = events.filter((e) => e.brandID === brandID &&
      e.event === "brand-start");
    const ended = events.filter((e) => e.brandID === brandID &&
      e.event === "brand-end");
    assert.ok(started.length <= 1 && ended.length <= 1);
    for (const record of own) {
      assert.ok(record.attempts.length <= 5);
      record.attempts.forEach((attempt, index) => {
        assert.equal(attempt.number, index + 1);
        const pair = events.filter((e) => e.brandID === brandID &&
          e.seasonID === record.id && e.attempt === attempt.number);
        assert.deepEqual(pair.map((e) => e.event),
          ["attempt-start", "attempt-end"]);
        assert.ok(started[0] && started[0].atMs <= attempt.startedMs &&
          attempt.startedMs <= pair[0].atMs &&
          pair[0].atMs <= attempt.endedMs &&
          attempt.endedMs <= pair[1].atMs);
        assert.equal(pair[1].status, attempt.status);
        if (ended[0]) assert.ok(ended[0].atMs >= pair[1].atMs);
      });
    }
    const attemptEvents = events.filter((e) => e.brandID === brandID &&
      e.event.startsWith("attempt-"));
    assert.equal(attemptEvents.length,
      own.reduce((n, r) => n + r.attempts.length * 2, 0));
    const success = own.every((r) => r.status === "succeeded");
    if (success) assert.ok(started[0] && ended[0]);
    if (ended[0]) {
      assert.ok(started[0] && own.every((r) =>
        r.attempts.length > 0) && ended[0].atMs >= started[0].atMs);
    }
    const admittedMs = started[0] ? started[0].atMs - originMs : null;
    const releasedMs = ended[0] ? ended[0].atMs - originMs : null;
    return {brandID, statuses: own.map((r) => ({id: r.id, status: r.status})),
      admittedMs, queueWaitMs: admittedMs, releasedMs,
      completedMs: success ? releasedMs : null,
      serviceMs: admittedMs !== null && releasedMs !== null ?
        releasedMs - admittedMs : null};
  });
  if (serial) {
    brands.forEach((brand, index) => {
      if (index && brand.admittedMs !== null) {
        const prior = brands[index - 1].releasedMs;
        assert.ok(prior !== null && brand.admittedMs >= prior);
      }
    });
  }
  return {brands, firstBrandMs: brands[0]?.completedMs ?? null};
}
