import assert from "node:assert/strict";
import {repeatedRegression} from "./comparison-report.js";
import {largeSeasons} from "./large-input.js";
import {median} from "./result.js";

export type LargeSample = {budget: string; repeat: number;
  verdict: string; wallMs: number | null; firstMs: number | null;
  seasonMs: Record<string, number>; readBytes: number | null;
  memoryMaxRatio: number | null; pressure: boolean | null};
const budgets = ["off", "128", "256"] as const;

// 검증된 원본에서만 추출한 표본을 받는다. 중단을 성공 시간으로 대체하지 않는다.
export function largeStatistics(samples: LargeSample[]) {
  const keys = samples.map((s) => `${s.budget}/${s.repeat}`);
  assert.equal(new Set(keys).size, samples.length);
  assert.ok(samples.every((s) => budgets.includes(s.budget as
    typeof budgets[number]) && Number.isInteger(s.repeat) &&
    s.repeat >= 1 && s.repeat <= 5));
  const comparisons = budgets.map((budget) => {
    const own = samples.filter((s) => s.budget === budget);
    const successes = own.filter((s) => s.verdict === "succeeded");
    const counts = Object.fromEntries(["succeeded", "aborted", "failed",
      "unavailable", "notRun"].map((status) => [status,
      own.filter((s) => s.verdict === status).length]));
    const complete = successes.length === 5;
    const executed = counts.succeeded + counts.aborted + counts.failed;
    const memory = own.flatMap((s) => s.memoryMaxRatio === null ? [] :
      [s.memoryMaxRatio]);
    return {budget, planned: 5, recorded: own.length, counts, complete,
      executed, failureOrAbortRate: executed ?
        (counts.failed + counts.aborted) / executed : null,
      medianMs: complete ? median(successes.map((s) => Number(s.wallMs))) :
        null,
      firstMedianMs: complete ? median(successes.map((s) =>
        Number(s.firstMs))) : null,
      readBytesMedian: complete ? median(successes.map((s) =>
        Number(s.readBytes))) : null,
      maxMemoryRatio: memory.length ? Math.max(...memory) : null,
      medianPeakMemoryRatio: memory.length === 5 ? median(memory) : null,
      pressureEstablished: complete ? successes.every((s) => s.pressure) :
        null};
  });
  const regressions = ["128", "256"].map((candidate) => {
    const pairs = Array.from({length: 5}, (_, i) => ({
      base: samples.find((s) => s.budget === "off" && s.repeat === i + 1 &&
        s.verdict === "succeeded"),
      candidate: samples.find((s) => s.budget === candidate &&
        s.repeat === i + 1 && s.verdict === "succeeded")}));
    const complete = pairs.every((p) => p.base && p.candidate);
    const compare = (read: (s: LargeSample) => number | null) => complete ?
      repeatedRegression(pairs.map((p) => {
        assert.ok(p.base);
        return Number(read(p.base));
      }), pairs.map((p) => {
        assert.ok(p.candidate);
        return Number(read(p.candidate));
      })) : null;
    const wall = compare((s) => s.wallMs);
    const first = compare((s) => s.firstMs);
    const improvementPercent = wall ?
      (1 - wall.candidateMedian / wall.baselineMedian) * 100 : null;
    return {baseline: "off", candidate, complete,
      pairs: pairs.filter((p) => p.base && p.candidate).length,
      wall, first, improvementPercent,
      meetsLocalSpeedTarget: wall && first ?
        wall.candidateMedian * 10 <= wall.baselineMedian * 9 &&
        !wall.withholdAdoption && !first.withholdAdoption : null,
      seasons: largeSeasons().map((s) => ({id: s.id,
        result: compare((v) => v.seasonMs[s.id])}))};
  });
  return {comparisons, regressions};
}
