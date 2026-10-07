import {createHash} from "node:crypto";
import {measuredSync} from "../performance/metrics.js";
import {observeBuffer} from "../performance/buffer-inventory.js";
import {inStage, type PipelineRuntime} from "../pipeline/resources.js";
import {mapScheduled} from "../pipeline/scheduling.js";
import {browserImageGate} from "../queue/browser-gate.js";

export function canonicalCandidateURL(sourceURL: string): string {
  const url = new URL(sourceURL);
  url.hash = "";
  const sortedEntries = Array.from(url.searchParams.entries())
    .sort(([lhsKey, lhsValue], [rhsKey, rhsValue]) =>
      lhsKey.localeCompare(rhsKey) || lhsValue.localeCompare(rhsValue));
  url.search = "";
  sortedEntries.forEach(([key, value]) => url.searchParams.append(key, value));
  return url.toString();
}

export function mergeCanonicalCandidates<Candidate extends {sourceURL: string}>(
  groups: Candidate[][],
): Candidate[] {
  const candidates: Candidate[] = [];
  const seen = new Set<string>();
  for (const candidate of groups.flat()) {
    const key = canonicalCandidateURL(candidate.sourceURL);
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    candidates.push(candidate);
  }
  return candidates;
}

export function imageContentHash(bytes: Uint8Array): string {
  return measuredSync("image.hash", () =>
    createHash("sha256").update(bytes).digest("hex"));
}

export function dedupeCandidatesByContentHash<
  Candidate extends {sourceURL: string},
>(
  candidates: Candidate[],
  contentHashByCanonicalURL: ReadonlyMap<string, string>,
): Candidate[] {
  const seenHashes = new Set<string>();
  return candidates.filter((candidate) => {
    const hash = contentHashByCanonicalURL.get(
      canonicalCandidateURL(candidate.sourceURL),
    );
    if (hash === undefined || seenHashes.has(hash)) {
      return hash === undefined;
    }
    seenHashes.add(hash);
    return true;
  });
}

export type ContentHashDedupeResult<Candidate> = {
  candidates: Candidate[];
  contentHashes: Array<{
    canonicalURL: string;
    contentHash: string;
  }>;
  sourceCandidateCount: number;
  resolvedCandidateCount: number;
  contentHashCandidateCount: number;
  failureCount: number;
  complete: boolean;
};

export async function resolveContentHashDedupe<
  Candidate extends {sourceURL: string},
>(input: {
  candidates: Candidate[];
  loadBytes: (candidate: Candidate) => Promise<Uint8Array | null>;
  concurrency?: number;
  pipeline?: PipelineRuntime;
  onHashedBytes?: (candidate: Candidate, bytes: Uint8Array) => void;
}): Promise<ContentHashDedupeResult<Candidate>> {
  const candidates = mergeCanonicalCandidates([input.candidates]);
  const hashes = new Map<string, string>();
  let cursor = 0;
  let failureCount = 0;
  const concurrency = Math.max(
    1,
    Math.min(input.concurrency ?? 4, candidates.length),
  );
  const resolveCandidate = async (candidate: Candidate): Promise<void> => {
    try {
      await browserImageGate.withImageWork(async () => {
        const bytes = await inStage(input.pipeline, "download", () =>
          input.loadBytes(candidate));
        if (bytes === null || bytes.byteLength === 0) {
          failureCount += 1;
          return;
        }
        const release = observeBuffer("source", bytes);
        try {
          hashes.set(
            canonicalCandidateURL(candidate.sourceURL),
            imageContentHash(bytes),
          );
          input.onHashedBytes?.(candidate, bytes);
        } finally {
          release();
        }
      }, input.pipeline?.signal);
    } catch {
      if (input.pipeline?.signal?.aborted) throw input.pipeline.signal.reason;
      failureCount += 1;
    }
  };
  if (input.pipeline) {
    await mapScheduled(candidates, input.pipeline.hashes, resolveCandidate,
      input.pipeline.signal);
  } else {
    await Promise.all(Array.from({length: concurrency}, async () => {
      for (;;) {
        const index = cursor;
        cursor += 1;
        const candidate = candidates[index];
        if (candidate === undefined) return;
        await resolveCandidate(candidate);
      }
    }));
  }
  const deduped = dedupeCandidatesByContentHash(candidates, hashes);
  return {
    candidates: deduped,
    contentHashes: Array.from(hashes, ([canonicalURL, contentHash]) => ({
      canonicalURL,
      contentHash,
    })),
    sourceCandidateCount: candidates.length,
    resolvedCandidateCount: hashes.size,
    contentHashCandidateCount: deduped.length,
    failureCount,
    complete: failureCount === 0,
  };
}
