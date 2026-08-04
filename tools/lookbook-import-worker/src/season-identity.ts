/* eslint-disable max-len */
export type ExistingSeasonIdentity = {
  seasonID: string;
  title: string;
  sourceURL: string;
};

export type DiscoveryCandidateIdentity = {
  candidateID: string;
  title: string;
  seasonURL: string;
};

export type CandidateResolution =
  | "newSeason"
  | "matchedByURL"
  | "matchedByUniqueNormalizedTitle"
  | "awaitingReviewAmbiguousTitle"
  | "awaitingReviewConflictingMatch"
  | "awaitingReviewDuplicateConvergence";

export type ResolvedCandidateIdentity = DiscoveryCandidateIdentity & {
  normalizedTitleKey: string | null;
  resolution: CandidateResolution;
  matchedSeasonID: string | null;
};

const GENERIC_TITLE_PATTERN = /^(?:lookbook|collection|campaign|season|new collection)$/;

export function canonicalSeasonURL(rawValue: string): string {
  const parsed = new URL(rawValue);
  parsed.protocol = parsed.protocol.toLowerCase();
  parsed.hostname = parsed.hostname.toLowerCase();
  parsed.hash = "";
  if ((parsed.protocol === "https:" && parsed.port === "443") ||
      (parsed.protocol === "http:" && parsed.port === "80")) parsed.port = "";
  Array.from(parsed.searchParams.keys())
    .filter((key) => /^utm_|^(?:fbclid|gclid)$/i.test(key))
    .forEach((key) => parsed.searchParams.delete(key));
  parsed.searchParams.sort();
  return parsed.toString();
}

export function normalizedSeasonTitleKey(rawTitle: string): string | null {
  const plain = rawTitle.normalize("NFKC").toLowerCase()
    .replace(/spring\s*[/]?\s*summer|s\s*[/]\s*s/g, " ss ")
    .replace(/fall\s*[/]?\s*winter|autumn\s*[/]?\s*winter|f\s*[/]\s*w/g, " fw ")
    .replace(/\b(20)?(\d{2})\s*(ss|fw)\b/g, "$2 $3")
    .replace(/\b(ss|fw)\s*(20)?(\d{2})\b/g, "$3 $1")
    .replace(/[^a-z0-9가-힣]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
  if (!plain || GENERIC_TITLE_PATTERN.test(plain)) return null;
  const seasonal = plain.match(/(?:^| )(\d{2})(?: |)(ss|fw)(?: |$)/);
  if (seasonal) return `${seasonal[1]}-${seasonal[2]}`;
  return plain;
}

export function resolveSeasonCandidateIdentities(
  candidates: DiscoveryCandidateIdentity[],
  existingSeasons: ExistingSeasonIdentity[],
): ResolvedCandidateIdentity[] {
  const existingByURL = new Map<string, ExistingSeasonIdentity[]>();
  const existingByTitle = new Map<string, ExistingSeasonIdentity[]>();
  for (const season of existingSeasons) {
    append(existingByURL, canonicalSeasonURL(season.sourceURL), season);
    const key = normalizedSeasonTitleKey(season.title);
    if (key) append(existingByTitle, key, season);
  }

  const resolved = candidates.map((candidate): ResolvedCandidateIdentity => {
    const key = normalizedSeasonTitleKey(candidate.title);
    const urlMatches = existingByURL.get(canonicalSeasonURL(candidate.seasonURL)) ?? [];
    const titleMatches = key ? existingByTitle.get(key) ?? [] : [];
    if (urlMatches.length === 1) {
      if (titleMatches.length > 0 &&
          !titleMatches.some((item) => item.seasonID === urlMatches[0].seasonID)) {
        return result(candidate, key, "awaitingReviewConflictingMatch", null);
      }
      return result(candidate, key, "matchedByURL", urlMatches[0].seasonID);
    }
    if (urlMatches.length > 1 || titleMatches.length > 1 || key === null) {
      return result(candidate, key, "awaitingReviewAmbiguousTitle", null);
    }
    if (titleMatches.length === 1) {
      return result(
        candidate, key, "matchedByUniqueNormalizedTitle", titleMatches[0].seasonID,
      );
    }
    return result(candidate, key, "newSeason", null);
  });

  const convergence = new Map<string, number>();
  resolved.forEach((item) => {
    if (item.matchedSeasonID) {
      convergence.set(item.matchedSeasonID, (convergence.get(item.matchedSeasonID) ?? 0) + 1);
    }
  });
  return resolved.map((item) => item.matchedSeasonID &&
      (convergence.get(item.matchedSeasonID) ?? 0) > 1 ?
    result(item, item.normalizedTitleKey, "awaitingReviewDuplicateConvergence", null) :
    item);
}

function append<T>(map: Map<string, T[]>, key: string, value: T): void {
  map.set(key, [...(map.get(key) ?? []), value]);
}

function result(
  candidate: DiscoveryCandidateIdentity,
  normalizedTitleKey: string | null,
  resolution: CandidateResolution,
  matchedSeasonID: string | null,
): ResolvedCandidateIdentity {
  return {...candidate, normalizedTitleKey, resolution, matchedSeasonID};
}
