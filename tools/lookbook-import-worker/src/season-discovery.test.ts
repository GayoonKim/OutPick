import assert from "node:assert/strict";
import test from "node:test";

import {
  classifyDiscovery,
  extractSeasonCandidates,
  shouldUseRenderedDiscovery,
} from "./season-discovery.js";

test("정적 HTML에서 시즌 후보를 추출한다", () => {
  const candidates = extractSeasonCandidates(
    [
      "<a href=\"/product/archive-detail.html?product_no=5153" +
        "&cate_no=125\">",
      "<img data-src=\"/web/upload/lookbook/fw26.jpg\" " +
        "alt=\"OUTSTANDING FW 2026\">",
      "<span>OUTSTANDING FW 2026</span>",
      "</a>",
    ].join(""),
    "https://outstanding-co.kr/lookbook/list.html?cate_no=125",
  );

  assert.equal(candidates.length, 1);
  assert.equal(candidates[0].title, "OUTSTANDING FW 2026");
  assert.equal(
    candidates[0].seasonURL,
    "https://outstanding-co.kr/product/archive-detail.html?product_no=5153&cate_no=125",
  );
  assert.equal(
    candidates[0].coverImageURL,
    "https://outstanding-co.kr/web/upload/lookbook/fw26.jpg",
  );
});

test("이미지 alt와 상품명 라벨에서 시즌명을 정리한다", () => {
  const candidates = extractSeasonCandidates(
    [
      "<a href=\"/lookbook/detail.html?product_no=5153&cate_no=125\">",
      "<img src=\"/empty.png\" data-src=\"/web/product/medium/look.jpg\" ",
      "alt=\"SU Heritage Meets Looney Tunes\">",
      "</a>",
      "<a href=\"/lookbook/detail.html?product_no=5153&cate_no=125\">",
      "<strong class=\"name\"><span class=\"title\">상품명</span> : ",
      "<span>SU Heritage Meets Looney Tunes</span></strong>",
      "<strong class=\"title\">상품요약정보</strong> : <span>&nbsp;</span>",
      "</a>",
    ].join(""),
    "https://outstanding-co.kr/lookbook/list.html?cate_no=125",
  );

  assert.equal(candidates.length, 1);
  assert.equal(candidates[0].title, "SU Heritage Meets Looney Tunes");
  assert.equal(
    candidates[0].coverImageURL,
    "https://outstanding-co.kr/web/product/medium/look.jpg",
  );
});

test("이미지 SEO 설명 꼬리와 중첩 HTML entity를 제거한다", () => {
  const candidates = extractSeasonCandidates(
    [
      "<a href=\"/lookbook/detail.html?product_no=3120&cate_no=125\">",
      "<img data-src=\"/web/product/medium/riders.jpg\" ",
      "alt=\"S/S 2023 &amp;#039;OUTSTANDING RIDERS CLUB&amp;#039; 컬렉션 이미지\">",
      "</a>",
      "<a href=\"/lookbook/detail.html?product_no=4786&cate_no=125\">",
      "<img data-src=\"/web/product/medium/fall.jpg\" ",
      "alt=\"25 FALL EDITORIAL: PART I - 아메리칸 빈티지 스타일의 가을 컬렉션 이미지\">",
      "</a>",
    ].join(""),
    "https://outstanding-co.kr/lookbook/list.html?cate_no=125",
  );

  assert.equal(candidates.length, 2);
  assert.equal(candidates[0].title, "S/S 2023 'OUTSTANDING RIDERS CLUB'");
  assert.equal(candidates[1].title, "25 FALL EDITORIAL: PART I");
});

test("네비게이션 링크와 JS 템플릿 href는 시즌 후보에서 제외한다", () => {
  const candidates = extractSeasonCandidates(
    [
      "<a href=\"/campaigns/list.html?cate_no=126\">Campaigns</a>",
      "<a href=\"/lookbook/list.html?cate_no=125\">Lookbooks</a>",
      "<a href=\"/stores/stores.html?cate_no=130\">STORE</a>",
      "<a href=\"' + $(this).attr('src') + '\">",
      "<img src=\"' + $(this).attr('src') + '\">",
      "</a>",
    ].join(""),
    "https://outstanding-co.kr/lookbook/detail.html?product_no=5153",
  );

  assert.equal(candidates.length, 0);
});

test("후보가 없으면 rendered discovery 대상이다", () => {
  assert.equal(
    shouldUseRenderedDiscovery({
      candidates: [],
      strategy: "lowConfidenceStatic",
      loadMoreDetected: false,
      dynamicRenderingDetected: false,
    }),
    true,
  );
});

test("load-more 신호가 있으면 rendered discovery 대상이다", () => {
  assert.equal(
    shouldUseRenderedDiscovery({
      candidates: [{
        title: "FW 2026",
        seasonURL: "https://brand.example/product/archive-detail.html?product_no=1",
        coverImageURL: null,
        score: 70,
      }],
      strategy: "staticAnchors",
      loadMoreDetected: true,
      dynamicRenderingDetected: false,
    }),
    true,
  );
});

test("충분한 정적 후보는 rendered discovery 대상이 아니다", () => {
  assert.equal(
    shouldUseRenderedDiscovery({
      candidates: [
        {
          title: "FW 2026",
          seasonURL: "https://brand.example/product/archive-detail.html?product_no=1",
          coverImageURL: "https://brand.example/1.jpg",
          score: 90,
        },
        {
          title: "SS 2026",
          seasonURL: "https://brand.example/product/archive-detail.html?product_no=2",
          coverImageURL: "https://brand.example/2.jpg",
          score: 90,
        },
        {
          title: "FW 2025",
          seasonURL: "https://brand.example/product/archive-detail.html?product_no=3",
          coverImageURL: "https://brand.example/3.jpg",
          score: 90,
        },
      ],
      strategy: "staticAnchors",
      loadMoreDetected: false,
      dynamicRenderingDetected: false,
    }),
    false,
  );
});

test("load-more 감지는 공통 로직 개선으로 분류된다", () => {
  const classification = classifyDiscovery({
    candidateCount: 12,
    loadMoreDetected: true,
    dynamicRenderingDetected: false,
    renderedFallbackUsed: false,
    renderedImproved: false,
  });

  assert.equal(classification.status, "needsReview");
  assert.deepEqual(classification.failureReasons, ["load_more_detected"]);
  assert.equal(classification.suggestedFixScope, "common_logic");
  assert.equal(
    classification.suggestedFixes[0]?.type,
    "enable_load_more_click_loop",
  );
});

test("후보 0개는 failed 진단으로 분류된다", () => {
  const classification = classifyDiscovery({
    candidateCount: 0,
    loadMoreDetected: false,
    dynamicRenderingDetected: false,
    renderedFallbackUsed: false,
    renderedImproved: false,
  });

  assert.equal(classification.status, "failed");
  assert.deepEqual(classification.failureReasons, ["no_candidates_found"]);
  assert.equal(classification.errorMessage, "시즌 후보를 찾지 못했습니다.");
});
