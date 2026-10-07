import {MetricsRecorder, type MeasurementContext} from "./metrics.js";
import {startResourceSampling} from "./resources.js";

export type PerformanceOptions = {
  enabled: boolean;
  sourceRevision: string;
  instanceID: string;
  inputDigest?: string;
  settingsDigest?: string;
  emit?: (report: unknown) => void;
};

export async function withMeasurement<T>(
  options: PerformanceOptions | undefined,
  mode: MeasurementContext["mode"],
  operation: () => Promise<T>,
  correlation: Pick<MeasurementContext, "batchID"> = {},
): Promise<T> {
  if (!options?.enabled) return operation();
  const recorder = new MetricsRecorder({...options, ...correlation, mode});
  const resources = startResourceSampling();
  let outcome: "returned" | "threw" = "threw";
  try {
    const result = await recorder.run(operation);
    outcome = "returned";
    return result;
  } finally {
    const measurement = recorder.finish(outcome);
    try {
      const report = {measurement, resources: await resources.stop()};
      if (options.emit) options.emit(report);
      else console.log("[lookbook-import-performance]", JSON.stringify(report));
    } catch {
      // 계측 출력 실패로 제품 작업을 다시 시도하지 않는다.
      console.warn("[lookbook-import-performance] report unavailable");
    }
  }
}
