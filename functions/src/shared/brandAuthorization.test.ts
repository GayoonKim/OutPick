import assert from "node:assert/strict";
import test from "node:test";
import {
  findUserIDByEmail,
  hasBrandWriteAccessData,
  isBrandOwnerData,
} from "./brandAuthorization.js";

test("owner와 admin만 브랜드 쓰기 권한을 가진다", () => {
  assert.equal(hasBrandWriteAccessData({role: "owner"}), true);
  assert.equal(hasBrandWriteAccessData({role: "admin"}), true);
  assert.equal(hasBrandWriteAccessData({role: "viewer"}), false);
  assert.equal(hasBrandWriteAccessData({role: 1}), false);
  assert.equal(hasBrandWriteAccessData(undefined), false);
});

test("owner 판정은 정확한 owner role만 허용한다", () => {
  assert.equal(isBrandOwnerData({role: "owner"}), true);
  assert.equal(isBrandOwnerData({role: "admin"}), false);
  assert.equal(isBrandOwnerData(undefined), false);
});

test("이메일 사용자 조회는 users 문서가 아니라 Firebase Auth를 사용한다", async () => {
  const calls: string[] = [];
  const auth = {
    async getUserByEmail(email: string) {
      calls.push(email);
      return {uid: "auth-user-id"};
    },
  };

  assert.equal(
    await findUserIDByEmail("user@example.com", auth),
    "auth-user-id",
  );
  assert.deepEqual(calls, ["user@example.com"]);
});

test("Firebase Auth user-not-found를 callable not-found로 변환한다", async () => {
  const auth = {
    async getUserByEmail(email: string): Promise<{uid: string}> {
      void email;
      const error = new Error("User not found") as Error & {code: string};
      error.code = "auth/user-not-found";
      throw error;
    },
  };

  await assert.rejects(
    findUserIDByEmail("missing@example.com", auth),
    (error: {code?: string}) => error.code === "not-found",
  );
});
