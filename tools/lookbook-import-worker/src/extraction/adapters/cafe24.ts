import type {
  ExtractionAdapterContext,
  PlatformExtractionAdapter,
} from "./types.js";

export const CAFE24_ADAPTER_KEY = "cafe24";
export const CAFE24_ADAPTER_VERSION = "1.0.0";

const STRONG_CAFE24_MARKERS = [
  /\bxans-[a-z0-9_-]+/i,
  /\bec-data-(?:src|lazy|original)\b/i,
  /(?:^|\/\/)[^"'\s>]*echosting\.cafe24\.com\//i,
  /\/web\/upload\/NNEditor\//i,
];

export const cafe24Adapter: PlatformExtractionAdapter = {
  key: CAFE24_ADAPTER_KEY,
  version: CAFE24_ADAPTER_VERSION,
  matches: (context) => isCafe24Document(context),
  imageRules: {
    contentSectionRules: [
      {
        label: "archiveSourceDetail",
        pattern: /archive[_-]?source[_-]?detail|archive-source-detail/i,
        weight: 430,
      },
      {
        label: "cafe24ProductAdditional",
        pattern:
          /xans-product-additional|prdDetailContentLazy|product-additional/i,
        weight: 360,
      },
      {
        label: "cafe24NNEditor",
        pattern: /NNEditor/i,
        weight: 270,
      },
    ],
    noiseImageURLPatterns: [
      /\/(?:ec_admin|skin\/base_|design\/skin\/admin|design\/skin\/default)\//i,
    ],
    hardNoiseImageURLPatterns: [
      new RegExp(
        "echosting\\.cafe24\\.com/skin|/skin/base|/SkinImg/|/morenvyimg/",
        "i",
      ),
    ],
  },
};

function isCafe24Document(context: ExtractionAdapterContext): boolean {
  let hostname = "";
  try {
    hostname = new URL(context.sourceURL).hostname.toLowerCase();
  } catch {
    return false;
  }
  if (hostname === "cafe24.com" || hostname.endsWith(".cafe24.com")) {
    return true;
  }
  if (STRONG_CAFE24_MARKERS.some((pattern) => pattern.test(context.html))) {
    return true;
  }
  return (
    /\/product\/[^"'?#]*(?:detail|archive)[^"'?#]*\.html/i.test(context.html) &&
    /\/web\/upload\//i.test(context.html)
  );
}
