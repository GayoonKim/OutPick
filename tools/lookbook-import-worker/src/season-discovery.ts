/* eslint-disable max-len */
import type {Page} from "playwright";

import {
  extractionResult,
  extractionResultWithStrategy,
  mergeExtractionVersionSets,
  type ExtractionCandidateEvidence,
  type ExtractionResult,
} from "./extraction/core.js";
import {selectExtractionAdapters} from "./extraction/adapters/registry.js";
import {extractionCandidateKey} from "./extraction/evidence.js";
import type {ExtractionVersionSet} from "./extraction/version.js";
import {
  assertPublicHTTPURL,
  fetchPublicHTTP,
  responseBytes,
  retryableStatusError,
} from "./public-http.js";

type SeasonCandidate = {
  title: string;
  seasonURL: string;
  coverImageURL: string | null;
  score: number;
};

type AnchorCandidate = SeasonCandidate & {
  linkText: string;
  pageOrder: number;
};

type DiagnosticLimits = {
  maxLoadMoreClicks: number;
  maxScrollAttempts: number;
  settleMs: number;
  timeoutMs: number;
  maxDiagnosticCandidates: number;
  maxStoredCandidates: number;
};

type SuggestedFixScope = "common_logic" | "brand_adapter" | "unknown";

type FailureReason =
  | "archive_url_missing"
  | "archive_url_fetch_failed"
  | "no_candidates_found"
  | "low_confidence_candidates"
  | "load_more_detected"
  | "dynamic_rendering_detected"
  | "worker_timeout"
  | "worker_failed"
  | "unknown";

type SuggestedFix = {
  type:
    | "enable_rendered_discovery"
    | "enable_load_more_click_loop"
    | "enable_infinite_scroll"
    | "expand_lazy_image_attributes"
    | "add_brand_adapter"
    | "none";
  scope: SuggestedFixScope;
  confidence: number;
  message: string;
};

export type DiscoveryExtraction = ExtractionResult<SeasonCandidate> & {
  loadMoreDetected: boolean;
  dynamicRenderingDetected: boolean;
};

type RenderedDiscovery = DiscoveryExtraction & {
  candidateCountBeforeExpansion: number;
  loadMoreClickCount: number;
  infiniteScrollAttempted: boolean;
  scrollAttemptCount: number;
};

export type DiscoverSeasonsDiagnosticRequest = {
  brandID?: unknown;
  archiveURL?: unknown;
  requestedBy?: unknown;
  diagnosticID?: unknown;
  limits?: unknown;
};

export type DiscoverSeasonsDiagnosticResponse = {
  status: "passed" | "failed" | "needsReview";
  sourceURL: string;
  candidates: SeasonCandidate[];
  diagnostic: {
    staticCandidateCount: number;
    renderedCandidateCount: number | null;
    candidateCountBeforeExpansion: number;
    candidateCountAfterExpansion: number;
    storedCandidateCount: number;
    diagnosticCandidateCount: number;
    loadMoreDetected: boolean;
    loadMoreClickCount: number;
    infiniteScrollAttempted: boolean;
    scrollAttemptCount: number;
    dynamicRenderingDetected: boolean;
    renderedFallbackUsed: boolean;
    parserStrategy: string;
    adapterKey: string | null;
    candidateEvidence: ExtractionCandidateEvidence[];
    extractionVersions: ExtractionVersionSet;
    failureReasons: FailureReason[];
    suggestedFixScope: SuggestedFixScope;
    suggestedFixes: SuggestedFix[];
    summaryMessage: string | null;
    errorMessage: string | null;
  };
};

const DEFAULT_LIMITS: DiagnosticLimits = {
  maxLoadMoreClicks: 20,
  maxScrollAttempts: 20,
  settleMs: 800,
  timeoutMs: 45000,
  maxDiagnosticCandidates: 120,
  maxStoredCandidates: 80,
};
const HTML_MAX_BYTES = 5 * 1024 * 1024;
const USER_AGENT =
  "OutPickLookbookImporter/0.1 (+https://outpick.app)";
const LOAD_MORE_TEXT_PATTERN =
  /^(?:더\s*보기|more|load\s*more|view\s*more|전체보기|\+)$/i;
const DYNAMIC_RENDERING_SIGNAL_PATTERNS = [
  /__NEXT_DATA__/i,
  /__NUXT__|__NUXT_DATA__|\bnuxt(?:App|State)?\b/i,
  /data-reactroot/i,
  /\bhydrateRoot\b/i,
  /\bcreateRoot\b/i,
];
const SEASON_SIGNAL_PATTERN =
  /lookbook|collection|campaign|archive|season|spring|summer|fall|winter|f\/w|s\/s|20\d{2}|\d{2}\s*(?:fw|ss)|\b(?:fw|ss)\b/i;
