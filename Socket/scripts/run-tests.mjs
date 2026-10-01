import { readdir } from "node:fs/promises";
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const socketRoot = dirname(scriptDirectory);
const testRoot = join(socketRoot, "test");

async function collectTests(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const paths = [];

  for (const entry of entries) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      paths.push(...await collectTests(path));
    } else if (entry.isFile() && entry.name.endsWith(".test.js")) {
      paths.push(path);
    }
  }

  return paths;
}

const testFiles = (await collectTests(testRoot)).sort();
if (testFiles.length === 0) {
  console.error("Socket test를 찾지 못했습니다.");
  process.exit(1);
}

const reporterPath = process.env.OUTPICK_GATE_REPORTER_PATH;
const resultPath = process.env.OUTPICK_GATE_RESULT_PATH;
if (Boolean(reporterPath) !== Boolean(resultPath)) {
  console.error("게이트 reporter와 결과 경로를 함께 지정해야 합니다.");
  process.exit(1);
}
const reporterArgs = reporterPath ? [
  "--test-reporter", reporterPath,
  "--test-reporter-destination", resultPath,
] : [];

const child = spawn(process.execPath, ["--test", ...reporterArgs, ...testFiles], {
  cwd: socketRoot,
  stdio: "inherit"
});

child.on("error", (error) => {
  console.error("Socket test runner 실행에 실패했습니다.", error);
  process.exit(1);
});

child.on("exit", (code, signal) => {
  if (signal) {
    console.error(`Socket test runner가 ${signal} signal로 종료됐습니다.`);
    process.exit(1);
  }
  process.exit(code ?? 1);
});
