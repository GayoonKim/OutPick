export type LaunchPolicy =
  | {kind: "refill"; concurrency: number | null}
  | {kind: "batch"; size: number; concurrency: number | null};

export function validateLaunch(policy: LaunchPolicy): void {
  if (!["refill", "batch"].includes(policy.kind) ||
    (policy.concurrency !== null &&
      (!Number.isSafeInteger(policy.concurrency) || policy.concurrency < 1)) ||
    (policy.kind === "batch" &&
      (!Number.isSafeInteger(policy.size) || policy.size < 1))) {
    throw new Error("실행 폭과 묶음 크기는 양의 정수 또는 명시적 전체 제출이어야 합니다.");
  }
}

// 실패한 작업의 형제 작업도 모두 끝난 뒤 호출자에게 오류를 전달한다.
export async function drainAll<T>(
  operations: Array<() => Promise<T>>,
): Promise<T[]> {
  const settled = await Promise.allSettled(operations.map(async (op) => op()));
  return unwrap(settled);
}

function unwrap<T>(settled: PromiseSettledResult<T>[]): T[] {
  return settled.map((result) => {
    if (result.status === "rejected") throw result.reason;
    return result.value;
  });
}

export async function mapScheduled<T, R>(
  items: readonly T[], policy: LaunchPolicy,
  operation: (item: T, index: number) => Promise<R>,
  signal?: AbortSignal,
): Promise<R[]> {
  validateLaunch(policy);
  const results: PromiseSettledResult<R>[] = [];
  const size = policy.kind === "batch" ?
    policy.size : Math.max(1, items.length);
  for (let start = 0; start < items.length; start += size) {
    if (signal?.aborted) break;
    const end = Math.min(start + size, items.length);
    let cursor = start;
    const width = Math.min(policy.concurrency ?? (end - start), end - start);
    await Promise.all(Array.from({length: width}, async () => {
      while (cursor < end) {
        if (signal?.aborted) break;
        const index = cursor++;
        try {
          results[index] = {status: "fulfilled",
            value: await operation(items[index], index)};
        } catch (reason) {
          results[index] = {status: "rejected", reason};
        }
      }
    }));
  }
  // 이미 실행 중인 형제는 종료를 기다리되 다음 묶음과 빈자리는 시작하지 않는다.
  signal?.throwIfAborted();
  return unwrap(results);
}
