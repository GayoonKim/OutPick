/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {
  assertAccountActive,
  assertAccountCapability,
  requireActiveAccountData,
} from "./accountStatus.js";

test("active 계정만 사용자 mutation을 수행할 수 있다", () => {
  assert.doesNotThrow(() => requireActiveAccountData({accountStatus: "active"}));
  assert.throws(
    () => requireActiveAccountData({accountStatus: "deletionPending"}),
    (error: {code?: string}) => error.code === "failed-precondition",
  );
  assert.throws(
    () => requireActiveAccountData(undefined),
    (error: {code?: string}) => error.code === "failed-precondition",
  );
});

test("통합 moderation account 문서 한 번으로 active와 capability를 확인한다", async () => {
  const requested: string[] = [];
  const store = {
    collection(name: string) {
      requested.push(name);
      return {
        doc(uid: string) {
          requested.push(uid);
          return {
            async get() {
              const data = {
                accountStatus: "active",
                moderationStatus: "active",
              };
              return {
                exists: true,
                data: () => data,
              };
            },
          };
        },
      };
    },
  };

  await assert.doesNotReject(assertAccountActive("user-a", store));
  assert.deepEqual(requested, ["moderationAccounts", "user-a"]);
});

test("restricted 계정은 신고할 수 있지만 UGC를 만들 수 없다", async () => {
  const store = {
    collection() {
      return {
        doc() {
          return {
            async get() {
              return {
                exists: true,
                data: () => ({
                  accountStatus: "active",
                  moderationStatus: "restricted",
                }),
              };
            },
          };
        },
      };
    },
  };
  await assert.doesNotReject(
    assertAccountCapability("user-a", "report", store),
  );
  await assert.rejects(
    assertAccountCapability("user-a", "createUGC", store),
    (error: {code?: string}) => error.code === "permission-denied",
  );
});
