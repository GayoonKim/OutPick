/* eslint-disable max-len */
import {
  extractionResult,
  type ExtractionResult,
} from "./core.js";
import {selectExtractionAdapters} from "./adapters/registry.js";
import type {
  ContentSectionRule,
  ImageExtractionRules,
} from "./adapters/types.js";
import {extractionCandidateKey} from "./evidence.js";

export type ImageCandidate = {
  sourceURL: string;
  alt: string | null;
};

export type ImageExtractionResult = ExtractionResult<ImageCandidate>;

export type SeasonCoverImageCandidate = {
  sourceURL: string;
  strategy: string;
};

const MIN_STRONG_SECTION_WEIGHT = 240;
const GENERIC_CONTENT_SECTION_RULES: ContentSectionRule[] = [
  {
    label: "productDetailContent",
    pattern:
      /prdDetail|detail[_-]?content|detailArea|product[_-]?detail[_-]?area/i,
    weight: 300,
  },
  {
    label: "editorContent",
    pattern: /fr-view|se-main-container|editor|edibot/i,
    weight: 260,
  },
  {
    label: "lookbookContent",
    pattern:
      /lookbook|collection[_-]?detail|collection[_-]?view|campaign|season/i,
    weight: 180,
  },
  {
    label: "mainContent",
    pattern: /\bmain\b|article|content/i,
    weight: 80,
  },
];

