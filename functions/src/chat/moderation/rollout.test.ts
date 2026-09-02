import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {assertModeratorDelegationCreationEnabled} from "./rollout.js";

test("관리자 위임 생성 gate는 기본 비활성 상태를 거부한다", () => {
  assert.throws(
    () => assertModeratorDelegationCreationEnabled(false),
    (error) => error instanceof HttpsError &&
      error.code === "failed-precondition" &&
      (error.details as {errorCode?: unknown})?.errorCode ===
        "FEATURE_NOT_AVAILABLE",
  );
});

test("관리자 위임 생성 gate가 활성화되면 요청을 허용한다", () => {
  assert.doesNotThrow(() => assertModeratorDelegationCreationEnabled(true));
});

test("서버 gate는 신규 임명과 관리자 후임 이전 두 callable에만 연결된다", () => {
  const source = readFileSync(
    join(__dirname, "functions.js"),
    "utf8",
  );
  assert.equal(
    source.match(/assertModeratorDelegationCreationEnabled\)\(\);/g)?.length,
    2,
  );
  assert.match(
    source,
    new RegExp(
      "assignRoomModerator[\\s\\S]*?" +
      "assertModeratorDelegationCreationEnabled\\)\\(\\);",
    ),
  );
  assert.match(
    source,
    new RegExp(
      "transferRoomOwnershipAndLeave[\\s\\S]*?" +
      "assertModeratorDelegationCreationEnabled\\)\\(\\);",
    ),
  );
});
