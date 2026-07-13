import express from "express";
import { createServer } from "node:http";
import { Server } from "socket.io";

import { createGracefulShutdown } from "../lifecycle/gracefulShutdown.js";
import { registerHealthRoutes } from "../lifecycle/healthRoutes.js";

const SOCKET_OPTIONS = Object.freeze({
  maxHttpBufferSize: 2 * 1024 * 1024,
  perMessageDeflate: { threshold: 1024 }
});

export function createSocketApplication({
  clock,
  createDependencies,
  expressFactory = express,
  httpServerFactory = createServer,
  socketServerFactory = (server, options) => new Server(server, options),
  shutdownDependencies = {}
}) {
  const app = expressFactory();
  const server = httpServerFactory(app);
  // Socket.IO는 전달된 option 객체에 내부 기본값을 추가하므로 새 객체를 넘긴다.
  const socketOptions = {
    ...SOCKET_OPTIONS,
    perMessageDeflate: { ...SOCKET_OPTIONS.perMessageDeflate }
  };
  const io = socketServerFactory(server, socketOptions);
  const dependencies = createDependencies({ io });
  const shutdownController = createGracefulShutdown({
    io,
    server,
    ...shutdownDependencies
  });

  registerHealthRoutes({
    app,
    clock,
    isShuttingDown: shutdownController.isShuttingDown
  });
  io.use(dependencies.reconnectMiddleware);
  io.use(dependencies.firebaseAuthMiddleware);
  io.on("connection", dependencies.registerSocketHandlers);

  return {
    app,
    server,
    io,
    rooms: dependencies.rooms,
    fetchRoomsFromFirebase: dependencies.fetchRoomsFromFirebase,
    shutdownController
  };
}
