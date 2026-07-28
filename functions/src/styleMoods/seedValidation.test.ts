import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import path from "node:path";
import test from "node:test";
import {
  styleMoodTerms,
  validateStyleMoodSeedEntries,
} from "./policy.js";

const seedPath = path.join(
  process.cwd(),
  "seeds",
  "style-moods.v1.json"
);

test("v1 seed는 확정된 56개와 20개 온보딩 무드를 가진다", () => {
  const entries = validateStyleMoodSeedEntries(
    JSON.parse(readFileSync(seedPath, "utf8"))
  );
  assert.equal(entries.length, 56);
  assert.equal(
    entries.filter((entry) => entry.isFeaturedInOnboarding).length,
    20
  );
  assert.equal(entries[0].moodID, "casual");
  assert.equal(entries[0].sortOrder, 10);
  assert.equal(entries.at(-1)?.moodID, "clean_girl");
  assert.equal(entries.at(-1)?.sortOrder, 560);
});

test("v1 seed의 ID, sortOrder, 전체 정규화 용어는 고유하다", () => {
  const entries = validateStyleMoodSeedEntries(
    JSON.parse(readFileSync(seedPath, "utf8"))
  );
  const moodIDs = entries.map((entry) => entry.moodID);
  const sortOrders = entries.map((entry) => entry.sortOrder);
  const terms = entries.flatMap((entry) =>
    styleMoodTerms(entry).map((term) => term.normalizedTerm)
  );

  assert.equal(new Set(moodIDs).size, moodIDs.length);
  assert.equal(new Set(sortOrders).size, sortOrders.length);
  assert.equal(new Set(terms).size, terms.length);
});
