import { randomUUID } from "node:crypto";

const DELIVERY_LEASE_MS = 60_000;
const DELIVERY_POLL_MS = 5_000;
const DELIVERY_BATCH_SIZE = 50;
const DELIVERY_MAX_ATTEMPTS = 10;
const DELIVERY_TERMINAL_TTL_MS = 7 * 24 * 60 * 60_000;

function timestampMillis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return typeof value === "number" ? value : 0;
}

function nonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function deliveryEvent(job) {
  if (job.eventKind === "messageDeleted" &&
      nonEmptyString(job.roomID) &&
      nonEmptyString(job.messageID) &&
      Number.isInteger(job.seq) && job.seq > 0 &&
      Number.isInteger(job.deletionRevision) && job.deletionRevision > 0) {
    return {
      name: "chat:messageDeleted",
      payload: {
        roomID: job.roomID,
        messageID: job.messageID,
        seq: job.seq,
        deletionRevision: job.deletionRevision
      }
    };
  }
  if (job.eventKind === "deletionHeadAdvanced" &&
      nonEmptyString(job.roomID) &&
      Number.isInteger(job.fromRevision) && job.fromRevision > 0 &&
      Number.isInteger(job.toRevision) && job.toRevision >= job.fromRevision) {
    return {
      name: "chat:messageDeletionHeadAdvanced",
      payload: {
        roomID: job.roomID,
        fromRevision: job.fromRevision,
        toRevision: job.toRevision
      }
    };
  }
  throw new Error("invalid_deletion_delivery_job");
}

