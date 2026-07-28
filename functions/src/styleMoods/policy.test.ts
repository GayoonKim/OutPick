import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  canonicalStyleMoodTerm,
  normalizedStyleMoodTerm,
  parseCreateStyleMoodInput,
  parseUpdateStyleMoodInput,
  resolveStyleMoodUpdate,
  styleMoodTermIndexID,
  validateStyleMoodSeedEntries,
} from "./policy.js";

test("무드 용어는 NFKC, 공백 축약, 소문자로 정규화한다", () => {
  assert.equal(canonicalStyleMoodTerm("  ＯＬＤ   MONEY "), "OLD MONEY");
  assert.equal(normalizedStyleMoodTerm("  ＯＬＤ   MONEY "), "old money");
  assert.equal(styleMoodTermIndexID("street"), styleMoodTermIndexID("street"));
  assert.notEqual(styleMoodTermIndexID("street"), styleMoodTermIndexID("스트릿"));
});

test("생성 입력은 optional ID와 기본 정렬값을 지원한다", () => {
  const input = parseCreateStyleMoodInput({
    displayName: " 스트릿 ",
    displayGroup: "스트릿·트렌드",
    aliases: ["streetwear", "street"],
  }, 1234);

  assert.deepEqual(input, {
    moodID: null,
    displayName: "스트릿",
    normalizedName: "스트릿",
    displayGroup: "스트릿·트렌드",
    aliases: ["streetwear", "street"],
    sortOrder: 1234,
    isFeaturedInOnboarding: false,
    status: "active",
  });
});

test("ID, 그룹, alias 중복과 빈 수정 요청을 거부한다", () => {
  assert.throws(() => parseCreateStyleMoodInput({
    moodID: "Bad-ID",
    displayName: "테스트",
    displayGroup: "베이직·포멀",
    aliases: [],
  }, 1), HttpsError);
  assert.throws(() => parseCreateStyleMoodInput({
    displayName: "테스트",
    displayGroup: "알 수 없음",
    aliases: [],
  }, 1), HttpsError);
  assert.throws(() => parseCreateStyleMoodInput({
    displayName: "Street",
    displayGroup: "스트릿·트렌드",
    aliases: ["street"],
  }, 1), HttpsError);
  assert.throws(() => parseUpdateStyleMoodInput({
    moodID: "streetwear",
  }), HttpsError);
});

test("seed는 ID, 정렬값, 전체 용어 충돌을 거부한다", () => {
  const base = {
    schemaVersion: 1,
    displayGroup: "베이직·포멀",
    aliases: [],
    isFeaturedInOnboarding: false,
    status: "active",
  };
  assert.throws(() => validateStyleMoodSeedEntries([
    {...base, moodID: "one", displayName: "하나", sortOrder: 10},
    {...base, moodID: "one", displayName: "둘", sortOrder: 20},
  ]), HttpsError);
  assert.throws(() => validateStyleMoodSeedEntries([
    {
      ...base,
      moodID: "one",
      displayName: "하나",
      aliases: ["shared"],
      sortOrder: 10,
    },
    {
      ...base,
      moodID: "two",
      displayName: "둘",
      aliases: ["SHARED"],
      sortOrder: 20,
    },
  ]), HttpsError);
});

test("표시 이름 변경은 기존 alias와의 최종 충돌도 거부한다", () => {
  const current = {
    displayName: "스트릿",
    normalizedName: "스트릿",
    displayGroup: "스트릿·트렌드" as const,
    aliases: ["streetwear", "street"],
    sortOrder: 170,
    isFeaturedInOnboarding: true,
    status: "active" as const,
  };

  assert.throws(() => resolveStyleMoodUpdate(current, {
    moodID: "streetwear",
    displayName: "streetwear",
  }), HttpsError);
  assert.deepEqual(resolveStyleMoodUpdate(current, {
    moodID: "streetwear",
    displayName: "스트리트웨어",
    aliases: ["streetwear", "street"],
  }), {
    ...current,
    displayName: "스트리트웨어",
    normalizedName: "스트리트웨어",
  });
});
