import type {Firestore} from "firebase-admin/firestore";
import {FieldValue} from "firebase-admin/firestore";

type ImageCandidate = {
  sourceURL: string;
  alt: string | null;
};

type ImageExtractionResult = {
  candidates: ImageCandidate[];
  strategy: string;
  rawCandidateCount: number;
};

type ContentSection = {
  html: string;
  index: number;
  label: string;
  weight: number;
};

type ImportJobData = {
  brandID?: unknown;
  jobType?: unknown;
  status?: unknown;
  sourceURL?: unknown;
  createdAt?: unknown;
};

type SingleJobProcessResult = {
  jobID: string;
  processed: boolean;
  status: "parsed" | "failed" | "skipped";
  reason?: string;
  sourceURL?: string;
  imageCandidateCount?: number;
  errorMessage?: string;
};

type BatchProcessResult = {
  brandID: string;
  requestedJobCount: number;
  processedJobCount: number;
  failedJobCount: number;
  skippedJobCount: number;
  results: SingleJobProcessResult[];
};

type JobClaimResult =
  | {
      claimed: true;
      sourceURL: string;
    }
  | {
      claimed: false;
      status: "skipped";
      reason: string;
      sourceURL?: string;
    };

type ProcessResult =
  | {
      processed: false;
      reason: "noQueuedJob";
    }
  | {
      processed: true;
      brandID: string;
      jobID: string;
      sourceURL: string;
      imageCandidateCount: number;
    };

const MAX_IMAGE_CANDIDATES_TO_STORE = 120;
const MIN_STRONG_SECTION_WEIGHT = 240;
const DEFAULT_BATCH_CONCURRENCY = 3;
const MAX_BATCH_CONCURRENCY = 3;

