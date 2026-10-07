import {readFileSync} from "node:fs";
import {monitorEventLoopDelay, performance} from "node:perf_hooks";
import sharp from "sharp";

export type ContainerMemory = {
  source: "cgroup-v2" | "cgroup-v1";
  usedBytes: number;
  limitBytes: number;
};

export async function readContainerMemory(
  // 작은 cgroup 상태 파일만 동기로 읽어 변환 작업 풀의 대기를 피한다.
  read: (path: string) => Promise<string> =
  async (path) => readFileSync(path, "utf8"),
): Promise<ContainerMemory | null> {
  for (const [source, usagePath, limitPath] of [
    ["cgroup-v2", "/sys/fs/cgroup/memory.current",
      "/sys/fs/cgroup/memory.max"],
    ["cgroup-v1",
      "/sys/fs/cgroup/memory/memory.usage_in_bytes",
      "/sys/fs/cgroup/memory/memory.limit_in_bytes"],
  ] as const) {
    try {
      const [used, limit] = await Promise.all([
        read(usagePath), read(limitPath),
      ]);
      const usedBytes = Number(used.trim());
      const limitBytes = Number(limit.trim());
      if (used.trim() && limit.trim() &&
        Number.isSafeInteger(usedBytes) && usedBytes >= 0 &&
        Number.isSafeInteger(limitBytes) && limitBytes > 0) {
        return {source, usedBytes, limitBytes};
      }
    } catch {
      // 미지원 환경을 사용량 0으로 취급하지 않는다.
    }
  }
  return null;
}

// Worker의 짧은 보호 표본은 작은 cgroup 파일을 동기로 읽는다.
export function readContainerMemorySync(
  read: (path: string) => string = (path) => readFileSync(path, "utf8"),
): ContainerMemory | null {
  for (const [source, usagePath, limitPath] of [
    ["cgroup-v2", "/sys/fs/cgroup/memory.current",
      "/sys/fs/cgroup/memory.max"],
    ["cgroup-v1",
      "/sys/fs/cgroup/memory/memory.usage_in_bytes",
      "/sys/fs/cgroup/memory/memory.limit_in_bytes"],
  ] as const) {
    try {
      const used = read(usagePath).trim();
      const limit = read(limitPath).trim();
      const usedBytes = Number(used);
      const limitBytes = Number(limit);
      if (used && limit && Number.isSafeInteger(usedBytes) && usedBytes >= 0 &&
          Number.isSafeInteger(limitBytes) && limitBytes > 0) {
        return {source, usedBytes, limitBytes};
      }
    } catch {
      // 환경을 추정하지 않고 다음 cgroup layout만 확인한다.
    }
  }
  return null;
}

export function startResourceSampling(): {stop: () => Promise<unknown>} {
  const startedCPU = process.cpuUsage();
  const delay = monitorEventLoopDelay({resolution: 20});
  delay.enable();
  let samples = 0;
  let missingContainerSamples = 0;
  let maxRSSBytes = 0;
  let maxExternalBytes = 0;
  let maxArrayBufferBytes = 0;
  let maxHeapUsedBytes = 0;
  let maxContainerRatio: number | null = null;
  let maxSharpQueue = 0;
  let maxSharpProcess = 0;
  let maxSampleGapMs = 0;
  let previousSampleAt: number | null = null;
  let containerSource: string | null = null;
  let pending: Promise<void> | null = null;
  let missedTicks = 0;
  let samplingErrors = 0;
  const sample = async (): Promise<void> => {
    const now = performance.now();
    if (previousSampleAt !== null) {
      maxSampleGapMs = Math.max(maxSampleGapMs, now - previousSampleAt);
    }
    previousSampleAt = now;
    samples += 1;
    const memory = process.memoryUsage();
    maxRSSBytes = Math.max(maxRSSBytes, memory.rss);
    maxExternalBytes = Math.max(maxExternalBytes, memory.external);
    maxArrayBufferBytes = Math.max(maxArrayBufferBytes, memory.arrayBuffers);
    maxHeapUsedBytes = Math.max(maxHeapUsedBytes, memory.heapUsed);
    const counters = sharp.counters();
    maxSharpQueue = Math.max(maxSharpQueue, counters.queue);
    maxSharpProcess = Math.max(maxSharpProcess, counters.process);
    const container = await readContainerMemory();
    if (container === null) {
      missingContainerSamples += 1;
    } else {
      containerSource = container.source;
      maxContainerRatio = Math.max(maxContainerRatio ?? 0,
        container.usedBytes / container.limitBytes);
    }
  };
  const safeSample = async (): Promise<void> => {
    try {
      await sample();
    } catch {
      samplingErrors += 1;
    }
  };
  const tick = (): void => {
    if (pending !== null) {
      missedTicks += 1;
      return;
    }
    pending = safeSample().finally(() => {
      pending = null;
    });
  };
  tick();
  const timer = setInterval(tick, 100);
  timer.unref();
  return {
    async stop(): Promise<unknown> {
      clearInterval(timer);
      try {
        await pending;
        await safeSample();
      } finally {
        delay.disable();
      }
      const cpu = process.cpuUsage(startedCPU);
      return {
        scope: "shared-process-and-container-not-per-job",
        samples, missedTicks, samplingErrors, maxSampleGapMs,
        sampleIntervalMs: 100,
        cpuUserMicros: cpu.user, cpuSystemMicros: cpu.system,
        maxRSSBytes, maxHeapUsedBytes, maxExternalBytes, maxArrayBufferBytes,
        maxSharpQueue, maxSharpProcess, sharpConcurrency: sharp.concurrency(),
        eventLoopMaxMs: delay.max / 1e6,
        eventLoopMeanMs: Number.isFinite(delay.mean) ? delay.mean / 1e6 : null,
        containerSource, maxContainerRatio, missingContainerSamples,
        containerMemoryAvailable: samples > 0 && samplingErrors === 0 &&
          missingContainerSamples === 0,
        versions: {node: process.version, sharp: sharp.versions},
      };
    },
  };
}
