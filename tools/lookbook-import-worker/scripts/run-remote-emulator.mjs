import {existsSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {spawnSync} from "node:child_process";
import {resolve, join} from "node:path";

const root = fileURLToPath(new URL("../../../", import.meta.url));
const environment = {...process.env, CI: "true"};
if (spawnSync("java", ["-version"], {env: environment, stdio: "ignore"}).status !== 0) {
  const java = [environment.JAVA_HOME,
    "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home",
    "/usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"]
    .filter(Boolean).find((path) => existsSync(join(path, "bin/java")));
  if (!java) throw new Error("에뮬레이터 Java가 없습니다.");
  environment.JAVA_HOME = java;
  environment.PATH = `${java}/bin:${environment.PATH}`;
}
const reporter = environment.OUTPICK_GATE_REPORTER_PATH;
const result = environment.OUTPICK_GATE_RESULT_PATH;
if (Boolean(reporter) !== Boolean(result)) throw new Error("게이트 reporter/결과 경로 불일치");
const quote = (value) => `'${value.replaceAll("'", "'\\''")}'`;
const args = [process.execPath, "--test", "--test-concurrency=1",
  ...(reporter ? ["--test-reporter", reporter,
    "--test-reporter-destination", result] : []),
  resolve(root, "tools/lookbook-import-worker/scripts/remote.emulator.mjs")];
const child = spawnSync("firebase", ["emulators:exec", "--only", "firestore,storage",
  "--project", "demo-lookbook-performance", "--config",
  resolve(root, "firebase.lookbook-performance.json"),
  args.map(quote).join(" ")], {cwd: root, env: environment, stdio: "inherit"});
if (child.error) throw child.error;
process.exitCode = child.status ?? 1;
