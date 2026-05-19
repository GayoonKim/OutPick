import {createHash} from "node:crypto";
import type {Firestore} from "firebase-admin/firestore";
import {FieldValue} from "firebase-admin/firestore";

type ImageCandidate = {
  sourceURL: string;
  alt: string | null;
};

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

type ArchiveScope = {
  cateNo: string | null;
};

type DiscoveryResult = {
  brandID: string;
  sourceURL: string;
  candidateCount: number;
};

const MAX_SEASON_CANDIDATES_TO_STORE = 80;

/**
 * 룩북 목록 URL에서 시즌 후보를 찾아 Firestore에 저장합니다.
 *
 * @param {Firestore} db Firestore Admin SDK 인스턴스입니다.
 * @param {string} brandID 후보를 저장할 브랜드 문서 ID입니다.
 * @param {string} archiveURL 룩북 목록 URL입니다.
 * @return {Promise<DiscoveryResult>} 후보 탐색 결과입니다.
 */
export async function discoverSeasonCandidates(
  db: Firestore,
  brandID: string,
  archiveURL: string
): Promise<DiscoveryResult> {
  const brandRef = db.collection("brands").doc(brandID);

  await brandRef.update({
    discoveryStatus: "running",
    lastDiscoveryErrorMessage: null,
    lastDiscoveryRequestedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  try {
    const html = await fetchHTML(archiveURL);
    const candidates = extractSeasonCandidates(html, archiveURL)
      .slice(0, MAX_SEASON_CANDIDATES_TO_STORE);

    await replaceStoredCandidates(db, brandID, archiveURL, candidates);
    await brandRef.update({
      discoveryStatus: "success",
      lastDiscoveryCompletedAt: FieldValue.serverTimestamp(),
      lastDiscoveryErrorMessage: null,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      brandID,
      sourceURL: archiveURL,
      candidateCount: candidates.length,
    };
  } catch (error) {
    await brandRef.update({
      discoveryStatus: "failed",
      lastDiscoveryErrorMessage: errorMessage(error),
      lastDiscoveryCompletedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    throw error;
  }
}

/**
 * URL에서 HTML 문자열을 가져옵니다.
 *
 * @param {string} url 가져올 페이지 URL입니다.
 * @return {Promise<string>} 응답 HTML 문자열입니다.
 */
async function fetchHTML(url: string): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15_000);

  try {
    const response = await fetch(url, {
      redirect: "follow",
      signal: controller.signal,
      headers: {
        "user-agent":
          "OutPickLookbookImporter/0.1 (+https://outpick.app)",
        "accept":
          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      },
    });

    if (!response.ok) {
      throw new Error(`룩북 목록 URL 응답 실패: HTTP ${response.status}`);
    }

    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.toLowerCase().includes("text/html")) {
      throw new Error(`HTML 응답이 아닙니다: ${contentType || "unknown"}`);
    }

    return await response.text();
  } finally {
    clearTimeout(timeout);
  }
}

/**
 * 룩북 목록 HTML에서 시즌 후보를 추출합니다.
 *
 * @param {string} html 룩북 목록 HTML 문자열입니다.
 * @param {string} archiveURL 상대 경로 보정 기준 URL입니다.
 * @return {SeasonCandidate[]} 페이지 노출 순서로 정렬된 시즌 후보 목록입니다.
 */
function extractSeasonCandidates(
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
  if (!scope.cateNo) {
    return false;
  }

  const url = new URL(seasonURL);
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
 * 기존 후보를 지우고 새 후보 목록을 저장합니다.
 *
 * @param {Firestore} db Firestore Admin SDK 인스턴스입니다.
 * @param {string} brandID 브랜드 문서 ID입니다.
 * @param {string} archiveURL 후보를 추출한 룩북 목록 URL입니다.
 * @param {SeasonCandidate[]} candidates 저장할 후보 목록입니다.
 */
async function replaceStoredCandidates(
  db: Firestore,
  brandID: string,
  archiveURL: string,
  candidates: SeasonCandidate[]
): Promise<void> {
  const collectionRef = db
    .collection("brands")
    .doc(brandID)
    .collection("seasonCandidates");

  const existingSnapshot = await collectionRef.limit(300).get();
  const batch = db.batch();

  for (const doc of existingSnapshot.docs) {
    batch.delete(doc.ref);
  }

  candidates.forEach((candidate, index) => {
    batch.set(collectionRef.doc(candidateID(candidate.seasonURL)), {
      brandID,
      title: candidate.title,
      seasonURL: candidate.seasonURL,
      coverImageURL: candidate.coverImageURL,
      sourceArchiveURL: archiveURL,
      extractionScore: candidate.score,
      sortIndex: index,
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  await batch.commit();
}

/**
 * 시즌 URL 기반으로 안정적인 후보 문서 ID를 만듭니다.
 *
 * @param {string} seasonURL 시즌 상세 URL입니다.
 * @return {string} Firestore 문서 ID입니다.
 */
function candidateID(seasonURL: string): string {
  return createHash("sha1").update(seasonURL).digest("hex").slice(0, 24);
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
    trimmed.toLowerCase().startsWith("javascript:")
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
  const value = `${url.pathname}?${url.searchParams.toString()}`;
  return (
    /\/(?:product|category|board|member|order|cart|myshop)\//i.test(value) ||
    /(?:list\.html|login|basket|search|coupon|privacy)/i.test(value)
  );
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
  if (/(spring|summer|fall|winter|fw|ss|f\/w|s\/s|20\d{2}|\d{2}fw|\d{2}ss)/i
    .test(haystack)) {
    score += 28;
  }
  if (image) {
    score += 90;
  }
  if (/view all|privacy|agreement|login|cart|search/i.test(linkText)) {
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
    if (sourceURL) {
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

/**
 * unknown 오류 값을 저장 가능한 메시지로 변환합니다.
 *
 * @param {unknown} error 변환할 오류 값입니다.
 * @return {string} 오류 메시지입니다.
 */
function errorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return "알 수 없는 시즌 후보 탐색 오류가 발생했습니다.";
}
