import assert from "node:assert/strict";
import {after, beforeEach, test} from "node:test";
import {db} from "../functions/lib/core/firebase.js";
import {dueRoomOwnershipSuccessionJobIDs, processRoomOwnershipSuccessionJob, processRoomSuccessionAttempt, replayFailedRoomOwnershipSuccessionJob, settleExpiredRoomSuccession} from "../functions/lib/chat/moderation/roomSuccessionJobs.js";

assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? "", /^(127\.0\.0\.1|localhost):\d+$/);
assert.equal(process.env.GCLOUD_PROJECT, "outpick-rules-test");
const now = new Date("2026-09-02T10:00:00Z");
const late = new Date(now.getTime() + 50_000);
const uid = "deadline-owner";
const moderator = "deadline-moderator";
const job = db.collection("roomOwnershipSuccessionJobs").doc("deadline-job");
const room = (id) => db.collection("Rooms").doc(`deadline-${id}`);
const attempt = (id) => job.collection("roomSuccessionAttempts").doc(room(id).id);

async function clear() {
  for (const collection of ["Rooms", "users", "moderationAccounts", "userPublicProfiles", "roomOwnershipSuccessionJobs", "roomModerationStates", "chatRoleEventDeliveryJobs", "moderationRoomCleanupJobs"]) {
    await db.recursiveDelete(db.collection(collection));
  }
}

async function seedRoom(id, owner = uid) {
  const ref = room(id);
  await ref.set({ownerUID: owner, creatorUID: owner, isClosed: false, lifecycleStatus: "active", seq: 0, unreadMessageSeq: 0, memberCount: 2});
  for (const [userID, role] of [[owner, "owner"], [moderator, "moderator"]]) {
    const data = {userID, role, ...(role === "moderator" ? {moderatorSince: now} : {})};
    await ref.collection("members").doc(userID).set(data);
    await db.collection("users").doc(userID).collection("joinedRooms").doc(ref.id).set({...data, roomID: ref.id});
  }
  await db.collection("roomModerationStates").doc(ref.id).set({moderatorCount: 1});
}

beforeEach(async () => {
  await clear();
  await db.collection("moderationAccounts").doc(uid).set({accountStatus: "active", moderationStatus: "suspended", stateVersion: 1});
  await db.collection("moderationAccounts").doc(moderator).set({accountStatus: "active", moderationStatus: "active", moderationPrincipalID: "deadline-principal"});
  await db.collection("userPublicProfiles").doc(moderator).set({nickname: "후임"});
  await job.set({schemaVersion: 3, targetUID: uid, cause: "permanentSuspension", expectedStateVersion: 1,
    status: "pending", phase: "ownedCanonical", attempt: 0, nextAttemptAt: now, pendingRoomCount: 0, failedRoomCount: 0});
});
after(async () => {await clear(); await db.terminate();});

async function discover() {await processRoomOwnershipSuccessionJob(job.id, db, now);}
async function finishParent(at = now) {
  for (let index = 0; index < 5; index += 1) {
    await processRoomOwnershipSuccessionJob(job.id, db, at);
    if (["completed", "failed"].includes((await job.get()).get("status"))) return;
  }
}

test("한 방이 50초에 만료돼도 다른 방의 성공과 일반 참여방 정리를 보존한다", async () => {
  await seedRoom("success");
  await seedRoom("failure");
  await seedRoom("ordinary", "other-owner");
  await room("ordinary").collection("members").doc(uid).set({userID: uid, role: "member"});
  await db.collection("users").doc(uid).collection("joinedRooms").doc(room("ordinary").id).set({role: "member"});
  await discover();
  await processRoomSuccessionAttempt(job.id, room("success").id, 1, db, () => now);
  await processRoomSuccessionAttempt(job.id, room("failure").id, 1, db, () => late);
  await finishParent(late);
  assert.equal((await room("success").get()).get("ownerUID"), moderator);
  assert.equal((await attempt("success").get()).get("status"), "completed");
  assert.equal((await room("failure").get()).get("ownerUID"), uid);
  assert.equal((await room("failure").get()).get("isClosed"), false);
  assert.equal((await room("failure").collection("members").doc(uid).get()).exists, true);
  assert.equal((await room("ordinary").collection("members").doc(uid).get()).exists, false);
  assert.equal((await job.get()).get("result"), "partialFailure");
  assert.equal((await job.get()).get("failedRoomCount"), 1);
  assert.equal((await job.get()).get("pendingRoomCount"), 0);
});