export function createDeletionDeliveryWatcher({
  db,
  admin,
  io,
  clock,
  logger = console,
  scheduleInterval = (callback, milliseconds) => setInterval(callback, milliseconds),
  clearScheduledInterval = (timer) => clearInterval(timer),
  leaseToken = randomUUID
}) {
  let unsubscribe = null;
  let interval = null;
  let draining = null;
  let stopped = false;

  function terminalExpiresAt(nowMillis) {
    return admin.firestore.Timestamp.fromMillis(nowMillis + DELIVERY_TERMINAL_TTL_MS);
  }

  async function claim(jobRef) {
    const token = leaseToken();
    const nowMillis = clock.nowMillis();
    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(jobRef);
      if (!snapshot.exists) return null;
      const data = snapshot.data() || {};
      const dueAt = timestampMillis(data.nextAttemptAt);
      const leaseExpiresAt = timestampMillis(data.leaseExpiresAt);
      const isExpiredProcessing = data.status === "processing" &&
        leaseExpiresAt <= nowMillis;
      const isDue = (data.status === "pending" || data.status === "retryPending") &&
        dueAt <= nowMillis;
      if (!isDue && !isExpiredProcessing) return null;

      const previousAttempt = Number.isInteger(data.attempt) ? data.attempt : 0;
      if (!isExpiredProcessing && previousAttempt >= DELIVERY_MAX_ATTEMPTS) {
        transaction.update(jobRef, {
          status: "failed",
          leaseToken: null,
          leaseExpiresAt: null,
          nextAttemptAt: null,
          lastErrorCode: "max_attempts_exceeded",
          failedAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: terminalExpiresAt(nowMillis),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        return null;
      }

      // 만료 lease는 마지막 물리 시도 중 프로세스가 종료됐을 수 있으므로 같은 attempt로 회수한다.
      const attempt = isExpiredProcessing ? Math.max(previousAttempt, 1) : previousAttempt + 1;
      transaction.update(jobRef, {
        status: "processing",
        attempt,
        leaseToken: token,
        leaseExpiresAt: admin.firestore.Timestamp.fromMillis(nowMillis + DELIVERY_LEASE_MS),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      return { token, attempt, data };
    });
  }

  async function complete(jobRef, token) {
    const nowMillis = clock.nowMillis();
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(jobRef);
      const data = snapshot.data() || {};
      if (!snapshot.exists || data.status !== "processing" || data.leaseToken !== token) {
        return;
      }
      transaction.update(jobRef, {
        status: "completed",
        leaseToken: null,
        leaseExpiresAt: null,
        nextAttemptAt: null,
        lastErrorCode: null,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: terminalExpiresAt(nowMillis),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    });
  }

  async function retry(jobRef, claimResult, errorCode) {
    const nowMillis = clock.nowMillis();
    const terminal = claimResult.attempt >= DELIVERY_MAX_ATTEMPTS;
    const delay = Math.min(5 * 60_000, 1_000 * (2 ** Math.min(claimResult.attempt, 8)));
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(jobRef);
      const data = snapshot.data() || {};
      if (!snapshot.exists || data.status !== "processing" ||
          data.leaseToken !== claimResult.token) return;
      transaction.update(jobRef, {
        status: terminal ? "failed" : "retryPending",
        leaseToken: null,
        leaseExpiresAt: null,
        nextAttemptAt: terminal ? null :
          admin.firestore.Timestamp.fromMillis(nowMillis + delay),
        lastErrorCode: terminal ? "max_attempts_exceeded" : errorCode,
        ...(terminal ? {
          failedAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: terminalExpiresAt(nowMillis)
        } : {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    });
  }

  async function deliver(jobRef) {
    const claimed = await claim(jobRef);
    if (!claimed) return false;
    try {
      const event = deliveryEvent(claimed.data);
      io.to(claimed.data.roomID).emit(event.name, event.payload);
      await complete(jobRef, claimed.token);
      return true;
    } catch (error) {
      const errorCode = error instanceof Error &&
        error.message === "invalid_deletion_delivery_job" ?
        "invalid_delivery_job" : "delivery_failed";
      logger.error("[deletion-delivery-watcher] delivery failed", {
        jobPath: jobRef.path,
        errorCode
      });
      await retry(jobRef, claimed, errorCode);
      return false;
    }
  }

  async function drainOnce() {
    if (stopped) return;
    const now = admin.firestore.Timestamp.fromMillis(clock.nowMillis());
    const jobs = db.collection("chatMessageDeletionDeliveryJobs");
    const snapshots = await Promise.all([
      jobs.where("status", "==", "pending")
        .limit(DELIVERY_BATCH_SIZE)
        .get(),
      jobs.where("status", "==", "retryPending")
        .where("nextAttemptAt", "<=", now)
        .orderBy("nextAttemptAt", "asc")
        .limit(DELIVERY_BATCH_SIZE)
        .get(),
      jobs.where("status", "==", "processing")
        .where("leaseExpiresAt", "<=", now)
        .orderBy("leaseExpiresAt", "asc")
        .limit(DELIVERY_BATCH_SIZE)
        .get()
    ]);
    const dueDocuments = new Map();
    for (const snapshot of snapshots) {
      for (const document of snapshot.docs) {
        if (!dueDocuments.has(document.ref.path)) {
          dueDocuments.set(document.ref.path, document);
        }
      }
    }
    for (const document of [...dueDocuments.values()].slice(0, DELIVERY_BATCH_SIZE)) {
      await deliver(document.ref);
    }
  }

  function requestDrain() {
    if (stopped || draining) return draining;
    draining = drainOnce()
      .catch((error) => logger.error("[deletion-delivery-watcher] drain failed", error))
      .finally(() => { draining = null; });
    return draining;
  }

  function start() {
    if (unsubscribe || interval) return stop;
    stopped = false;
    unsubscribe = db.collection("chatMessageDeletionDeliveryJobs")
      .where("status", "in", ["pending", "retryPending", "processing"])
      .onSnapshot(
        () => { void requestDrain(); },
        (error) => logger.error("[deletion-delivery-watcher] snapshot failed", error)
      );
    interval = scheduleInterval(() => { void requestDrain(); }, DELIVERY_POLL_MS);
    interval?.unref?.();
    void requestDrain();
    return stop;
  }

  function stop() {
    stopped = true;
    unsubscribe?.();
    unsubscribe = null;
    if (interval) clearScheduledInterval(interval);
    interval = null;
  }

  return { start, stop, drainOnce, deliver };
}
