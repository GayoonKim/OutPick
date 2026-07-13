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
});
