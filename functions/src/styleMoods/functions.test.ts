import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  handleCreateStyleMood,
  handleUpdateStyleMood,
} from "./functions.js";
import {
  CreateStyleMoodInput,
  UpdateStyleMoodInput,
} from "./contracts.js";

test("생성 handler는 관리자 검증 후 정규화한 값을 저장한다", async () => {
  const calls: string[] = [];
  const received: CreateStyleMoodInput[] = [];
  const result = await handleCreateStyleMood("admin", {
    moodID: "streetwear",
    displayName: "스트릿",
    displayGroup: "스트릿·트렌드",
    aliases: ["streetwear"],
    isFeaturedInOnboarding: true,
  }, {
    assertTotalAdmin: async (uid) => {
      calls.push(`auth:${uid}`);
    },
    createRecord: async (input) => {
      calls.push("create");
      received.push(input);
      return "streetwear";
    },
    updateRecord: async () => undefined,
    now: () => 100,
  });

  assert.deepEqual(calls, ["auth:admin", "create"]);
  assert.equal(received[0]?.normalizedName, "스트릿");
  assert.equal(received[0]?.sortOrder, 100);
  assert.deepEqual(result, {moodID: "streetwear"});
});

test("비인증 생성은 관리자 검증 전에 거부한다", async () => {
  let authorizationCalled = false;
  await assert.rejects(() => handleCreateStyleMood(undefined, {}, {
    assertTotalAdmin: async () => {
      authorizationCalled = true;
    },
    createRecord: async () => "unused",
    updateRecord: async () => undefined,
    now: () => 1,
  }), HttpsError);
  assert.equal(authorizationCalled, false);
});

test("수정 handler는 관리자 검증과 patch 저장을 수행한다", async () => {
  let received: UpdateStyleMoodInput | null = null;
  const result = await handleUpdateStyleMood("admin", {
    moodID: "minimal",
    status: "inactive",
  }, {
    assertTotalAdmin: async () => undefined,
    createRecord: async () => "unused",
    updateRecord: async (input) => {
      received = input;
    },
    now: () => 1,
  });

  assert.deepEqual(received, {moodID: "minimal", status: "inactive"});
  assert.deepEqual(result, {moodID: "minimal"});
});
