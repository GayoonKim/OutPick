type ImageCandidate = {
  sourceURL: string;
  alt: string | null;
};

export type SeasonCandidate = {
  title: string;
  seasonURL: string;
  coverImageURL: string | null;
  score: number;
};

type AnchorCandidate = SeasonCandidate & {
  linkText: string;
  pageOrder: number;
};

type ArchiveScope = {
  cateNo: string | null;
  host: string;
};

const EXTERNAL_SERVICE_HOST_PATTERNS = [
  /(?:^|\.)instagram\.com$/i,
  /(?:^|\.)facebook\.com$/i,
  /(?:^|\.)youtube\.com$/i,
  /(?:^|\.)youtu\.be$/i,
  /(?:^|\.)tiktok\.com$/i,
  /(?:^|\.)kakao\.com$/i,
  /(?:^|\.)naver\.com$/i,
  /(?:^|\.)channel\.io$/i,
  /(?:^|\.)charlla\.io$/i,
  /(?:^|\.)cafe24\.com$/i,
  /(?:^|\.)kcp\.co\.kr$/i,
  /(?:^|\.)domainster\.com$/i,
  /(?:^|\.)a2hosting\.com$/i,
];

const NOISE_IMAGE_PATTERN =
  new RegExp(
    "(?:logo|icon|favicon|sns|insta|instagram|facebook|kakao|youtube|" +
    "global|flag|chat|blank|placeholder|loading|sprite)",
    "i",
  );
const NOISE_LINK_TEXT_PATTERN =
  new RegExp(
    "^(?:logo|home|홈|한국어|english|中文|日本語|usd|krw|eur|jpy|" +
    "config|cart|login|join|search|view all|more|전체보기|장바구니|" +
    "로그인|회원가입)$",
    "i",
  );
const SEASON_SIGNAL_PATTERN =
  new RegExp(
    "lookbook|collection|campaign|archive|season|spring|summer|" +
    "fall|winter|f/w|s/s|20\\d{2}|\\d{2}\\s*(?:fw|ss)|\\b(?:fw|ss)\\b",
    "i",
  );
const PLACEHOLDER_HREF_PATTERN =
  new RegExp(
    "\\{|\\}|\\$action_|클릭시\\s*이동|이동할\\s*주소|링크주소|link\\s*url",
    "i",
  );
const NON_SEASON_PATH_SEGMENT_PATTERN =
  new RegExp(
    "^(?:account|basket|cart|checkout|coupon|login|member|myshop|" +
    "order|privacy|search|wishlist)$",
    "i",
  );
const NON_SEASON_PATH_PREFIX_PATTERN =
  new RegExp(
    "^(?:board|category|goods|item|items|member|myshop|order|" +
    "product|products)$",
    "i",
  );
const HARD_NOISE_IMAGE_PATTERN =
  new RegExp(
    "(?:cart\\.svg|hexcode\\.png|bg[_-]?search|youtube[_-]?icon|" +
    "global/.{0,16}_32x24|ic[_-]?(?:arr|star)|btn|button)",
    "i",
  );

/**
 * 룩북 목록 HTML에서 시즌 후보를 추출합니다.
 *
 * @param {string} html 룩북 목록 HTML 문자열입니다.
 * @param {string} archiveURL 상대 경로 보정 기준 URL입니다.
 * @return {SeasonCandidate[]} 페이지 노출 순서로 정렬된 시즌 후보 목록입니다.
 */
