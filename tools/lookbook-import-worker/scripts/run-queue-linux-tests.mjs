import {spawnSync} from "node:child_process";
import {fileURLToPath} from "node:url";
import {dirname, resolve} from "node:path";

const workerDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const reporterPath = process.env.OUTPICK_GATE_REPORTER_PATH;
const resultPath = process.env.OUTPICK_GATE_RESULT_PATH;
if (Boolean(reporterPath) !== Boolean(resultPath)) {
  throw new Error("게이트 reporter와 결과 경로를 함께 지정해야 합니다.");
}
const reporterArgs = reporterPath ? ["--test-reporter", reporterPath,
  "--test-reporter-destination", resultPath] : [];
const result = spawnSync(process.execPath, ["--test", ...reporterArgs,
  "scripts/queue-linux-gate.test.mjs"],
{cwd: workerDirectory, stdio: "inherit"});
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
