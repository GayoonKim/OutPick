import type {
  ExpectedCandidateSpec,
  FixtureDifferential,
  FixtureExpected,
  FixtureSnapshot,
} from "./types.js";

export function expandExpectedCandidates(
  specs: ExpectedCandidateSpec[],
): Array<{key: string; title?: string}> {
  return specs.flatMap((spec) => {
    if (spec.type === "exact") {
      return [{key: spec.key, title: spec.title}];
    }
    return Array.from(
      {length: spec.end - spec.start + 1},
      (_, offset) => ({
        key: spec.template.replace("{index}", String(spec.start + offset)),
      }),
    );
  });
}

export function expectedSnapshot(expected: FixtureExpected): FixtureSnapshot {
  const candidates = expandExpectedCandidates(expected.candidates);
  return {
    candidateKeys: candidates.map((candidate) => candidate.key),
    candidateTitles: Object.fromEntries(candidates.flatMap((candidate) =>
      candidate.title === undefined ? [] : [[candidate.key, candidate.title]])),
    strategy: expected.strategy,
    adapter: expected.adapter,
    quality: expected.quality,
  };
}

export function fixtureDifferential(
  before: FixtureSnapshot,
  after: FixtureSnapshot,
): FixtureDifferential {
  const beforeSet = new Set(before.candidateKeys);
  const afterSet = new Set(after.candidateKeys);
  const sharedKeys = before.candidateKeys.filter((key) => afterSet.has(key));
  const movedCandidates = sharedKeys.flatMap((key) => {
    const beforeIndex = before.candidateKeys.indexOf(key);
    const afterIndex = after.candidateKeys.indexOf(key);
    return beforeIndex === afterIndex ? [] : [{key, beforeIndex, afterIndex}];
  });
  const titleChanges = sharedKeys.flatMap((key) => {
    const beforeTitle = before.candidateTitles[key];
    const afterTitle = after.candidateTitles[key];
    if (
      beforeTitle === undefined ||
      afterTitle === undefined ||
      beforeTitle === afterTitle
    ) {
      return [];
    }
    return [{key, before: beforeTitle, after: afterTitle}];
  });
  return {
    addedCandidateKeys: after.candidateKeys.filter(
      (key) => !beforeSet.has(key),
    ),
    removedCandidateKeys: before.candidateKeys.filter(
      (key) => !afterSet.has(key),
    ),
    movedCandidates,
    titleChanges,
    strategyChange: before.strategy === after.strategy ? null : {
      before: before.strategy,
      after: after.strategy,
    },
    adapterChange: deepEqual(before.adapter, after.adapter) ? null : {
      before: before.adapter,
      after: after.adapter,
    },
    qualityChange: deepEqual(before.quality, after.quality) ? null : {
      before: before.quality,
      after: after.quality,
    },
  };
}

export function differentialIsEmpty(diff: FixtureDifferential): boolean {
  return diff.addedCandidateKeys.length === 0 &&
    diff.removedCandidateKeys.length === 0 &&
    diff.movedCandidates.length === 0 &&
    diff.titleChanges.length === 0 &&
    diff.strategyChange === null &&
    diff.adapterChange === null &&
    diff.qualityChange === null;
}

function deepEqual(lhs: unknown, rhs: unknown): boolean {
  return JSON.stringify(lhs) === JSON.stringify(rhs);
}