export function extractSeasonCandidates(
  html: string,
  archiveURL: string
): SeasonCandidate[] {
  const scope = archiveScope(archiveURL);
  const candidateMap = new Map<string, AnchorCandidate>();
  const anchorPattern =
    /<a\b[^>]*href\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>[\s\S]*?<\/a>/gi;

  let pageOrder = 0;

  for (const match of html.matchAll(anchorPattern)) {
    const anchorHTML = match[0];
    const currentPageOrder = pageOrder;
    pageOrder += 1;
    const href = match[2] ?? match[3] ?? match[4] ?? "";
    const seasonURL = normalizedURL(href, archiveURL);
    if (
      !seasonURL ||
      isIgnoredHref(seasonURL) ||
      isOutsideArchiveScope(seasonURL, scope)
    ) {
      continue;
    }

    const linkText = plainText(anchorHTML);
    if (isIgnoredLinkText(linkText, seasonURL)) {
      continue;
    }
    const image = firstImageCandidate(anchorHTML, archiveURL);
    const title = seasonTitle(linkText, image?.alt, seasonURL);
    const score = seasonCandidateScore(seasonURL, linkText, image);

    if (score < 45) {
      continue;
    }

    const previous = candidateMap.get(seasonURL);
    if (!previous || shouldReplaceCandidate(previous, score, image)) {
      candidateMap.set(seasonURL, {
        title,
        seasonURL,
        coverImageURL: image?.sourceURL ?? null,
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
    .map((candidate) => ({
      title: candidate.title,
      seasonURL: candidate.seasonURL,
      coverImageURL: candidate.coverImageURL,
      score: candidate.score,
    }));

  const candidatesWithCover = candidates.filter((candidate) => {
    return candidate.coverImageURL !== null;
  });

  // 한국어 주석: 룩북 목록 페이지에서 커버 이미지가 충분히 잡히면
  // 메뉴/드롭다운의 텍스트 링크 후보는 저장하지 않습니다.
  return candidatesWithCover.length >= 2 ? candidatesWithCover : candidates;
}

/**
 * 룩북 목록 URL에서 후보 탐색 범위를 추출합니다.
 *
 * @param {string} archiveURL 룩북 목록 URL입니다.
 * @return {ArchiveScope} 후보 탐색 범위입니다.
 */
function archiveScope(archiveURL: string): ArchiveScope {
  const url = new URL(archiveURL);
  return {
    cateNo: url.searchParams.get("cate_no"),
    host: normalizedHost(url),
  };
}

/**
 * 후보 URL이 룩북 목록 범위 밖인지 판단합니다.
 *
 * @param {string} seasonURL 시즌 후보 URL입니다.
 * @param {ArchiveScope} scope 룩북 목록 URL에서 추출한 범위입니다.
 * @return {boolean} 범위 밖이면 true입니다.
 */
function isOutsideArchiveScope(
  seasonURL: string,
  scope: ArchiveScope
): boolean {
  const url = new URL(seasonURL);
  const candidateHost = normalizedHost(url);
  if (
    !candidateHost ||
    candidateHost !== scope.host &&
    !candidateHost.endsWith(`.${scope.host}`)
  ) {
    return true;
  }

  if (!scope.cateNo) {
    return false;
  }

  const candidateCateNo = url.searchParams.get("cate_no");
  return candidateCateNo !== null && candidateCateNo !== scope.cateNo;
}

/**
 * 같은 URL 후보를 새 후보로 교체할지 판단합니다.
 *
 * @param {AnchorCandidate} previous 기존 후보입니다.
 * @param {number} nextScore 새 후보 점수입니다.
 * @param {ImageCandidate | null} nextImage 새 후보 대표 이미지입니다.
 * @return {boolean} 교체해야 하면 true입니다.
 */
function shouldReplaceCandidate(
  previous: AnchorCandidate,
  nextScore: number,
  nextImage: ImageCandidate | null
): boolean {
  const previousHasCover = previous.coverImageURL !== null;
  const nextHasCover = nextImage !== null;

  if (nextHasCover && !previousHasCover) {
    return true;
  }
  if (!nextHasCover && previousHasCover) {
    return false;
  }
  return previous.score < nextScore;
}

/**
 * href 값을 절대 URL로 정규화합니다.
 *
 * @param {string} rawValue 원본 href 값입니다.
 * @param {string} baseURL 상대 경로 보정 기준 URL입니다.
 * @return {string | null} 정규화된 URL입니다.
 */
function normalizedURL(rawValue: string, baseURL: string): string | null {
  const trimmed = htmlDecode(rawValue).trim();
  if (
    !trimmed ||
    trimmed.startsWith("#") ||
    trimmed.toLowerCase().startsWith("javascript:") ||
    isPlaceholderHref(trimmed)
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

/**
 * 명백히 시즌 상세가 아닌 링크를 제외합니다.
 *
 * @param {string} href 정규화된 링크 URL입니다.
 * @return {boolean} 제외 대상이면 true입니다.
 */
function isIgnoredHref(href: string): boolean {
  const url = new URL(href);
  const value = htmlDecode(decodeURIComponentSafe(
    `${url.pathname}?${url.searchParams.toString()}`
  ));
  if (isExternalServiceHost(url.hostname) || isRootOrIndexURL(url)) {
    return true;
  }
  if (isPlaceholderHref(value)) {
    return true;
  }
  if (isImageFileURL(url)) {
    return true;
  }
  if (/\/product\/archive-detail\.html/i.test(url.pathname)) {
    return false;
  }
  if (isNonSeasonPath(url)) {
    return true;
  }
  return (
    /\/(?:product|category|board|member|order|cart|myshop)\//i.test(value) ||
    /(?:list\.html|login|basket|search|coupon|privacy)/i.test(value)
  );
}

/**
 * 시즌 상세가 아니라 장바구니/검색/일반 상품 등으로 보이는 path인지 판단합니다.
 *
 * @param {URL} url 검사할 URL입니다.
 * @return {boolean} 시즌 후보에서 제외해야 하면 true입니다.
 */
function isNonSeasonPath(url: URL): boolean {
  const segments = url.pathname
    .split("/")
    .map((segment) => segment.trim())
    .filter((segment) => segment.length > 0);
  const hasBlockedSegment = segments.some((segment) => {
    return NON_SEASON_PATH_SEGMENT_PATTERN.test(segment);
  });
  if (hasBlockedSegment) {
    return true;
  }
  const hasBlockedPrefix = segments.some((segment) => {
    return NON_SEASON_PATH_PREFIX_PATTERN.test(segment);
  });
  return hasBlockedPrefix;
}

/**
 * 이미지 파일 자체를 가리키는 URL인지 판단합니다.
 *
 * @param {URL} url 검사할 URL입니다.
 * @return {boolean} 직접 이미지 URL이면 true입니다.
 */
function isImageFileURL(url: URL): boolean {
  return /\.(?:avif|gif|jpe?g|png|webp)(?:$|[?#])/i.test(url.pathname);
}

/**
 * 템플릿/placeholder href인지 판단합니다.
 *
 * @param {string} value 검사할 href 또는 URL 일부입니다.
 * @return {boolean} placeholder면 true입니다.
 */
function isPlaceholderHref(value: string): boolean {
  return PLACEHOLDER_HREF_PATTERN.test(value);
}

/**
 * URL 디코딩이 가능한 값만 안전하게 디코딩합니다.
 *
 * @param {string} value 원본 문자열입니다.
 * @return {string} 디코딩된 문자열 또는 원본 문자열입니다.
 */
function decodeURIComponentSafe(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

/**
 * 링크 텍스트가 메뉴/언어/통화 전환처럼 명백한 노이즈인지 판단합니다.
 *
 * @param {string} linkText 링크 텍스트입니다.
 * @param {string} seasonURL 시즌 후보 URL입니다.
 * @return {boolean} 제외 대상이면 true입니다.
 */
function isIgnoredLinkText(linkText: string, seasonURL: string): boolean {
  const normalized = linkText.trim();
  if (!normalized) {
    return false;
  }
  return NOISE_LINK_TEXT_PATTERN.test(normalized) &&
    !SEASON_SIGNAL_PATTERN.test(`${seasonURL} ${normalized}`);
}

/**
 * 시즌 후보 가능성을 점수화합니다.
 *
 * @param {string} seasonURL 시즌 후보 URL입니다.
 * @param {string} linkText 링크 텍스트입니다.
 * @param {ImageCandidate | null} image 대표 이미지 후보입니다.
 * @return {number} 후보 신뢰도 점수입니다.
 */
function seasonCandidateScore(
  seasonURL: string,
  linkText: string,
  image: ImageCandidate | null
): number {
  let score = 0;
  const haystack = `${seasonURL} ${linkText} ${image?.alt ?? ""}`;

  if (/\/collection\/view\.html/i.test(seasonURL)) {
    score += 70;
  }
  if (/[?&](?:product_no|product|season|id)=/i.test(seasonURL)) {
    score += 24;
  }
  if (/lookbook|collection|campaign|archive|season/i.test(haystack)) {
    score += 26;
  }
  if (SEASON_SIGNAL_PATTERN.test(haystack)) {
    score += 28;
  }
  if (image) {
    score += 90;
  }
  if (/view all|privacy|agreement|login|cart|search/i.test(linkText)) {
    score -= 80;
  }
  if (NOISE_LINK_TEXT_PATTERN.test(linkText.trim()) &&
    !SEASON_SIGNAL_PATTERN.test(haystack)) {
    score -= 80;
  }

  return score;
}

/**
 * 앵커 HTML에서 첫 이미지 후보를 추출합니다.
 *
 * @param {string} html 앵커 HTML 문자열입니다.
 * @param {string} baseURL 상대 경로 보정 기준 URL입니다.
 * @return {ImageCandidate | null} 대표 이미지 후보입니다.
 */
function firstImageCandidate(
  html: string,
  baseURL: string
): ImageCandidate | null {
  const match = html.match(/<img\b[^>]*>/i);
  if (!match) {
    return null;
  }

  const tag = match[0];
  const alt = attributeValue(tag, "alt");
  const values = [
    attributeValue(tag, "ec-data-src"),
    attributeValue(tag, "data-src"),
    attributeValue(tag, "data-original"),
    attributeValue(tag, "data-lazy-src"),
    attributeValue(tag, "src"),
    ...srcsetURLs(attributeValue(tag, "srcset")),
    ...srcsetURLs(attributeValue(tag, "data-srcset")),
  ];

  for (const value of values) {
    const sourceURL = normalizedImageURL(value, baseURL);
    if (sourceURL && !isNoiseImageURL(sourceURL, alt)) {
      return {
        sourceURL,
        alt,
      };
    }
  }

  return null;
}

/**
 * 시즌 후보 제목을 만듭니다.
 *
 * @param {string} linkText 링크 텍스트입니다.
 * @param {string | null | undefined} alt 이미지 대체 텍스트입니다.
 * @param {string} seasonURL 시즌 상세 URL입니다.
 * @return {string} 표시용 시즌 후보 제목입니다.
 */
function seasonTitle(
  linkText: string,
  alt: string | null | undefined,
  seasonURL: string
): string {
  const explicitTitle = [linkText, alt]
    .map((value) => value?.trim() ?? "")
    .find((value) => value.length > 0 && !/^view all$/i.test(value));
  if (explicitTitle) {
    return explicitTitle;
  }

  const url = new URL(seasonURL);
  const fileName = url.pathname.split("/").filter(Boolean).pop() ?? "";
  const normalized = fileName
    .replace(/\.(html?|php)$/i, "")
    .replace(/[-_]+/g, " ")
    .trim();

  return normalized || "시즌 후보";
}

/**
 * HTML 태그 문자열에서 속성 값을 읽습니다.
 *
 * @param {string} tag HTML 태그 문자열입니다.
 * @param {string} attributeName 읽을 속성 이름입니다.
 * @return {string | null} 속성 값 또는 null입니다.
 */
function attributeValue(tag: string, attributeName: string): string | null {
  const pattern = new RegExp(
    `${attributeName}\\s*=\\s*("([^"]*)"|'([^']*)'|([^\\s>]+))`,
    "i"
  );
  const match = tag.match(pattern);
  const value = match?.[2] ?? match?.[3] ?? match?.[4] ?? null;
  return value ? htmlDecode(value) : null;
}

/**
 * HTML에서 태그를 제거하고 텍스트만 남깁니다.
 *
 * @param {string} html HTML 문자열입니다.
 * @return {string} 정리된 텍스트입니다.
 */
function plainText(html: string): string {
  return htmlDecode(
    html
      .replace(/<script\b[\s\S]*?<\/script>/gi, " ")
      .replace(/<style\b[\s\S]*?<\/style>/gi, " ")
      .replace(/<[^>]+>/g, " ")
  )
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * srcset 문자열에서 URL 후보만 분리합니다.
 *
 * @param {string | null} srcset srcset 속성 값입니다.
 * @return {string[]} 추출된 URL 후보 목록입니다.
 */
function srcsetURLs(srcset: string | null): string[] {
  if (!srcset) {
    return [];
  }

  return srcset
    .split(",")
    .map((candidate) => candidate.trim().split(/\s+/)[0])
    .filter((candidate) => candidate.length > 0);
}

/**
 * 이미지 URL 후보를 절대 URL로 정규화합니다.
 *
 * @param {string | null} rawValue 원본 URL 후보입니다.
 * @param {string} baseURL 상대 경로 보정 기준 URL입니다.
 * @return {string | null} 정규화된 이미지 URL입니다.
 */
function normalizedImageURL(
  rawValue: string | null,
  baseURL: string
): string | null {
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
    return url.toString();
  } catch {
    return null;
  }
}

/**
 * 이미지 후보가 로고/아이콘/SNS 같은 장식 이미지인지 판단합니다.
 *
 * @param {string} sourceURL 이미지 URL입니다.
 * @param {string | null} alt 이미지 alt 값입니다.
 * @return {boolean} 노이즈 이미지면 true입니다.
 */
function isNoiseImageURL(sourceURL: string, alt: string | null): boolean {
  const value = `${sourceURL} ${alt ?? ""}`;
  return NOISE_IMAGE_PATTERN.test(value) ||
    HARD_NOISE_IMAGE_PATTERN.test(value);
}

/**
 * URL host를 비교 가능한 형태로 정규화합니다.
 *
 * @param {URL} url 정규화할 URL입니다.
 * @return {string} 정규화된 host입니다.
 */
function normalizedHost(url: URL): string {
  return url.hostname.toLowerCase().replace(/^www\./, "");
}

/**
 * 외부 서비스 URL인지 판단합니다.
 *
 * @param {string} hostname URL hostname입니다.
 * @return {boolean} 외부 서비스면 true입니다.
 */
function isExternalServiceHost(hostname: string): boolean {
  const host = hostname.toLowerCase().replace(/^www\./, "");
  return EXTERNAL_SERVICE_HOST_PATTERNS.some((pattern) => pattern.test(host));
}

/**
 * 홈/root/index 링크인지 판단합니다.
 *
 * @param {URL} url 검사할 URL입니다.
 * @return {boolean} root/index 링크면 true입니다.
 */
function isRootOrIndexURL(url: URL): boolean {
  const path = url.pathname.replace(/\/+$/, "") || "/";
  return path === "/" || /\/index\.html?$/i.test(path);
}

/**
 * 자주 등장하는 HTML 엔티티를 디코딩합니다.
 *
 * @param {string} value 원본 문자열입니다.
 * @return {string} 디코딩된 문자열입니다.
 */
function htmlDecode(value: string): string {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ");
}
