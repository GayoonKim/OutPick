import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {createHash} from "node:crypto";

export function readJSON(root, name) {
  return JSON.parse(readFileSync(resolve(root, "contracts/brand-operations", name), "utf8"));
}

// 계약 예제의 일관성 검사이며 서비스 API의 실제 구현을 대신하지 않는다.
export function fixtureName(value) {
  assert.equal(typeof value, "string");
  const normalized = value.normalize("NFKC").trim().replace(/\s+/gu, " ").toLowerCase();
  assert.ok(normalized.length > 0 && normalized.length <= 80);
  return normalized;
}

export function fixtureURL(value) {
  assert.equal(typeof value, "string");
  const input = value.trim();
  assert.ok(input.length > 0 && input.length <= 2048);
  const url = new URL(input.includes("://") ? input : `https://${input}`);
  assert.ok(["http:", "https:"].includes(url.protocol));
  assert.ok(url.hostname && !url.username && !url.password);
  return url.toString();
}

export function fixtureIdentity(value) {
  return [fixtureName(value.brandName), fixtureURL(value.websiteURL)];
}

export function fileDigest(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

export function checkPublicContract(c) {
  assert.equal(c.contractVersion, 1);
  assert.equal(c.scope, "public-client");
  assert.deepEqual(c.request.requiredFields, ["brandName", "websiteURL"]);
  assert.deepEqual(c.request.identityFields, ["normalizedBrandName", "canonicalWebsiteURL"]);
  assert.equal(c.request.englishNameParticipatesInIdentity, false);
  assert.deepEqual(c.request.uniqueRequesterKey, ["uid", "groupID"]);
  assert.deepEqual(c.userStatuses.map(s => s.value), ["submitted", "reviewing", "added", "rejected"]);
  assert.deepEqual(c.userStatuses.map(s => s.label), ["요청 접수", "처리 중", "등록 완료", "보류"]);
  assert.equal(c.search.mode, "contains");
  assert.equal(c.search.distinctBy, "brandID");
  assert.equal(c.history.authoritativeStatus, "requestGroup");
  assert.equal(c.history.exposeOtherRequesters, false);
  assert.equal(c.history.exposeAdminNote, false);
  assert.equal(c.history.exposeAudit, false);
  assert.deepEqual(c.publication.values, ["pending", "public"]);
  assert.equal(c.publication.unknownIsVisible, false);
  for (const key of ["emptySeasonQualifies", "partialSeasonQualifies", "extractionOnlyQualifies", "reviewPendingQualifies"]) assert.equal(c.publication[key], false);
  assert.equal(c.images.brandCardRepresentative, false);
  assert.equal(c.images.seasonCover, true);
  assert.equal(c.images.lookbook, true);
  assert.equal(c.images.deleteExistingFields, false);
  assert.equal(c.images.deleteExistingObjects, false);
}

export function checkFixtureIDs(f) {
  assert.equal(f.contractVersion, 1);
  const ids = Object.values(f).filter(Array.isArray).flat().map(v => v.id);
  assert.ok(ids.length > 0);
  assert.ok(ids.every(v => typeof v === "string" && v.length > 0));
  assert.equal(new Set(ids).size, ids.length);
}
