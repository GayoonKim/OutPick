import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {
  assertQueueBrandAvailable,
  queueAuthorization,
} from "./authorization.js";

/* eslint-disable valid-jsdoc */
/** Firestore transaction 문서 읽기를 재현한다. */
function fixture(documents: Record<string, Record<string, unknown>>) {
  const reads: string[] = [];
  const db = {
    doc(path: string) {
      return {path};
    },
  };
  const transaction = {
    async get(ref: {path: string}) {
      reads.push(ref.path);
      const data = documents[ref.path];
      return {
        exists: data !== undefined,
        data: () => data,
      };
    },
  };
  return {db, transaction, reads};
}

test("queue callable은 활성 플랫폼 관리자와 유효 브랜드만 허용한다", async () => {
  const {db, transaction, reads} = fixture({
    "brands/brand-1": {deletionStatus: "active"},
    "platformAdmins/admin-1": {isActive: true},
    "brandAdmins/admin-1": {isActive: true},
    "brands/brand-1/admins/admin-1": {role: "owner"},
  });

  await queueAuthorization(db as never)(
    transaction as never,
    "admin-1",
    "brand-1",
  );
  assert.deepEqual(
    reads,
    ["brands/brand-1", "platformAdmins/admin-1"],
  );
});

test("legacy total admin 또는 brand owner만으로 queue API를 호출할 수 없다", async () => {
  const {db, transaction} = fixture({
    "brands/brand-1": {deletionStatus: "active"},
    "brandAdmins/admin-1": {isActive: true},
    "brands/brand-1/admins/admin-1": {role: "owner"},
  });

  await assert.rejects(
    queueAuthorization(db as never)(
      transaction as never,
      "admin-1",
      "brand-1",
    ),
    (error: Error) => error.message === "PERMISSION_DENIED",
  );
});

test("회수된 플랫폼 관리자와 삭제 브랜드는 거절한다", async () => {
  const revoked = fixture({
    "brands/brand-1": {deletionStatus: "active"},
    "platformAdmins/admin-1": {
      isActive: true,
      revokedAt: Timestamp.fromMillis(1),
    },
  });
  await assert.rejects(
    queueAuthorization(revoked.db as never)(
      revoked.transaction as never,
      "admin-1",
      "brand-1",
    ),
    (error: Error) => error.message === "PERMISSION_DENIED",
  );

  const deleted = fixture({
    "brands/brand-1": {deletionStatus: "deleted"},
    "platformAdmins/admin-1": {isActive: true},
  });
  await assert.rejects(
    queueAuthorization(deleted.db as never)(
      deleted.transaction as never,
      "admin-1",
      "brand-1",
    ),
    (error: Error) => error.message === "TARGET_DELETED",
  );
});

test("권한이 회수돼도 이미 접수된 배치 준비는 브랜드 상태만 확인한다", async () => {
  const {db, transaction, reads} = fixture({
    "brands/brand-1": {deletionStatus: "active"},
  });

  await assertQueueBrandAvailable(
    db as never,
    transaction as never,
    "brand-1",
  );
  assert.deepEqual(reads, ["brands/brand-1"]);
});
