import assert from "node:assert/strict";
import test from "node:test";

import { createSocketApplication } from "../../src/app/createSocketApplication.js";

test("application factory는 route/middleware/connection만 등록하고 listen하지 않는다", () => {
  const routes = [];
  const middleware = [];
  const listeners = [];
  const app = { get: (path, handler) => routes.push({ path, handler }) };
  const server = { listening: false, listenCalls: 0, listen() { this.listenCalls += 1; } };
  const io = {
    use: (handler) => middleware.push(handler),
    on: (event, handler) => listeners.push({ event, handler }),
    close() {}
  };
  let socketOptions;
  const reconnect = () => {};
  const auth = () => {};
  const connection = () => {};

  const application = createSocketApplication({
    clock: {
      uptimeSeconds: () => 0,
      nowDate: () => new Date("2026-07-14T00:00:00.000Z")
    },
    createDependencies: ({ io: receivedIO }) => {
      assert.equal(receivedIO, io);
      return {
        reconnectMiddleware: reconnect,
        firebaseAuthMiddleware: auth,
        registerSocketHandlers: connection,
        rooms: {},
        fetchRoomsFromFirebase: async () => {}
      };
    },
    expressFactory: () => app,
    httpServerFactory: (receivedApp) => {
      assert.equal(receivedApp, app);
      return server;
    },
    socketServerFactory: (receivedServer, options) => {
      assert.equal(receivedServer, server);
      socketOptions = options;
      return io;
    },
    shutdownDependencies: {
      exit() {},
      scheduleTimeout: () => ({ unref() {} }),
      clearScheduledTimeout() {}
    }
  });

  assert.deepEqual(routes.map((item) => item.path).sort(), ["/", "/healthz", "/readyz"]);
  assert.deepEqual(middleware, [reconnect, auth]);
  assert.deepEqual(listeners, [{ event: "connection", handler: connection }]);
  assert.equal(socketOptions.maxHttpBufferSize, 2 * 1024 * 1024);
  assert.equal(socketOptions.perMessageDeflate.threshold, 1024);
  assert.equal(Object.isExtensible(socketOptions), true);
  assert.equal(Object.isExtensible(socketOptions.perMessageDeflate), true);
  assert.equal(server.listenCalls, 0);
  assert.equal(application.server, server);
});