const NOISE_LINK_TEXT_PATTERN =
  /^(?:logo|home|홈|한국어|english|中文|日本語|usd|krw|eur|jpy|config|cart|login|join|search|view all|more|전체보기|장바구니|로그인|회원가입)$/i;
const NON_SEASON_PATH_PATTERN =
  /\/(?:basket|cart|checkout|coupon|login|member|myshop|order|privacy|search|wishlist)(?:\/|$)/i;
const HARD_NOISE_IMAGE_PATTERN =
  /(?:logo|favicon|sprite|blank|placeholder|loading|btn|button|icon|sns|social|facebook|instagram|kakao|youtube)/i;

export async function processDiscoverSeasonsDiagnosticRequest(
  request: DiscoverSeasonsDiagnosticRequest,
): Promise<DiscoverSeasonsDiagnosticResponse> {
  requiredDocumentID(request.brandID, "brandID");
  requiredString(request.requestedBy, "requestedBy");
  requiredString(request.diagnosticID, "diagnosticID");
  const sourceURL = normalizedHTTPURL(
    requiredString(request.archiveURL, "archiveURL"),
    "archiveURL",
  );
  const limits = diagnosticLimits(request.limits);

  return withTimeout(
    runDiscovery(sourceURL, limits),
    limits.timeoutMs,
    sourceURL,
  );
}

export function extractSeasonCandidates(
  html: string,
  archiveURL: string,
  limit = DEFAULT_LIMITS.maxDiagnosticCandidates,
): SeasonCandidate[] {
  const candidateMap = new Map<string, AnchorCandidate>();
  const anchorPattern =
    /<a\b[^>]*href\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>[\s\S]*?<\/a>/gi;
  let pageOrder = 0;

  for (const match of html.matchAll(anchorPattern)) {
    const anchorHTML = match[0];
    const currentPageOrder = pageOrder;
    pageOrder += 1;
    const href = match[2] ?? match[3] ?? match[4] ?? "";
    const seasonURL = normalizedCandidateURL(href, archiveURL);
    if (!seasonURL || isIgnoredHref(seasonURL)) {
      continue;
    }
    const linkText = plainText(anchorHTML);
    if (NOISE_LINK_TEXT_PATTERN.test(linkText)) {
      continue;
    }
    const image = firstImageURL(anchorHTML, archiveURL);
    if (!isLikelySeasonCandidateURL(seasonURL, linkText, image)) {
      continue;
    }
    const title = seasonTitle(anchorHTML, linkText, seasonURL);
    const score = seasonCandidateScore(seasonURL, linkText, image);
    if (score < 45) {
      continue;
    }
    const previous = candidateMap.get(seasonURL);
    if (previous) {
      candidateMap.set(
        seasonURL,
        mergedAnchorCandidate(previous, {
          title,
          seasonURL,
          coverImageURL: image,
          score,
          linkText,
          pageOrder: currentPageOrder,
        }),
      );
    } else {
      candidateMap.set(seasonURL, {
        title,
        seasonURL,
        coverImageURL: image,
        score,
        linkText,
        pageOrder: currentPageOrder,
      });
    }
  }

  const candidates = Array.from(candidateMap.values())
    .sort((lhs, rhs) => {
      if (lhs.pageOrder !== rhs.pageOrder) {
        return lhs.pageOrder - rhs.pageOrder;
      }
      return lhs.seasonURL.localeCompare(rhs.seasonURL);
    })
    .map(({title, seasonURL, coverImageURL, score}) => ({
      title,
      seasonURL,
      coverImageURL,
      score,
    }));
  const candidatesWithCover = candidates.filter((item) => item.coverImageURL !== null);
  const selected = candidatesWithCover.length >= 2 ? candidatesWithCover : candidates;
  return selected.slice(0, limit);
}

export function shouldUseRenderedDiscovery(
  extraction: Pick<
    DiscoveryExtraction,
    "candidates" | "strategy" | "loadMoreDetected" | "dynamicRenderingDetected"
  >,
): boolean {
  if (extraction.candidates.length === 0) {
    return true;
  }
  if (extraction.loadMoreDetected || extraction.dynamicRenderingDetected) {
    return true;
  }
  if (
    extraction.candidates.length <= 2 &&
    extraction.strategy === "lowConfidenceStatic"
  ) {
    return true;
  }
  return false;
}

