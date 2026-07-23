import {createHash} from "node:crypto";

import type {ExpectedCountEvidence} from "./expected-count.js";
import type {ProgrammaticGalleryEvidence} from "./programmatic-gallery.js";
import type {
  ExtractionQuality,
  ExtractionQualityReason,
} from "./quality.js";
import type {ExtractionVersionSet} from "./version.js";

export type ReviewContract = {
  templateSignature: string;
  trustBaselineID: string;
  reviewSnapshotHash: string;
  reviewCandidateKeys: string[];
  trustEligible: boolean;
};

export function makeReviewContract(input: {
  brandID: string;
  sourceURL: string;
  strategy: string;
  candidateKeys: string[];
  expectedCountEvidence: ExpectedCountEvidence[];
  programmaticGalleryEvidence: ProgrammaticGalleryEvidence;
  quality: ExtractionQuality;
  candidateCount: number;
  renderedCandidateCount: number | null;
  contentHashComplete: boolean;
  versions: ExtractionVersionSet;
  structureTokens?: string[];
}): ReviewContract {
  const templateSignature = stableHash({
    strategy: input.strategy,
    expectedKinds: input.expectedCountEvidence
      .map((item) => item.kind)
      .sort(),
    programmaticSignals: [...input.programmaticGalleryEvidence.signals].sort(),
    rendered: input.renderedCandidateCount !== null,
    structureTokens: [...(input.structureTokens ?? [])].sort(),
  }, 32);
  const host = new URL(input.sourceURL).hostname.toLowerCase();
  const trustBaselineID = stableHash({
    brandID: input.brandID,
    host,
    templateSignature,
    extractorMajor: majorVersion(input.versions.extractorVersion),
    platformAdapterKey: input.versions.platformAdapterKey,
    platformAdapterVersion: input.versions.platformAdapterVersion,
    domainAdapterKey: input.versions.domainAdapterKey,
    domainAdapterVersion: input.versions.domainAdapterVersion,
  }, 40);
  const reviewCandidateKeys = [...input.candidateKeys];
  return {
    templateSignature,
    trustBaselineID,
    reviewCandidateKeys,
    reviewSnapshotHash: stableHash({
      candidateKeys: reviewCandidateKeys,
      quality: input.quality,
      templateSignature,
      versions: input.versions,
    }, 40),
    trustEligible: trustEligible({
      quality: input.quality,
      expectedCountEvidence: input.expectedCountEvidence,
      candidateCount: input.candidateCount,
      contentHashComplete: input.contentHashComplete,
    }),
  };
}

export function extractionStructureTokens(html: string): string[] {
  const tokens = new Set<string>();
  const relevant = new RegExp([
    "lookbook|archive|gallery|collection|campaign",
    "product|detail|editor|nneditor|xans",
  ].join("|"), "i");
  for (const match of html.matchAll(
    /<(?:main|article|section|div|ul|ol)\b[^>]*(?:id|class)=["']([^"']+)["']/gi,
  )) {
    String(match[1] ?? "")
      .split(/\s+/)
      .map((token) => token.trim().toLowerCase())
      .filter((token) => token.length > 0 && relevant.test(token))
      .forEach((token) => tokens.add(token.slice(0, 80)));
  }
  return Array.from(tokens).sort().slice(0, 40);
}

export function trustCanAutoApprove(
  quality: ExtractionQuality,
  trustEligible: boolean,
): boolean {
  return trustEligible && unsafeTrustReasons(quality.reasons).length === 0;
}

export function reviewDisposition(input: {
  trusted: boolean;
  quality: ExtractionQuality;
  trustEligible: boolean;
}): "materialize" | "awaitingReview" {
  return trustCanAutoApprove(input.quality, input.trustEligible) ?
    "materialize" :
    "awaitingReview";
}

function trustEligible(input: {
  quality: ExtractionQuality;
  expectedCountEvidence: ExpectedCountEvidence[];
  candidateCount: number;
  contentHashComplete: boolean;
}): boolean {
  if (!input.contentHashComplete) {
    return false;
  }
  const unsafeReasons = unsafeTrustReasons(input.quality.reasons);
  if (unsafeReasons.length > 0) {
    return false;
  }
  const expectedCounts = input.expectedCountEvidence.map((item) => item.value);
  return input.quality.status === "accepted" &&
    expectedCounts.includes(input.candidateCount);
}

function unsafeTrustReasons(
  reasons: ExtractionQualityReason[],
): ExtractionQualityReason[] {
  return reasons.filter(
    (reason) => reason !== "programmatic_gallery_requires_review",
  );
}

function majorVersion(version: string): string {
  return version.split(".")[0] ?? version;
}

function stableHash(value: unknown, length: number): string {
  return createHash("sha256")
    .update(JSON.stringify(value))
    .digest("hex")
    .slice(0, length);
}
