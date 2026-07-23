import {
  extractionSourceEvidence,
  type ExtractionSourceEvidence,
} from "./evidence.js";
import {
  CURRENT_EXTRACTION_VERSIONS,
  type ExtractionVersionSet,
} from "./version.js";

export type ExtractionCandidateEvidence = {
  candidateKey: string;
  strategy: string;
  sourceKind: "static_dom" | "rendered_dom";
  source: ExtractionSourceEvidence;
};

export type ExtractionResult<Candidate> = {
  candidates: Candidate[];
  strategy: string;
  rawCandidateCount: number;
  candidateEvidence: ExtractionCandidateEvidence[];
  versions: ExtractionVersionSet;
};

export function extractionResult<Candidate>(input: {
  candidates: Candidate[];
  strategy: string;
  rawCandidateCount: number;
  sourceURL: string;
  candidateKey: (candidate: Candidate) => string;
  sourceKind?: "static_dom" | "rendered_dom";
  versions?: ExtractionVersionSet;
}): ExtractionResult<Candidate> {
  const source = extractionSourceEvidence(input.sourceURL);
  const sourceKind = input.sourceKind ?? "static_dom";
  return {
    candidates: input.candidates,
    strategy: input.strategy,
    rawCandidateCount: input.rawCandidateCount,
    candidateEvidence: input.candidates.map((candidate) => ({
      candidateKey: input.candidateKey(candidate),
      strategy: input.strategy,
      sourceKind,
      source,
    })),
    versions: input.versions ?? CURRENT_EXTRACTION_VERSIONS,
  };
}

export function extractionResultWithStrategy<Candidate>(
  result: ExtractionResult<Candidate>,
  strategy: string,
  sourceKind: "static_dom" | "rendered_dom",
): ExtractionResult<Candidate> {
  return {
    ...result,
    strategy,
    candidateEvidence: result.candidateEvidence.map((evidence) => ({
      ...evidence,
      strategy,
      sourceKind,
    })),
  };
}

export function mergeExtractionResults<Candidate>(input: {
  results: ExtractionResult<Candidate>[];
  strategy: string;
  candidateKey: (candidate: Candidate) => string;
}): ExtractionResult<Candidate> {
  const candidates: Candidate[] = [];
  const candidateEvidence: ExtractionCandidateEvidence[] = [];
  const seen = new Set<string>();
  input.results.forEach((result) => {
    result.candidates.forEach((candidate, index) => {
      const key = input.candidateKey(candidate);
      if (seen.has(key)) {
        return;
      }
      seen.add(key);
      candidates.push(candidate);
      const evidence = result.candidateEvidence[index];
      if (evidence !== undefined) {
        candidateEvidence.push(evidence);
      }
    });
  });
  return {
    candidates,
    strategy: input.strategy,
    rawCandidateCount: input.results.reduce(
      (count, result) => count + result.rawCandidateCount,
      0,
    ),
    candidateEvidence,
    versions: mergeExtractionVersionSets(
      input.results.map((result) => result.versions),
    ),
  };
}

export function mergeExtractionVersionSets(
  versions: ExtractionVersionSet[],
): ExtractionVersionSet {
  return versions.reduce((selected, candidate) => ({
    extractorVersion: candidate.extractorVersion,
    platformAdapterKey:
      candidate.platformAdapterKey ?? selected.platformAdapterKey,
    platformAdapterVersion:
      candidate.platformAdapterVersion ?? selected.platformAdapterVersion,
    domainAdapterKey: candidate.domainAdapterKey ?? selected.domainAdapterKey,
    domainAdapterVersion:
      candidate.domainAdapterVersion ?? selected.domainAdapterVersion,
  }), CURRENT_EXTRACTION_VERSIONS);
}

export function selectExtractionCandidates<Candidate>(input: {
  result: ExtractionResult<Candidate>;
  candidates: Candidate[];
  candidateKey: (candidate: Candidate) => string;
}): ExtractionResult<Candidate> {
  const evidenceByKey = new Map<string, ExtractionCandidateEvidence>();
  input.result.candidates.forEach((candidate, index) => {
    const evidence = input.result.candidateEvidence[index];
    if (evidence !== undefined) {
      evidenceByKey.set(input.candidateKey(candidate), evidence);
    }
  });
  return {
    ...input.result,
    candidates: input.candidates,
    candidateEvidence: input.candidates.flatMap((candidate) => {
      const evidence = evidenceByKey.get(input.candidateKey(candidate));
      return evidence === undefined ? [] : [evidence];
    }),
  };
}