export function classifyDiscovery(
  input: {
    candidateCount: number;
    loadMoreDetected: boolean;
    dynamicRenderingDetected: boolean;
    renderedFallbackUsed: boolean;
    renderedImproved: boolean;
    timedOut?: boolean;
  },
): {
  status: "passed" | "failed" | "needsReview";
  failureReasons: FailureReason[];
  suggestedFixScope: SuggestedFixScope;
  suggestedFixes: SuggestedFix[];
  summaryMessage: string | null;
  errorMessage: string | null;
} {
  const failureReasons: FailureReason[] = [];
  const suggestedFixes: SuggestedFix[] = [];

  if (input.timedOut) {
    failureReasons.push("worker_timeout");
  }
  if (input.candidateCount === 0) {
    failureReasons.push("no_candidates_found");
  }
  if (input.loadMoreDetected) {
    failureReasons.push("load_more_detected");
    suggestedFixes.push({
      type: "enable_load_more_click_loop",
      scope: "common_logic",
      confidence: 0.9,
      message: "더 보기 버튼을 반복 클릭하는 공통 로직이 필요합니다.",
    });
  }
  if (input.dynamicRenderingDetected || input.renderedFallbackUsed) {
    failureReasons.push("dynamic_rendering_detected");
    suggestedFixes.push({
      type: "enable_rendered_discovery",
      scope: "common_logic",
      confidence: input.renderedImproved ? 0.92 : 0.72,
      message: "JavaScript 렌더링 후 시즌 후보를 추출해야 합니다.",
    });
  }
  if (input.candidateCount > 0 && input.candidateCount <= 2) {
    failureReasons.push("low_confidence_candidates");
  }

  const dedupedReasons = Array.from(new Set(failureReasons));
  if (input.candidateCount === 0) {
    return {
      status: "failed",
      failureReasons: dedupedReasons,
      suggestedFixScope: suggestedFixes.length > 0 ? "common_logic" : "unknown",
      suggestedFixes,
      summaryMessage: null,
      errorMessage: "시즌 후보를 찾지 못했습니다.",
    };
  }
  if (dedupedReasons.length > 0) {
    return {
      status: "needsReview",
      failureReasons: dedupedReasons,
      suggestedFixScope: suggestedFixes.length > 0 ? "common_logic" : "unknown",
      suggestedFixes,
      summaryMessage: `시즌 후보 ${input.candidateCount}개를 찾았지만 추출 로직 확인이 필요합니다.`,
      errorMessage: null,
    };
  }
  return {
    status: "passed",
    failureReasons: [],
    suggestedFixScope: "unknown",
    suggestedFixes: [{
      type: "none",
      scope: "unknown",
      confidence: 1,
      message: "추가 조치가 필요하지 않습니다.",
    }],
    summaryMessage: `시즌 후보 ${input.candidateCount}개를 찾았습니다.`,
    errorMessage: null,
  };
}

async function runDiscovery(
  sourceURL: string,
  limits: DiagnosticLimits,
): Promise<DiscoverSeasonsDiagnosticResponse> {
  const html = await fetchHTML(sourceURL, limits.timeoutMs);
  const staticExtraction = extractionFromHTML(html, sourceURL, limits);
  const renderedFallbackNeeded = shouldUseRenderedDiscovery(staticExtraction);
  const renderedExtraction = renderedFallbackNeeded ?
    await renderedDiscovery(sourceURL, limits) :
    null;
  const renderedCandidates = renderedExtraction?.candidates ?? [];
  const mergedCandidates = mergeCandidates(
    staticExtraction.candidates,
    renderedCandidates,
    limits.maxDiagnosticCandidates,
  );
  const storedCandidates = mergedCandidates.slice(0, limits.maxStoredCandidates);
  const selectedStrategy = renderedExtraction?.strategy ?? staticExtraction.strategy;
  const selectedVersions = mergeExtractionVersionSets([
    staticExtraction.versions,
    ...(renderedExtraction === null ? [] : [renderedExtraction.versions]),
  ]);
  const selectedExtraction = extractionResult({
    candidates: storedCandidates,
    strategy: selectedStrategy,
    rawCandidateCount: mergedCandidates.length,
    sourceURL,
    candidateKey: (candidate) => extractionCandidateKey(candidate.seasonURL),
    sourceKind: renderedExtraction === null ? "static_dom" : "rendered_dom",
    versions: selectedVersions,
  });
  const candidateCountAfterExpansion =
    renderedExtraction?.candidates.length ?? staticExtraction.candidates.length;
  const renderedImproved =
    renderedExtraction !== null &&
    renderedExtraction.candidates.length > staticExtraction.candidates.length;
  const classification = classifyDiscovery({
    candidateCount: mergedCandidates.length,
    loadMoreDetected:
      staticExtraction.loadMoreDetected ||
      (renderedExtraction?.loadMoreDetected ?? false),
    dynamicRenderingDetected:
      staticExtraction.dynamicRenderingDetected ||
      (renderedExtraction?.dynamicRenderingDetected ?? false),
    renderedFallbackUsed: renderedExtraction !== null,
    renderedImproved,
  });

  return {
    status: classification.status,
    sourceURL,
    candidates: storedCandidates,
    diagnostic: {
      staticCandidateCount: staticExtraction.candidates.length,
      renderedCandidateCount: renderedExtraction?.candidates.length ?? null,
      candidateCountBeforeExpansion:
        renderedExtraction?.candidateCountBeforeExpansion ??
        staticExtraction.candidates.length,
      candidateCountAfterExpansion,
      storedCandidateCount: storedCandidates.length,
      diagnosticCandidateCount: mergedCandidates.length,
      loadMoreDetected:
        staticExtraction.loadMoreDetected ||
        (renderedExtraction?.loadMoreDetected ?? false),
      loadMoreClickCount: renderedExtraction?.loadMoreClickCount ?? 0,
      infiniteScrollAttempted: renderedExtraction?.infiniteScrollAttempted ?? false,
      scrollAttemptCount: renderedExtraction?.scrollAttemptCount ?? 0,
      dynamicRenderingDetected:
        staticExtraction.dynamicRenderingDetected ||
        (renderedExtraction?.dynamicRenderingDetected ?? false),
      renderedFallbackUsed: renderedExtraction !== null,
      parserStrategy: selectedStrategy,
      adapterKey: selectedVersions.platformAdapterKey,
      candidateEvidence: selectedExtraction.candidateEvidence,
      extractionVersions: selectedExtraction.versions,
      failureReasons: classification.failureReasons,
      suggestedFixScope: classification.suggestedFixScope,
      suggestedFixes: classification.suggestedFixes,
      summaryMessage: classification.summaryMessage,
      errorMessage: classification.errorMessage,
    },
  };
}

