/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import {existsSync, readdirSync, readFileSync} from "node:fs";
import path from "node:path";
import test from "node:test";

const sourceRoot = path.join(process.cwd(), "src");

function sourceFiles(directory = sourceRoot): string[] {
  return readdirSync(directory, {withFileTypes: true}).flatMap((entry) => {
    const filePath = path.join(directory, entry.name);
    if (entry.isDirectory()) return sourceFiles(filePath);
    return entry.isFile() && entry.name.endsWith(".ts") ? [filePath] : [];
  });
}

function owners(pattern: RegExp): string[] {
  return sourceFiles()
    .filter((file) => !file.endsWith(".test.ts"))
    .filter((file) => pattern.test(readFileSync(file, "utf8")))
    .map((file) => path.relative(sourceRoot, file));
}

test("Firebase Admin 초기화와 global runtime option owner는 하나다", () => {
  assert.deepEqual(owners(/\binitializeApp\s*\(/), ["core/firebase.ts"]);
  assert.deepEqual(owners(/\bsetGlobalOptions\s*\(/), ["core/runtime.ts"]);
  assert.deepEqual(owners(/\bonInit\s*\(/), []);
});

test("root index는 명시적 flat re-export만 가진다", () => {
  const source = readFileSync(path.join(sourceRoot, "index.ts"), "utf8");
  assert.doesNotMatch(source, /export\s+\*/);
  assert.doesNotMatch(source, /export\s+default/);
  assert.doesNotMatch(
    source,
    /onCall|onSchedule|onDocument|runTransaction|\.batch\(|storage\(\)/
  );
  assert.equal(source.trimStart().startsWith("export "), true);
});

test("feature는 다른 최상위 feature를 직접 import하지 않는다", () => {
  const featureRoots = new Set(["auth", "brand", "chat", "lookbook"]);
  const violations: string[] = [];
  for (const file of sourceFiles()) {
    const relativeFile = path.relative(sourceRoot, file);
    const sourceFeature = relativeFile.split(path.sep)[0];
    if (!featureRoots.has(sourceFeature)) continue;
    const source = readFileSync(file, "utf8");
    const imports = source.matchAll(/from\s+["'](\.[^"']+)["']/g);
    for (const match of imports) {
      const resolved = path.resolve(path.dirname(file), match[1]);
      const targetFeature = path
        .relative(sourceRoot, resolved)
        .split(path.sep)[0];
      if (featureRoots.has(targetFeature) && targetFeature !== sourceFeature) {
        violations.push(`${relativeFile} -> ${match[1]}`);
      }
    }
  }
  assert.deepEqual(violations, []);
});

test("모든 feature functions entrypoint는 공통 runtime에 의존한다", () => {
  const violations = sourceFiles()
    .filter((file) => file.endsWith(`${path.sep}functions.ts`))
    .filter((file) => !readFileSync(file, "utf8").includes("core/runtime.js"))
    .map((file) => path.relative(sourceRoot, file));
  assert.deepEqual(violations, []);
});

test("이동 전 root helper 파일은 남지 않는다", () => {
  const removedFiles = [
    "lookbookDeletionPurgeDrain.ts",
    "lookbookDeletionPurgeDrain.test.ts",
    "lookbookDeletionPurgeLease.ts",
    "lookbookDeletionPurgeLease.test.ts",
    "lookbookSeasonCandidateDiscovery.ts",
    "lookbookSeasonCandidateParser.ts",
  ];
  assert.deepEqual(
    removedFiles.filter((file) => existsSync(path.join(sourceRoot, file))),
    []
  );
});
