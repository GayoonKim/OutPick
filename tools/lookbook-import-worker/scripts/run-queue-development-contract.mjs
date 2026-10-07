import {spawnSync} from "node:child_process";
import {fileURLToPath} from "node:url";

const reporter = process.env.OUTPICK_GATE_REPORTER_PATH;
const result = process.env.OUTPICK_GATE_RESULT_PATH;
if (!reporter || !result) throw new Error("프로그램적 게이트를 통해 실행해야 합니다.");
const child = spawnSync(process.execPath, ["--test", "--test-reporter", reporter,
  "--test-reporter-destination", result,
  fileURLToPath(new URL("./queue-development-contract.test.mjs", import.meta.url))],
{stdio: "inherit", env: process.env});
if (child.error) throw child.error;
process.exitCode = child.status ?? 1;
