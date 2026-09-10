// 순서를 보존하고 첫 오류 이후 신규 작업을 중단한다. 실행 중 작업은 모두 기다린다.
export async function boundedMap<T, R>(
  items: readonly T[], concurrency: number, operation: (item: T, index: number) => Promise<R>,
): Promise<R[]> {
  if (!Number.isInteger(concurrency) || concurrency < 1) throw new Error("invalid concurrency");
  const results = new Array<R>(items.length);
  let next = 0;
  let failed = false;
  let failure: unknown;
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

export function imageConcurrency(value: string | undefined): number {
  const parsed = Number(value ?? 1);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 4) throw new Error("image concurrency must be 1...4");
  return parsed;
}