async function fetchHTML(sourceURL: string, timeoutMs: number): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchPublicHTTP(sourceURL, {
      signal: controller.signal,
      headers: {
        "user-agent": USER_AGENT,
        "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      },
    });
    if (!response.ok) {
      throw retryableStatusError(
        response.status,
        `룩북 목록 URL 응답 실패: HTTP ${response.status}`,
      );
    }
    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.toLowerCase().includes("text/html")) {
      throw new Error(`HTML 응답이 아닙니다: ${contentType || "unknown"}`);
    }
    return (await responseBytes(response, HTML_MAX_BYTES, "HTML")).toString("utf8");
  } finally {
    clearTimeout(timeout);
  }
}

function extractionFromHTML(
  html: string,
  sourceURL: string,
  limits: DiagnosticLimits,
): DiscoveryExtraction {
  const adapterSelection = selectExtractionAdapters({
    html,
    sourceURL,
    kind: "discovery",
  });
  const candidates = extractSeasonCandidates(
    html,
    sourceURL,
    limits.maxDiagnosticCandidates,
  );
  return {
    ...extractionResult({
      candidates,
      strategy: candidates.length <= 2 ? "lowConfidenceStatic" : "staticAnchors",
      rawCandidateCount: candidates.length,
      sourceURL,
      candidateKey: (candidate) => extractionCandidateKey(candidate.seasonURL),
      versions: adapterSelection.versions,
    }),
    loadMoreDetected: loadMoreSignalDetected(html),
    dynamicRenderingDetected: dynamicRenderingSignalCount(html) > 0,
  };
}

export function extractSeasonCandidateResult(
  html: string,
  sourceURL: string,
  limit = DEFAULT_LIMITS.maxDiagnosticCandidates,
): DiscoveryExtraction {
  return extractionFromHTML(html, sourceURL, {
    ...DEFAULT_LIMITS,
    maxDiagnosticCandidates: Math.min(
      Math.max(1, limit),
      DEFAULT_LIMITS.maxDiagnosticCandidates,
    ),
  });
}

