import {copyFile, mkdir} from "node:fs/promises";
import {homedir} from "node:os";
import {dirname, join, resolve} from "node:path";
import {fileURLToPath} from "node:url";

const source = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
if (args.length !== 0 && !(args.length === 2 && args[0] === "--target")) {
  throw new Error("사용법: node install.mjs [--target <설치 위치>]");
}
const target = resolve(args[1] ?? join(homedir(), ".codex", "tools", "verification-gate"));
if (target === source) throw new Error("원본 폴더와 설치 위치가 같습니다.");
await mkdir(target, {recursive: true});
for (const name of ["gate.mjs", "node-reporter.mjs", "gate.test.mjs"]) {
  await copyFile(join(source, name), join(target, name));
}
console.log(`공용 게이트 설치 완료: ${target}`);
