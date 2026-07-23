import {
  CURRENT_EXTRACTOR_VERSION,
  currentAdapterVersionsMatch,
} from "./adapters/registry.js";

export type ExtractionVersionSet = {
  extractorVersion: string;
  platformAdapterKey: string | null;
  platformAdapterVersion: string | null;
  domainAdapterKey: string | null;
  domainAdapterVersion: string | null;
};

export const CURRENT_EXTRACTION_VERSIONS: ExtractionVersionSet = Object.freeze({
  extractorVersion: CURRENT_EXTRACTOR_VERSION,
  platformAdapterKey: null,
  platformAdapterVersion: null,
  domainAdapterKey: null,
  domainAdapterVersion: null,
});

export function isReusableExtractionCache(input: {
  candidateCount: number;
  extractorVersion: unknown;
  platformAdapterKey: unknown;
  platformAdapterVersion: unknown;
  domainAdapterKey: unknown;
  domainAdapterVersion: unknown;
  qualityStatus: unknown;
  contentHashResolutionComplete: unknown;
}): boolean {
  return input.candidateCount > 0 &&
    input.extractorVersion === CURRENT_EXTRACTION_VERSIONS.extractorVersion &&
    currentAdapterVersionsMatch(input) &&
    (
      input.qualityStatus === "accepted" ||
      input.qualityStatus === "needsReview"
    ) &&
    input.contentHashResolutionComplete === true;
}
