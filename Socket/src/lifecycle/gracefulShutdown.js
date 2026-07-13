export function createGracefulShutdown({
  io,
  server,
  exit = (code) => process.exit(code),
  scheduleTimeout = (callback, milliseconds) => setTimeout(callback, milliseconds),
  clearScheduledTimeout = (timer) => clearTimeout(timer),
  logger = console,
  forceTimeoutMs = 10_000
}) {
  let shuttingDown = false;
  let forceTimer = null;

  function finish(error) {
    if (forceTimer) {
      clearScheduledTimeout(forceTimer);
      forceTimer = null;
    }
    if (error && error.code !== "ERR_SERVER_NOT_RUNNING") {
      logger.error("[shutdown] server close failed:", error);
      exit(1);
      return;
    }
    logger.log("[shutdown] server closed");
    exit(0);
  }

  function shutdown(signal) {
    if (shuttingDown) return;
    shuttingDown = true;
    logger.log(`[shutdown] received ${signal}, closing socket server`);

    forceTimer = scheduleTimeout(() => {
      logger.error("[shutdown] forced exit after timeout");
      exit(1);
    }, forceTimeoutMs);
    forceTimer?.unref?.();

    io.close(() => {
      if (server.listening) {
        server.close(finish);
      } else {
        finish();
      }
    });
  }

  return {
    isShuttingDown: () => shuttingDown,
    shutdown
  };
}
