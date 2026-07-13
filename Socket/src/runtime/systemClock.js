export function createSystemClock({
  now = Date.now,
  uptime = () => process.uptime()
} = {}) {
  return {
    nowMillis: () => now(),
    nowDate: () => new Date(now()),
    uptimeSeconds: () => Math.round(uptime())
  };
}
