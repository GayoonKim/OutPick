import assert from "node:assert/strict";
import test from "node:test";

import {cafe24Adapter} from "./adapters/cafe24.js";
import {
  createExtractionAdapterRegistry,
  selectExtractionAdapters,
} from "./adapters/registry.js";

test("Cafe24 공통 구조는 Cafe24 platform adapter를 선택한다", () => {
  const selection = selectExtractionAdapters({
    html: `
      <div class="xans-product-additional">
        <img ec-data-src="/web/upload/lookbook/1.jpg">
      </div>
    `,
    sourceURL: "https://brand.example/product/detail.html?product_no=1",
    kind: "season_images",
  });

  assert.deepEqual(selection.versions, {
    extractorVersion: "1.2.3",
    platformAdapterKey: "cafe24",
    platformAdapterVersion: "1.0.0",
    domainAdapterKey: null,
    domainAdapterVersion: null,
  });
});

test("Cafe24 근거가 없는 일반 페이지는 Generic으로 유지한다", () => {
  const selection = selectExtractionAdapters({
    html: `
      <main>
        <img src="/web/upload/lookbook/1.jpg">
      </main>
    `,
    sourceURL: "https://brand.example/lookbook",
    kind: "season_images",
  });

  assert.equal(selection.versions.platformAdapterKey, null);
  assert.equal(selection.imageRules.contentSectionRules.length, 0);
});

test("Cafe24 adapter 규칙은 다른 플랫폼 선택 결과에 포함되지 않는다", () => {
  const generic = selectExtractionAdapters({
    html: "<main><img src=\"/images/lookbook.jpg\"></main>",
    sourceURL: "https://shop.example/collections/summer",
    kind: "season_images",
  });
  const cafe24 = selectExtractionAdapters({
    html: "<div class=\"xans-product-additional\"></div>",
    sourceURL: "https://brand.example/product/detail.html",
    kind: "season_images",
  });

  assert.equal(
    generic.imageRules.contentSectionRules.some(
      (rule) => rule.label === "cafe24ProductAdditional",
    ),
    false,
  );
  assert.equal(
    cafe24.imageRules.contentSectionRules.some(
      (rule) => rule.label === "cafe24ProductAdditional",
    ),
    true,
  );
});

test("fixture가 등록되지 않은 domain adapter는 registry가 거부한다", () => {
  assert.throws(
    () => createExtractionAdapterRegistry({
      platformAdapters: [cafe24Adapter],
      domainAdapters: [{
        key: "brand-special",
        version: "1.0.0",
        platformKey: "cafe24",
        hosts: ["brand.example"],
        fixtureIDs: ["missing-fixture"],
      }],
      fixtureIDs: [],
    }),
    /domain adapter fixture가 등록되지 않았습니다/,
  );
});

test("host와 fixture가 확인된 domain adapter만 선택한다", () => {
  const registry = createExtractionAdapterRegistry({
    platformAdapters: [cafe24Adapter],
    domainAdapters: [{
      key: "brand-special",
      version: "1.0.0",
      platformKey: "cafe24",
      hosts: ["brand.example"],
      fixtureIDs: ["domain-brand-special"],
    }],
    fixtureIDs: ["domain-brand-special"],
  });
  const selected = registry.select({
    html: "<div class=\"xans-product-additional\"></div>",
    sourceURL: "https://brand.example/product/detail.html",
    kind: "season_images",
  });

  assert.equal(selected.versions.domainAdapterKey, "brand-special");
  assert.equal(selected.versions.domainAdapterVersion, "1.0.0");
});
