import type {ExtractionVersionSet} from "../version.js";

export type ExtractionKind = "discovery" | "season_images";

export type ExtractionAdapterContext = {
  html: string;
  sourceURL: string;
  kind: ExtractionKind;
};

export type ContentSectionRule = {
  label: string;
  pattern: RegExp;
  weight: number;
};

export type ImageExtractionRules = {
  contentSectionRules: ContentSectionRule[];
  noiseImageURLPatterns: RegExp[];
  hardNoiseImageURLPatterns: RegExp[];
};

export type PlatformExtractionAdapter = {
  key: string;
  version: string;
  matches: (context: ExtractionAdapterContext) => boolean;
  imageRules: ImageExtractionRules;
};

export type DomainExtractionAdapter = {
  key: string;
  version: string;
  platformKey: string;
  hosts: string[];
  fixtureIDs: string[];
  imageRules?: Partial<ImageExtractionRules>;
};

export type ExtractionAdapterSelection = {
  versions: ExtractionVersionSet;
  imageRules: ImageExtractionRules;
};
