import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {hasActivePlatformAdminData} from "./platformAuthorization.js";

test("활성 platform 관리자만 허용하고 legacy 또는 비활성 문서는 거절한다", () => {
  assert.equal(hasActivePlatformAdminData(undefined), false);
  assert.equal(hasActivePlatformAdminData({isActive: false}), false);
  assert.equal(hasActivePlatformAdminData({roles: ["admin"]}), false);
  assert.equal(hasActivePlatformAdminData({isActive: true}), true);
  assert.equal(
    hasActivePlatformAdminData({isActive: true, revokedAt: null}),
    true,
  );
  assert.equal(hasActivePlatformAdminData({
    isActive: true,
    revokedAt: Timestamp.fromMillis(1),
  }), false);
});
