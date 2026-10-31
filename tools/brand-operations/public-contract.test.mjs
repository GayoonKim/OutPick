import assert from "node:assert/strict";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {readJSON, fixtureName, fixtureURL, fixtureIdentity, checkPublicContract, checkFixtureIDs} from "./contract-support.mjs";

const root = fileURLToPath(new URL("../../", import.meta.url));
const contract = readJSON(root, "public-v1.json");
const fixtures = readJSON(root, "public-fixtures-v1.json");

// 계약 예제 전용 대조다. 소비자의 mapper 구현이나 실제 전송 검사를 대신하지 않는다.
function checkWireObject(value, fields) {
  assert.ok(value && typeof value === "object" && !Array.isArray(value));
  for (const [key, spec] of Object.entries(fields)) {
    assert.equal(Object.hasOwn(value, key), true, key);
    const raw = value[key];
    if (raw === null) { assert.equal(spec.nullable, true, key); continue; }
    if (spec.type === "integer") assert.ok(Number.isSafeInteger(raw), key);
    else if (spec.type === "array") assert.ok(Array.isArray(raw), key);
    else assert.equal(typeof raw, spec.type, key);
    if (spec.minLength !== undefined) assert.ok(raw.length >= spec.minLength, key);
    if (spec.minimum !== undefined) assert.ok(raw >= spec.minimum, key);
    if (spec.maximum !== undefined) assert.ok(raw <= spec.maximum, key);
    if (spec.maximumLength !== undefined) assert.ok(raw.length <= spec.maximumLength, key);
    if (spec.enum) assert.ok(spec.enum.includes(raw), key);
    if (spec.format === "UTC-ISO8601-milliseconds") {
      assert.match(raw, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/);
      assert.equal(new Date(raw).toISOString(), raw);
    }
    if (spec.format === "canonicalHTTPURL") assert.equal(fixtureURL(raw), raw);
    if (spec.shape) checkWireObject(raw, contract.wireTypes[spec.shape]);
    if (spec.items) for (const item of raw) checkWireObject(item, contract.wireTypes[spec.items]);
  }
}
function checkWireResponse(endpoint, value) {
  const wire = contract.wireTypes;
  checkWireObject(value, endpoint === "submitBrandRequest" ? wire.submission : wire.historyPage);
  const rows = endpoint === "submitBrandRequest" ? [value] : value.requests;
  for (const row of rows) {
    if (row.status !== "added") assert.equal(row.resolvedBrandID, null);
    if (endpoint === "listMyBrandRequests") {
      assert.ok(wire.invariants[value.scope + "Statuses"].includes(row.status));
      if (row.status === "rejected") assert.ok(contract.holdReasons.includes(row.rejectionReason));
      else assert.equal(row.rejectionReason, null);
    }
  }
}

test("B1-P11 상세 응답 타입과 필수 null 시각 범위 및 손상 커서 예제를 대조한다", () => {
  const wire = contract.wireTypes;
  assert.deepEqual(Object.keys(wire.submission), contract.submissionResponse.requiredFields);
  assert.deepEqual(Object.keys(wire.requestItem), contract.history.itemFields);
  for (const shape of [wire.submission, wire.requestItem, wire.historyPage, wire.historyCursor]) {
    assert.ok(Object.values(shape).every((field) => field.required === true));
  }
  assert.ok(fixtures.wireResponseCases.length >= 35);
  for (const row of fixtures.wireResponseCases) {
    if (row.valid) assert.doesNotThrow(() => checkWireResponse(row.endpoint, row.response), row.id);
    else assert.throws(() => checkWireResponse(row.endpoint, row.response), undefined, row.id);
  }
  assert.equal(wire.invalidResponse.fallbackToSuccessOrEnd, false);
});
test("B1-P12 공개 입력 커서 경계와 오류 reason 및 결과 불명 예제를 고정한다", () => {
  const rules = contract.history.inputBoundaries;
  assert.deepEqual(rules.scope.values, ["active", "history"]);
  assert.equal(rules.scope.omittedOrNull, "active");
  assert.equal(rules.cursor.exactlyOneNonNull, "INVALID_CURSOR");
  assert.equal(rules.cursor.documentNeedNotStillExist, true);
  assert.deepEqual(fixtures.errorCases.map(({id, ...value}) => value), contract.errorContract.cases.map(({id, ...value}) => value));
  assert.equal(contract.errorContract.publicNotCommittedMarker, false);
  assert.equal(contract.errorContract.nullableDestinationLookupFailure, "propagateError;DoNotSynthesizeNull");
  assert.ok(fixtures.pageInputCases.some((row) => row.id === "input-invalid-impossible-date"));
});

test("B1-P01 공개 계약은 필수 입력과 네 사용자 상태를 고정한다", () => {
  checkPublicContract(contract);
  const changed = structuredClone(contract);
  changed.request.requiredFields = ["brandName"];
  assert.throws(() => checkPublicContract(changed));
  changed.request.requiredFields = ["brandName", "websiteURL"];
  changed.userStatuses[2].label = "처리 중";
  assert.throws(() => checkPublicContract(changed));
});

