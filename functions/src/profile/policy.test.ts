import assert from "node:assert/strict";
import test from "node:test";
import {
  nicknameIndexID,
  normalizeNicknameDisplay,
  normalizeNicknameKey,
  parseCompleteOnboardingInput,
  parsePublicProfilePatch,
  parseSelectedMoodIDs,
} from "./policy.js";

test("닉네임은 NFKC 정규화와 공백 정리를 거쳐 동일 인덱스를 사용한다", () => {
  const display = normalizeNicknameDisplay("  Ｏｕｔ　Ｐｉｃｋ  ");
  assert.equal(display, "Out Pick");
  assert.equal(normalizeNicknameKey(display), "out pick");
  assert.equal(
    nicknameIndexID(display),
    nicknameIndexID("out pick"),
  );
});

test("닉네임 길이와 제어 문자를 거부한다", () => {
  assert.throws(() => normalizeNicknameDisplay("한"));
  assert.throws(() => normalizeNicknameDisplay("a".repeat(21)));
  assert.throws(() => normalizeNicknameDisplay("정상\u200B닉네임"));
});

test("관심 무드는 1~5개의 고유 문서 ID만 허용한다", () => {
  assert.deepEqual(parseSelectedMoodIDs(["minimal"]), ["minimal"]);
  assert.deepEqual(
    parseSelectedMoodIDs(["a", "b", "c", "d", "e"]),
    ["a", "b", "c", "d", "e"],
  );
  assert.throws(() => parseSelectedMoodIDs([]));
  assert.throws(() => parseSelectedMoodIDs(["a", "b", "c", "d", "e", "f"]));
  assert.throws(() => parseSelectedMoodIDs(["minimal", "minimal"]));
  assert.throws(() => parseSelectedMoodIDs(["invalid/id"]));
});

test("온보딩 입력은 사용자 소유 프로필 이미지 경로만 허용한다", () => {
  const parsed = parseCompleteOnboardingInput({
    nickname: "아웃픽",
    selectedMoodIDs: ["minimal"],
    avatarThumbPath: "profileImage/user-a/thumb/avatar.jpg",
    avatarOriginalPath: "profileImage/user-a/original/avatar.jpg",
  }, "user-a");
  assert.equal(parsed.avatarThumbPath, "profileImage/user-a/thumb/avatar.jpg");

  assert.throws(() => parseCompleteOnboardingInput({
    nickname: "아웃픽",
    selectedMoodIDs: ["minimal"],
    avatarThumbPath: "profileImage/user-b/thumb/avatar.jpg",
  }, "user-a"));
});

test("프로필 수정은 누락과 null 삭제를 구분한다", () => {
  assert.deepEqual(
    parsePublicProfilePatch({avatarThumbPath: null}, "user-a"),
    {avatarThumbPath: null},
  );
  assert.throws(() => parsePublicProfilePatch({}, "user-a"));
});
