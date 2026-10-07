import {AsyncLocalStorage} from "node:async_hooks";
import {createHash, randomUUID} from "node:crypto";
import {performance} from "node:perf_hooks";

export const STAGES = [
  "job", "html.download", "html.render", "image.download", "image.hash",
  "image.transform", "file.upload", "paths.save", "asset",
] as const;
export type Stage = typeof STAGES[number];
export type StageMetrics = {
  started: number;
  succeeded: number;
  failed: number;
  active: number;
  peakActive: number;
  totalMs: number;
  maxMs: number;
  receivedBytes: number;
  submittedBytes: number;
  completedBytes: number;
};
export type MeasurementContext = {
  sourceRevision: string;
  instanceID: string;
  mode: "task" | "wake" | "local-extraction" | "local-assets" |
    "local-connected" | "remote-connected";
  inputDigest?: string;
  settingsDigest?: string;
  batchID?: string;
};
export type Measurement = {
  schemaVersion: 1;
  runID: string;
  batchID: string | null;
  sourceRevision: string;
  instanceKey: string;
  mode: MeasurementContext["mode"];
  inputDigest: string | null;
  settingsDigest: string | null;
  startedAt: string;
  durationMs: number;
  operationOutcome: "returned" | "threw";
  complete: boolean;
  stages: Record<Stage, StageMetrics>;
  jobOutcomes: Record<string, number>;
};

const context = new AsyncLocalStorage<MetricsRecorder>();

export class MetricsRecorder {
  private readonly start: number;
  private readonly startedAt = new Date().toISOString();
  private readonly runID = randomUUID();
  private readonly stages = Object.fromEntries(STAGES.map((stage) => [stage, {
    started: 0, succeeded: 0, failed: 0, active: 0, peakActive: 0,
    totalMs: 0, maxMs: 0,
    receivedBytes: 0, submittedBytes: 0, completedBytes: 0,
  }])) as Record<Stage, StageMetrics>;
  private readonly jobOutcomes: Record<string, number> = {};
  private invalid = false;
  private ended = false;

  constructor(
    private readonly identity: MeasurementContext,
    private readonly now: () => number = () => performance.now(),
  ) {
    this.start = now();
  }

  run<T>(operation: () => T): T {
    return context.run(this, operation);
  }

  begin(stage: Stage): (succeeded: boolean) => void {
    const metric = this.stages[stage];
    if (this.ended) {
      this.invalid = true;
      return () => undefined;
    }
    metric.started += 1;
    metric.active += 1;
    metric.peakActive = Math.max(metric.peakActive, metric.active);
    const start = this.now();
    let finished = false;
    return (succeeded) => {
      if (finished) return;
      finished = true;
      const elapsed = this.now() - start;
      if (!Number.isFinite(elapsed) || elapsed < 0) this.invalid = true;
      metric.active -= 1;
      metric[succeeded ? "succeeded" : "failed"] += 1;
      metric.totalMs += Math.max(0, elapsed);
      metric.maxMs = Math.max(metric.maxMs, elapsed);
    };
  }

  bytes(
    stage: Stage,
    kind: "receivedBytes" | "submittedBytes" | "completedBytes",
    count: number,
  ): void {
    if (!Number.isSafeInteger(count) || count < 0) {
      this.invalid = true;
      return;
    }
    const total = this.stages[stage][kind] + count;
    if (!Number.isSafeInteger(total)) {
      this.invalid = true;
      return;
    }
    this.stages[stage][kind] = total;
  }

  jobOutcome(status: string): void {
    const allowed = [
      "queued", "processing", "awaitingReview", "awaitingRepairReview",
      "succeeded", "partialFailed", "failed", "cancelled", "skipped",
    ];
    const key = allowed.includes(status) ? status : "other";
    this.jobOutcomes[key] = (this.jobOutcomes[key] ?? 0) + 1;
  }

  finish(operationOutcome: Measurement["operationOutcome"]): Measurement {
    this.ended = true;
    const durationMs = this.now() - this.start;
    return {
      schemaVersion: 1,
      runID: this.runID,
      batchID: validBatchID(this.identity.batchID),
      sourceRevision: /^[a-f0-9]{7,64}$/.test(this.identity.sourceRevision) ?
        this.identity.sourceRevision : "unknown",
      instanceKey: createHash("sha256")
        .update(this.identity.instanceID).digest("hex").slice(0, 24),
      mode: this.identity.mode,
      inputDigest: validDigest(this.identity.inputDigest),
      settingsDigest: validDigest(this.identity.settingsDigest),
      startedAt: this.startedAt,
      durationMs,
      operationOutcome,
      complete: !this.invalid && Number.isFinite(durationMs) &&
        durationMs >= 0 && STAGES.every((s) => this.stages[s].active === 0),
      stages: Object.fromEntries(STAGES.map((s) => [s, {...this.stages[s]}])) as
        Record<Stage, StageMetrics>,
      jobOutcomes: {...this.jobOutcomes},
    };
  }
}

export function measured<T>(
  stage: Stage, operation: () => Promise<T>,
): Promise<T> {
  const recorder = context.getStore();
  if (!recorder) return operation();
  return measureWithRecorder(recorder, stage, operation);
}

async function measureWithRecorder<T>(
  recorder: MetricsRecorder,
  stage: Stage,
  operation: () => Promise<T>,
): Promise<T> {
  const end = recorder.begin(stage);
  try {
    const result = await operation();
    end(true);
    return result;
  } catch (error) {
    end(false);
    throw error;
  }
}

export function measuredSync<T>(stage: Stage, operation: () => T): T {
  const recorder = context.getStore();
  if (!recorder) return operation();
  const end = recorder.begin(stage);
  try {
    const result = operation();
    end(true);
    return result;
  } catch (error) {
    end(false);
    throw error;
  }
}

export function recordBytes(
  stage: Stage,
  kind: "receivedBytes" | "submittedBytes" | "completedBytes",
  count: number,
): void {
  context.getStore()?.bytes(stage, kind, count);
}

export function recordJobOutcome(status: string): void {
  context.getStore()?.jobOutcome(status);
}

function validDigest(value: string | undefined): string | null {
  return value && /^[a-f0-9]{64}$/.test(value) ? value : null;
}

function validBatchID(value: string | undefined): string | null {
  return typeof value === "string" &&
    /^[a-f0-9]{64}$/.test(value) ? value : null;
}
