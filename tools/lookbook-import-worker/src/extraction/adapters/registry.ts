import {
  CAFE24_ADAPTER_KEY,
  cafe24Adapter,
} from "./cafe24.js";
import type {
  DomainExtractionAdapter,
  ExtractionAdapterContext,
  ExtractionAdapterSelection,
  ImageExtractionRules,
  PlatformExtractionAdapter,
} from "./types.js";

const EXTRACTOR_VERSION = "1.2.3";
const EMPTY_IMAGE_RULES: ImageExtractionRules = {
  contentSectionRules: [],
  noiseImageURLPatterns: [],
  hardNoiseImageURLPatterns: [],
};

export type ExtractionAdapterRegistry = {
  select: (context: ExtractionAdapterContext) => ExtractionAdapterSelection;
  versionsAreCurrent: (input: {
    platformAdapterKey: unknown;
    platformAdapterVersion: unknown;
    domainAdapterKey: unknown;
    domainAdapterVersion: unknown;
  }) => boolean;
};

export function createExtractionAdapterRegistry(input: {
  platformAdapters?: PlatformExtractionAdapter[];
  domainAdapters?: DomainExtractionAdapter[];
  fixtureIDs?: string[];
} = {}): ExtractionAdapterRegistry {
  const platformAdapters = input.platformAdapters ?? [cafe24Adapter];
  const domainAdapters = input.domainAdapters ?? [];
  const fixtureIDs = new Set(input.fixtureIDs ?? []);
  validateRegistry(platformAdapters, domainAdapters, fixtureIDs);

  return {
    select: (context) => {
      const platform = platformAdapters.find((adapter) =>
        adapter.matches(context)) ?? null;
      const hostname = new URL(context.sourceURL).hostname.toLowerCase();
      const domain = platform === null ?
        null :
        domainAdapters.find((adapter) =>
          adapter.platformKey === platform.key &&
          adapter.hosts.some((host) => host.toLowerCase() === hostname),
        ) ?? null;
      return {
        versions: {
          extractorVersion: EXTRACTOR_VERSION,
          platformAdapterKey: platform?.key ?? null,
          platformAdapterVersion: platform?.version ?? null,
          domainAdapterKey: domain?.key ?? null,
          domainAdapterVersion: domain?.version ?? null,
        },
        imageRules: mergeImageRules(
          platform?.imageRules ?? EMPTY_IMAGE_RULES,
          domain?.imageRules,
        ),
      };
    },
    versionsAreCurrent: (versions) => {
      const platformKey = nullableString(versions.platformAdapterKey);
      const platformVersion = nullableString(versions.platformAdapterVersion);
      const domainKey = nullableString(versions.domainAdapterKey);
      const domainVersion = nullableString(versions.domainAdapterVersion);
      if (
        platformKey === undefined ||
        platformVersion === undefined ||
        domainKey === undefined ||
        domainVersion === undefined
      ) {
        return false;
      }
      if (platformKey === null) {
        return platformVersion === null &&
          domainKey === null &&
          domainVersion === null;
      }
      const platform = platformAdapters.find(
        (item) => item.key === platformKey,
      );
      if (!platform || platform.version !== platformVersion) {
        return false;
      }
      if (domainKey === null) {
        return domainVersion === null;
      }
      const domain = domainAdapters.find((item) =>
        item.key === domainKey && item.platformKey === platformKey);
      return domain !== undefined && domain.version === domainVersion;
    },
  };
}

export const EXTRACTION_ADAPTER_REGISTRY = createExtractionAdapterRegistry();

export function selectExtractionAdapters(
  context: ExtractionAdapterContext,
): ExtractionAdapterSelection {
  return EXTRACTION_ADAPTER_REGISTRY.select(context);
}

export function currentAdapterVersionsMatch(input: {
  platformAdapterKey: unknown;
  platformAdapterVersion: unknown;
  domainAdapterKey: unknown;
  domainAdapterVersion: unknown;
}): boolean {
  return EXTRACTION_ADAPTER_REGISTRY.versionsAreCurrent(input);
}

export const CURRENT_EXTRACTOR_VERSION = EXTRACTOR_VERSION;
export const CURRENT_PLATFORM_ADAPTER_KEYS = [CAFE24_ADAPTER_KEY] as const;

function validateRegistry(
  platformAdapters: PlatformExtractionAdapter[],
  domainAdapters: DomainExtractionAdapter[],
  fixtureIDs: Set<string>,
): void {
  assertUnique(
    platformAdapters.map((adapter) => adapter.key),
    "platform adapter",
  );
  assertUnique(domainAdapters.map((adapter) => adapter.key), "domain adapter");
  const platformKeys = new Set(platformAdapters.map((adapter) => adapter.key));
  domainAdapters.forEach((adapter) => {
    if (!platformKeys.has(adapter.platformKey)) {
      throw new Error(
        `domain adapter의 platform이 등록되지 않았습니다: ${adapter.key}`,
      );
    }
    if (adapter.hosts.length === 0) {
      throw new Error(`domain adapter host가 없습니다: ${adapter.key}`);
    }
    if (
      adapter.fixtureIDs.length === 0 ||
      !adapter.fixtureIDs.every((fixtureID) => fixtureIDs.has(fixtureID))
    ) {
      throw new Error(`domain adapter fixture가 등록되지 않았습니다: ${adapter.key}`);
    }
  });
}

function assertUnique(values: string[], label: string): void {
  if (new Set(values).size !== values.length) {
    throw new Error(`${label} key가 중복됐습니다.`);
  }
}

function mergeImageRules(
  platform: ImageExtractionRules,
  domain: Partial<ImageExtractionRules> | undefined,
): ImageExtractionRules {
  return {
    contentSectionRules: [
      ...platform.contentSectionRules,
      ...(domain?.contentSectionRules ?? []),
    ],
    noiseImageURLPatterns: [
      ...platform.noiseImageURLPatterns,
      ...(domain?.noiseImageURLPatterns ?? []),
    ],
    hardNoiseImageURLPatterns: [
      ...platform.hardNoiseImageURLPatterns,
      ...(domain?.hardNoiseImageURLPatterns ?? []),
    ],
  };
}

function nullableString(value: unknown): string | null | undefined {
  return value === null ? null : typeof value === "string" ? value : undefined;
}
