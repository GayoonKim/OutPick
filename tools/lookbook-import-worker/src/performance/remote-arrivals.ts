import assert from "node:assert/strict";
import {BRAND_ARRIVAL_INTERVAL_MS, type BrandArrival}
  from "./arrival-runner.js";
import {brandMetrics} from "./brand-metrics.js";
import type {SeasonInput, SeasonRecord, SeasonEvent}
  from "./season-runner.js";

export function remoteArrivalMetrics(inputs: SeasonInput[],
  seasons: SeasonRecord[], events: SeasonEvent[], originMs: number,
  serial: boolean, arrivals: BrandArrival[], limit: number | null) {
  const metrics = brandMetrics(inputs, seasons, events, originMs, serial);
  assert.deepEqual(arrivals.map((a) => a.brandID),
    metrics.brands.map((b) => b.brandID));
  let active = 0; let peak = 0;
  for (const event of events) {
    if (event.event === "attempt-start") active++;
    if (event.event === "attempt-end") active--;
    peak = Math.max(peak, active);
    assert.ok(active >= 0 && active <= (limit ?? inputs.length));
  }
  assert.equal(active, 0);
  const brands = metrics.brands.map((brand, index) => {
    const arrival = arrivals[index];
    assert.equal(arrival.scheduledMs,
      originMs + index * BRAND_ARRIVAL_INTERVAL_MS);
    const arrived = arrival.arrivedMs;
    if (arrived !== null) {
      assert.ok(Number.isFinite(arrived) && arrived >= arrival.scheduledMs);
    }
    if (brand.admittedMs !== null) {
      assert.ok(arrived !== null && originMs + brand.admittedMs >= arrived);
    }
    return {...brand, scheduledMs: arrival.scheduledMs - originMs,
      arrivedMs: arrived === null ? null : arrived - originMs,
      arrivalDelayMs: arrived === null ? null : arrived - arrival.scheduledMs,
      queueWaitMs: brand.admittedMs === null || arrived === null ? null :
        originMs + brand.admittedMs - arrived,
      completionAfterArrivalMs: brand.completedMs === null || arrived === null ?
        null : originMs + brand.completedMs - arrived};
  });
  return {...metrics, brands, seasonPeak: peak};
}
