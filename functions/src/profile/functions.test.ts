/* eslint-disable require-jsdoc, max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {
  handleCheckNicknameAvailability,
  handleCompleteOnboarding,
  handleUpdatePublicProfile,
  handleUpdateStylePreferences,
} from "./functions.js";

function dependencies() {
  return {
    assertActive: async (uid: string) => {
      void uid;
    },
    checkNicknameAvailability: async (uid: string, nickname: string) => ({
      isAvailable: uid === "user-a" && nickname === "아웃픽",
    }),
    completeRecord: async (uid: string) => ({
      userID: uid,
      onboardingVersion: 1,
    }),
    updatePublicRecord: async (uid: string, patch: {
      nickname?: string;
      avatarThumbPath?: string | null;
      avatarOriginalPath?: string | null;
    }) => ({
      userID: uid,
      nickname: patch.nickname ?? "기존닉네임",
      avatarThumbPath: patch.avatarThumbPath ?? null,
      avatarOriginalPath: patch.avatarOriginalPath ?? null,
    }),
    updatePreferencesRecord: async (uid: string, selectedMoodIDs: string[]) => ({
      userID: uid,
      selectedMoodIDs,
    }),
  };
}

test("닉네임 확인 handler는 인증과 정규화 후 가용성을 반환한다", async () => {
  const result = await handleCheckNicknameAvailability(
    "user-a",
    {nickname: " 아웃픽 "},
    dependencies(),
  );

  assert.deepEqual(result, {isAvailable: true});
});

test("온보딩 handler는 인증 사용자와 검증된 입력만 record 계층에 전달한다", async () => {
  const calls: unknown[] = [];
  const deps = {
    ...dependencies(),
    completeRecord: async (uid: string, input: unknown) => {
      calls.push({uid, input});
      return {userID: uid, onboardingVersion: 1};
    },
  };

  const result = await handleCompleteOnboarding("user-a", {
    nickname: " 아웃픽 ",
    selectedMoodIDs: ["minimal"],
  }, deps);
  assert.deepEqual(result, {userID: "user-a", onboardingVersion: 1});
  assert.deepEqual(calls, [{
    uid: "user-a",
    input: {
      nickname: "아웃픽",
      selectedMoodIDs: ["minimal"],
      avatarThumbPath: null,
      avatarOriginalPath: null,
    },
  }]);
});

test("프로필과 관심 무드 수정은 account active 검증 후 실행한다", async () => {
  const order: string[] = [];
  const deps = {
    ...dependencies(),
    assertActive: async () => {
      order.push("active");
    },
    updatePublicRecord: async (uid: string, patch: {nickname?: string}) => {
      order.push("public");
      return {
        userID: uid,
        nickname: patch.nickname ?? "기존닉네임",
        avatarThumbPath: null,
        avatarOriginalPath: null,
      };
    },
    updatePreferencesRecord: async (uid: string, selectedMoodIDs: string[]) => {
      order.push("preferences");
      return {userID: uid, selectedMoodIDs};
    },
  };

  await handleUpdatePublicProfile("user-a", {nickname: "새닉네임"}, deps);
  await handleUpdateStylePreferences(
    "user-a",
    {selectedMoodIDs: ["street"]},
    deps,
  );
  assert.deepEqual(order, ["active", "public", "active", "preferences"]);
});

test("미인증 handler 요청을 거부한다", async () => {
  await assert.rejects(
    handleCheckNicknameAvailability(undefined, {
      nickname: "아웃픽",
    }, dependencies()),
    (error: {code?: string}) => error.code === "unauthenticated",
  );
  await assert.rejects(
    handleCompleteOnboarding(undefined, {
      nickname: "아웃픽",
      selectedMoodIDs: ["minimal"],
    }, dependencies()),
    (error: {code?: string}) => error.code === "unauthenticated",
  );
});
