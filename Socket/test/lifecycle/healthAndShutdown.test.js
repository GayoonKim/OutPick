import assert from "node:assert/strict";
import test from "node:test";

import { createGracefulShutdown } from "../../src/lifecycle/gracefulShutdown.js";
import { registerHealthRoutes } from "../../src/lifecycle/healthRoutes.js";

function makeResponse() {
  return {
    statusCode: null,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; }
  };
}

test("health route는 정상 200과 shutdown 503 계약을 유지한다", () => {
  const routes = new Map();
  let shuttingDown = false;
  registerHealthRoutes({
    app: { get: (path, handler) => routes.set(path, handler) },
    clock: {
      uptimeSeconds: () => 7,
      nowDate: () => new Date("2026-07-14T00:00:00.000Z")
    },
    isShuttingDown: () => shuttingDown
  });

  const ready = makeResponse();
  routes.get("/readyz")({}, ready);
  assert.equal(ready.statusCode, 200);
  assert.deepEqual(ready.body, {
    ok: true,
    service: "outpick-socket",
    uptimeSeconds: 7,
    serverTime: "2026-07-14T00:00:00.000Z"
  });

  shuttingDown = true;
  const health = makeResponse();
  routes.get("/healthz")({}, health);
  assert.equal(health.statusCode, 503);
  assert.equal(health.body.ok, false);

  const root = makeResponse();
  routes.get("/")({}, root);
  assert.deepEqual(root.body, { service: "outpick-socket", health: "/readyz" });
});

test("shutdown은 io 다음 server를 닫고 한 번만 정상 종료한다", () => {
  const timeline = [];
  const exits = [];
  let scheduled;
  let cleared;
  const controller = createGracefulShutdown({
    io: { close: (callback) => { timeline.push("io.close"); callback(); } },
    server: {
      listening: true,
      close: (callback) => { timeline.push("server.close"); callback(); }
    },
    exit: (code) => exits.push(code),
    scheduleTimeout: (callback, milliseconds) => {
      scheduled = { callback, milliseconds, unref() {} };
      return scheduled;
    },
    clearScheduledTimeout: (timer) => { cleared = timer; },
    logger: { log() {}, error() {} }
  });

  controller.shutdown("SIGTERM");
  controller.shutdown("SIGINT");

  assert.deepEqual(timeline, ["io.close", "server.close"]);
  assert.deepEqual(exits, [0]);
  assert.equal(scheduled.milliseconds, 10_000);
  assert.equal(cleared, scheduled);
  assert.equal(controller.isShuttingDown(), true);
});
