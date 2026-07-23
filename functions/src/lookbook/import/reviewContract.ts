/* eslint-disable require-jsdoc */
export type ExtractionReviewDecision =
  | "approved"
  | "approvedWithExclusions"
  | "insufficientImages";

export function requiredReviewDecision(
  value: unknown
): ExtractionReviewDecision {
  if (
    value === "approved" ||
    value === "approvedWithExclusions" ||
    value === "insufficientImages"
  ) {
    return value;
  }
  throw new Error("지원하지 않는 review decision입니다.");
}

export function approvedCandidateKeys(input: {
  decision: ExtractionReviewDecision;
  candidateKeys: string[];
  excludedCandidateKeys: string[];
}): string[] {
  const candidates = Array.from(new Set(input.candidateKeys));
  const candidateSet = new Set(candidates);
  const excluded = Array.from(new Set(input.excludedCandidateKeys));
  if (excluded.some((key) => !candidateSet.has(key))) {
    throw new Error("review snapshot에 없는 제외 후보가 포함됐습니다.");
  }
  if (input.decision === "approved" && excluded.length > 0) {
    throw new Error("정상 승인에는 제외 후보를 지정할 수 없습니다.");
  }
  if (
    input.decision === "approvedWithExclusions" &&
    excluded.length === 0
  ) {
    throw new Error("오탐 승인에는 제외 후보가 필요합니다.");
  }
  if (input.decision === "insufficientImages") {
    return [];
  }
  const excludedSet = new Set(excluded);
  const approved = candidates.filter((key) => !excludedSet.has(key));
  if (approved.length === 0) {
    throw new Error("승인할 이미지 후보가 없습니다.");
  }
  return approved;
}

export function nextGeneration(value: unknown): number {
  const current = Number.isInteger(value) && Number(value) >= 0 ?
    Number(value) :
    0;
  return current + 1;
}
