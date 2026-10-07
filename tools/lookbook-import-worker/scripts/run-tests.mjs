import {readdir} from "node:fs/promises";
import {spawnSync} from "node:child_process";
import {fileURLToPath} from "node:url";
import {dirname, join, relative, resolve} from "node:path";

const workerDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");

async function collectTestFiles(directory) {
  const files = [];
  for (const entry of await readdir(directory, {withFileTypes: true})) {
    const entryPath = join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await collectTestFiles(entryPath));
    } else if (entry.isFile() && entry.name.endsWith(".test.ts")) {
      files.push(entryPath);
    }
  }
  return files;
}

// 이동·삭제된 테스트의 오래된 lib 산출물을 다시 실행하지 않는다.
const sourceDirectory = join(workerDirectory, "src");
const testFiles = (await collectTestFiles(sourceDirectory)).map((sourcePath) =>
  join(workerDirectory, "lib", relative(sourceDirectory, sourcePath))
    .replace(/\.ts$/, ".js"),
).sort();
if (testFiles.length === 0) {
  throw new Error("Worker 테스트 소스를 찾지 못했습니다.");
}

const reporterPath = process.env.OUTPICK_GATE_REPORTER_PATH;
const resultPath = process.env.OUTPICK_GATE_RESULT_PATH;
if (Boolean(reporterPath) !== Boolean(resultPath)) {
  throw new Error("게이트 reporter와 결과 경로를 함께 지정해야 합니다.");
}
const reporterArgs = reporterPath ? [
  "--test-reporter", reporterPath,
  "--test-reporter-destination", resultPath,
] : [];
const result = spawnSync(
  process.execPath,
  ["--test", ...reporterArgs, ...testFiles],
  {cwd: workerDirectory, stdio: "inherit"},
);
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