const NOISE_IMAGE_URL_PATTERNS = [
  /\/(?:M_banner|banner|banners|icon|icons|logo|favicon|layout)\//i,
  /\/web\/product\/(?:tiny|small|medium|list)\//i,
  /(?:btn_count_|btn_price_delete|ico_pay_point|icon_(?:facebook|twitter))\.(?:gif|png|jpg|jpeg|webp)(?:\?|$)/i,
  /(?:sprite|blank|placeholder|loading)\.(?:gif|png|svg)(?:\?|$)/i,
];
const HARD_NOISE_IMAGE_URL_PATTERNS = [
  /(?:^|\/\/)(?:www\.)?facebook\.com\/tr\?/i,
  /(?:^|\/\/)(?:www\.)?(?:googletagmanager|google-analytics|googleadservices)\.com\//i,
  /(?:^|\/\/)(?:www\.)?(?:channel|charlla)\.io\//i,
  /(?:chat|talk|kakao)[_-]?icon[^/]*\.(?:gif|png|svg|webp)(?:\?|$)/i,
  /(?:logo|favicon)[^/]*\.(?:gif|png|svg|webp)(?:\?|$)/i,
  /(?:social|sns|facebook|kakao|naver|instagram|twitter|fb_icon|insta_icon)/i,
  /\/img\/common\/global\/[^/?#]*_32x24\.png(?:[?#]|$)/i,
  /\/[^/?#]*(?:bg[_-]?search|youtube[_-]?icon|ic[_-]?(?:arr|star))[^/?#]*\.(?:gif|jpe?g|png|svg|webp)(?:[?#]|$)/i,
  /\/[^/?#]*(?:btn|button|icon-plus|count_|page_(?:first|prev|next)|close|share|menu|copy[_-]?icon|icon[_-]?copy)[^/?#]*\.(?:gif|jpe?g|png|svg|webp)(?:[?#]|$)/i,
  /(?:cursor|txt_progress|img_loading|top_banner|topbanner)/i,
];
const NOISE_CONTEXT_PATTERN =
  /product\/list\.html|category\/|view all|gnb|lnb|menu|header|footer|basket|cart|order|payment|purchase|quantity|option|결제|주문|장바구니|수량|옵션/i;

export function extractImageCandidates(
  html: string,
  baseURL: string,
): ImageExtractionResult {
  const adapterSelection = selectExtractionAdapters({
    html,
    sourceURL: baseURL,
    kind: "season_images",
  });
  const rules = adapterSelection.imageRules;
  const rawCandidates = collectImageCandidates(
    html,
    baseURL,
    false,
    true,
    rules,
  );
  const sections = contentSections(
    html,
    [...rules.contentSectionRules, ...GENERIC_CONTENT_SECTION_RULES],
  )
    .map((section) => {
      const candidates = collectImageCandidates(
        section.html,
        baseURL,
        true,
        false,
        rules,
      );
      return {
        candidates,
        index: section.index,
        label: section.label,
        score: section.weight + candidates.length * 10,
      };
    })
    .filter((section) => section.candidates.length > 0)
    .sort((lhs, rhs) => rhs.score - lhs.score || lhs.index - rhs.index);
  const bestSection = sections[0];
  if (
    bestSection &&
    (bestSection.score >= MIN_STRONG_SECTION_WEIGHT ||
      bestSection.candidates.length >= 2)
  ) {
    return extractionResult({
      candidates: bestSection.candidates,
      strategy: bestSection.label,
      rawCandidateCount: rawCandidates.length,
      sourceURL: baseURL,
      candidateKey: (candidate) => extractionCandidateKey(candidate.sourceURL),
      versions: adapterSelection.versions,
    });
  }
  const filteredCandidates = collectImageCandidates(
    html,
    baseURL,
    true,
    false,
    rules,
  );
  return extractionResult({
    candidates: filteredCandidates.length > 0 ? filteredCandidates : rawCandidates,
    strategy: filteredCandidates.length > 0 ? "filteredPageImages" : "allPageImages",
    rawCandidateCount: rawCandidates.length,
    sourceURL: baseURL,
    candidateKey: (candidate) => extractionCandidateKey(candidate.sourceURL),
    versions: adapterSelection.versions,
  });
}

export function extractSeasonCoverImageCandidate(
  html: string,
  baseURL: string,
): SeasonCoverImageCandidate | null {
  const adapterSelection = selectExtractionAdapters({
    html,
    sourceURL: baseURL,
    kind: "season_images",
  });
  const sections = contentSections(
    html,
    [
      ...adapterSelection.imageRules.contentSectionRules,
      ...GENERIC_CONTENT_SECTION_RULES,
    ],
  )
    .map((section) => ({
      ...section,
      candidates: collectImageCandidates(
        withoutSeasonCoverNoiseSections(section.html),
        baseURL,
        true,
        false,
        adapterSelection.imageRules,
      ),
    }))
    .filter((section) => section.weight >= 180 && section.candidates.length > 0)
    .sort((lhs, rhs) =>
      rhs.weight - lhs.weight || lhs.index - rhs.index,
    );
  const selected = sections[0];
  const candidate = selected?.candidates[0];
  return selected && candidate ? {
    sourceURL: candidate.sourceURL,
    strategy: selected.label,
  } : null;
}

function withoutSeasonCoverNoiseSections(html: string): string {
  const allRanges = Array.from(
    html.matchAll(/<(header|footer|nav|aside|section|div)\b[^>]*>/gi),
  ).flatMap((match) => {
    const openingTag = match[0];
    if (!(
      /<(?:header|footer|nav|aside)\b/i.test(openingTag) ||
      /banner|promotion|advert|related|recommend|recent|header|footer|navigation|\bnav\b/i
        .test(openingTag)
    )) {
      return [];
    }
    const start = match.index ?? 0;
    const section = sliceElementHTML(html, start, match[1]);
    return [{start, end: start + section.length}];
  });
  const ranges = allRanges.filter((range, index) =>
    !allRanges.some((outer, outerIndex) =>
      outerIndex !== index &&
      outer.start <= range.start &&
      outer.end >= range.end,
    ));
  return ranges
    .sort((lhs, rhs) => rhs.start - lhs.start)
    .reduce((result, range) =>
      result.slice(0, range.start) + result.slice(range.end), html);
}

function collectImageCandidates(
  html: string,
  baseURL: string,
  applyNoiseFilter: boolean,
  includeMetaImages: boolean,
  adapterRules: ImageExtractionRules,
): ImageCandidate[] {
  const candidates: ImageCandidate[] = [];
  const seen = new Set<string>();
  for (const match of html.matchAll(/<img\b[^>]*>/gi)) {
    const tag = match[0];
    appendURLs(
      candidates,
      seen,
      imageURLValues(tag),
      baseURL,
      attributeValue(tag, "alt"),
      tagContext(html, match.index ?? 0),
      applyNoiseFilter,
      adapterRules,
    );
  }
  for (const match of html.matchAll(/<source\b[^>]*>/gi)) {
    const tag = match[0];
    appendURLs(
      candidates,
      seen,
      [
        ...srcsetURLs(attributeValue(tag, "srcset")),
        ...srcsetURLs(attributeValue(tag, "data-srcset")),
      ],
      baseURL,
      null,
      tagContext(html, match.index ?? 0),
      applyNoiseFilter,
      adapterRules,
    );
  }
  if (!includeMetaImages) {
    return candidates;
  }
  for (const match of html.matchAll(/<meta\b[^>]*>/gi)) {
    const tag = match[0];
    const property = attributeValue(tag, "property") ??
      attributeValue(tag, "name");
    if (property?.toLowerCase() !== "og:image") {
      continue;
    }
    appendURLs(
      candidates,
      seen,
      [attributeValue(tag, "content")],
      baseURL,
      null,
      tag,
      applyNoiseFilter,
      adapterRules,
    );
  }
  return candidates;
}

function contentSections(
  html: string,
  rules: ContentSectionRule[],
): Array<{html: string; index: number; label: string; weight: number}> {
  const sections: Array<{
    html: string;
    index: number;
    label: string;
    weight: number;
  }> = [];
  for (const match of html.matchAll(/<(main|article|section|div)\b[^>]*>/gi)) {
    const rule = rules.find((item) => item.pattern.test(match[0]));
    if (!rule) {
      continue;
    }
    const sectionHTML = sliceElementHTML(html, match.index ?? 0, match[1]);
    if (!sectionHTML || !/<img\b/i.test(sectionHTML)) {
      continue;
    }
    sections.push({
      html: sectionHTML,
      index: match.index ?? 0,
      label: rule.label,
      weight: rule.weight,
    });
  }
  return sections.sort((lhs, rhs) => lhs.index - rhs.index);
}

function sliceElementHTML(html: string, startIndex: number, tagName: string): string {
  const tokenPattern = new RegExp(`<\\/?${tagName}\\b[^>]*>`, "gi");
  tokenPattern.lastIndex = startIndex;
  let depth = 0;
  for (;;) {
    const match = tokenPattern.exec(html);
    if (!match) {
      return html.slice(startIndex);
    }
    if (match[0].startsWith("</")) {
      depth -= 1;
    } else if (!match[0].endsWith("/>")) {
      depth += 1;
    }
    if (depth === 0) {
      return html.slice(startIndex, match.index + match[0].length);
    }
  }
}

function imageURLValues(tag: string): Array<string | null> {
  return [
    attributeValue(tag, "ec-data-src"),
    attributeValue(tag, "data-src"),
    attributeValue(tag, "data-original"),
    attributeValue(tag, "data-original-src"),
    attributeValue(tag, "data-lazy-src"),
    attributeValue(tag, "data-zoom-image"),
    attributeValue(tag, "src"),
    ...srcsetURLs(attributeValue(tag, "srcset")),
    ...srcsetURLs(attributeValue(tag, "data-srcset")),
  ];
}

function appendURLs(
  candidates: ImageCandidate[],
  seen: Set<string>,
  rawValues: Array<string | null>,
  baseURL: string,
  alt: string | null,
  context: string,
  applyNoiseFilter: boolean,
  adapterRules: ImageExtractionRules,
): void {
  for (const rawValue of rawValues) {
    const normalizedURL = normalizedImageURL(rawValue, baseURL);
    if (
      !normalizedURL ||
      seen.has(normalizedURL) ||
      isHardNoiseImage(normalizedURL, adapterRules) ||
      (applyNoiseFilter && isLikelyNoiseImage(
        normalizedURL,
        context,
        adapterRules,
      ))
    ) {
      continue;
    }
    seen.add(normalizedURL);
    candidates.push({sourceURL: normalizedURL, alt});
  }
}

function attributeValue(tag: string, attributeName: string): string | null {
  const pattern = new RegExp(
    `${attributeName}\\s*=\\s*("([^"]*)"|'([^']*)'|([^\\s>]+))`,
    "i",
  );
  const match = tag.match(pattern);
  return match?.[2] ?? match?.[3] ?? match?.[4] ?? null;
}

function srcsetURLs(srcset: string | null): string[] {
  if (!srcset) {
    return [];
  }
  return srcset
    .split(",")
    .map((candidate) => candidate.trim().split(/\s+/)[0])
    .filter((candidate) => candidate.length > 0);
}

function tagContext(html: string, index: number): string {
  return html.slice(Math.max(0, index - 500), Math.min(html.length, index + 500));
}

function normalizedImageURL(rawValue: string | null, baseURL: string): string | null {
  if (!rawValue) {
    return null;
  }
  const trimmed = rawValue.trim();
  if (!trimmed || trimmed.startsWith("data:")) {
    return null;
  }
  const decoded = htmlDecode(decodeURIComponentSafe(trimmed));
  if (isTemplateImageValue(decoded)) {
    return null;
  }
  try {
    const url = new URL(trimmed, baseURL);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return null;
    }
    if (isTemplateImageValue(htmlDecode(decodeURIComponentSafe(url.toString())))) {
      return null;
    }
    return url.toString();
  } catch {
    return null;
  }
}

function isTemplateImageValue(value: string): boolean {
  return (
    /{{|}}|\$\{?image|image_url|image_medium|image_small|\+\s*src\s*\+/i.test(value) ||
    /\$\([^)]*\)\.attr\((?:'|")src(?:'|")\)/i.test(value) ||
    /(?:'\s*\+|"\s*\+|\+\s*'|\+\s*")/.test(value)
  );
}

function decodeURIComponentSafe(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function htmlDecode(value: string): string {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&#039;|&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

function isLikelyNoiseImage(
  imageURL: string,
  context: string,
  adapterRules: ImageExtractionRules,
): boolean {
  return [
    ...NOISE_IMAGE_URL_PATTERNS,
    ...adapterRules.noiseImageURLPatterns,
  ].some((pattern) => pattern.test(imageURL)) ||
    NOISE_CONTEXT_PATTERN.test(context);
}

function isHardNoiseImage(
  imageURL: string,
  adapterRules: ImageExtractionRules,
): boolean {
  return [
    ...HARD_NOISE_IMAGE_URL_PATTERNS,
    ...adapterRules.hardNoiseImageURLPatterns,
  ].some((pattern) => pattern.test(imageURL));
}
