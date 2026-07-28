/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {
  assertAccountActive,
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

test("account 문서를 읽어 active 상태를 확인한다", async () => {
  const requested: string[] = [];
  const store = {
    collection(name: string) {
      requested.push(name);
      return {
        doc(uid: string) {
          requested.push(uid);
          return {
            async get() {
              return {
                exists: true,
                data: () => ({accountStatus: "active"}),
              };
            },
          };
        },
      };
    },
  };

  await assert.doesNotReject(assertAccountActive("user-a", store));
  assert.deepEqual(requested, ["users", "user-a"]);
});