test("B1-P02 공통 이름 URL 정규화 예제는 동일한 기대 결과를 갖는다", () => {
  for (const c of fixtures.normalizationCases) {
    assert.equal(fixtureName(c.name), c.expectedName, c.id);
    assert.equal(fixtureURL(c.url), c.expectedURL, c.id);
  }
});

test("B1-P03 이름 URL identity는 영문명과 무관하고 다른 URL을 합치지 않는다", () => {
  for (const c of fixtures.identityCases) {
    assert.equal(JSON.stringify(fixtureIdentity(c.left)) === JSON.stringify(fixtureIdentity(c.right)), c.same, c.id);
  }
});

test("B1-P04 필수 URL 누락과 빈 이름 및 잘못된 URL 예제를 거부한다", () => {
  for (const c of fixtures.invalidRequests) assert.throws(() => fixtureIdentity(c.input), undefined, c.id);
});

test("B1-P05 포함 검색 예제는 동명 브랜드 ID를 각각 보존한다", () => {
  for (const c of fixtures.searchCases) {
    const query = fixtureName(c.query);
    const ids = c.brands.filter(b => [b.name, b.englishName].some(v => v && fixtureName(v).includes(query))).map(b => b.brandID);
    assert.deepEqual(ids, c.expectedIDs, c.id);
    assert.equal(new Set(ids).size, ids.length, c.id);
  }
});

test("B1-P06 전체 시즌 게시 예제는 빈 결과 부분 실패와 검토 대기를 제외한다", () => {
  assert.deepEqual(contract.publication.values, ["pending", "public"]);
  for (const c of fixtures.publicationCases) {
    const qualifies = c.contentCount > 0 && c.readyCount === c.contentCount && c.reviewComplete && c.readable && !c.deleted;
    assert.equal(qualifies, c.expected, c.id);
  }
});

test("B1-P07 공개 계약은 운영 비공개 필드와 관리자 진입점을 포함하지 않는다", () => {
  const raw = ["public-v1.json", "public-fixtures-v1.json"].map(p => readFileSync(resolve(root, "contracts/brand-operations", p), "utf8")).join("\n");
  for (const value of ["actorUID", "operationID", "platformAdminTenants", "listAdminBrandRequests", "adminStage", "contactPending", "replyPending"]) assert.equal(raw.includes(value), false, value);
});

test("B1-P08 공통 예제 ID는 비어 있지 않고 중복되지 않는다", () => {
  checkFixtureIDs(fixtures);
  const broken = structuredClone(fixtures);
  broken.normalizationCases[1].id = broken.normalizationCases[0].id;
  assert.throws(() => checkFixtureIDs(broken));
});
test("B1-P09 공개 접수 예제는 필수 결과와 현재 목적지 null 및 중복 의미를 고정한다", () => {
  const endpoint = contract.endpoints.find((row) => row.name === "submitBrandRequest");
  assert.deepEqual(endpoint.requiredFields, ["brandName", "websiteURL"]);
  assert.deepEqual(endpoint.responseFields, ["requestID", "groupID", "status", "isDuplicate", "remainingToday", "resolvedBrandID"]);
  for (const example of fixtures.publicAPICases.filter((row) => row.endpoint === "submitBrandRequest")) {
    assert.deepEqual(Object.keys(example.expected), endpoint.responseFields);
    assert.ok(contract.userStatuses.some((state) => state.value === example.expected.status));
    assert.equal(typeof example.expected.isDuplicate, "boolean"); assert.ok(example.expected.remainingToday >= 0 && example.expected.remainingToday <= 5);
    assert.ok(example.expected.resolvedBrandID === null || typeof example.expected.resolvedBrandID === "string");
  }
  assert.equal(contract.submissionResponse.duplicateIncrements, 0); assert.equal(contract.submissionResponse.duplicateRechecksFulfillment, false);
});
test("B1-P10 공개 내역은 소비 커서와 중간 빈 계속 및 완료 후 대상 부재를 구분한다", () => {
  const page = contract.history.pagination;
  assert.equal(page.default, 20); assert.equal(page.max, 50); assert.equal(page.candidateMultiplier, 3);
  assert.equal(page.advanceBy, "lastConsumedDocument"); assert.equal(page.emptyWithCursorIsEnd, false); assert.equal(page.nullCursorRequiresExhaustion, true);
  assert.deepEqual(page.cursorInputFields, ["cursorCreatedAt", "cursorRequestID"]);
  const example = fixtures.publicAPICases.find((row) => row.id === "completed-current-private");
  assert.deepEqual(Object.keys(example.expectedItem), contract.history.itemFields);
  assert.equal(example.expectedItem.status, "added"); assert.equal(example.expectedItem.resolvedBrandID, null);
});