async function renderedDiscovery(
  sourceURL: string,
  limits: DiagnosticLimits,
): Promise<RenderedDiscovery> {
  await assertPublicHTTPURL(sourceURL);
  const {chromium} = await import("playwright");
  const browser = await chromium.launch({headless: true});
  try {
    const context = await browser.newContext({
      viewport: {width: 1440, height: 1800},
      userAgent:
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/124.0.0.0 Safari/537.36",
    });
    try {
      await context.route("**/*", async (route) => {
        const requestURL = route.request().url();
        try {
          await assertPublicHTTPURL(requestURL);
          await route.continue();
        } catch {
          await route.abort("blockedbyclient");
        }
      });
      const page = await context.newPage();
      await page.goto(sourceURL, {
        waitUntil: "domcontentloaded",
        timeout: Math.min(limits.timeoutMs, 20_000),
      });
      await page.waitForTimeout(limits.settleMs);
      await page.waitForLoadState("networkidle", {timeout: 3_000}).catch(() => {
        // 계속 열린 연결이 있어도 DOM 추출은 진행한다.
      });
      const beforeHTML = await page.content();
      const beforeExtraction = extractionFromHTML(beforeHTML, sourceURL, limits);
      const interaction = await runPageInteractions(page, sourceURL, limits);
      const finalHTML = await page.content();
      const finalExtraction = extractionFromHTML(finalHTML, sourceURL, limits);
      return {
        ...extractionResultWithStrategy(
          finalExtraction,
          `playwright:${finalExtraction.strategy}`,
          "rendered_dom",
        ),
        candidateCountBeforeExpansion: beforeExtraction.candidates.length,
        loadMoreClickCount: interaction.loadMoreClickCount,
        infiniteScrollAttempted: interaction.scrollAttemptCount > 0,
        scrollAttemptCount: interaction.scrollAttemptCount,
        loadMoreDetected:
          beforeExtraction.loadMoreDetected ||
          finalExtraction.loadMoreDetected ||
          interaction.loadMoreDetected,
        dynamicRenderingDetected:
          beforeExtraction.dynamicRenderingDetected ||
          finalExtraction.dynamicRenderingDetected,
      };
    } finally {
      await context.close();
    }
  } finally {
    await browser.close();
  }
}

async function runPageInteractions(
  page: Page,
  sourceURL: string,
  limits: DiagnosticLimits,
): Promise<{
  loadMoreDetected: boolean;
  loadMoreClickCount: number;
  scrollAttemptCount: number;
}> {
  let loadMoreDetected = false;
  let loadMoreClickCount = 0;
  let stagnantClickCount = 0;
  let previousCandidateCount = extractSeasonCandidates(
    await page.content(),
    sourceURL,
    limits.maxDiagnosticCandidates,
  ).length;

  for (let index = 0; index < limits.maxLoadMoreClicks; index += 1) {
    const clicked = await clickLoadMoreCandidate(page);
    if (!clicked) {
      break;
    }
    loadMoreDetected = true;
    loadMoreClickCount += 1;
    await page.waitForTimeout(limits.settleMs);
    const nextCandidateCount = extractSeasonCandidates(
      await page.content(),
      sourceURL,
      limits.maxDiagnosticCandidates,
    ).length;
    if (nextCandidateCount <= previousCandidateCount) {
      stagnantClickCount += 1;
      if (stagnantClickCount >= 2) {
        break;
      }
    } else {
      stagnantClickCount = 0;
      previousCandidateCount = nextCandidateCount;
    }
  }

  let scrollAttemptCount = 0;
  let stagnantScrollCount = 0;
  for (let index = 0; index < limits.maxScrollAttempts; index += 1) {
    await page.evaluate(() => {
      const pageGlobal = globalThis as unknown as {
        document: {body: {scrollHeight: number}};
        scrollTo: (x: number, y: number) => void;
      };
      pageGlobal.scrollTo(0, pageGlobal.document.body.scrollHeight);
    });
    scrollAttemptCount += 1;
    await page.waitForTimeout(limits.settleMs);
    const nextCandidateCount = extractSeasonCandidates(
      await page.content(),
      sourceURL,
      limits.maxDiagnosticCandidates,
    ).length;
    if (nextCandidateCount <= previousCandidateCount) {
      stagnantScrollCount += 1;
      if (stagnantScrollCount >= 2) {
        break;
      }
    } else {
      stagnantScrollCount = 0;
      previousCandidateCount = nextCandidateCount;
    }
  }

  return {loadMoreDetected, loadMoreClickCount, scrollAttemptCount};
}

async function clickLoadMoreCandidate(page: Page): Promise<boolean> {
  return await page.evaluate((patternSource) => {
    type BrowserElement = {
      innerText?: string;
      textContent?: string | null;
      getAttribute: (name: string) => string | null;
      hasAttribute: (name: string) => boolean;
      click: () => void;
    };
    const browserDocument = (globalThis as unknown as {
      document: {
        querySelectorAll: (selector: string) => ArrayLike<BrowserElement>;
      };
    }).document;
    const pattern = new RegExp(patternSource, "i");
    const elements = Array.from(
      browserDocument.querySelectorAll("button,a,[role='button']"),
    );
    const target = elements.find((element) => {
      const text = (element.innerText || element.textContent || "").trim();
      const ariaLabel = (element.getAttribute("aria-label") || "").trim();
      const className = element.getAttribute("class") || "";
      const disabled =
        element.hasAttribute("disabled") ||
        element.getAttribute("aria-disabled") === "true";
      if (disabled) {
        return false;
      }
      return (
        pattern.test(text) ||
        pattern.test(ariaLabel) ||
        /more|load|view_more|btnMore|paginate/i.test(className)
      );
    });
    if (!target) {
      return false;
    }
    target.click();
    return true;
  }, LOAD_MORE_TEXT_PATTERN.source);
}

