/* eslint-disable require-jsdoc, max-len */
import {randomUUID} from "node:crypto";
import {FieldPath, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {db} from "../../core/firebase.js";
import {removeOrdinaryMembership, resolveOwnedRoom, RoomMembershipSweepCause} from "./roomMembershipSweep.js";
import {nextRoomSuccessionAttempt, retryableSuccessionError, roomSuccessionExpired, ROOM_SUCCESSION_MAX_ATTEMPTS, ROOM_SUCCESSION_WINDOW_MILLIS, successionRetryDelayMillis} from "./roomSuccessionPolicy.js";

export type SuccessionClock = () => Date;
const PAGE_SIZE = 25;
const PARENT_LEASE_MILLIS = 60_000;
const RETENTION_MILLIS = 30 * 24 * 60 * 60 * 1000;
const ACTIVE = ["pending", "retryPending", "processing"];
type Snapshot = FirebaseFirestore.DocumentSnapshot;
type Patch = FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>;
type RoomClaim = {uid: string; cause: RoomMembershipSweepCause; attempt: number} | {failed: string} | null;

const timestamp = (value: unknown): number => value instanceof Timestamp ? value.toMillis() : NaN;
const count = (value: unknown): number => Number.isSafeInteger(value) && Number(value) >= 0 ? Number(value) : 0;
const parentRef = (firestore: Firestore, jobID: string) => firestore.collection("roomOwnershipSuccessionJobs").doc(jobID);
const roomRef = (firestore: Firestore, jobID: string, roomID: string) => parentRef(firestore, jobID).collection("roomSuccessionAttempts").doc(roomID);
const clockFor = (value: Date | SuccessionClock): SuccessionClock => typeof value === "function" ? value : () => value;

async function currentFence(transaction: Transaction, firestore: Firestore, job: Snapshot): Promise<boolean> {
  const uid = job.get("targetUID");
  if (typeof uid !== "string" || !uid || uid.includes("/")) return false;
  if (job.get("cause") === "permanentSuspension") {
    const account = await transaction.get(firestore.collection("moderationAccounts").doc(uid));
    return account.exists && account.get("accountStatus") === "active" && account.get("moderationStatus") === "suspended" &&
      Number.isSafeInteger(job.get("expectedStateVersion")) && account.get("stateVersion") === job.get("expectedStateVersion");
  }
  const requestID = job.get("accountDeletionRequestID");
  const generation = job.get("accountGenerationID");
  if (job.get("cause") !== "accountDeletion" || typeof requestID !== "string" || !requestID || requestID.includes("/") || !generation) return false;
  const [request, user] = await Promise.all([
    transaction.get(firestore.collection("accountDeletionRequests").doc(requestID)),
    transaction.get(firestore.collection("users").doc(uid)),
  ]);
  return request.exists && request.get("uid") === uid && request.get("accountGenerationID") === generation &&
    ["finalizing", "retryPending"].includes(request.get("status")) && request.get("stage") === "rooms" &&
    user.exists && user.get("accountStatus") === "deletionPending" && user.get("accountGenerationID") === generation;
}

function terminalRoom(transaction: Transaction, job: Snapshot, room: Snapshot, status: "completed" | "failed", result: string, now: Date): void {
  if (!ACTIVE.includes(room.get("status"))) return;
  if (!Number.isSafeInteger(job.get("pendingRoomCount")) || job.get("pendingRoomCount") <= 0 ||
    !Number.isSafeInteger(job.get("failedRoomCount")) || job.get("failedRoomCount") < 0) throw new Error("room_succession_counter_invalid");
  const failed = status === "failed";
  transaction.update(room.ref, {
    status, result, nextAttemptAt: null, leaseOwner: null, leaseExpiresAt: null,
    lastErrorCode: failed ? result : null, completedAt: Timestamp.fromDate(now), updatedAt: Timestamp.fromDate(now),
    expiresAt: failed ? null : Timestamp.fromMillis(now.getTime() + RETENTION_MILLIS),
  });
  transaction.update(job.ref, {
    pendingRoomCount: Math.max(0, count(job.get("pendingRoomCount")) - 1),
    failedRoomCount: count(job.get("failedRoomCount")) + (failed ? 1 : 0),
    updatedAt: Timestamp.fromDate(now),
    ...(job.get("status") === "failed" && job.get("pendingRoomCount") === 1 ? {nextAttemptAt: null} : {}),
  });
}

// 만료 확정과 성공 commit은 같은 방별 상태 문서에 경합하므로 성공을 실패로 덮어쓰지 않는다.
export async function settleExpiredRoomSuccession(jobID: string, roomID: string, firestore = db, clock: SuccessionClock = () => new Date()): Promise<void> {
  const failed = await firestore.runTransaction<boolean>(async (transaction) => {
    const [job, room] = await Promise.all([
      transaction.get(parentRef(firestore, jobID)), transaction.get(roomRef(firestore, jobID, roomID)),
    ]);
    if (!job.exists || !room.exists || !ACTIVE.includes(room.get("status"))) return false;
    const now = clock();
    if (roomSuccessionExpired(timestamp(room.get("deadlineAt")), now.getTime())) {
      terminalRoom(transaction, job, room, "failed", "room_succession_deadline_exceeded", now);
      return true;
    }
    return false;
  });
  if (failed) reportRoomFailure(jobID, roomID, "room_succession_deadline_exceeded");
}

function reportRoomFailure(jobID: string, roomID: string, code: string): void {
  console.error("[roomSuccession] terminal room failure", {severity: "ERROR", alertType: "ROOM_OWNERSHIP_SUCCESSION_FAILED", jobID, roomID, code});
}

export async function processRoomSuccessionAttempt(jobID: string, roomID: string, generation: number, firestore = db, clock: SuccessionClock = () => new Date()): Promise<void> {
  const ref = roomRef(firestore, jobID, roomID);
  const leaseOwner = randomUUID();
  const claim = await firestore.runTransaction<RoomClaim>(async (transaction) => {
    const [job, room] = await Promise.all([transaction.get(parentRef(firestore, jobID)), transaction.get(ref)]);
    if (!job.exists || !room.exists || room.get("generation") !== generation || !ACTIVE.includes(room.get("status"))) return null;
    const now = clock();
    if (roomSuccessionExpired(timestamp(room.get("deadlineAt")), now.getTime())) {
      terminalRoom(transaction, job, room, "failed", "room_succession_deadline_exceeded", now);
      return {failed: "room_succession_deadline_exceeded"};
    }
    // 응답 유실/실행 중인 commit을 새 worker가 중복 실행하지 않는다. 만료 후에는 실패 확정만 가능하다.
    if (room.get("status") === "processing" || timestamp(room.get("nextAttemptAt")) > now.getTime()) return null;
    // 부모의 탐색/정리 실패는 계정 fence 취소가 아니다. 생성된 방은 독립 예산으로 실행한다.
    if (!(await currentFence(transaction, firestore, job))) {
      terminalRoom(transaction, job, room, "completed", "staleFence", now);
      return null;
    }
    const attempt = count(room.get("attempt")) + 1;
    if (attempt > ROOM_SUCCESSION_MAX_ATTEMPTS) {
      terminalRoom(transaction, job, room, "failed", "max_attempts_exceeded", now);
      return {failed: "max_attempts_exceeded"};
    }
    transaction.update(ref, {status: "processing", attempt, leaseOwner, leaseExpiresAt: room.get("deadlineAt"), updatedAt: Timestamp.fromDate(now)});
    return {uid: job.get("targetUID") as string, cause: job.get("cause") as RoomMembershipSweepCause, attempt};
  });
  if (!claim) return;
  if ("failed" in claim) {
    reportRoomFailure(jobID, roomID, claim.failed);
    return;
  }
  try {
    await resolveOwnedRoom(firestore, firestore.collection("Rooms").doc(roomID), claim.uid, claim.cause, clock(), async (transaction) => {
      const [job, room] = await Promise.all([transaction.get(parentRef(firestore, jobID)), transaction.get(ref)]);
      if (!job.exists || !room.exists || room.get("status") !== "processing" || room.get("leaseOwner") !== leaseOwner || room.get("generation") !== generation) {
        throw new Error("room_succession_lease_lost");
      }
      if (!(await currentFence(transaction, firestore, job))) throw new Error("room_succession_stale_fence");
      const now = clock();
      if (roomSuccessionExpired(timestamp(room.get("deadlineAt")), now.getTime())) throw new Error("room_succession_deadline_exceeded");
      return () => terminalRoom(transaction, job, room, "completed", "resolved", now);
    });
  } catch (error) {
    // commit 응답 유실도 다시 상태를 읽는다. 성공한 방은 재실행/실패 처리하지 않는다.
    const failed = await firestore.runTransaction<string | null>(async (transaction) => {
      const [job, room] = await Promise.all([transaction.get(parentRef(firestore, jobID)), transaction.get(ref)]);
      if (!job.exists || !room.exists || room.get("status") !== "processing" || room.get("leaseOwner") !== leaseOwner || room.get("generation") !== generation) return null;
      const now = clock();
      if (error instanceof Error && error.message === "room_succession_stale_fence") {
        terminalRoom(transaction, job, room, "completed", "staleFence", now);
        return null;
      }
      const deadline = timestamp(room.get("deadlineAt"));
      const next = retryableSuccessionError(error) ? nextRoomSuccessionAttempt(claim.attempt, deadline, now.getTime()) : null;
      if (next === null) {
        const code = roomSuccessionExpired(deadline, now.getTime()) ? "room_succession_deadline_exceeded" :
          retryableSuccessionError(error) ? "room_succession_attempts_exhausted" : error instanceof Error ? error.message.slice(0, 120) : "unknown";
        terminalRoom(transaction, job, room, "failed", code, now);
        return code;
      } else {
        transaction.update(ref, {status: "retryPending", nextAttemptAt: Timestamp.fromMillis(next), leaseOwner: null, leaseExpiresAt: null, updatedAt: Timestamp.fromDate(now)});
      }
      return null;
    });
    if (failed) reportRoomFailure(jobID, roomID, failed);
  }
}

async function finishParent(firestore: Firestore, jobID: string, lease: string, patch: Patch | ((job: Snapshot) => Patch)): Promise<void> {
  await firestore.runTransaction(async (transaction) => {
    const job = await transaction.get(parentRef(firestore, jobID));
    if (!job.exists || job.get("status") !== "processing" || job.get("leaseOwner") !== lease) throw new Error("room_succession_lease_lost");
    transaction.update(job.ref, typeof patch === "function" ? patch(job) : patch);
  });
}

function parentFailurePatch(job: Snapshot, code: string, now: Date): Patch {
  return {status: "failed", result: "orchestrationFailure", lastErrorCode: code,
    nextAttemptAt: count(job.get("pendingRoomCount")) > 0 ? Timestamp.fromMillis(now.getTime() + 5_000) : null,
    leaseOwner: null, leaseExpiresAt: null, completedAt: Timestamp.fromDate(now), updatedAt: Timestamp.fromDate(now), expiresAt: null};
}

// 실패한 부모는 탐색/일반 정리를 재개하지 않고 기존 자식의 만료 정리만 이어 간다.
async function drainFailedParentRooms(jobID: string, firestore: Firestore, clock: SuccessionClock): Promise<void> {
  const ref = parentRef(firestore, jobID);
  const job = await ref.get();
  if (!job.exists || job.get("status") !== "failed" || count(job.get("pendingRoomCount")) === 0) return;
  const active = await ref.collection("roomSuccessionAttempts").where("status", "in", ACTIVE).limit(PAGE_SIZE).get();
  for (const room of active.docs) await settleExpiredRoomSuccession(jobID, room.id, firestore, clock);
  await firestore.runTransaction(async (transaction) => {
    const current = await transaction.get(ref);
    if (!current.exists || current.get("status") !== "failed") return;
    transaction.update(ref, {nextAttemptAt: count(current.get("pendingRoomCount")) > 0 ? Timestamp.fromMillis(clock().getTime() + 5_000) : null});
  });
}

// 계정 작업은 발견/일반 퇴장/집계만 담당한다. 개별 방의 성공·실패·시간 예산을 공유하지 않는다.
export async function processRoomOwnershipSuccessionJob(jobID: string, firestore = db, time: Date | SuccessionClock = () => new Date()): Promise<boolean> {
  const clock = clockFor(time);
  const lease = randomUUID();
  const claimed = await firestore.runTransaction(async (transaction) => {
    const job = await transaction.get(parentRef(firestore, jobID));
    const now = clock();
    if (!job.exists || !ACTIVE.includes(job.get("status")) || timestamp(job.get("nextAttemptAt")) > now.getTime() ||
      (job.get("status") === "processing" && timestamp(job.get("leaseExpiresAt")) > now.getTime())) return null;
    const attempt = count(job.get("attempt")) + 1;
    if (attempt > 4) {
      transaction.update(job.ref, parentFailurePatch(job, "max_attempts_exceeded", now));
      return null;
    }
    const valid = await currentFence(transaction, firestore, job);
    transaction.update(job.ref, {schemaVersion: 3, status: "processing", attempt, leaseOwner: lease, leaseExpiresAt: Timestamp.fromMillis(now.getTime() + PARENT_LEASE_MILLIS)});
    return {data: job.data() ?? {}, valid, attempt};
  });
  if (!claimed) {
    await drainFailedParentRooms(jobID, firestore, clock);
    return false;
  }
  const uid = claimed.data.targetUID as string;
  let phase = claimed.data.phase ?? "ownedCanonical";
  const cursor = claimed.data.cursor as string | undefined;
  const continuation = (): Patch => ({status: "retryPending", attempt: 0, nextAttemptAt: Timestamp.fromDate(clock()), leaseOwner: null, leaseExpiresAt: null, updatedAt: Timestamp.fromDate(clock())});
  try {
    if (!claimed.valid) phase = "waitingRooms";
    if (phase === "ownedCanonical" || phase === "ownedLegacy") {
      let query = firestore.collection("Rooms").where(phase === "ownedCanonical" ? "ownerUID" : "creatorUID", "==", uid)
        .where("isClosed", "==", false).orderBy(FieldPath.documentId()).limit(PAGE_SIZE);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      await firestore.runTransaction(async (transaction) => {
        const job = await transaction.get(parentRef(firestore, jobID));
        if (job.get("leaseOwner") !== lease || job.get("status") !== "processing") throw new Error("room_succession_lease_lost");
        if (!(await currentFence(transaction, firestore, job))) throw new Error("room_succession_stale_fence");
        const candidates = page.docs.filter((room) => (room.get("ownerUID") ?? room.get("creatorUID")) === uid);
        const existing = await Promise.all(candidates.map((room) => transaction.get(roomRef(firestore, jobID, room.id))));
        const now = clock();
        let added = 0;
        for (const [index, room] of candidates.entries()) {
          if (existing[index].exists) continue;
          added += 1;
          transaction.create(existing[index].ref, {
            roomID: room.id, generation: 1, status: "pending", attempt: 0,
            startedAt: Timestamp.fromDate(now), deadlineAt: Timestamp.fromMillis(now.getTime() + ROOM_SUCCESSION_WINDOW_MILLIS),
            nextAttemptAt: Timestamp.fromDate(now), leaseOwner: null, leaseExpiresAt: null, result: null, lastErrorCode: null,
            createdAt: Timestamp.fromDate(now), updatedAt: Timestamp.fromDate(now), expiresAt: null,
          });
        }
        const exhausted = page.size < PAGE_SIZE;
        transaction.update(job.ref, {...continuation(),
          phase: exhausted ? (phase === "ownedCanonical" ? "ownedLegacy" : "members") : phase,
          cursor: exhausted ? null : page.docs[page.size - 1].id,
          pendingRoomCount: count(job.get("pendingRoomCount")) + added,
          failedRoomCount: count(job.get("failedRoomCount")),
        });
      });
      return false;
    }
    if (phase === "members") {
      let query = firestore.collectionGroup("members").where("userID", "==", uid).orderBy(FieldPath.documentId()).limit(PAGE_SIZE);
      if (cursor) query = query.startAfter(firestore.doc(cursor));
      const page = await query.get();
      for (const member of page.docs) {
        const room = member.ref.parent.parent;
        if (!room) continue;
        await removeOrdinaryMembership(firestore, room, uid, clock(), async (transaction) => {
          const job = await transaction.get(parentRef(firestore, jobID));
          if (job.get("leaseOwner") !== lease || job.get("status") !== "processing" || !(await currentFence(transaction, firestore, job))) throw new Error("room_succession_lease_lost");
        });
      }
      await finishParent(firestore, jobID, lease, {...continuation(), phase: page.size < PAGE_SIZE ? "waitingRooms" : "members", cursor: page.size < PAGE_SIZE ? null : page.docs[page.size - 1].ref.path});
      return false;
    }
    // 5분 watchdog은 만료된 방에 새 승계를 시작하지 않는다.
    const active = await parentRef(firestore, jobID).collection("roomSuccessionAttempts").where("status", "in", ACTIVE).limit(PAGE_SIZE).get();
    for (const room of active.docs) await settleExpiredRoomSuccession(jobID, room.id, firestore, clock);
    return await firestore.runTransaction(async (transaction) => {
      const job = await transaction.get(parentRef(firestore, jobID));
      if (job.get("leaseOwner") !== lease || job.get("status") !== "processing") throw new Error("room_succession_lease_lost");
      const now = clock();
      if (count(job.get("pendingRoomCount")) > 0) {
        transaction.update(job.ref, {...continuation(), phase: "waitingRooms", nextAttemptAt: Timestamp.fromMillis(now.getTime() + 5_000)});
        return false;
      }
      const failed = count(job.get("failedRoomCount")) > 0;
      transaction.update(job.ref, {status: failed ? "failed" : "completed", phase: "waitingRooms", result: failed ? "partialFailure" : claimed.valid ? "resolved" : "staleFence",
        attempt: 0, leaseOwner: null, leaseExpiresAt: null, nextAttemptAt: null, completedAt: Timestamp.fromDate(now), updatedAt: Timestamp.fromDate(now),
        expiresAt: failed ? null : Timestamp.fromMillis(now.getTime() + RETENTION_MILLIS)});
      return !failed;
    });
  } catch (error) {
    const now = clock();
    const delay = successionRetryDelayMillis(claimed.attempt);
    const terminal = delay === null || !retryableSuccessionError(error);
    const code = error instanceof Error ? error.message.slice(0, 120) : "unknown";
    await finishParent(firestore, jobID, lease, (job) => terminal ? parentFailurePatch(job, code, now) :
      {status: "retryPending", nextAttemptAt: Timestamp.fromMillis(now.getTime() + delay),
        lastErrorCode: code, leaseOwner: null, leaseExpiresAt: null, updatedAt: Timestamp.fromDate(now)});
    if (terminal) console.error("[roomSuccession] parent failure", {severity: "ERROR", alertType: "ROOM_OWNERSHIP_SUCCESSION_FAILED", jobID, code});
    return false;
  }
}

export async function replayFailedRoomOwnershipSuccessionJob(jobID: string, roomID: string, expectedTargetUID: string, firestore = db, clock: SuccessionClock = () => new Date()): Promise<boolean> {
  return firestore.runTransaction(async (transaction) => {
    const [job, room] = await Promise.all([transaction.get(parentRef(firestore, jobID)), transaction.get(roomRef(firestore, jobID, roomID))]);
    if (!job.exists || !room.exists || job.get("targetUID") !== expectedTargetUID || room.get("status") !== "failed" ||
      (!ACTIVE.includes(job.get("status")) && job.get("status") !== "failed") || !(await currentFence(transaction, firestore, job))) return false;
    const now = clock();
    transaction.update(room.ref, {status: "pending", generation: count(room.get("generation")) + 1, attempt: 0,
      startedAt: Timestamp.fromDate(now), deadlineAt: Timestamp.fromMillis(now.getTime() + ROOM_SUCCESSION_WINDOW_MILLIS), nextAttemptAt: Timestamp.fromDate(now),
      leaseOwner: null, leaseExpiresAt: null, lastErrorCode: null, result: null, completedAt: null, expiresAt: null, updatedAt: Timestamp.fromDate(now)});
    transaction.update(job.ref, {pendingRoomCount: count(job.get("pendingRoomCount")) + 1, failedRoomCount: Math.max(0, count(job.get("failedRoomCount")) - 1),
      ...(job.get("status") === "failed" ? (job.get("result") === "partialFailure" ?
        {status: "retryPending", attempt: 0, nextAttemptAt: Timestamp.fromDate(now), result: null, completedAt: null, expiresAt: null} :
        {nextAttemptAt: Timestamp.fromDate(now)}) : {}), updatedAt: Timestamp.fromDate(now)});
    return true;
  });
}

export async function dueRoomOwnershipSuccessionJobIDs(firestore = db, now = new Date(), limit = 25): Promise<string[]> {
  const snapshot = await firestore.collection("roomOwnershipSuccessionJobs").where("status", "in", [...ACTIVE, "failed"])
    .where("nextAttemptAt", "<=", Timestamp.fromDate(now)).orderBy("nextAttemptAt").limit(limit).get();
  return snapshot.docs.map((document) => document.id);
}
