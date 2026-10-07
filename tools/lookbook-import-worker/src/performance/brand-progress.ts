import {performance} from "node:perf_hooks";

type Fields = {event: string; brandID?: string; seasonID?: string;
  attempt?: number; status?: string; atMs?: number};
export type ProgressLine = Fields & {runID: string; sequence: number;
  progressMs: number};

// OOM 전의 작은 경계 기록만 즉시 출력한다. 이미지/URL/인증은 받지 않는다.
export class BrandProgress {
  readonly controller = new AbortController();
  errorCode: "evidence-limit" | "evidence-write" | null = null;
  private tail: Promise<void> = Promise.resolve();
  private bytes = 0;
  private sequence = 0;
  private readonly started = performance.now();
  constructor(private readonly runID: string,
    private readonly write: (line: string) => Promise<void> = (line) =>
      new Promise((resolve, reject) => {
        process.stdout.write(line, (error) =>
          error ? reject(error) : resolve());
      }), private readonly limit = 256 * 1024) {}

  emit(fields: Fields): Promise<void> {
    const line: ProgressLine = {runID: this.runID, sequence: ++this.sequence,
      progressMs: performance.now() - this.started,
      event: fields.event,
      ...(fields.brandID === undefined ? {} : {brandID: fields.brandID}),
      ...(fields.seasonID === undefined ? {} : {seasonID: fields.seasonID}),
      ...(fields.attempt === undefined ? {} : {attempt: fields.attempt}),
      ...(fields.status === undefined ? {} : {status: fields.status}),
      ...(fields.atMs === undefined ? {} : {atMs: fields.atMs})};
    const serialized = `${JSON.stringify(line)}\n`;
    this.bytes += Buffer.byteLength(serialized);
    if (this.bytes > this.limit) this.fail("evidence-limit");
    const next = this.tail.then(async () => {
      if (this.errorCode) throw new Error(this.errorCode);
      try {
        await this.write(serialized);
      } catch {
        this.fail("evidence-write");
        throw new Error(this.errorCode ?? "evidence-write");
      }
    });
    // 소비자가 회수하기 전에 실패하더라도 unhandled rejection을 만들지 않는다.
    this.tail = next.catch(() => undefined);
    return next;
  }
  async drain(): Promise<void> {
    await this.tail;
  }
  private fail(code: NonNullable<BrandProgress["errorCode"]>): void {
    this.errorCode ??= code;
    this.controller.abort(new Error(this.errorCode));
  }
}
