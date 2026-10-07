import assert from "node:assert/strict";
import {median} from "./result.js";
import {repeatedRegression} from "./comparison-report.js";
import type {BrandLoad, BrandOrder} from "./brand-comparison.js";

export type BrandSample = {id: string; load: BrandLoad; order: BrandOrder;
  repeat: number; verdict: string; wallMs: number | null;
  firstSeasonMs: number | null; firstBrandMs: number | null;
  brands: Array<{brandID: string; completedMs: number | null;
    queueWaitMs: number | null; serviceMs: number | null}>;
  memoryMaxRatio: number | null; readBytes: number | null};
export function brandStatistics(samples: BrandSample[]) {
  const keys = samples.map((s) => `${s.load}/${s.order}/${s.repeat}`);
  assert.equal(new Set(keys).size, samples.length);
  assert.ok(samples.every((s) => ["standard", "large"].includes(s.load) &&
    ["parallel", "serial-brands"].includes(s.order) &&
    Number.isInteger(s.repeat) && s.repeat >= 1 && s.repeat <= 5));
  const groups = (["standard", "large"] as const).flatMap((load) =>
    (["parallel", "serial-brands"] as const).map((order) => {
      const own = samples.filter((s) => s.load === load && s.order === order);
      const success = own.filter((s) => s.verdict === "succeeded");
      const complete = success.length === 5;
      const counts = Object.fromEntries(["succeeded", "aborted", "failed",
        "unavailable", "notRun"].map((v) =>
        [v, own.filter((s) => s.verdict === v).length]));
      const read = (key: "wallMs" | "firstBrandMs" | "firstSeasonMs" |
        "readBytes") => complete ?
        median(success.map((s) => Number(s[key]))) : null;
      const memory = own.flatMap((s) => s.memoryMaxRatio === null ? [] :
        [s.memoryMaxRatio]);
      const executed = counts.succeeded + counts.aborted + counts.failed;
      return {load, order, planned: 5, counts, complete, executed,
        failureOrAbortRate: executed ?
          (counts.aborted + counts.failed) / executed : null,
        medianMs: read("wallMs"), firstBrandMedianMs: read("firstBrandMs"),
        firstSeasonMedianMs: read("firstSeasonMs"),
        readBytesMedian: read("readBytes"),
        observedMemoryRuns: memory.length,
        maxMemoryRatio: memory.length ? Math.max(...memory) : null,
        brands: complete ? success[0].brands.map((brand, index) => ({
          brandID: brand.brandID,
          completedMedianMs: median(success.map((s) =>
            Number(s.brands[index].completedMs))),
          queueWaitMedianMs: median(success.map((s) =>
            Number(s.brands[index].queueWaitMs))),
          serviceMedianMs: median(success.map((s) =>
            Number(s.brands[index].serviceMs))),
        })) : null};
    }));
  const comparisons = (["standard", "large"] as const).map((load) => {
    const pairs = Array.from({length: 5}, (_, i) => ({
      base: samples.find((s) => s.load === load && s.order === "parallel" &&
        s.repeat === i + 1 && s.verdict === "succeeded"),
      candidate: samples.find((s) => s.load === load &&
        s.order === "serial-brands" &&
        s.repeat === i + 1 && s.verdict === "succeeded")}));
    const complete = pairs.every((p) => p.base && p.candidate);
    const compare = (read: (s: BrandSample) => number | null) => complete ?
      repeatedRegression(pairs.map((p) => Number(read(p.base!))),
        pairs.map((p) => Number(read(p.candidate!)))) : null;
    const wall = compare((s) => s.wallMs);
    const firstSeason = compare((s) => s.firstSeasonMs);
    return {load, complete,
      pairs: pairs.filter((p) => p.base && p.candidate).length,
      wall, firstSeason, firstBrand: compare((s) => s.firstBrandMs),
      improvementPercent: wall ?
        (1 - wall.candidateMedian / wall.baselineMedian) * 100 : null,
      meetsLocalSpeedTarget: wall && firstSeason ?
        wall.candidateMedian * 10 <= wall.baselineMedian * 9 &&
        !firstSeason.withholdAdoption : null,
      brands: complete ? pairs[0].base!.brands.map((b, i) => ({
        brandID: b.brandID,
        result: compare((s) => s.brands[i].completedMs)})) : null};
  });
  return {groups, comparisons};
}
