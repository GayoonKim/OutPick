/* eslint-disable require-jsdoc */
export async function mapWithConcurrency<T, R>(
  values: T[],
  concurrency: number,
  work: (value: T, index: number) => Promise<R>
): Promise<R[]> {
  const results: R[] = [];
  let cursor = 0;
  const workerCount = Math.min(Math.max(1, concurrency), values.length);
  const workers = Array.from({length: workerCount}, async () => {
    for (;;) {
      const index = cursor;
      cursor += 1;
      const value = values[index];
      if (value === undefined) {
        return;
      }
      results[index] = await work(value, index);
    }
  });
  await Promise.all(workers);
  return results;
}
