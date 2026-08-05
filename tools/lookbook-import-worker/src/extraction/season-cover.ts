/* eslint-disable max-len */
import {extractSeasonCoverImageCandidate} from "./image-candidates.js";

export type CoverImageSource = "list" | "detail" | "none";

export type SeasonCoverCandidate = {
  title: string;
  seasonURL: string;
  coverImageURL: string | null;
  coverImageSource: CoverImageSource;
  coverImageStrategy: string | null;
  score: number;
};

export type SeasonCoverSummary = {
  coverImageCount: number;
  listCoverImageCount: number;
  detailCoverAttemptCount: number;
  detailCoverSuccessCount: number;
  detailCoverFailureCount: number;
  detailCoverSkippedCount: number;
};

export type SeasonCoverEnrichment = {
  candidates: SeasonCoverCandidate[];
  summary: SeasonCoverSummary;
};

export const SEASON_COVER_LIMITS = Object.freeze({
  maxAttempts: 30,
  concurrency: 3,
  budgetMs: 15_000,
});

export async function enrichSeasonCovers(input: {
  candidates: SeasonCoverCandidate[];
  overallDeadlineAt: number;
  fetchHTML: (url: string, signal: AbortSignal) => Promise<string>;
  now?: () => number;
  limits?: Partial<typeof SEASON_COVER_LIMITS>;
}): Promise<SeasonCoverEnrichment> {
  const now = input.now ?? Date.now;
  const limits = {
    ...SEASON_COVER_LIMITS,
    ...input.limits,
  };
  const candidates = input.candidates.map((candidate) => ({...candidate}));
  const missingIndexes = candidates.flatMap((candidate, index) =>
    candidate.coverImageURL === null ? [index] : [],
  );
  const targetIndexes = missingIndexes.slice(0, limits.maxAttempts);
  const budgetEndsAt = Math.min(
    now() + Math.max(0, limits.budgetMs),
    input.overallDeadlineAt,
  );
  const controller = new AbortController();
  const remainingMs = Math.max(0, budgetEndsAt - now());
  const timeout = setTimeout(() => controller.abort(), remainingMs);
  let cursor = 0;
  let attemptCount = 0;
  let successCount = 0;
  let failureCount = 0;

  const workers = Array.from(
    {length: Math.min(limits.concurrency, targetIndexes.length)},
    async () => {
      for (;;) {
        if (controller.signal.aborted || now() >= budgetEndsAt) {
          controller.abort();
          return;
        }
        const targetOffset = cursor;
        cursor += 1;
        const candidateIndex = targetIndexes[targetOffset];
        if (candidateIndex === undefined) {
          return;
        }
        const candidate = candidates[candidateIndex];
        attemptCount += 1;
        try {
          const html = await input.fetchHTML(
            candidate.seasonURL,
            controller.signal,
          );
          const cover = extractSeasonCoverImageCandidate(
            html,
            candidate.seasonURL,
          );
          if (cover === null) {
            failureCount += 1;
            continue;
          }
          candidates[candidateIndex] = {
            ...candidate,
            coverImageURL: cover.sourceURL,
            coverImageSource: "detail",
            coverImageStrategy: cover.strategy,
          };
          successCount += 1;
        } catch {
          failureCount += 1;
        }
      }
    },
  );

  try {
    await Promise.all(workers);
  } finally {
    clearTimeout(timeout);
  }

  const listCoverImageCount = candidates.filter(
    (candidate) => candidate.coverImageSource === "list",
  ).length;
  return {
    candidates,
    summary: {
      coverImageCount: listCoverImageCount + successCount,
      listCoverImageCount,
      detailCoverAttemptCount: attemptCount,
      detailCoverSuccessCount: successCount,
      detailCoverFailureCount: failureCount,
      detailCoverSkippedCount: Math.max(0, missingIndexes.length - attemptCount),
    },
  };
}
