import {AsyncLocalStorage} from "node:async_hooks";

type Kind = "source" | "jpeg";
type Counts = {bytes: number; peakBytes: number; references: number};
const active = new AsyncLocalStorage<BufferInventory>();

// 같은 객체는 한 번 세지만 서로 다른 view/원본 캐시/native 메모리와 합산하지 않는다.
export class BufferInventory {
  private readonly held = new Map<Uint8Array, Map<Kind, number>>();
  private bytes = 0;
  private peakBytes = 0;
  private readonly kinds: Record<Kind, Counts> = {
    source: {bytes: 0, peakBytes: 0, references: 0},
    jpeg: {bytes: 0, peakBytes: 0, references: 0},
  };

  run<T>(operation: () => T): T {
    return active.run(this, operation);
  }

  retain(kind: Kind, bytes: Uint8Array): () => void {
    let refs = this.held.get(bytes);
    if (!refs) {
      refs = new Map();
      this.held.set(bytes, refs);
      this.bytes += bytes.byteLength;
      this.peakBytes = Math.max(this.peakBytes, this.bytes);
    }
    const count = refs.get(kind) ?? 0;
    const totals = this.kinds[kind];
    if (count === 0) {
      totals.bytes += bytes.byteLength;
      totals.peakBytes = Math.max(totals.peakBytes, totals.bytes);
    }
    totals.references++;
    refs.set(kind, count + 1);
    let released = false;
    return () => {
      if (released) return;
      released = true;
      const count = refs.get(kind) ?? 0;
      if (count === 0) throw new Error("보유 참조의 회계가 일치하지 않습니다.");
      totals.references--;
      if (count === 1) {
        refs.delete(kind);
        totals.bytes -= bytes.byteLength;
      } else {
        refs.set(kind, count - 1);
      }
      if (refs.size === 0) {
        this.held.delete(bytes);
        this.bytes -= bytes.byteLength;
      }
    };
  }

  snapshot() {
    return {scope: "logical-payload-not-rss-or-cache",
      currentBytes: this.bytes, peakBytes: this.peakBytes,
      objects: this.held.size,
      source: {...this.kinds.source}, jpeg: {...this.kinds.jpeg}};
  }
}

export function observeBuffer(kind: Kind, bytes: Uint8Array): () => void {
  return active.getStore()?.retain(kind, bytes) ?? (() => undefined);
}
