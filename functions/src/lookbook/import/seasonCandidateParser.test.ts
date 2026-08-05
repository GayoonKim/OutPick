import assert from "node:assert/strict";
import test from "node:test";
import {extractSeasonCandidates} from "./seasonCandidateParser.js";

test("archive 내부 시즌 링크를 순서대로 추출하고 중복을 제거한다", () => {
  const html = `
    <a href="/lookbook/2026-spring">
      <img src="/images/spring.jpg" alt="2026 Spring">2026 Spring
    </a>
    <a href="/lookbook/2026-spring">2026 Spring Collection</a>
    <a href="https://other.example/season">Other</a>
  `;
  const candidates = extractSeasonCandidates(
    html,
    "https://brand.example/lookbook"
  );
  assert.equal(candidates.length, 1);
  assert.equal(candidates[0].seasonURL,
    "https://brand.example/lookbook/2026-spring");
  assert.equal(candidates[0].coverImageURL,
    "https://brand.example/images/spring.jpg");
  assert.equal(candidates[0].coverImageSource, "list");
  assert.equal(candidates[0].coverImageStrategy, "listElementImage");
});

test("대표 이미지가 있는 후보가 둘 이상이어도 이미지 없는 시즌을 유지한다", () => {
  const html = `
    <a href="/product/archive-detail.html?product_no=1">
      <img src="/images/fw.jpg">FW 2026
    </a>
    <a href="/product/archive-detail.html?product_no=2">
      <img src="/images/ss.jpg">SS 2026
    </a>
    <a href="/product/archive-detail.html?product_no=3">FW 2025</a>
  `;
  const candidates = extractSeasonCandidates(
    html,
    "https://brand.example/lookbook"
  );

  assert.equal(candidates.length, 3);
  assert.deepEqual(candidates.map((candidate) => candidate.coverImageSource), [
    "list", "list", "none",
  ]);
});
