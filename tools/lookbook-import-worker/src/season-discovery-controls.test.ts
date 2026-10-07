import assert from "node:assert/strict";
import test from "node:test";
import {chromium} from "playwright";
import {inspectDiscoveryPageControls} from "./season-discovery-controls.js";
import {classifyDiscovery, extractSeasonCandidateResult}
  from "./season-discovery.js";

test("탐색 최종 판정은 한 페이지 paginate와 script 문자열을 미완료로 보지 않는다",
  async () => {
    const browser = await chromium.launch({headless: true});
    try {
      const page = await browser.newPage();
      await page.setContent(`<script>const loadMore = true;</script>
        <div class="ec-base-paginate"><a href="#none">&lt;</a>
        <a href="?page=1" class="this">1</a><a href="#none">&gt;</a></div>`);
      const html = await page.content();
      assert.equal(extractSeasonCandidateResult(html,
        "https://example.com/collection").loadMoreDetected, true);
      const controls = await inspectDiscoveryPageControls(page);
      assert.deepEqual(controls, {loadMoreDetected: false,
        forwardPaginationDetected: false, clicked: false});
      assert.equal(classifyDiscovery({candidateCount: 29,
        loadMoreDetected: true, dynamicRenderingDetected: false,
        renderedFallbackUsed: true, renderedImproved: false,
        unresolvedExpansion: controls.loadMoreDetected ||
          controls.forwardPaginationDetected}).status, "passed");
    } finally {
      await browser.close();
    }
  });

test("탐색은 가시 활성 more만 클릭하고 숨김 disabled 컨트롤을 제외한다",
  async () => {
    const browser = await chromium.launch({headless: true});
    try {
      const page = await browser.newPage();
      await page.setContent(`<button style="display:none">more</button>
        <button disabled>더 보기</button>
        <button aria-disabled="true">more</button>
        <button id="loadMore" onclick="this.remove()">load more</button>`);
      assert.equal((await inspectDiscoveryPageControls(page)).loadMoreDetected,
        true);
      assert.equal((await inspectDiscoveryPageControls(page, true)).clicked,
        true);
      assert.deepEqual(await inspectDiscoveryPageControls(page, true),
        {loadMoreDetected: false, forwardPaginationDetected: false,
          clicked: false});
    } finally {
      await browser.close();
    }
  });

test("탐색은 실제 다음 페이지를 교정 필요로 유지하고 이전 현재 링크를 제외한다",
  async () => {
    const browser = await chromium.launch({headless: true});
    try {
      const page = await browser.newPage();
      await page.route("https://example.com/**", (route) =>
        route.fulfill({status: 200, contentType: "text/html", body: "<body>"}));
      await page.goto("https://example.com/collection?page=2");
      await page.setContent(`<div class="paging">
        <a href="?page=1">1</a>
        <a class="this" href="?page=2">2</a>
        <a class="prev" href="?page=1">previous</a>
        <a href="?page=3">3</a></div>`);
      const controls = await inspectDiscoveryPageControls(page);
      assert.equal(controls.forwardPaginationDetected, true);
      assert.equal(classifyDiscovery({candidateCount: 29,
        loadMoreDetected: true, dynamicRenderingDetected: false,
        renderedFallbackUsed: true, renderedImproved: false,
        unresolvedExpansion: controls.forwardPaginationDetected}).status,
      "needsReview");
      await page.setContent(`<div class="paging"><a class="this"
        href="?page=2">2</a><a href="?page=1">1</a>
        <a href="#none">next</a></div>`);
      assert.equal((await inspectDiscoveryPageControls(page))
        .forwardPaginationDetected, false);
    } finally {
      await browser.close();
    }
  });
