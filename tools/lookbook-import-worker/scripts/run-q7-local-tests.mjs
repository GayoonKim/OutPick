import {spawnSync} from "node:child_process";
import {fileURLToPath} from "node:url";

const reporter = process.env.OUTPICK_GATE_REPORTER_PATH;
const result = process.env.OUTPICK_GATE_RESULT_PATH;
if (!reporter || !result) throw new Error("프로그램적 게이트를 통해 실행해야 합니다.");
const files = ["q7-verification.test.mjs", "q7-resume.test.mjs", "q7-wave.test.mjs", "queue-development-contract.test.mjs", "q7-retry-contract.test.mjs"]
  .map((name) => fileURLToPath(new URL("./" + name, import.meta.url)));
const child = spawnSync(process.execPath, ["--test", "--test-reporter", reporter,
  "--test-reporter-destination", result, ...files],
{stdio: "inherit", env: process.env});
if (child.error) throw child.error;
process.exitCode = child.status ?? 1;
