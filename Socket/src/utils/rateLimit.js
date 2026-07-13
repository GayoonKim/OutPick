export function createRateLimiter({ clock }) {
  const rateBuckets = new Map();

  function allowRate(key, limit, windowMs) {
    const now = clock.nowMillis();
    const arr = rateBuckets.get(key) || [];
    while (arr.length && (now - arr[0] > windowMs)) arr.shift();
    if (arr.length >= limit) return false;
    arr.push(now);
    rateBuckets.set(key, arr);
    return true;
  }

  return { allowRate };
}
