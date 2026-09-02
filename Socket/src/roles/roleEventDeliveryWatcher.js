import { randomUUID } from "node:crypto";

const DELIVERY_LEASE_MS = 60_000;
const DELIVERY_POLL_MS = 5_000;
const DELIVERY_BATCH_SIZE = 50;
const MAX_DELIVERY_ATTEMPTS = 10;
const FAILED_RETENTION_MS = 24 * 60 * 60 * 1_000;

function timestampMillis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return typeof value === "number" ? value : 0;
}

export function createRoleEventDeliveryWatcher({
  db,
  admin,
  io,
  clock,
  logger = console,
  scheduleInterval = (callback, milliseconds) => setInterval(callback, milliseconds),
  clearScheduledInterval = (timer) => clearInterval(timer),
  leaseOwner = randomUUID
}) {
  let unsubscribe = null;
  let interval = null;
  let draining = null;
  let stopped = false;

  async function claim(jobRef) {
    const owner = leaseOwner();
    const nowMillis = clock.nowMillis();
    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(jobRef);
      if (!snapshot.exists) return null;
      const data = snapshot.data() || {};
      const dueAt = timestampMillis(data.nextAttemptAt);
      const leaseExpiresAt = timestampMillis(data.leaseExpiresAt);
      const claimable = (data.status === "pending" || data.status === "retryPending")
        ? dueAt <= nowMillis
        : data.status === "processing" && leaseExpiresAt <= nowMillis;
      if (!claimable) return null;
      const attempt = Number.isInteger(data.attempt) ? data.attempt + 1 : 1;
      transaction.update(jobRef, {
        status: "processing",
        attempt,
        leaseOwner: owner,
        leaseExpiresAt: admin.firestore.Timestamp.fromMillis(nowMillis + DELIVERY_LEASE_MS),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      return {owner, attempt, data};
    });
  }

  async function complete(jobRef, owner) {
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(jobRef);
      const data = snapshot.data() || {};
      if (!snapshot.exists || data.status !== "processing" || data.leaseOwner !== owner) return;
      transaction.delete(jobRef);
    });
  }

  async function retry(jobRef, claimed) {
    const nowMillis = clock.nowMillis();
    const terminal = claimed.attempt >= MAX_DELIVERY_ATTEMPTS;
    const delay = Math.min(5 * 60_000, 1_000 * (2 ** Math.min(claimed.attempt - 1, 8)));
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(jobRef);
      const data = snapshot.data() || {};
      if (!snapshot.exists || data.status !== "processing" || data.leaseOwner !== claimed.owner) return;
      transaction.update(jobRef, {
        status: terminal ? "failed" : "retryPending",
        leaseOwner: null,
        leaseExpiresAt: null,
        nextAttemptAt: terminal ? null :
          admin.firestore.Timestamp.fromMillis(nowMillis + delay),
        lastErrorCode: "delivery_failed",
        expiresAt: terminal ?
          admin.firestore.Timestamp.fromMillis(nowMillis + FAILED_RETENTION_MS) : null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    });
  }

  async function deliver(jobRef) {
    const claimed = await claim(jobRef);
    if (!claimed) return false;
    const job = claimed.data;
    try {
      if (!job.roomID || !job.eventID || !Number.isInteger(job.seq)) {
        throw new Error("invalid_delivery_job");
      }
      const eventSnapshot = await db.collection("Rooms").doc(job.roomID)
        .collection("Messages").doc(job.eventID).get();
      const event = eventSnapshot.data() || {};
      if (!eventSnapshot.exists || event.ID !== job.eventID || event.seq !== job.seq ||
          event.messageType !== "roomRoleEvent" || event.serverGenerated !== true ||
          !event.roleEvent || typeof event.roleEvent !== "object") {
        throw new Error("delivery_event_not_ready");
      }
      io.to(job.roomID).emit("chat:roomRoleEvent", event);
      await complete(jobRef, claimed.owner);
      return true;
    } catch (error) {
      logger.error("[role-event-delivery-watcher] delivery failed", {
        jobPath: jobRef.path,
        errorCode: error instanceof Error ? error.message : "delivery_failed"
      });
      await retry(jobRef, claimed);
      return false;
    }
  }

  async function drainOnce() {
    if (stopped) return;
    const now = admin.firestore.Timestamp.fromMillis(clock.nowMillis());
    const jobs = db.collection("chatRoleEventDeliveryJobs");
    const snapshots = await Promise.all([
      jobs.where("status", "==", "pending").limit(DELIVERY_BATCH_SIZE).get(),
      jobs.where("status", "==", "retryPending")
        .where("nextAttemptAt", "<=", now).orderBy("nextAttemptAt", "asc")
        .limit(DELIVERY_BATCH_SIZE).get(),
      jobs.where("status", "==", "processing")
        .where("leaseExpiresAt", "<=", now).orderBy("leaseExpiresAt", "asc")
        .limit(DELIVERY_BATCH_SIZE).get()
    ]);
    const dueDocuments = new Map();
    for (const snapshot of snapshots) {
      for (const document of snapshot.docs) dueDocuments.set(document.ref.path, document);
    }
    for (const document of [...dueDocuments.values()].slice(0, DELIVERY_BATCH_SIZE)) {
      await deliver(document.ref);
    }
  }

  function requestDrain() {
    if (stopped || draining) return draining;
    draining = drainOnce()
      .catch((error) => logger.error("[role-event-delivery-watcher] drain failed", error))
      .finally(() => { draining = null; });
    return draining;
  }

  function start() {
    if (unsubscribe || interval) return stop;
    stopped = false;
    unsubscribe = db.collection("chatRoleEventDeliveryJobs")
      .where("status", "in", ["pending", "retryPending", "processing"])
      .onSnapshot(
        () => { void requestDrain(); },
        (error) => logger.error("[role-event-delivery-watcher] snapshot failed", error)
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

  return {start, stop, drainOnce, deliver};
}