test("claim 뒤 읽기 지연으로 기한을 넘으면 권한 변경과 이벤트 생성 모두 차단한다", async () => {
  await seedRoom("late"); await discover();
  let ticks = 0;
  await processRoomSuccessionAttempt(job.id, room("late").id, 1, db, () => ++ticks >= 3 ? late : now);
  assert.equal((await room("late").get()).get("ownerUID"), uid);
  assert.equal((await room("late").collection("Messages").get()).size, 0);
  assert.equal((await attempt("late").get()).get("lastErrorCode"), "room_succession_deadline_exceeded");
});

test("성공 commit의 응답이 유실돼도 성공 상태와 이벤트를 보존한다", async () => {
  await seedRoom("response"); await discover();
  let transactions = 0;
  const unreliable = new Proxy(db, {get(target, key) {
    if (key === "runTransaction") return async (...args) => {
      const result = await target.runTransaction(...args);
      if (++transactions === 2) throw Object.assign(new Error("lost_commit_response"), {code: 14});
      return result;
    };
    const value = Reflect.get(target, key);
    return typeof value === "function" ? value.bind(target) : value;
  }});
  await processRoomSuccessionAttempt(job.id, room("response").id, 1, unreliable, () => now);
  await settleExpiredRoomSuccession(job.id, room("response").id, db, () => late);
  await processRoomSuccessionAttempt(job.id, room("response").id, 1, db, () => late);
  assert.equal((await attempt("response").get()).get("status"), "completed");
  assert.equal((await room("response").collection("Messages").get()).size, 1);
  assert.equal((await job.get()).get("failedRoomCount"), 0);
});

test("진행 중인 방이 장애 후 만료되면 재승계하지 않고 실패 기록만 남긴다", async () => {
  await seedRoom("crash"); await discover();
  await attempt("crash").update({status: "processing", leaseOwner: "lost-worker", attempt: 1});
  await processRoomSuccessionAttempt(job.id, room("crash").id, 1, db, () => now);
  assert.equal((await room("crash").get()).get("ownerUID"), uid);
  await settleExpiredRoomSuccession(job.id, room("crash").id, db, () => late);
  await settleExpiredRoomSuccession(job.id, room("crash").id, db, () => late);
  assert.equal((await job.get()).get("failedRoomCount"), 1);
  assert.equal((await attempt("crash").get()).get("status"), "failed");
});

test("수동 재처리는 실패 방 하나에만 새 50초 세대를 열고 늦은 이전 task를 거부한다", async () => {
  await seedRoom("replay"); await seedRoom("keep"); await discover();
  await processRoomSuccessionAttempt(job.id, room("keep").id, 1, db, () => now);
  await settleExpiredRoomSuccession(job.id, room("replay").id, db, () => late);
  await finishParent(late);
  assert.equal(await replayFailedRoomOwnershipSuccessionJob(job.id, room("replay").id, "wrong-user", db, () => late), false);
  assert.equal(await replayFailedRoomOwnershipSuccessionJob(job.id, room("keep").id, uid, db, () => late), false);
  assert.equal(await replayFailedRoomOwnershipSuccessionJob(job.id, room("replay").id, uid, db, () => late), true);
  assert.equal(await replayFailedRoomOwnershipSuccessionJob(job.id, room("replay").id, uid, db, () => late), false);
  await processRoomSuccessionAttempt(job.id, room("replay").id, 1, db, () => late);
  await settleExpiredRoomSuccession(job.id, room("replay").id, db, () => late);
  assert.equal((await room("replay").get()).get("ownerUID"), uid);
  await processRoomSuccessionAttempt(job.id, room("replay").id, 2, db, () => late);
  await finishParent(late);
  assert.equal((await job.get()).get("result"), "resolved");
  assert.equal((await room("keep").collection("Messages").get()).size, 1);
  assert.equal((await attempt("replay").get()).get("generation"), 2);
});

