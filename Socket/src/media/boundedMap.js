// 실패 후에는 새 작업을 시작하지 않고 진행 중인 작업까지 종료한 뒤 반환한다.
export async function boundedMap(items, concurrency, operation) {
  if (!Number.isInteger(concurrency) || concurrency < 1) throw new Error("invalid concurrency");
  const results = new Array(items.length);
  let next = 0;
  let failed = false;
  let failure;
  await Promise.all(Array.from({length: Math.min(concurrency, items.length)}, async () => {
    while (!failed && next < items.length) {
      const index = next++;
      try { results[index] = await operation(items[index], index); }
      catch (error) { if (!failed) failure = error; failed = true; }
    }
  }));
  if (failed) throw failure;
  return results;
}
