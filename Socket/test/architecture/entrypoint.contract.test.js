import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const testDirectory = dirname(fileURLToPath(import.meta.url));
const socketRoot = join(testDirectory, "..", "..");

test("index.js는 bootstrap/listen/signal 조립만 유지한다", async () => {
  const source = await readFile(join(socketRoot, "index.js"), "utf8");
  assert.equal(source.includes("socket.on("), false);
  assert.equal(source.includes("io.use("), false);
  assert.equal(source.includes(".collection("), false);
  assert.equal(source.includes("runTransaction"), false);
  assert.ok(source.split("\n").length <= 60);
});

test("firebaseAdmin module은 import-time 초기화를 수행하지 않는다", async () => {
  const source = await readFile(join(socketRoot, "src", "firebaseAdmin.js"), "utf8");
  assert.equal((source.match(/initializeFirebaseAdmin\(/g) || []).length, 1);
  assert.equal(source.includes("export const db"), false);
  assert.equal(source.includes("export { admin }"), false);
});

test("application factory는 process/listen을 직접 소유하지 않는다", async () => {
  const source = await readFile(
    join(socketRoot, "src", "app", "createSocketApplication.js"),
    "utf8"
  );
  assert.equal(source.includes("process.on("), false);
  assert.equal(source.includes("process.exit("), false);
  assert.equal(source.includes(".listen("), false);
});

test("production DI는 공통 message single-flight만 한 번 생성한다", async () => {
  const source = await readFile(
    join(socketRoot, "src", "app", "createProductionDependencies.js"),
    "utf8"
  );
  assert.equal(
    (source.match(/createMessageDeliverySingleFlight\(\)/g) || []).length,
    1
  );
  assert.equal(source.includes("createMediaDeliveryState"), false);
  assert.equal(source.includes("mediaDeliveryState"), false);
});