const CONTENT_SECTION_RULES: Array<{
  label: string;
  pattern: RegExp;
  weight: number;
}> = [
  {
    label: "cafe24ProductAdditional",
    pattern:
      /xans-product-additional|prdDetailContentLazy|product-additional/i,
    weight: 360,
  },
  {
    label: "productDetailContent",
    pattern:
      /prdDetail|detail[_-]?content|detailArea|product[_-]?detail[_-]?area/i,
    weight: 300,
  },
  {
    label: "editorContent",
    pattern: /NNEditor|fr-view|se-main-container|editor|edibot/i,
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
  /(?:sprite|blank|placeholder|loading)\.(?:gif|png|svg)(?:\?|$)/i,
];

const NOISE_CONTEXT_PATTERN =
  /product\/list\.html|category\/|view all|gnb|lnb|menu|header|footer/i;

/**
 * 큐에 쌓인 시즌 URL import job 하나를 처리합니다.
 *
 * 현재 1차 워커의 책임은 실제 Season/Post 생성이 아니라,
 * 시즌 URL 접근 가능성과 이미지 후보 추출 가능성을 검증하는 것입니다.
 *
 * @param {Firestore} db Firestore Admin SDK 인스턴스입니다.
 * @param {string} brandID 처리할 브랜드 문서 ID입니다.
 * @return {Promise<ProcessResult>} 처리 결과 요약입니다.
 */
export async function processNextSeasonImportJob(
  db: Firestore,
  brandID: string
): Promise<ProcessResult> {
  const queuedJobs = await db
    .collection("brands")
    .doc(brandID)
    .collection("importJobs")
    .where("status", "==", "queued")
    .limit(20)
    .get();

  const jobSnapshot = queuedJobs.docs
    .filter((snapshot) => {
      const data = snapshot.data() as ImportJobData;
      return data.jobType === "importSeasonFromURL";
    })
    .sort((lhs, rhs) => {
      const left = createdAtMillis(lhs.data() as ImportJobData);
      const right = createdAtMillis(rhs.data() as ImportJobData);
      return left - right;
    })[0];

  if (!jobSnapshot) {
    return {
      processed: false,
      reason: "noQueuedJob",
    };
  }

  const result = await processSeasonImportJobByID(
    db,
    brandID,
    jobSnapshot.id
  );

  if (!result.processed || result.status !== "parsed") {
    return {
      processed: false,
      reason: "noQueuedJob",
    };
  }

  return {
    processed: true,
    brandID,
    jobID: result.jobID,
    sourceURL: result.sourceURL ?? "",
    imageCandidateCount: result.imageCandidateCount ?? 0,
  };
}

/**
 * 선택한 시즌 import job 목록을 제한된 병렬성으로 처리합니다.
 *
 * @param {Firestore} db Firestore Admin SDK 인스턴스입니다.
 * @param {string} brandID 처리할 브랜드 문서 ID입니다.
 * @param {string[]} jobIDs 처리할 import job ID 목록입니다.
 * @param {number} concurrency 동시에 처리할 최대 job 수입니다.
 * @return {Promise<BatchProcessResult>} 배치 처리 결과입니다.
 */
export async function processSeasonImportJobs(
  db: Firestore,
  brandID: string,
  jobIDs: string[],
  concurrency = DEFAULT_BATCH_CONCURRENCY
): Promise<BatchProcessResult> {
  const uniqueJobIDs = Array.from(new Set(jobIDs));
  const safeConcurrency = Math.max(
    1,
    Math.min(MAX_BATCH_CONCURRENCY, Math.floor(concurrency))
  );
  const results: SingleJobProcessResult[] = [];
  let cursor = 0;

  const workers = Array.from(
    {length: Math.min(safeConcurrency, uniqueJobIDs.length)},
    async () => {
      for (;;) {
        const currentIndex = cursor;
        cursor += 1;

        const jobID = uniqueJobIDs[currentIndex];
        if (!jobID) {
          return;
        }

        const result = await processSeasonImportJobByID(db, brandID, jobID);
        results[currentIndex] = result;
      }
    }
  );

  await Promise.all(workers);

  return {
    brandID,
    requestedJobCount: uniqueJobIDs.length,
    processedJobCount: results.filter((result) => {
      return result.processed && result.status === "parsed";
    }).length,
    failedJobCount: results.filter((result) => {
      return result.status === "failed";
    }).length,
    skippedJobCount: results.filter((result) => {
      return result.status === "skipped";
    }).length,
    results,
  };
}

/**
 * 특정 시즌 import job 하나를 처리합니다.
 *
 * @param {Firestore} db Firestore Admin SDK 인스턴스입니다.
 * @param {string} brandID 처리할 브랜드 문서 ID입니다.
 * @param {string} jobID 처리할 import job ID입니다.
 * @return {Promise<SingleJobProcessResult>} 단일 job 처리 결과입니다.
 */
async function processSeasonImportJobByID(
  db: Firestore,
  brandID: string,
  jobID: string
): Promise<SingleJobProcessResult> {
  const jobRef = db
    .collection("brands")
    .doc(brandID)
    .collection("importJobs")
    .doc(jobID);

  const claim = await db.runTransaction<JobClaimResult>(async (transaction) => {
    const freshSnapshot = await transaction.get(jobRef);
    const data = freshSnapshot.data() as ImportJobData | undefined;

    if (!freshSnapshot.exists) {
      return {
        claimed: false,
        reason: "notFound",
        status: "skipped" as const,
      };
    }

    if (data?.jobType !== "importSeasonFromURL") {
      return {
        claimed: false,
        reason: "invalidJobType",
        status: "skipped" as const,
      };
    }

    if (data.status === "parsed" || data.status === "success") {
      return {
        claimed: false,
        reason: "alreadyProcessed",
        status: "skipped" as const,
        sourceURL: stringField(data.sourceURL, "sourceURL"),
      };
    }

    if (data.status !== "queued") {
      return {
        claimed: false,
        reason: `notQueued:${String(data.status ?? "unknown")}`,
        status: "skipped" as const,
        sourceURL: stringField(data.sourceURL, "sourceURL"),
      };
    }

    const claimedBrandID = stringField(data.brandID, "brandID");
    const sourceURL = stringField(data.sourceURL, "sourceURL");

    if (claimedBrandID !== brandID) {
      throw new Error("job 문서의 brandID가 요청 brandID와 다릅니다.");
    }

    transaction.update(jobRef, {
      status: "running",
      errorMessage: null,
      startedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      claimed: true,
      sourceURL,
    };
  });

  if (!claim.claimed) {
    return {
      jobID,
      processed: false,
      status: claim.status,
      reason: claim.reason,
      sourceURL: claim.sourceURL,
    };
  }

  try {
    const html = await fetchHTML(claim.sourceURL);
    const extraction = extractImageCandidates(html, claim.sourceURL);

    await jobRef.update({
      status: "parsed",
      imageCandidateCount: extraction.candidates.length,
      imageCandidates: extraction.candidates.slice(
        0,
        MAX_IMAGE_CANDIDATES_TO_STORE
      ),
      imageExtractionStrategy: extraction.strategy,
      rawImageCandidateCount: extraction.rawCandidateCount,
      parsedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      jobID,
      processed: true,
      status: "parsed",
      sourceURL: claim.sourceURL,
      imageCandidateCount: extraction.candidates.length,
    };
  } catch (error) {
    const message = errorMessage(error);
    await jobRef.update({
      status: "failed",
      errorMessage: message,
      failedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      jobID,
      processed: true,
      status: "failed",
      sourceURL: claim.sourceURL,
      errorMessage: message,
    };
  }
}

/**
 * 시즌 URL에서 HTML 문자열을 가져옵니다.
 *
 * @param {string} url 가져올 시즌 페이지 URL입니다.
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
      throw new Error(`시즌 URL 응답 실패: HTTP ${response.status}`);
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
 * HTML에서 시즌 본문 이미지 후보 URL을 추출합니다.
 *
 * @param {string} html 파싱할 HTML 문자열입니다.
 * @param {string} baseURL 상대 경로 보정에 사용할 기준 URL입니다.
 * @return {ImageExtractionResult} 이미지 후보와 추출 전략입니다.
 */
function extractImageCandidates(
  html: string,
  baseURL: string
): ImageExtractionResult {
  const rawCandidates = collectImageCandidates(html, baseURL, {
    applyNoiseFilter: false,
    includeMetaImages: true,
  });
  const sectionCandidates = contentSections(html)
    .map((section) => {
      const candidates = collectImageCandidates(section.html, baseURL, {
        applyNoiseFilter: false,
        includeMetaImages: false,
      });
      const score = section.weight + candidates.length * 10;

      return {
        candidates,
        label: section.label,
        score,
      };
    })
    .filter((section) => section.candidates.length > 0)
    .sort((lhs, rhs) => rhs.score - lhs.score);

  const bestSection = sectionCandidates[0];
  if (
    bestSection &&
    (
      bestSection.score >= MIN_STRONG_SECTION_WEIGHT ||
      bestSection.candidates.length >= 2
    )
  ) {
    return {
      candidates: bestSection.candidates,
      strategy: bestSection.label,
      rawCandidateCount: rawCandidates.length,
    };
  }

  const filteredCandidates = collectImageCandidates(html, baseURL, {
    applyNoiseFilter: true,
    includeMetaImages: false,
  });

  return {
    candidates: filteredCandidates.length > 0 ?
      filteredCandidates :
      rawCandidates,
    strategy: filteredCandidates.length > 0 ?
      "filteredPageImages" :
      "allPageImages",
    rawCandidateCount: rawCandidates.length,
  };
}

/**
 * HTML 조각에서 이미지 후보 URL을 수집합니다.
 *
 * @param {string} html 파싱할 HTML 문자열입니다.
 * @param {string} baseURL 상대 경로 보정에 사용할 기준 URL입니다.
 * @param {{applyNoiseFilter: boolean, includeMetaImages: boolean}} options
 * 이미지 수집 옵션입니다.
 * @return {ImageCandidate[]} 중복 제거된 이미지 후보 목록입니다.
 */
function collectImageCandidates(
  html: string,
  baseURL: string,
  options: {
    applyNoiseFilter: boolean;
    includeMetaImages: boolean;
  }
): ImageCandidate[] {
  const candidates: ImageCandidate[] = [];
  const seen = new Set<string>();

  // 한국어 주석: 수동 시즌 URL은 본문 블록을 우선 파싱하고,
  // 전역 파싱은 실패 시 보수적인 fallback으로만 사용합니다.
  for (const match of html.matchAll(/<img\b[^>]*>/gi)) {
    const tag = match[0];
    const alt = attributeValue(tag, "alt");
    const urlValues = imageURLValues(tag);
    const context = tagContext(html, match.index ?? 0);

    appendURLs(
      candidates,
      seen,
      urlValues,
      baseURL,
      alt,
      context,
      options.applyNoiseFilter
    );
  }

  for (const match of html.matchAll(/<source\b[^>]*>/gi)) {
    const tag = match[0];
    const context = tagContext(html, match.index ?? 0);
    const urlValues = [
      ...srcsetURLs(attributeValue(tag, "srcset")),
      ...srcsetURLs(attributeValue(tag, "data-srcset")),
    ];

    appendURLs(
      candidates,
      seen,
      urlValues,
      baseURL,
      null,
      context,
      options.applyNoiseFilter
    );
  }

  if (!options.includeMetaImages) {
    return candidates;
  }

  for (const match of html.matchAll(/<meta\b[^>]*>/gi)) {
    const tag = match[0];
    const property =
      attributeValue(tag, "property") ?? attributeValue(tag, "name");
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
      options.applyNoiseFilter
    );
  }

  return candidates;
}

/**
 * 본문 이미지가 들어있을 가능성이 높은 HTML 블록을 찾습니다.
 *
 * @param {string} html 전체 HTML 문자열입니다.
 * @return {ContentSection[]} 본문 후보 블록 목록입니다.
 */
function contentSections(html: string): ContentSection[] {
  const sections: ContentSection[] = [];
  const startTagPattern = /<(main|article|section|div)\b[^>]*>/gi;

  for (const match of html.matchAll(startTagPattern)) {
    const tag = match[0];
    const rule = CONTENT_SECTION_RULES.find((item) => {
      return item.pattern.test(tag);
    });
    if (!rule) {
      continue;
    }

    const tagName = match[1];
    const sectionHTML = sliceElementHTML(html, match.index ?? 0, tagName);
    if (!sectionHTML || imageTagCount(sectionHTML) === 0) {
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

/**
 * 시작 태그 위치에서 해당 요소 HTML을 잘라냅니다.
 *
 * @param {string} html 전체 HTML 문자열입니다.
 * @param {number} startIndex 시작 태그 인덱스입니다.
 * @param {string} tagName 요소 태그 이름입니다.
 * @return {string} 추출된 요소 HTML 문자열입니다.
 */
function sliceElementHTML(
  html: string,
  startIndex: number,
  tagName: string
): string {
  const tokenPattern = new RegExp(`<\\/?${tagName}\\b[^>]*>`, "gi");
  tokenPattern.lastIndex = startIndex;
  let depth = 0;

  for (;;) {
    const match = tokenPattern.exec(html);
    if (!match) {
      return html.slice(startIndex);
    }

    const token = match[0];
    if (token.startsWith("</")) {
      depth -= 1;
    } else if (!token.endsWith("/>")) {
      depth += 1;
    }

    if (depth === 0) {
      return html.slice(startIndex, match.index + token.length);
    }
  }
}

/**
 * HTML 조각에 포함된 img 태그 수를 계산합니다.
 *
 * @param {string} html 검사할 HTML 문자열입니다.
 * @return {number} img 태그 개수입니다.
 */
function imageTagCount(html: string): number {
  return Array.from(html.matchAll(/<img\b[^>]*>/gi)).length;
}

/**
 * 이미지 태그에서 URL로 볼 수 있는 속성 값을 읽습니다.
 *
 * @param {string} tag img 태그 문자열입니다.
 * @return {Array<string | null>} URL 후보 목록입니다.
 */
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

/**
 * 이미지 태그 주변의 짧은 HTML 문맥을 가져옵니다.
 *
 * @param {string} html 전체 HTML 문자열입니다.
 * @param {number} index 이미지 태그 시작 인덱스입니다.
 * @return {string} 이미지 주변 HTML 문맥입니다.
 */
function tagContext(html: string, index: number): string {
  const start = Math.max(0, index - 500);
  const end = Math.min(html.length, index + 500);
  return html.slice(start, end);
}

/**
 * URL 후보들을 정규화해서 결과 배열에 추가합니다.
 *
 * @param {ImageCandidate[]} candidates 누적 이미지 후보 배열입니다.
 * @param {Set<string>} seen 이미 추가한 URL 집합입니다.
 * @param {Array<string | null>} rawValues 원본 URL 후보 목록입니다.
 * @param {string} baseURL 상대 경로 보정에 사용할 기준 URL입니다.
 * @param {string | null} alt 이미지 대체 텍스트입니다.
 * @param {string} context 이미지 태그 주변 HTML 문맥입니다.
 * @param {boolean} applyNoiseFilter 노이즈 이미지 제외 여부입니다.
 */
function appendURLs(
  candidates: ImageCandidate[],
  seen: Set<string>,
  rawValues: Array<string | null>,
  baseURL: string,
  alt: string | null,
  context: string,
  applyNoiseFilter: boolean
): void {
  for (const rawValue of rawValues) {
    const normalizedURL = normalizedImageURL(rawValue, baseURL);
    if (
      !normalizedURL ||
      seen.has(normalizedURL) ||
      (
        applyNoiseFilter &&
        isLikelyNoiseImage(normalizedURL, context)
      )
    ) {
      continue;
    }

    seen.add(normalizedURL);
    candidates.push({
      sourceURL: normalizedURL,
      alt,
    });
  }
}

/**
 * 메뉴/배너/아이콘성 이미지를 제외할지 판단합니다.
 *
 * @param {string} imageURL 정규화된 이미지 URL입니다.
 * @param {string} context 이미지 태그 주변 HTML 문맥입니다.
 * @return {boolean} 노이즈 이미지로 보이면 true입니다.
 */
function isLikelyNoiseImage(imageURL: string, context: string): boolean {
  if (NOISE_IMAGE_URL_PATTERNS.some((pattern) => pattern.test(imageURL))) {
    return true;
  }
  return NOISE_CONTEXT_PATTERN.test(context);
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
  return match?.[2] ?? match?.[3] ?? match?.[4] ?? null;
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
 * @param {string} baseURL 상대 경로 보정에 사용할 기준 URL입니다.
 * @return {string | null} 정규화된 이미지 URL 또는 null입니다.
 */
function normalizedImageURL(
  rawValue: string | null,
  baseURL: string
): string | null {
  if (!rawValue) {
    return null;
  }

  const trimmed = rawValue.trim();
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
 * Firestore job 문서의 문자열 필드를 검증합니다.
 *
 * @param {unknown} value 검증할 값입니다.
 * @param {string} fieldName 오류 메시지에 사용할 필드명입니다.
 * @return {string} trim 처리된 문자열입니다.
 */
function stringField(value: unknown, fieldName: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${fieldName} 값이 올바르지 않습니다.`);
  }
  return value.trim();
}

/**
 * Firestore Timestamp 값을 정렬 가능한 숫자로 변환합니다.
 *
 * @param {ImportJobData} data import job 문서 데이터입니다.
 * @return {number} 생성 시각 밀리초 값입니다.
 */
function createdAtMillis(data: ImportJobData): number {
  const createdAt = data.createdAt;
  if (
    createdAt &&
    typeof createdAt === "object" &&
    "toMillis" in createdAt &&
    typeof createdAt.toMillis === "function"
  ) {
    return createdAt.toMillis();
  }

  return Number.MAX_SAFE_INTEGER;
}

/**
 * unknown 오류 값을 사용자에게 저장 가능한 메시지로 바꿉니다.
 *
 * @param {unknown} error 변환할 오류 값입니다.
 * @return {string} 오류 메시지입니다.
 */
function errorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return "알 수 없는 import worker 오류가 발생했습니다.";
}
