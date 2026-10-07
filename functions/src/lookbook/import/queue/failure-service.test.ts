import assert from "node:assert/strict";
import test from "node:test";
import type {Firestore} from "firebase-admin/firestore";
import {
  seasonImportFailureID, dismissSeasonImportFailure,
  admitSeasonImportFailureRetry, listSeasonImportFailures,
} from "./failure-service.js";

test("KR01 실패 identity는 같은 URL에 고정되고 다른 query를 합치지 않는다", () => {
  const source = "https://brand.example/collection?season=1";
  assert.equal(seasonImportFailureID(source), seasonImportFailureID(source));
  assert.notEqual(seasonImportFailureID(source),
    seasonImportFailureID("https://brand.example/collection?season=2"));
  assert.throws(() => seasonImportFailureID("file:///private"), /INVALID_CONTRACT/);
});

test("KR01 실패 API는 잘못된 version 실행ID 입력과 cursor를 저장소 조회 전에 거절한다", async () => {
  const db = {doc: () => {
    throw new Error("DATABASE_MUST_NOT_BE_READ");
  }} as unknown as Firestore;
  const data = {queueContractVersion: 1,
    requestID: "11111111-1111-4111-8111-111111111111",
    requestCreatedAt: 1, brandID: "brand", failureID: "a".repeat(64),
    expectedVersion: 1};
  await assert.rejects(() => dismissSeasonImportFailure(db, "uid", data),
    /INVALID_CONTRACT/);
  await assert.rejects(() => admitSeasonImportFailureRetry(db, "uid", {
    ...data, expectedExecutionID: "execution", expectedVersion: 0,
  }), /INVALID_CONTRACT/);
  await assert.rejects(() => listSeasonImportFailures(db, "uid", {
    brandID: "brand", cursor: {updatedAt: "1", failureID: "a".repeat(64)},
  }), /INVALID_CONTRACT/);
});
