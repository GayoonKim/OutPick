/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {handleUpdateSeasonMoods} from "./seasonMoodFunctions.js";

test("총 관리자 검증 뒤 시즌 무드 교체를 실행한다", async () => {
  const calls: string[] = [];
  const result = await handleUpdateSeasonMoods(
    "admin-user",
    {
      brandID: "brand-1",
      seasonID: "season-1",
      moodIDs: ["minimal", "street"],
    },
    {
      assertTotalAdmin: async (uid) => {
        calls.push(`admin:${uid}`);
      },
      updateRecord: async (brandID, seasonID, moodIDs, uid) => {
        calls.push(`${brandID}:${seasonID}:${moodIDs.join(",")}:${uid}`);
      },
    }
  );

  assert.deepEqual(calls, [
    "admin:admin-user",
    "brand-1:season-1:minimal,street:admin-user",
  ]);
  assert.deepEqual(result.moodIDs, ["minimal", "street"]);
});

test("미인증 또는 잘못된 시즌 무드 요청을 거부한다", async () => {
  const dependencies = {
    assertTotalAdmin: () => Promise.resolve(),
    updateRecord: () => Promise.resolve(),
  };
  await assert.rejects(
    () => handleUpdateSeasonMoods(undefined, {}, dependencies),
    HttpsError
  );
  await assert.rejects(
    () => handleUpdateSeasonMoods(
      "admin-user",
      {brandID: "brand-1", seasonID: "season-1", moodIDs: ["a", "a"]},
      dependencies
    ),
    HttpsError
  );
});

test("총 관리자 검증 실패 시 시즌 문서를 수정하지 않는다", async () => {
  let didUpdate = false;
  await assert.rejects(
    () => handleUpdateSeasonMoods(
      "brand-owner",
      {brandID: "brand-1", seasonID: "season-1", moodIDs: []},
      {
        assertTotalAdmin: () => Promise.reject(
          new HttpsError("permission-denied", "총 관리자 권한이 없습니다.")
        ),
        updateRecord: () => {
          didUpdate = true;
          return Promise.resolve();
        },
      }
    ),
    HttpsError
  );
  assert.equal(didUpdate, false);
});