test("legacy creatorUID가 남아 있어도 완료한 승계를 다시 발견하지 않는다", async () => {
  await seedRoom("legacy"); await discover();
  await processRoomSuccessionAttempt(job.id, room("legacy").id, 1, db, () => now);
  await finishParent();
  assert.equal((await job.get()).get("result"), "resolved");
  assert.equal((await job.collection("roomSuccessionAttempts").get()).size, 1);
  assert.equal((await room("legacy").get()).get("creatorUID"), uid);
});

test("승계 도중 계정 제재가 취소되면 후임을 만들지 않는다", async () => {
  await seedRoom("stale"); await discover();
  await db.collection("moderationAccounts").doc(uid).update({stateVersion: 2, moderationStatus: "active"});
  await processRoomSuccessionAttempt(job.id, room("stale").id, 1, db, () => now);
  assert.equal((await room("stale").get()).get("ownerUID"), uid);
  assert.equal((await attempt("stale").get()).get("result"), "staleFence");
});

test("일반 참여방 27개는 50초를 지나 여러 페이지로 정리해도 승계 실패로 처리하지 않는다", async () => {
  for (let i = 0; i < 27; i += 1) {
    const ref = room(`ordinary-${String(i).padStart(2, "0")}`);
    await ref.set({ownerUID: "other", creatorUID: "other", isClosed: false, memberCount: 2});
    await ref.collection("members").doc(uid).set({userID: uid, role: "member"});
    await db.collection("users").doc(uid).collection("joinedRooms").doc(ref.id).set({role: "member"});
  }
  await finishParent(new Date(now.getTime() + 120_000));
  assert.equal((await job.get()).get("result"), "resolved");
  assert.equal((await db.collectionGroup("members").where("userID", "==", uid).get()).size, 0);
  assert.equal((await job.collection("roomSuccessionAttempts").get()).size, 0);
});

test("일시적인 승계 오류도 최대 네 번만 실행하며 다른 방의 예산을 소비하지 않는다", async () => {
  await seedRoom("retry"); await seedRoom("independent"); await discover();
  for (const [index, offset] of [0, 5_000, 20_000, 40_000].entries()) {
    let calls = 0;
    const failing = new Proxy(db, {get(target, key) {
      if (key === "runTransaction") return async (...args) => {
        if (++calls === 2) throw Object.assign(new Error("unavailable"), {code: 14});
        return target.runTransaction(...args);
      };
      const value = Reflect.get(target, key);
      return typeof value === "function" ? value.bind(target) : value;
    }});
    await processRoomSuccessionAttempt(job.id, room("retry").id, 1, failing, () => new Date(now.getTime() + offset));
    assert.equal((await attempt("retry").get()).get("attempt"), index + 1);
  }
  assert.equal((await attempt("retry").get()).get("status"), "failed");
  await processRoomSuccessionAttempt(job.id, room("independent").id, 1, db, () => new Date(now.getTime() + 49_000));
  assert.equal((await attempt("independent").get()).get("attempt"), 1);
  assert.equal((await attempt("independent").get()).get("status"), "completed");
  assert.equal((await room("retry").get()).get("ownerUID"), uid);
});

async function failParent() {
  await job.update({phase: "members"});
  const failing = new Proxy(db, {get(target, key) {
    if (key === "collectionGroup") return () => {throw new Error("injected_parent_query_failure");};
    const value = Reflect.get(target, key);
    return typeof value === "function" ? value.bind(target) : value;
  }});
  await processRoomOwnershipSuccessionJob(job.id, failing, now);
  assert.equal((await job.get()).get("status"), "failed");
  assert.equal((await job.get()).get("result"), "orchestrationFailure");
}