function mergeCandidates(
  staticCandidates: SeasonCandidate[],
  renderedCandidates: SeasonCandidate[],
  limit: number,
): SeasonCandidate[] {
  const byURL = new Map<string, SeasonCandidate>();
  for (const candidate of [...staticCandidates, ...renderedCandidates]) {
    const previous = byURL.get(candidate.seasonURL);
    if (
      !previous ||
      shouldReplaceCandidate(
        {
          ...previous,
          linkText: previous.title,
          pageOrder: Number.MAX_SAFE_INTEGER,
        },
        candidate.title,
        candidate.score,
        candidate.coverImageURL,
      )
    ) {
      byURL.set(candidate.seasonURL, candidate);
    }
  }
  return Array.from(byURL.values()).slice(0, limit);
}

function shouldReplaceCandidate(
  previous: AnchorCandidate,
  nextTitle: string,
  nextScore: number,
  nextImage: string | null,
): boolean {
  const previousHasCover = previous.coverImageURL !== null;
  const nextHasCover = nextImage !== null;
  if (nextHasCover && !previousHasCover) {
    return true;
  }
  if (!nextHasCover && previousHasCover) {
    return false;
  }
  if (previous.score === nextScore && isFallbackSeasonTitle(previous.title)) {
    return !isFallbackSeasonTitle(nextTitle);
  }
  return previous.score < nextScore;
}

function mergedAnchorCandidate(
  previous: AnchorCandidate,
  next: AnchorCandidate,
): AnchorCandidate {
  const previousHasMeaningfulTitle = !isFallbackSeasonTitle(previous.title);
  const nextHasMeaningfulTitle = !isFallbackSeasonTitle(next.title);

  if (previousHasMeaningfulTitle !== nextHasMeaningfulTitle) {
    return {
      ...(nextHasMeaningfulTitle ? next : previous),
      coverImageURL: next.coverImageURL ?? previous.coverImageURL,
      score: Math.max(previous.score, next.score),
      pageOrder: Math.min(previous.pageOrder, next.pageOrder),
    };
  }

  if (shouldReplaceCandidate(
    previous,
    next.title,
    next.score,
    next.coverImageURL,
  )) {
    return {
      ...next,
      coverImageURL: next.coverImageURL ?? previous.coverImageURL,
      score: Math.max(previous.score, next.score),
      pageOrder: Math.min(previous.pageOrder, next.pageOrder),
    };
  }

  return {
    ...previous,
    coverImageURL: previous.coverImageURL ?? next.coverImageURL,
    score: Math.max(previous.score, next.score),
    pageOrder: Math.min(previous.pageOrder, next.pageOrder),
  };
}

function seasonCandidateScore(
  seasonURL: string,
  linkText: string,
  imageURL: string | null,
): number {
  let score = 0;
  if (SEASON_SIGNAL_PATTERN.test(`${seasonURL} ${linkText}`)) {
    score += 50;
  }
  if (imageURL !== null) {
    score += 35;
  }
  if (/\/product\/(?:archive-detail|detail|detail_basic|detail_new)\.html/i.test(seasonURL)) {
    score += 25;
  }
  if (/\b20\d{2}\b|\b\d{2}\s*(?:ss|fw)\b/i.test(linkText)) {
    score += 20;
  }
  return score;
}

function seasonTitle(
  anchorHTML: string,
  linkText: string,
  seasonURL: string,
): string {
  const textTitle = normalizedSeasonTitleText(linkText);
  if (textTitle !== null) {
    return textTitle;
  }

  const imageTitle = firstImageTitle(anchorHTML);
  if (imageTitle !== null) {
    return imageTitle;
  }

  try {
    const url = new URL(seasonURL);
    const fallback = url.pathname
      .split("/")
      .filter(Boolean)
      .pop()
      ?.replace(/\.(html?|php)$/i, "")
      .replace(/[-_]+/g, " ")
      .trim();
    if (!fallback || isFallbackSeasonTitle(fallback)) {
      return "시즌 후보";
    }
    return fallback.slice(0, 120);
  } catch {
    return "시즌 후보";
  }
}

