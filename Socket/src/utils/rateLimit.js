const rateBuckets = new Map();

export function allowRate(key, limit, windowMs) {
  const now = Date.now();
  const arr = rateBuckets.get(key) || [];
  while (arr.length && (now - arr[0] > windowMs)) arr.shift();
  if (arr.length >= limit) return false;
  arr.push(now);
  rateBuckets.set(key, arr);
  return true;
}
