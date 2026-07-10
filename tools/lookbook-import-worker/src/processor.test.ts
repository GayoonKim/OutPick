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

test("일반 script src만으로는 동적 렌더링 fallback을 실행하지 않는다", () => {
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
      "<html><script src=\"/assets/app.js\"></script></html>",
    ),
    null,
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
    [
      "<div id=\"detail-info\">",
      "<img src=\"//img.echosting.cafe24.com/skin/base_ko_KR/product/" +
        "btn_count_up.gif\" alt=\"수량증가\">",
      "<img src=\"//img.echosting.cafe24.com/design/skin/admin/ko_KR/" +
        "product/ico_pay_point.gif\" alt=\"현재 결제가 진행 중입니다.\">",
      "<img src=\"//brand.example/web/product/tiny/202108/" +
        "shopping-bag.jpeg\" alt=\"\">",
      "</div>",
      "<div class=\"archive-source-detail\">",
      "<img src=\"/web/upload/NNEditor/20260608/look-01.jpg\" alt=\"\">",
      "<img src=\"/web/upload/NNEditor/20260608/look-02.jpg\" alt=\"\">",
      "</div>",
    ].join(""),
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

test("채팅 아이콘과 추적 픽셀은 raw 후보에서도 제외한다", () => {
  const extraction = extractImageCandidates(
    [
      "<img src=\"https://onnt1993.cafe24.com/1993/chat-icon-w.svg\" alt=\"chat\">",
      "<img src=\"https://www.facebook.com/tr?id=123&ev=PageView&noscript=1\">",
    ].join(""),
    "https://brand.example/lookbook/detail.html?product_no=1",
  );

  assert.deepEqual(extraction.candidates, []);
  assert.equal(
    fallbackReasonForExtraction(extraction, "<html></html>"),
    "noStaticCandidates",
  );
});

test("소셜/버튼/템플릿 이미지는 raw 후보에서도 제외한다", () => {
  const extraction = extractImageCandidates(
    [
      "<img src=\"/artfinger/img/social-google.png\" alt=\"google\">",
      "<img src=\"/SkinImg/img/login_sns1.png\" alt=\"sns\">",
      "<img src=\"/morenvyimg/top_searchbox_btn01.gif\" alt=\"search\">",
      "<img src=\"/%7B%7B%7Bimage_url%7D%7D%7D\" alt=\"template\">",
      "<img src=\"' + $(this).attr('src') + '\" alt=\"template\">",
      "<img src=\"/web/upload/NNEditor/20260608/look-01.jpg\" alt=\"look\">",
    ].join(""),
    "https://brand.example/lookbook/detail.html?product_no=1",
  );

  assert.deepEqual(
    extraction.candidates.map((item) => item.sourceURL),
    ["https://brand.example/web/upload/NNEditor/20260608/look-01.jpg"],
  );
});

test("노이즈 필터는 브랜드 도메인의 button 문자열을 오탐하지 않는다", () => {
  const extraction = extractImageCandidates(
    "<img src=\"https://www.buttonplay.co.kr/web/upload/lookbook/look-01.jpg\">",
    "https://www.buttonplay.co.kr/lookbook/detail_basic.html?product_no=372",
  );

  assert.deepEqual(
    extraction.candidates.map((item) => item.sourceURL),
    ["https://www.buttonplay.co.kr/web/upload/lookbook/look-01.jpg"],
  );
});

test("관측된 장식 이미지는 raw 후보에서도 제외한다", () => {
  const extraction = extractImageCandidates(
    [
      "<img src=\"https://img.cafe24.com/img/common/global/ko_KR_32x24.png\">",
      "<img src=\"https://rootfinder.co.kr/artfinger/img/bg_search.png\">",
      "<img src=\"https://www.buttonplay.co.kr/web/img/youtube_icon_2.png\">",
      "<img src=\"https://www.edenik.com/web/upload/kdesign/ico/ic_star0.png\">",
      "<img src=\"https://www.edenik.com/web/upload/kdesign/ico/ic_arr_back_b.svg\">",
      "<img src=\"https://brand.example/web/product/big/202606/look-01.jpg\">",
    ].join(""),
    "https://brand.example/lookbook/detail.html?product_no=1",
  );

  assert.deepEqual(
    extraction.candidates.map((item) => item.sourceURL),
    ["https://brand.example/web/product/big/202606/look-01.jpg"],
  );
});