function normalizedSeasonTitleText(rawValue: string): string | null {
  let value = htmlDecode(rawValue)
    .replace(/\u00a0/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!value || NOISE_LINK_TEXT_PATTERN.test(value)) {
    return null;
  }

  const productNameMatch = value.match(
    /(?:상품명|product\s*name)\s*:?\s*(.+?)(?:\s*(?:상품요약정보|summary|판매가|price)\s*:|$)/i,
  );
  if (productNameMatch?.[1]) {
    value = productNameMatch[1].trim();
  }
  value = value
    .replace(/^(?:상품명|product\s*name)\s*:?\s*/i, "")
    .replace(/\s*(?:상품요약정보|summary|판매가|price)\s*:.*$/i, "")
    .trim();
  value = stripImageDescriptionSuffix(value);

  if (!value || NOISE_LINK_TEXT_PATTERN.test(value) || isFallbackSeasonTitle(value)) {
    return null;
  }
  return value.slice(0, 120);
}

function stripImageDescriptionSuffix(value: string): string {
  let title = value.trim();
  if (/\s-\s[^-]*(?:제품|상품|의류|컬렉션|스타일|스타일링|패션|옷)?\s*이미지$/i.test(title)) {
    title = title.replace(/\s-\s[^-]*이미지$/i, "").trim();
  }
  return title
    .replace(/\s+(?:제품|상품|의류|컬렉션|스타일|스타일링|패션|옷)?\s*이미지$/i, "")
    .trim();
}

function firstImageTitle(html: string): string | null {
  const imageTag = html.match(/<img\b[^>]*>/i)?.[0] ?? null;
  if (!imageTag) {
    return null;
  }
  for (const attributeName of ["alt", "title", "aria-label"]) {
    const value = normalizedSeasonTitleText(attributeValue(imageTag, attributeName) ?? "");
    if (value !== null) {
      return value;
    }
  }
  return null;
}

