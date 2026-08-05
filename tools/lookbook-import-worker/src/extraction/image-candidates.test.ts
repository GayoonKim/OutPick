import assert from "node:assert/strict";
import test from "node:test";

import {extractSeasonCoverImageCandidate} from "./image-candidates.js";

test("Generic 시즌 콘텐츠 영역의 첫 유효 이미지를 선택한다", () => {
  const candidate = extractSeasonCoverImageCandidate(
    [
      "<header><img src='/assets/logo.png'></header>",
      "<section class='lookbook-content'>",
      "<img src='/covers/first.jpg'><img src='/covers/second.jpg'>",
      "</section>",
      "<footer><img src='/assets/footer.jpg'></footer>",
    ].join(""),
    "https://brand.example/collections/fw-2026",
  );

  assert.deepEqual(candidate, {
    sourceURL: "https://brand.example/covers/first.jpg",
    strategy: "lookbookContent",
  });
});

test("Cafe24의 구체적인 콘텐츠 영역을 Generic 영역보다 우선한다", () => {
  const candidate = extractSeasonCoverImageCandidate(
    [
      "<section class='collection-view'><img src='/generic.jpg'></section>",
      "<div class='xans-product-additional'>",
      "<img ec-data-src='/web/upload/NNEditor/cover.jpg'>",
      "</div>",
    ].join(""),
    "https://brand.example/product/collection-single.html?product_no=1",
  );

  assert.deepEqual(candidate, {
    sourceURL: "https://brand.example/web/upload/NNEditor/cover.jpg",
    strategy: "cafe24ProductAdditional",
  });
});

test("low-confidence 전체 페이지와 main 영역만 있으면 선택하지 않는다", () => {
  assert.equal(extractSeasonCoverImageCandidate(
    "<main><img src='/possible-banner.jpg'></main>",
    "https://brand.example/archive",
  ), null);
});

test("선택한 콘텐츠 영역 안의 banner와 related 이미지를 제외한다", () => {
  const candidate = extractSeasonCoverImageCandidate(
    [
      "<section class='lookbook-content'>",
      "<div class='hero-banner'><img src='/banner.jpg'></div>",
      "<img src='/actual-cover.jpg'>",
      "<aside class='related-products'><img src='/related.jpg'></aside>",
      "</section>",
    ].join(""),
    "https://brand.example/collections/fw-2026",
  );

  assert.equal(candidate?.sourceURL, "https://brand.example/actual-cover.jpg");
});
