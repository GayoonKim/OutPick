import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

const manifest = JSON.parse(readFileSync(new URL("../firestore.indexes.json", import.meta.url), "utf8"));

test("역할 이벤트 subject는 기존 단일 collection 인덱스와 익명화 group 조회를 함께 보존한다", () => {
  const field = manifest.fieldOverrides.find((item) =>
    item.collectionGroup === "Messages" && item.fieldPath === "roleEvent.subjectUID");
  assert.deepEqual(field.indexes, [
    {order: "ASCENDING", queryScope: "COLLECTION"},
    {order: "DESCENDING", queryScope: "COLLECTION"},
    {arrayConfig: "CONTAINS", queryScope: "COLLECTION"},
    {order: "ASCENDING", queryScope: "COLLECTION_GROUP"},
  ]);
});

for (const collectionGroup of ["roomRoleMutationReceipts", "chatRoleEventDeliveryJobs", "roomSuccessionAttempts"]) {
  test(`${collectionGroup}의 expiresAt은 TTL 삭제와 불필요한 인덱스 제외를 선언한다`, () => {
    const overrides = manifest.fieldOverrides.filter((field) =>
      field.collectionGroup === collectionGroup && field.fieldPath === "expiresAt");
    assert.equal(overrides.length, 1);
    assert.equal(overrides[0].ttl, true);
    assert.deepEqual(overrides[0].indexes, []);
  });
}
