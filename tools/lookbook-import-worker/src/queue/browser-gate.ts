/* eslint-disable require-jsdoc */

type GateSignal = AbortSignal | undefined;
type GateWaiter = () => void;
type BrowserGateSnapshot = {
  activeImages: number;
  activeBrowser: boolean;
  queuedBrowsers: number;
};

/**
 * Chromium 렌더링과 이미지/해시 작업이 한 Worker 인스턴스에서 겹치지 않게 한다.
 * 브라우저가 기다리기 시작하면 새 이미지 작업은 브라우저가 끝날 때까지 대기한다.
 */
export class BrowserImageGate {
  private activeImages = 0;
  private activeBrowser = false;
  private readonly browserQueue: symbol[] = [];
  private readonly waiters = new Set<GateWaiter>();
  private readonly browserTransitionCleanup = new Set<() => void>();

  registerBrowserTransitionCleanup(cleanup: () => void): () => void {
    this.browserTransitionCleanup.add(cleanup);
    return () => this.browserTransitionCleanup.delete(cleanup);
  }

  async withImageWork<T>(
    operation: () => Promise<T>,
    signal?: GateSignal,
  ): Promise<T> {
    while (this.activeBrowser || this.browserQueue.length > 0) {
      await this.waitForChange(signal);
    }
    signal?.throwIfAborted();
    this.activeImages++;
    this.notifyWaiters();
    try {
      return await operation();
    } finally {
      this.activeImages--;
      this.notifyWaiters();
    }
  }

  async withBrowserWork<T>(
    operation: (signal?: GateSignal) => Promise<T>,
    signal?: GateSignal,
  ): Promise<T> {
    const ticket = Symbol("browser-work");
    this.browserQueue.push(ticket);
    this.notifyWaiters();
    let entered = false;
    try {
      for (;;) {
        signal?.throwIfAborted();
        if (this.browserQueue[0] === ticket &&
            !this.activeBrowser && this.activeImages === 0) {
          this.browserQueue.shift();
          this.activeBrowser = true;
          entered = true;
          this.notifyWaiters();
          for (const cleanup of this.browserTransitionCleanup) cleanup();
          break;
        }
        await this.waitForChange(signal);
      }
      return await operation(signal);
    } finally {
      if (entered) this.activeBrowser = false;
      else {
        const index = this.browserQueue.indexOf(ticket);
        if (index >= 0) this.browserQueue.splice(index, 1);
      }
      this.notifyWaiters();
    }
  }

  snapshot(): BrowserGateSnapshot {
    return {
      activeImages: this.activeImages,
      activeBrowser: this.activeBrowser,
      queuedBrowsers: this.browserQueue.length,
    };
  }

  private waitForChange(signal?: GateSignal): Promise<void> {
    signal?.throwIfAborted();
    return new Promise((resolve, reject) => {
      let settled = false;
      const cleanup = () => {
        this.waiters.delete(wake);
        signal?.removeEventListener("abort", onAbort);
      };
      const wake = () => {
        if (settled) return;
        settled = true;
        cleanup();
        resolve();
      };
      const onAbort = () => {
        if (settled) return;
        settled = true;
        cleanup();
        reject(signal?.reason ?? new Error("RESOURCE_GATE_ABORTED"));
      };
      this.waiters.add(wake);
      signal?.addEventListener("abort", onAbort, {once: true});
      if (signal?.aborted) onAbort();
    });
  }

  private notifyWaiters(): void {
    for (const wake of [...this.waiters]) wake();
  }
}

// import pipeline, import fallback, discovery, 진단 경로가 같은 인스턴스를 공유한다.
export const browserImageGate = new BrowserImageGate();
