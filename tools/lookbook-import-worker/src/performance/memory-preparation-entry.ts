import {readFile, writeFile} from "node:fs/promises";
import {measurePreparation, validatePreparationResult}
  from "./memory-preparation.js";

const [root, planPath, resultPath] = process.argv.slice(2);
const plan = JSON.parse(await readFile(planPath, "utf8"));
const result = await measurePreparation(plan, root);
await writeFile(resultPath, JSON.stringify(result, null, 2), {flag: "wx"});
try {
  validatePreparationResult(plan, result);
} catch {
  process.exitCode = 1;
}
