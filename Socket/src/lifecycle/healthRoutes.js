export function registerHealthRoutes({
  app,
  clock,
  isShuttingDown
}) {
  function sendHealthResponse(_request, response) {
    const shuttingDown = isShuttingDown();
    response.status(shuttingDown ? 503 : 200).json({
      ok: !shuttingDown,
      service: "outpick-socket",
      uptimeSeconds: clock.uptimeSeconds(),
      serverTime: clock.nowDate().toISOString()
    });
  }

  app.get("/readyz", sendHealthResponse);
  app.get("/healthz", sendHealthResponse);
  app.get("/", (_request, response) => {
    response.status(200).json({
      service: "outpick-socket",
      health: "/readyz"
    });
  });
}