test("부모 일반 정리가 실패해도 준비된 방은 독립 승계하고 부모 오류는 보존한다", async () => {
  await seedRoom("before"); await seedRoom("after"); await discover();
  await processRoomSuccessionAttempt(job.id, room("before").id, 1, db, () => now);
  const deadline = (await attempt("after").get()).get("deadlineAt").toMillis();
  await failParent();
  await processRoomSuccessionAttempt(job.id, room("after").id, 1, db, () => now);
  assert.equal((await room("after").get()).get("ownerUID"), moderator);
  assert.equal((await attempt("after").get()).get("result"), "resolved");
  assert.equal((await attempt("after").get()).get("deadlineAt").toMillis(), deadline);
  assert.equal((await room("before").collection("Messages").get()).size, 1);
  const parent = await job.get();
  assert.equal(parent.get("status"), "failed");
  assert.equal(parent.get("lastErrorCode"), "injected_parent_query_failure");
  assert.equal(parent.get("phase"), "members");
  assert.equal(parent.get("pendingRoomCount"), 0);
  assert.equal(parent.get("nextAttemptAt"), null);
  assert.equal(parent.get("expiresAt"), null);
});

test("claim 이후 부모가 실패해도 최종 mutation guard는 유효한 방 승계를 허용한다", async () => {
  await seedRoom("mid-claim"); await discover();
  let calls = 0;
  const racing = new Proxy(db, {get(target, key) {
    if (key === "runTransaction") return async (...args) => {
      const result = await target.runTransaction(...args);
      if (++calls === 1) await failParent();
      return result;
    };
    const value = Reflect.get(target, key);
    return typeof value === "function" ? value.bind(target) : value;
  }});
  await processRoomSuccessionAttempt(job.id, room("mid-claim").id, 1, racing, () => now);
  assert.equal((await attempt("mid-claim").get()).get("result"), "resolved");
  assert.equal((await job.get()).get("result"), "orchestrationFailure");
});

test("부모 실패 후에도 실제 계정 fence 취소는 승계를 막는다", async () => {
  await seedRoom("cancelled"); await discover(); await failParent();
  await db.collection("moderationAccounts").doc(uid).update({stateVersion: 2, moderationStatus: "active"});
  await processRoomSuccessionAttempt(job.id, room("cancelled").id, 1, db, () => now);
  assert.equal((await attempt("cancelled").get()).get("result"), "staleFence");
  assert.equal((await room("cancelled").get()).get("ownerUID"), uid);
  assert.equal((await job.get()).get("result"), "orchestrationFailure");
});

test("실패 부모 watchdog은 누락 task의 만료만 확정하고 실패 방 replay는 부모 오류를 지우지 않는다", async () => {
  await seedRoom("missed"); await discover(); await failParent();
  assert.ok((await dueRoomOwnershipSuccessionJobIDs(db, late)).includes(job.id));
  await processRoomOwnershipSuccessionJob(job.id, db, late);
  assert.equal((await attempt("missed").get()).get("status"), "failed");
  assert.equal((await room("missed").get()).get("ownerUID"), uid);
  assert.equal((await job.get()).get("nextAttemptAt"), null);
  assert.equal(await replayFailedRoomOwnershipSuccessionJob(job.id, room("missed").id, uid, db, () => late), true);
  assert.ok((await dueRoomOwnershipSuccessionJobIDs(db, late)).includes(job.id));
  await processRoomOwnershipSuccessionJob(job.id, db, late);
  await processRoomSuccessionAttempt(job.id, room("missed").id, 2, db, () => late);
  assert.equal((await attempt("missed").get()).get("result"), "resolved");
  const parent = await job.get();
  assert.equal(parent.get("status"), "failed");
  assert.equal(parent.get("result"), "orchestrationFailure");
  assert.equal(parent.get("lastErrorCode"), "injected_parent_query_failure");
  assert.equal(parent.get("pendingRoomCount"), 0);
  assert.equal(parent.get("failedRoomCount"), 0);
  assert.equal(parent.get("nextAttemptAt"), null);
});

test("부모 claim 재시도 소진도 방 기한과 독립이며 watchdog 예약을 유지한다", async () => {
  await seedRoom("exhausted-parent"); await discover();
  await job.update({attempt: 4});
  await processRoomOwnershipSuccessionJob(job.id, db, now);
  assert.equal((await job.get()).get("result"), "orchestrationFailure");
  assert.equal((await job.get()).get("lastErrorCode"), "max_attempts_exceeded");
  assert.ok((await dueRoomOwnershipSuccessionJobIDs(db, late)).includes(job.id));
  await processRoomSuccessionAttempt(job.id, room("exhausted-parent").id, 1, db, () => now);
  assert.equal((await attempt("exhausted-parent").get()).get("result"), "resolved");
});
