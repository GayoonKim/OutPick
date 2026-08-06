/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";

import {
  enrichSeasonCovers,
  type SeasonCoverCandidate,
} from "./season-cover.js";

function candidate(index: number, hasListCover = false): SeasonCoverCandidate {
  return {
    title: `Season ${index}`,
    seasonURL: `https://brand.example/season/${index}`,
    coverImageURL: hasListCover ?
      `https://brand.example/list/${index}.jpg` : null,
    coverImageSource: hasListCover ? "list" : "none",
    coverImageStrategy: hasListCover ? "listElementImage" : null,
    score: 80,
  };
}

const detailHTML = (index: number) =>
  `<section class="lookbook-content"><img src="/detail/${index}.jpg"></section>`;

test("목록 이미지는 유지하고 상세 요청을 시작하지 않는다", async () => {
  let fetchCount = 0;
  const result = await enrichSeasonCovers({
    candidates: [candidate(1, true)],
    overallDeadlineAt: Date.now() + 1000,
    fetchHTML: async () => {
      fetchCount += 1;
      return detailHTML(1);
    },
  });

  assert.equal(fetchCount, 0);
  assert.equal(result.candidates[0].coverImageSource, "list");
  assert.deepEqual(result.summary, {
    coverImageCount: 1,
    listCoverImageCount: 1,
    detailCoverAttemptCount: 0,
    detailCoverSuccessCount: 0,
    detailCoverFailureCount: 0,
    detailCoverSkippedCount: 0,
  });
});

test("상세 성공과 실패를 후보별로 격리하고 identity와 순서를 보존한다", async () => {
  const inputs = [candidate(1), candidate(2, true), candidate(3)];
  const result = await enrichSeasonCovers({
    candidates: inputs,
    overallDeadlineAt: Date.now() + 1000,
    fetchHTML: async (url) => url.endsWith("/1") ?
      detailHTML(1) : "<header><img src='/logo.png'></header>",
  });

  assert.deepEqual(
    result.candidates.map(({title, seasonURL}) => ({title, seasonURL})),
    inputs.map(({title, seasonURL}) => ({title, seasonURL})),
  );
  assert.equal(result.candidates[0].coverImageSource, "detail");
  assert.equal(result.candidates[0].coverImageStrategy, "lookbookContent");
  assert.equal(result.candidates[1].coverImageSource, "list");
  assert.equal(result.candidates[2].coverImageSource, "none");
  assert.deepEqual(result.summary, {
    coverImageCount: 2,
    listCoverImageCount: 1,
    detailCoverAttemptCount: 2,
    detailCoverSuccessCount: 1,
    detailCoverFailureCount: 1,
    detailCoverSkippedCount: 0,
  });
});

test("상세 요청은 동시 3개를 넘지 않는다", async () => {
  let active = 0;
  let maxActive = 0;
  const result = await enrichSeasonCovers({
    candidates: Array.from({length: 8}, (_, index) => candidate(index + 1)),
    overallDeadlineAt: Date.now() + 1000,
    fetchHTML: async (url) => {
      active += 1;
      maxActive = Math.max(maxActive, active);
      await new Promise((resolve) => setTimeout(resolve, 5));
      active -= 1;
      return detailHTML(Number(url.split("/").at(-1)));
    },
  });

  assert.equal(maxActive, 3);
  assert.equal(result.summary.detailCoverAttemptCount, 8);
  assert.equal(result.summary.detailCoverSuccessCount, 8);
});

test("최대 30개만 시도하고 나머지는 건너뛴다", async () => {
  const result = await enrichSeasonCovers({
    candidates: Array.from({length: 35}, (_, index) => candidate(index + 1)),
    overallDeadlineAt: Date.now() + 1000,
    fetchHTML: async (url) => detailHTML(Number(url.split("/").at(-1))),
  });

  assert.equal(result.summary.detailCoverAttemptCount, 30);
  assert.equal(result.summary.detailCoverSuccessCount, 30);
  assert.equal(result.summary.detailCoverSkippedCount, 5);
});

test("전체 deadline 잔여 시간이 없으면 상세 요청을 시작하지 않는다", async () => {
  const result = await enrichSeasonCovers({
    candidates: [candidate(1), candidate(2)],
    overallDeadlineAt: 0,
    now: () => 0,
    fetchHTML: async () => detailHTML(1),
  });

  assert.equal(result.summary.detailCoverAttemptCount, 0);
  assert.equal(result.summary.detailCoverSkippedCount, 2);
});
