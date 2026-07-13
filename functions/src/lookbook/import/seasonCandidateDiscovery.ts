import {createHash} from "node:crypto";
import type {Firestore} from "firebase-admin/firestore";
import {FieldValue} from "firebase-admin/firestore";
import {
  extractSeasonCandidates,
  type SeasonCandidate,
} from "./seasonCandidateParser.js";

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
