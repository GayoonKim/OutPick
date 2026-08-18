export function createRateLimiter({
  clock,
  idleTTLms = 60_000,
  sweepIntervalMs = 30_000,
  maxActiveBuckets = 50_000,
  onCapacity = () => {}
}) {
  const rateBuckets = new Map();
  let lastSweepAt = clock.nowMillis();

  function sweep(now, force = false) {
    if (!force && now - lastSweepAt < sweepIntervalMs) return 0;
    let removed = 0;
    for (const [key, bucket] of rateBuckets) {
      if (now - bucket.lastSeenAt >= idleTTLms) {
        rateBuckets.delete(key);
        removed += 1;
      }
    }
    lastSweepAt = now;
    return removed;
  }

  function allowRate(key, limit, windowMs, requestID = "") {
    const now = clock.nowMillis();
    sweep(now);

    let bucket = rateBuckets.get(key);
    if (!bucket) {
      if (rateBuckets.size >= maxActiveBuckets) {
        onCapacity({ activeBuckets: rateBuckets.size, maxActiveBuckets });
        return false;
      }
      bucket = { times: [], requestIDs: new Map(), lastSeenAt: now };
      rateBuckets.set(key, bucket);
    }

    bucket.lastSeenAt = now;
    while (bucket.times.length && (now - bucket.times[0] > windowMs)) {
      bucket.times.shift();
    }
    for (const [id, countedAt] of bucket.requestIDs) {
      if (now - countedAt > windowMs) bucket.requestIDs.delete(id);
    }

    const normalizedRequestID = typeof requestID === "string" ? requestID.trim() : "";
    if (normalizedRequestID && bucket.requestIDs.has(normalizedRequestID)) return true;
    if (bucket.times.length >= limit) return false;

    bucket.times.push(now);
    if (normalizedRequestID) bucket.requestIDs.set(normalizedRequestID, now);
    return true;
  }

  return {
    allowRate,
    sweep: () => sweep(clock.nowMillis(), true),
    activeBucketCount: () => rateBuckets.size
  };
}
