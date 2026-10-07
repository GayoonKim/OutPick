type Entry = {bytes: Buffer | null; retained: boolean; borrowers: number};
type Budget = {
  reserve: (bytes: number) => boolean;
  release: (bytes: number) => void;
  hit: () => void;
  miss: () => void;
  closed: () => void;
};
export type SourceBufferLease = {readonly bytes: Buffer; release: () => void};

// 예산은 보관/대여 중인 원본 payload의 합이며 전체 RSS 한도가 아니다.
export class SourceBufferStore {
  private bytes = 0;
  private peakBytes = 0;
  private hits = 0;
  private misses = 0;
  private rejected = 0;
  private scopes = 0;
  private readonly openScopes = new Set<SourceBufferScope>();

  constructor(readonly budgetBytes: number | null) {
    if (budgetBytes !== null &&
      (!Number.isSafeInteger(budgetBytes) || budgetBytes < 0)) {
      throw new Error("보관 예산은 비음수 정수 또는 null이어야 합니다.");
    }
  }

  openScope(): SourceBufferScope {
    this.scopes++;
    const scope = new SourceBufferScope({
      reserve: (size) => {
        if (!Number.isSafeInteger(this.bytes + size) ||
          (this.budgetBytes !== null && this.bytes + size > this.budgetBytes)) {
          this.rejected++;
          return false;
        }
        this.bytes += size;
        this.peakBytes = Math.max(this.peakBytes, this.bytes);
        return true;
      },
      release: (size) => {
        this.bytes -= size;
      },
      hit: () => {
        this.hits++;
      },
      miss: () => {
        this.misses++;
      },
      closed: () => {
        this.scopes--;
        this.openScopes.delete(scope);
      },
    });
    this.openScopes.add(scope);
    return scope;
  }

  clearRetained(): void {
    for (const scope of this.openScopes) scope.clearRetained();
  }

  snapshot() {
    return {budgetBytes: this.budgetBytes, retainedBytes: this.bytes,
      peakRetainedBytes: this.peakBytes, hits: this.hits, misses: this.misses,
      rejectedByBudget: this.rejected, openScopes: this.scopes};
  }
}

export class SourceBufferScope {
  private readonly entries = new Map<string, Entry>();
  private closed = false;

  constructor(private readonly budget: Budget) {}

  retain(canonicalURL: string, requestContext: string, bytes: Buffer): boolean {
    if (this.closed || bytes.length === 0) return false;
    const key = JSON.stringify([canonicalURL, requestContext]);
    // 이미 해시한 원본을 늦은 재다운로드 결과로 교체하지 않는다.
    if (this.entries.has(key)) return false;
    if (!this.budget.reserve(bytes.length)) return false;
    this.entries.set(key, {bytes, retained: true, borrowers: 0});
    return true;
  }

  clearRetained(): void {
    for (const entry of this.entries.values()) {
      entry.retained = false;
      this.disposeIfUnused(entry);
    }
    this.entries.clear();
  }

  acquire(
    canonicalURL: string, requestContext: string,
  ): SourceBufferLease | null {
    const key = JSON.stringify([canonicalURL, requestContext]);
    const entry = this.entries.get(key);
    if (this.closed || !entry?.bytes) {
      this.budget.miss();
      return null;
    }
    this.budget.hit();
    entry.borrowers++;
    let released = false;
    return {
      // 소비자는 원본을 수정하지 않고 변환 입력으로만 사용한다.
      get bytes() {
        if (released || entry.bytes === null) {
          throw new Error("반환한 원본 바이트는 다시 사용할 수 없습니다.");
        }
        return entry.bytes;
      },
      release: () => {
        if (released) return;
        released = true;
        entry.borrowers--;
        this.disposeIfUnused(entry);
      },
    };
  }

  retainOnly(canonicalURLs: ReadonlySet<string>, requestContext: string): void {
    const keys = new Set([...canonicalURLs]
      .map((url) => JSON.stringify([url, requestContext])));
    for (const [key, entry] of this.entries) {
      const [, context] = JSON.parse(key) as [string, string];
      if (context !== requestContext || keys.has(key)) continue;
      this.entries.delete(key);
      entry.retained = false;
      this.disposeIfUnused(entry);
    }
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    for (const entry of this.entries.values()) {
      entry.retained = false;
      this.disposeIfUnused(entry);
    }
    this.entries.clear();
    this.budget.closed();
  }

  private disposeIfUnused(entry: Entry): void {
    if (entry.retained || entry.borrowers !== 0 || entry.bytes === null) return;
    this.budget.release(entry.bytes.length);
    entry.bytes = null;
  }
}

export async function withSourceBufferScope<T>(
  store: SourceBufferStore | undefined,
  operation: (scope: SourceBufferScope | undefined) => Promise<T>,
): Promise<T> {
  const scope = store?.openScope();
  try {
    return await operation(scope);
  } finally {
    scope?.close();
  }
}

export async function usingSourceBytes<T>(
  scope: SourceBufferScope | undefined,
  canonicalURL: string, requestContext: string,
  load: () => Promise<Buffer>, consume: (bytes: Buffer) => Promise<T>,
): Promise<T> {
  const lease = scope?.acquire(canonicalURL, requestContext);
  try {
    return await consume(lease ? lease.bytes : await load());
  } finally {
    lease?.release();
  }
}
