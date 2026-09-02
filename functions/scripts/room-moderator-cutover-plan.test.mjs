import assert from "node:assert/strict";
import test from "node:test";
import {
  DEVELOPMENT_CONFIRMATION,
  cutoverPlanHash,
  joinedProjectionInventory,
  roomCutoverPlan,
  validateCutoverApply,
} from "./room-moderator-cutover-plan.mjs";

test("joined projection 전체 inventory는 room별로 묶고 mismatch와 orphan을 차단한다", () => {
  const inventory = joinedProjectionInventory(["room-a", "room-b"], [
    {id: "user-b", documentRoomID: "room-a", roomID: "room-a"},
    {id: "user-a", documentRoomID: "room-a", roomID: "wrong-room"},
    {id: "orphan-user", documentRoomID: "missing-room", roomID: "missing-room"},
  ]);
  assert.deepEqual(
    inventory.byRoomID.get("room-a").map((projection) => projection.id),
    ["user-a", "user-b"],
  );
  assert.deepEqual(inventory.byRoomID.get("room-b"), []);
  assert.deepEqual(inventory.blockers, [
    {roomID: "missing-room", blocker: "JOINED_PROJECTION_ORPHAN:orphan-user"},
    {roomID: "room-a", blocker: "JOINED_ROOM_ID_MISMATCH:user-a"},
  ]);
});

function fixture(overrides = {}) {
  return {
    room: {id: "room", creatorUID: "owner", seq: 3},
    messages: [
      {id: "m1", seq: 1, type: "text"},
      {id: "event", seq: 2, type: "roomRoleEvent", serverGenerated: true, roleEvent: {kind: "moderatorAssigned"}},
      {id: "m2", seq: 3, type: "text", unreadMessageSeq: 2},
    ],
    members: [{id: "owner"}, {id: "moderator", role: "moderator", moderatorSince: "timestamp"}],
    joined: [
      {id: "owner", lastReadSeq: 2},
      {id: "moderator", role: "moderator", moderatorSince: "timestamp", lastReadSeq: 3},
    ],
    moderationState: null,
    ...overrides,
  };
}

test("legacy 누락 필드는 owner와 dual counter·role·moderatorCount로 계획한다", () => {
  const plan = roomCutoverPlan(fixture());
  assert.deepEqual(plan.blockers, []);
  assert.equal(plan.expectedUnreadMessageSeq, 2);
  assert.equal(plan.moderatorCount, 1);
  assert.deepEqual(plan.writes, [
    {path: "roomModerationStates/room", fields: {schemaVersion: 1, moderatorCount: 1}},
    {path: "Rooms/room", fields: {unreadMessageSeq: 2, ownerUID: "owner"}},
    {path: "Rooms/room/members/owner", fields: {role: "owner"}},
    {path: "users/moderator/joinedRooms/room", fields: {lastReadUnreadMessageSeq: 2}},
    {path: "users/owner/joinedRooms/room", fields: {role: "owner", lastReadUnreadMessageSeq: 1}},
  ]);
});

test("owner 충돌·중복 owner·projection 누락은 자동 보정하지 않고 차단한다", () => {
  const plan = roomCutoverPlan(fixture({
    room: {id: "room", ownerUID: "owner", creatorUID: "other", seq: 0, unreadMessageSeq: 0},
    messages: [],
    members: [{id: "owner", role: "owner"}, {id: "other", role: "owner"}],
    joined: [{id: "owner", role: "owner", lastReadSeq: 0, lastReadUnreadMessageSeq: 0}],
    moderationState: {moderatorCount: 0},
  }));
  assert.ok(plan.blockers.includes("ROOM_OWNER_CONFLICT"));
  assert.ok(plan.blockers.includes("MEMBER_OWNER_DUPLICATE_OR_CONFLICT"));
  assert.ok(plan.blockers.includes("JOINED_PROJECTION_MISSING:other"));
});

test("stored counter가 계산값보다 앞서면 역전으로 차단한다", () => {
  const plan = roomCutoverPlan(fixture({
    room: {id: "room", ownerUID: "owner", creatorUID: "owner", seq: 3, unreadMessageSeq: 3},
  }));
  assert.ok(plan.blockers.includes("ROOM_UNREAD_SEQ_AHEAD"));
});

test("plan hash는 입력 순서와 무관하고 필드가 바뀌면 달라진다", () => {
  const first = roomCutoverPlan(fixture());
  const second = {...first, writes: [...first.writes].reverse()};
  assert.equal(cutoverPlanHash([first]), cutoverPlanHash([second]));
  second.writes[0] = {...second.writes[0], fields: {role: "member"}};
  assert.notEqual(cutoverPlanHash([first]), cutoverPlanHash([second]));
});

test("계획 필드를 반영한 재실행은 write가 없는 멱등 상태다", () => {
  const input = fixture();
  const first = roomCutoverPlan(input);
  const rerun = roomCutoverPlan({
    ...input,
    room: {...input.room, ownerUID: "owner", unreadMessageSeq: 2},
    members: input.members.map((member) => member.id === "owner" ? {...member, role: "owner"} : member),
    joined: input.joined.map((joined) => ({
      ...joined,
      role: joined.id === "owner" ? "owner" : joined.role,
      lastReadUnreadMessageSeq: joined.id === "owner" ? 1 : 2,
    })),
    moderationState: {schemaVersion: 1, moderatorCount: 1},
  });
  assert.ok(first.writes.length > 0);
  assert.deepEqual(rerun.blockers, []);
  assert.deepEqual(rerun.writes, []);
});

test("apply는 blocker·exact count·hash·confirmation을 모두 검사한다", () => {
  const summary = {roomCount: 1, writeCount: 2, blockerCount: 0, planHash: "hash"};
  const base = {
    projectID: "outpick-test",
    expectedRoomCount: 1,
    expectedWriteCount: 2,
    expectedPlanHash: "hash",
    apply: false,
    confirmation: null,
  };
  assert.doesNotThrow(() => validateCutoverApply(base, summary));
  assert.throws(() => validateCutoverApply({...base, expectedWriteCount: 3}, summary), /expected-write-count/);
  assert.throws(() => validateCutoverApply(base, {...summary, blockerCount: 1}), /blocker/);
  assert.throws(() => validateCutoverApply({...base, apply: true}, summary), /--confirm/);
  assert.doesNotThrow(() => validateCutoverApply({
    ...base, apply: true, confirmation: DEVELOPMENT_CONFIRMATION,
  }, summary));
});