function firstImageURL(html: string, baseURL: string): string | null {
  const imageTag = html.match(/<img\b[^>]*>/i)?.[0] ?? null;
  if (imageTag) {
    for (const value of imageURLValues(imageTag)) {
      const normalized = normalizedImageURL(value, baseURL);
      if (normalized !== null) {
        return normalized;
      }
    }
  }
  const sourceTag = html.match(/<source\b[^>]*>/i)?.[0] ?? null;
  if (sourceTag) {
    for (const value of [
      ...srcsetURLs(attributeValue(sourceTag, "srcset")),
      ...srcsetURLs(attributeValue(sourceTag, "data-srcset")),
    ]) {
      const normalized = normalizedImageURL(value, baseURL);
      if (normalized !== null) {
        return normalized;
      }
    }
  }
  const styleURL = html.match(/url\((["']?)([^"')]+)\1\)/i)?.[2] ?? null;
  return normalizedImageURL(styleURL, baseURL);
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

function normalizedImageURL(rawValue: string | null, baseURL: string): string | null {
  if (!rawValue) {
    return null;
  }
  const trimmed = htmlDecode(rawValue).trim();
  if (!trimmed || trimmed.startsWith("data:")) {
    return null;
  }
  try {
    const url = new URL(trimmed, baseURL);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return null;
    }
    const value = htmlDecode(decodeURIComponentSafe(url.toString()));
    if (HARD_NOISE_IMAGE_PATTERN.test(value)) {
      return null;
    }
    return url.toString();
  } catch {
    return null;
  }
}

function normalizedCandidateURL(rawValue: string, baseURL: string): string | null {
  const trimmed = htmlDecode(rawValue).trim();
  if (
    !trimmed ||
    trimmed.startsWith("#") ||
    trimmed.toLowerCase().startsWith("javascript:") ||
    /(?:\$\(('|")|'\s*\+|"\s*\+|\+\s*'|\+\s*")/.test(trimmed)
  ) {
    return null;
  }
  try {
    const url = new URL(trimmed, baseURL);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return null;
    }
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}

function isLikelySeasonCandidateURL(
  rawURL: string,
  linkText: string,
  imageURL: string | null,
): boolean {
  try {
    const url = new URL(rawURL);
    if (
      /\/(?:product|lookbook|archive|collection|campaigns?)(?:\/|_)(?:archive[-_])?detail(?:_basic|_new)?\.html$/i
        .test(url.pathname)
    ) {
      return true;
    }
    if (/\/(?:detail|archive-detail)(?:\/|$)/i.test(url.pathname)) {
      return true;
    }
    return (
      imageURL !== null &&
      /\b(?:20\d{2}|\d{2}\s*(?:ss|fw)|(?:ss|fw)\s*\d{2}|spring|summer|fall|winter|season)\b/i
        .test(linkText)
    );
  } catch {
    return false;
  }
}

function isIgnoredHref(rawURL: string): boolean {
  try {
    const url = new URL(rawURL);
    if (NON_SEASON_PATH_PATTERN.test(url.pathname)) {
      return true;
    }
    if (/\.(?:jpe?g|png|gif|webp|svg)(?:$|\?)/i.test(url.pathname)) {
      return true;
    }
    if (/\/(?:board|member|order|cart|myshop)\//i.test(url.pathname)) {
      return true;
    }
    return /(?:login|basket|search|coupon|privacy)/i.test(url.toString());
  } catch {
    return true;
  }
}

function loadMoreSignalDetected(html: string): boolean {
  if (/btnMore|loadMore|viewMore|moreBtn|paginate/i.test(html)) {
    return true;
  }
  const text = plainText(html);
  return /더\s*보기|load\s*more|view\s*more/i.test(text);
}

function dynamicRenderingSignalCount(html: string): number {
  return DYNAMIC_RENDERING_SIGNAL_PATTERNS.reduce((count, pattern) => {
    const flags = pattern.flags.includes("g") ? pattern.flags : `${pattern.flags}g`;
    return count + Array.from(html.matchAll(new RegExp(pattern.source, flags))).length;
  }, 0);
}

function plainText(html: string): string {
  return htmlDecode(
    html
      .replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<[^>]+>/g, " ")
      .replace(/\s+/g, " "),
  ).trim();
}

function isFallbackSeasonTitle(title: string): boolean {
  return /^(?:view|detail|archive-detail|collection|product|season 후보)$/i
    .test(title.trim());
}

function diagnosticLimits(value: unknown): DiagnosticLimits {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return DEFAULT_LIMITS;
  }
  const record = value as Record<string, unknown>;
  return {
    maxLoadMoreClicks: literalLimit(
      record.maxLoadMoreClicks,
      DEFAULT_LIMITS.maxLoadMoreClicks,
    ) as 20,
    maxScrollAttempts: literalLimit(
      record.maxScrollAttempts,
      DEFAULT_LIMITS.maxScrollAttempts,
    ) as 20,
    settleMs: literalLimit(record.settleMs, DEFAULT_LIMITS.settleMs) as 800,
    timeoutMs: literalLimit(record.timeoutMs, DEFAULT_LIMITS.timeoutMs) as 45000,
    maxDiagnosticCandidates: literalLimit(
      record.maxDiagnosticCandidates,
      DEFAULT_LIMITS.maxDiagnosticCandidates,
    ) as 120,
    maxStoredCandidates: literalLimit(
      record.maxStoredCandidates,
      DEFAULT_LIMITS.maxStoredCandidates,
    ) as 80,
  };
}

function literalLimit(value: unknown, expected: number): number {
  return value === expected ? expected : expected;
}

function normalizedHTTPURL(rawValue: string, fieldName: string): string {
  try {
    const url = new URL(rawValue);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      throw new Error(`${fieldName} 값은 HTTP 또는 HTTPS URL이어야 합니다.`);
    }
    url.hash = "";
    return url.toString();
  } catch (error) {
    if (error instanceof Error && error.message.includes(fieldName)) {
      throw error;
    }
    throw new Error(`${fieldName} 값이 올바른 URL이 아닙니다.`);
  }
}

function requiredString(value: unknown, fieldName: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${fieldName} 값이 필요합니다.`);
  }
  return value.trim();
}

function requiredDocumentID(value: unknown, fieldName: string): string {
  const id = requiredString(value, fieldName);
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(id)) {
    throw new Error(`${fieldName} 값이 올바르지 않습니다.`);
  }
  return id;
}

function htmlDecode(value: string): string {
  let decoded = value;
  for (let index = 0; index < 2; index += 1) {
    const next = decoded
      .replace(/&nbsp;/g, " ")
      .replace(/&amp;/g, "&")
      .replace(/&quot;/g, "\"")
      .replace(/&#039;|&apos;/g, "'")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">");
    if (next === decoded) {
      break;
    }
    decoded = next;
  }
  return decoded;
}

function decodeURIComponentSafe(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

async function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  sourceURL: string,
): Promise<T> {
  let timeout: NodeJS.Timeout | null = null;
  const timeoutPromise = new Promise<never>((_resolve, reject) => {
    timeout = setTimeout(() => {
      reject(new Error(`시즌 목록 진단 시간이 초과되었습니다: ${sourceURL}`));
    }, timeoutMs);
  });
  try {
    return await Promise.race([promise, timeoutPromise]);
  } finally {
    if (timeout !== null) {
      clearTimeout(timeout);
    }
  }
}
