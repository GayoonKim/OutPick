import assert from "node:assert/strict";
import test from "node:test";

import {
  extractImageCandidates,
  fallbackReasonForExtraction,
} from "./processor.js";

const candidate = {sourceURL: "https://brand.example/lookbook.jpg", alt: null};

test("정적 후보가 없으면 Playwright fallback 대상이다", () => {
  assert.equal(
    fallbackReasonForExtraction(
      {candidates: [], strategy: "allPageImages", rawCandidateCount: 0},
      "<html></html>",
    ),
    "noStaticCandidates",
  );
});

test("강한 section 후보가 충분하면 fallback을 실행하지 않는다", () => {
  assert.equal(
    fallbackReasonForExtraction(
      {
        candidates: [
          candidate,
          {...candidate, sourceURL: "https://brand.example/2.jpg"},
        ],
        strategy: "productDetailContent",
        rawCandidateCount: 2,
      },
      "<html></html>",
    ),
    null,
  );
});

test("낮은 strategy의 단일 후보는 fallback 대상이다", () => {
  assert.equal(
    fallbackReasonForExtraction(
      {
        candidates: [candidate],
        strategy: "filteredPageImages",
        rawCandidateCount: 1,
      },
      "<html></html>",
    ),
    "singleLowConfidenceCandidate",
  );
});

test("동적 렌더링 신호와 적은 후보가 함께 있으면 fallback 대상이다", () => {
  assert.equal(
    fallbackReasonForExtraction(
      {
        candidates: Array.from({length: 5}, (_, index) => ({
          sourceURL: `https://brand.example/${index}.jpg`,
          alt: null,
        })),
        strategy: "allPageImages",
        rawCandidateCount: 5,
      },
      "<html><script id=\"__NEXT_DATA__\">{}</script></html>",
    ),
    "partialCandidatesWithDynamicSignals",
  );
});

test("raw 후보 대비 최종 후보가 크게 줄면 fallback 대상이다", () => {
  assert.equal(
    fallbackReasonForExtraction(
      {
        candidates: [
          candidate,
          {...candidate, sourceURL: "https://brand.example/2.jpg"},
        ],
        strategy: "filteredPageImages",
        rawCandidateCount: 12,
      },
      "<html></html>",
    ),
    "rawCandidateDropWithLowConfidenceStrategy",
  );
});

test("Cafe24 archive 상세에서는 구매 영역 이미지 대신 archive source 이미지를 사용한다", () => {
  const extraction = extractImageCandidates(
    `
    <div id="detail-info">
      <img src="//img.echosting.cafe24.com/skin/base_ko_KR/product/btn_count_up.gif" alt="수량증가">
      <img src="//img.echosting.cafe24.com/design/skin/admin/ko_KR/product/ico_pay_point.gif" alt="현재 결제가 진행 중입니다.">
      <img src="//brand.example/web/product/tiny/202108/shopping-bag.jpeg" alt="">
    </div>
    <div class="archive-source-detail">
      <img src="/web/upload/NNEditor/20260608/look-01.jpg" alt="">
      <img src="/web/upload/NNEditor/20260608/look-02.jpg" alt="">
    </div>
    `,
    "https://brand.example/product/archive-detail.html?product_no=3759",
  );

  assert.equal(extraction.strategy, "archiveSourceDetail");
  assert.deepEqual(
    extraction.candidates.map((item) => item.sourceURL),
    [
      "https://brand.example/web/upload/NNEditor/20260608/look-01.jpg",
      "https://brand.example/web/upload/NNEditor/20260608/look-02.jpg",
    ],
  );
});
