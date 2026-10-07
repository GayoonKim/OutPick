import assert from "node:assert/strict";
import {readFile, writeFile} from "node:fs/promises";
import {dirname, join} from "node:path";
import {type ComparisonPlan, validateComparisonPlan} from "./comparison.js";
import {checkLocalEnvironment} from "./local-entry.js";
import {loadFrozenInput} from "./frozen-input.js";
import {runOverhead, assessOverhead} from "./overhead.js";

const [, , input, planPath, outputPath] = process.argv;
if (!input || !planPath || !outputPath) throw new Error("입출력 경로 필요");
await checkLocalEnvironment();
const plan = JSON.parse(await readFile(planPath, "utf8")) as ComparisonPlan;
validateComparisonPlan(plan);
const frozen = await loadFrozenInput(input);
assert.equal(frozen.inputDigest, plan.inputDigest);
const payload = await runOverhead(plan, frozen.execute, undefined,
  async (entry, result) => {
    await writeFile(join(dirname(outputPath), `${entry.id}.json`),
      JSON.stringify({...entry, result}), {flag: "wx"});
  });
await writeFile(outputPath, JSON.stringify({...payload,
  assessment: assessOverhead(plan, payload),
  scope: "single-process-warmup-off-on-then-five-alternating-pairs",
}, null, 2), {flag: "wx"});
