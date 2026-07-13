import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const testDirectory = dirname(fileURLToPath(import.meta.url));
const socketRoot = join(testDirectory, "..", "..");

async function collectJavaScript(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const paths = [];
  for (const entry of entries) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      paths.push(...await collectJavaScript(path));
    } else if (entry.isFile() && entry.name.endsWith(".js")) {
      paths.push(path);
    }
  }
  return paths;
}

async function productionSource() {
  const paths = [
    join(socketRoot, "index.js"),
    ...await collectJavaScript(join(socketRoot, "src"))
  ];
  return (await Promise.all(paths.map((path) => readFile(path, "utf8")))).join("\n");
}

function captures(source, pattern) {
  return [...source.matchAll(pattern)].map((match) => match[1]).sort();
}

test("HTTP route 계약은 /, /healthz, /readyz 세 개다", async () => {
  const source = await productionSource();
  assert.deepEqual(
    captures(source, /\.get\(\s*["']([^"']+)["']/g),
    ["/", "/healthz", "/readyz"]
  );
});

test("Socket client event 등록 계약은 11개와 disconnect다", async () => {
  const source = await productionSource();
  assert.deepEqual(
    captures(source, /socket\.on\(\s*["']([^"']+)["']/g),
    [
      "chat message",
      "chat:lookbookShare",
      "chat:mediaFinalize",
      "chat:mediaPreflight",
      "client:hello",
      "client:ping",
      "create room",
      "disconnect",
      "join room",
      "leave room",
      "room:leave-or-close",
      "set username"
    ].sort()
  );
});

test("Socket middleware 두 개와 connection listener 하나를 등록한다", async () => {
  const source = await productionSource();
  assert.equal((source.match(/io\.use\(/g) || []).length, 2);
  assert.equal((source.match(/io\.on\(\s*["']connection["']/g) || []).length, 1);
});
