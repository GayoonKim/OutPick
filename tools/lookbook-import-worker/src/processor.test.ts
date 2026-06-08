import assert from "node:assert/strict";
import test from "node:test";

import {fallbackReasonForExtraction} from "./processor.js";

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
