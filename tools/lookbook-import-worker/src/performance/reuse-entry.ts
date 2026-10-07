import assert from "node:assert/strict";
import {readFile, writeFile} from "node:fs/promises";
import {pathToFileURL} from "node:url";
import {loadFrozenInput} from "./frozen-input.js";
import {checkLocalEnvironment} from "./local-entry.js";
import {runReuse, validateReusePlan, type ReusePlan}
  from "./reuse-comparison.js";
import {connectedExecutor} from "./reuse-input.js";
import {ReuseTrace} from "./reuse-trace.js";
import {assertApprovedContract, contractFor, PRESSURE_INPUT}
  from "./reuse-contract.js";
import {deriveLargeInput, assertLargeInput, largeTraceProfile}
  from "./large-input.js";
import {BrandProgress} from "./brand-progress.js";

export async function runReuseEntry(input: string, planPath: string,
  output: string) {
  await checkLocalEnvironment();
  const plan = JSON.parse(await readFile(planPath, "utf8")) as ReusePlan;
  validateReusePlan(plan);
  const progress = plan.brandComparison ?
    new BrandProgress(plan.id) : undefined;
  try {
    await progress?.emit({event: "preflight-start"});
    const frozen = await loadFrozenInput(input);
    assert.equal(frozen.inputDigest,
      plan.largeInput || plan.brandComparison ?
        PRESSURE_INPUT : plan.inputDigest);
    const large = plan.largeInput ? deriveLargeInput(frozen.connectedInput,
      frozen.inputDigest) : undefined;
    if (large) assertLargeInput(large);
    const inputContract = large?.contract ?? (plan.loadPressure ||
    plan.submission ?
      contractFor(frozen.connectedInput,
        plan.load ?? "six") : undefined);
    if (inputContract && !large) {
      assertApprovedContract(inputContract, plan.load ?? "six");
    }
    const trace = plan.diagnostic ? new ReuseTrace(large ?
      largeTraceProfile(large.contract) : undefined) : undefined;
    await progress?.emit({event: "preflight-end"});
    const result = await runReuse(plan,
      connectedExecutor(large?.connectedInput ?? frozen.connectedInput,
        trace, plan.arm === "prepared"),
      undefined, trace, progress);
    if (!progress?.errorCode) {
      await progress?.emit({event: "measurement-finished"});
    }
    await writeFile(output, JSON.stringify({...result,
      ...(inputContract ? {inputContract} : {}),
      runtime: {platform: process.platform, arch: process.arch,
        node: process.version},
      scope: "local-connected-not-production-quality-or-review-resumption",
    }, null, 2), {flag: "wx"});
  } catch (error) {
    if (!progress?.errorCode) throw error;
    await writeFile(output, JSON.stringify({id: plan.id,
      evidenceError: progress.errorCode}), {flag: "wx"});
  } finally {
    await progress?.drain();
  }
}
if (process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [, , input, plan, output] = process.argv;
  if (!input || !plan || !output) throw new Error("입력/계획/결과 경로 필요");
  await runReuseEntry(input, plan, output);
}
