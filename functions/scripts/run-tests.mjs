import {readdir} from "node:fs/promises";
import {spawnSync} from "node:child_process";
import {fileURLToPath} from "node:url";
import {dirname, join, resolve} from "node:path";

const scriptsDirectory = dirname(fileURLToPath(import.meta.url));
const functionsDirectory = resolve(scriptsDirectory, "..");
const libDirectory = join(functionsDirectory, "lib");

async function collectTestFiles(directory) {
  const entries = await readdir(directory, {withFileTypes: true});
  const files = [];

  for (const entry of entries) {
    const entryPath = join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await collectTestFiles(entryPath));
    } else if (entry.isFile() && entry.name.endsWith(".test.js")) {
      files.push(entryPath);
    }
  }

  return files;
}

const testFiles = (await collectTestFiles(libDirectory)).sort();
if (testFiles.length === 0) {
  throw new Error("컴파일된 Functions 테스트 파일을 찾지 못했습니다.");
}

const result = spawnSync(
  process.execPath,
  ["--test", ...testFiles],
  {cwd: functionsDirectory, stdio: "inherit"}
);

if (result.error) {
  throw result.error;
}

process.exitCode = result.status ?? 1;
