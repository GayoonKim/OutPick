import assert from "node:assert/strict";
import {mkdtemp, mkdir, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";

import {evaluateFixtureCase, evaluateFixtureCorpus} from "./corpus.js";
import {fixtureDifferential} from "./differential.js";
import {loadFixtureCorpus} from "./manifest.js";
import type {FixtureCase, FixtureSnapshot} from "./types.js";

const fixtureRoot = join(process.cwd(), "fixtures");

test("전체 fixture corpus가 golden 계약을 통과한다", async () => {
  const results = await evaluateFixtureCorpus(fixtureRoot);

  assert.deepEqual(
    results.map((result) => result.fixtureID),
    [
      "incident-youth-programmatic-gallery",
      "platform-cafe24-hatchingroom-archive-source",
      "platform-cafe24-outstanding-discovery",
      "platform-cafe24-outstanding-nneditor",
      "platform-cafe24-underscore-detail-discovery",
    ],
  );
  assert.equal(results.every((result) => result.passed), true);
});

test("candidate와 strategy/adapter/quality 변경 diff를 모두 계산한다", () => {
  const before: FixtureSnapshot = {
    candidateKeys: ["a", "b", "c"],
    candidateTitles: {a: "A", b: "B"},
    strategy: "static",
    adapter: {platformKey: null, domainKey: null},
    quality: {status: "accepted", reasons: []},
  };
  const after: FixtureSnapshot = {
    candidateKeys: ["b", "a", "d"],
    candidateTitles: {a: "A2", b: "B"},
    strategy: "rendered",
    adapter: {platformKey: "cafe24", domainKey: null},
    quality: {status: "needsReview", reasons: ["raw_candidate_drop"]},
  };

  assert.deepEqual(fixtureDifferential(before, after), {
    addedCandidateKeys: ["d"],
    removedCandidateKeys: ["c"],
    movedCandidates: [
      {key: "a", beforeIndex: 0, afterIndex: 1},
      {key: "b", beforeIndex: 1, afterIndex: 0},
    ],
    titleChanges: [{key: "a", before: "A", after: "A2"}],
    strategyChange: {before: "static", after: "rendered"},
    adapterChange: {
      before: {platformKey: null, domainKey: null},
      after: {platformKey: "cafe24", domainKey: null},
    },
    qualityChange: {
      before: {status: "accepted", reasons: []},
      after: {status: "needsReview", reasons: ["raw_candidate_drop"]},
    },
  });
});

test("relative order는 추가 후보를 허용하지만 필수 순서를 보존한다", () => {
  const fixture = inMemoryDiscoveryFixture("relative");
  const passed = evaluateFixtureCase(fixture);
  assert.equal(passed.passed, true);

  fixture.expected.candidates = [
    fixture.expected.candidates[1],
    fixture.expected.candidates[0],
  ];
  const failed = evaluateFixtureCase(fixture);
  assert.equal(failed.passed, false);
  assert.equal(failed.errors.includes("relative 후보 순서가 바뀌었습니다."), true);
});

test("fixture corpus는 민감 query key를 거부한다", async () => {
  const root = await mkdtemp(join(tmpdir(), "outpick-fixture-"));
  const directory = join(root, "case");
  await mkdir(directory);
  try {
    await Promise.all([
      writeFile(join(directory, "input.html"), "<html></html>"),
      writeFile(join(directory, "metadata.json"), JSON.stringify({
        schemaVersion: 1,
        id: "sensitive-case",
        kind: "season_images",
        classification: "incident",
        sourceURL: "https://brand.example/lookbook?token=secret",
        inputFile: "input.html",
        provenance: {kind: "incident_minimized", issue: "test"},
      })),
      writeFile(join(directory, "expected.json"), JSON.stringify({
        schemaVersion: 1,
        candidates: [],
        negativeCandidateKeys: [],
        orderPolicy: "strict",
        strategy: "allPageImages",
        adapter: {platformKey: null, domainKey: null},
        quality: {status: "failed", reasons: ["no_candidates"]},
      })),
    ]);
    await assert.rejects(
      loadFixtureCorpus(root),
      /민감 URL\/metadata/,
    );
  } finally {
    await rm(root, {recursive: true});
  }
});

function inMemoryDiscoveryFixture(
  orderPolicy: "strict" | "relative",
): FixtureCase {
  return {
    directory: "memory",
    metadata: {
      schemaVersion: 1,
      id: "relative-order",
      kind: "discovery",
      classification: "generic",
      sourceURL: "https://brand.example/lookbook",
      inputFile: "input.html",
      provenance: {kind: "synthetic", issue: "relative order"},
    },
    expected: {
      schemaVersion: 1,
      candidates: [
        {
          type: "exact",
          key: "https://brand.example/lookbook/2026-spring",
          title: "2026 Spring",
        },
        {
          type: "exact",
          key: "https://brand.example/lookbook/2025-fall",
          title: "2025 Fall",
        },
      ],
      negativeCandidateKeys: [],
      orderPolicy,
      strategy: "staticAnchors",
      adapter: {platformKey: null, domainKey: null},
      quality: null,
    },
    inputHTML: [
      "<a href=\"/lookbook/2026-spring\">",
      "<img src=\"/spring.jpg\">2026 Spring</a>",
      "<a href=\"/lookbook/bonus\">",
      "<img src=\"/bonus.jpg\">2026 Bonus</a>",
      "<a href=\"/lookbook/2025-fall\">",
      "<img src=\"/fall.jpg\">2025 Fall</a>",
    ].join(""),
    renderedHTML: null,
  };
}
