import assert from "node:assert/strict";
import {readFile, writeFile} from "node:fs/promises";
import {pathToFileURL} from "node:url";
import {validateComparisonPlan, runComparison, type ComparisonPlan}
  from "./comparison.js";
import {loadFrozenInput} from "./frozen-input.js";

export async function runLocalEntry(inputDirectory: string,
  planPath: string, outputPath: string): Promise<void> {
  await checkLocalEnvironment();
  const plan = JSON.parse(await readFile(planPath, "utf8")) as ComparisonPlan;
  validateComparisonPlan(plan);
  const frozen = await loadFrozenInput(inputDirectory);
  assert.equal(frozen.inputDigest, plan.inputDigest);
  const result = await runComparison(plan, frozen.execute);
  await writeFile(outputPath, JSON.stringify({...result,
    runtime: {platform: process.platform, arch: process.arch,
      node: process.version},
    scope: "local-replay-extraction-review-and-post-approval-save-separated",
  }, null, 2), {flag: "wx"});
}

export async function checkLocalEnvironment(): Promise<void> {
  assert.equal(process.platform, "linux");
  assert.equal(process.arch, "arm64");
  assert.equal(process.versions.node.split(".")[0], "24");
  const [quota, period] = (await readFile("/sys/fs/cgroup/cpu.max", "utf8"))
    .trim().split(/\s+/).map(Number);
  assert.ok(Number.isFinite(quota) && quota > 0 && quota === period);
  assert.equal((await readFile("/sys/fs/cgroup/memory.max", "utf8")).trim(),
    String(2 * 2**30));
  const swap = await readFile("/sys/fs/cgroup/memory.swap.max", "utf8");
  assert.equal(swap.trim(), "0");
}

if (process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [, , input, plan, output] = process.argv;
  if (!input || !plan || !output) throw new Error("입력/계획/결과 경로 필요");
  await runLocalEntry(input, plan, output);
}
