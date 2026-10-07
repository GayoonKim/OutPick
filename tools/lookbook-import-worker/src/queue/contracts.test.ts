import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import path from "node:path";
import test from "node:test";
import {
  QUEUE_CONTRACT_VERSION, QUEUE_POLICY, QUEUE_BATCH_STATES,
  QUEUE_ADMISSION_STATUSES, QUEUE_ERROR_CODES,
  parseQueueRequestEnvelope, newQueueAdmissionTimeError, parseQueueBatchState,
} from "./contracts.js";

const fixture = JSON.parse(readFileSync(path.resolve(
  process.cwd(), "../../contracts/lookbook-import-queue-v1.json",
), "utf8")) as {
  contractVersion: number;
  policy: Record<string, number>;
  batchStates: string[];
  admissionStatuses: string[];
  errorCodes: string[];
  envelopeCases: Array<{name: string; input: unknown; error: string | null}>;
  newAdmissionTimeCases: Array<{
    name: string; requestCreatedAt: number; now: number; error: string | null;
  }>;
  receiptLookupExample: {
    request: unknown; now: number;
    receiptExists: boolean; expectedAction: string;
  };
};

test("PQ00 계약 버전 정책 상태 오류 분류가 공용 fixture와 일치한다", () => {
  assert.equal(QUEUE_CONTRACT_VERSION, fixture.contractVersion);
  assert.deepEqual(QUEUE_POLICY, fixture.policy);
  assert.deepEqual(QUEUE_BATCH_STATES, fixture.batchStates);
  assert.deepEqual(QUEUE_ADMISSION_STATUSES, fixture.admissionStatuses);
  assert.deepEqual(QUEUE_ERROR_CODES, fixture.errorCodes);
});

test("PQ00 요청 공통 필드는 정상 입력을 보존하고 잘못된 계약을 거절한다", () => {
  for (const row of fixture.envelopeCases) {
    if (row.error) {
      assert.throws(() => parseQueueRequestEnvelope(row.input),
        {message: row.error}, row.name);
    } else {
      assert.deepEqual(parseQueueRequestEnvelope(row.input),
        row.input, row.name);
    }
  }
});

test("PQ00 신규 접수 시간은 정확한 경계를 허용하고 일 밀리초 초과를 거절한다", () => {
  for (const row of fixture.newAdmissionTimeCases) {
    assert.equal(newQueueAdmissionTimeError(row.requestCreatedAt, row.now),
      row.error, row.name);
  }
  for (const value of [NaN, Infinity, -1, 0.5, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => newQueueAdmissionTimeError(0, value),
      {message: "INVALID_CONTRACT"});
    assert.throws(() => newQueueAdmissionTimeError(value, 0),
      {message: "INVALID_CONTRACT"});
  }
});

test("PQ00 공통 파싱은 오래된 영수증의 조회를 신규 접수 만료로 막지 않는다", () => {
  const example = fixture.receiptLookupExample;
  const request = parseQueueRequestEnvelope(example.request);
  const timeError = newQueueAdmissionTimeError(
    request.requestCreatedAt, example.now);
  assert.equal(timeError,
    "REQUEST_EXPIRED");
  assert.equal(example.receiptExists, true);
  assert.equal(example.expectedAction,
    "lookupExistingReceiptBeforeNewAdmissionTimeCheck");
  // 실제 영수증 조회 순서는 Q1 admission 통합 검사에서 검증한다.
});

test("PQ00 복구와 차례 종료를 보존하고 알 수 없는 상태를 거절한다", () => {
  for (const state of fixture.batchStates) {
    assert.equal(parseQueueBatchState(state), state);
  }
  for (const state of ["completed", "success", "failed", "", null, 1]) {
    assert.throws(() => parseQueueBatchState(state),
      {message: "INVALID_CONTRACT"});
  }
});
