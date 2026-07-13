import assert from "node:assert/strict";
import test from "node:test";
import {
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
