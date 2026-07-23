import type {
  ExtractionQualityReason,
  ExtractionQualityStatus,
} from "../extraction/quality.js";

export type FixtureKind = "discovery" | "season_images";
export type FixtureClassification = "generic" | "platform" | "incident";

export type FixtureMetadata = {
  schemaVersion: 1;
  id: string;
  kind: FixtureKind;
  classification: FixtureClassification;
  sourceURL: string;
  inputFile: string;
  renderedFile?: string;
  provenance: {
    kind: "synthetic" | "incident_minimized";
    issue: string;
  };
};

export type ExpectedCandidateSpec =
  | {type: "exact"; key: string; title?: string}
  | {type: "numeric_range"; template: string; start: number; end: number};

export type FixtureExpected = {
  schemaVersion: 1;
  candidates: ExpectedCandidateSpec[];
  negativeCandidateKeys: string[];
  orderPolicy: "strict" | "relative";
  strategy: string;
  adapter: {
    platformKey: string | null;
    domainKey: string | null;
  };
  quality: {
    status: ExtractionQualityStatus;
    reasons: ExtractionQualityReason[];
  } | null;
};

export type FixtureCase = {
  directory: string;
  metadata: FixtureMetadata;
  expected: FixtureExpected;
  inputHTML: string;
  renderedHTML: string | null;
};

export type FixtureSnapshot = {
  candidateKeys: string[];
  candidateTitles: Record<string, string>;
  strategy: string;
  adapter: {
    platformKey: string | null;
    domainKey: string | null;
  };
  quality: FixtureExpected["quality"];
};

export type CandidateMove = {
  key: string;
  beforeIndex: number;
  afterIndex: number;
};

export type FixtureDifferential = {
  addedCandidateKeys: string[];
  removedCandidateKeys: string[];
  movedCandidates: CandidateMove[];
  titleChanges: Array<{key: string; before: string; after: string}>;
  strategyChange: {before: string; after: string} | null;
  adapterChange: {
    before: FixtureSnapshot["adapter"];
    after: FixtureSnapshot["adapter"];
  } | null;
  qualityChange: {
    before: FixtureSnapshot["quality"];
    after: FixtureSnapshot["quality"];
  } | null;
};

export type FixtureEvaluation = {
  fixtureID: string;
  passed: boolean;
  errors: string[];
  differential: FixtureDifferential;
  current: FixtureSnapshot;
};
