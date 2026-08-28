import assert from "node:assert/strict";
import test from "node:test";
import {
  APPLY_CONFIRMATION,
  buildRevisionAssignments,
  validateApplyGate,
} from "./chat-deletion-cutover-plan.mjs";

const expected = {roomHash: "room-hash", count: 2, head: 0};
const baseOptions = {
  projectID: "outpick-test",
  expectedRoomHash: "room-hash",
  expectedCount: 2,
  expectedHead: 0,
  apply: false,
  confirmation: null,
};

test("revision은 seq 순서로 현재 head 다음부터 연속 부여한다", () => {
  assert.deepEqual(buildRevisionAssignments([
    {id: "later", seq: 8},
    {id: "earlier", seq: 3},
  ], 4), [
    {id: "earlier", seq: 3, deletionRevision: 5},
    {id: "later", seq: 8, deletionRevision: 6},
  ]);
});

test("중복 seq는 revision 계획을 거부한다", () => {
  assert.throws(
    () => buildRevisionAssignments([{id: "a", seq: 1}, {id: "b", seq: 1}], 0),
    /중복/,
  );
});

test("Development dry-run은 정확한 예상값이면 통과한다", () => {
  assert.doesNotThrow(() => validateApplyGate(baseOptions, expected));
});

test("apply는 exact confirmation 없이는 거부한다", () => {
  assert.throws(
    () => validateApplyGate({...baseOptions, apply: true}, expected),
    /--confirm/,
  );
  assert.doesNotThrow(() => validateApplyGate({
    ...baseOptions,
    apply: true,
    confirmation: APPLY_CONFIRMATION,
  }, expected));
});

test("Production과 예상 상태 drift는 write gate에서 거부한다", () => {
  assert.throws(
    () => validateApplyGate({...baseOptions, projectID: "outpick-664ae"}, expected),
    /Development/,
  );
  assert.throws(
    () => validateApplyGate(baseOptions, {...expected, count: 3}),
    /--expected-count/,
  );
  assert.throws(
    () => validateApplyGate(baseOptions, {...expected, head: 1}),
    /--expected-head/,
  );
});
