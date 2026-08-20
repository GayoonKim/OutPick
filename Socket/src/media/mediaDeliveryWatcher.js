import { randomUUID } from "node:crypto";

const DELIVERY_LEASE_MS = 60_000;
const DELIVERY_POLL_MS = 5_000;
const DELIVERY_BATCH_SIZE = 50;

function timestampMillis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return typeof value === "number" ? value : 0;
}

export function createMediaDeliveryWatcher({
  db,
  admin,
  io,
  clock,
  fanoutChatPush,
  logger = console,
  scheduleInterval = (callback, milliseconds) => setInterval(callback, milliseconds),
  clearScheduledInterval = (timer) => clearInterval(timer),
  leaseToken = randomUUID
}) {
  let unsubscribe = null;
  let interval = null;
  let draining = null;
  let stopped = false;

  async function claim(jobRef) {
    const token = leaseToken();
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
        leaseToken: token,
        leaseExpiresAt: admin.firestore.Timestamp.fromMillis(nowMillis + DELIVERY_LEASE_MS),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      return { token, attempt, data };
    });
  }

  async function complete(jobRef, token) {
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
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    });
  }

  async function retry(jobRef, claimResult) {
    const delay = Math.min(5 * 60_000, 1_000 * (2 ** Math.min(claimResult.attempt, 8)));
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(jobRef);
      const data = snapshot.data() || {};
      if (!snapshot.exists || data.status !== "processing" ||
          data.leaseToken !== claimResult.token) return;
      transaction.update(jobRef, {
        status: "retryPending",
        leaseToken: null,
        leaseExpiresAt: null,
        nextAttemptAt: admin.firestore.Timestamp.fromMillis(clock.nowMillis() + delay),
        lastErrorCode: "delivery_failed",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    });
  }

  function notifySenderReady(message, job) {
    const sockets = io.sockets?.sockets;
    if (!sockets || typeof sockets.values !== "function") return;
    for (const socket of sockets.values()) {
      if (String(socket.userUID || "").trim() !== String(message.senderUID || "").trim()) {
        continue;
      }
      socket.emit("chat:mediaProcessingStatusChanged", {
        roomID: job.roomID,
        uploadID: job.messageID,
        messageID: job.messageID,
        processingStatus: "ready",
        seq: job.seq
      });
    }
  }

  async function deliver(jobRef) {
    const claimed = await claim(jobRef);
    if (!claimed) return false;
    const job = claimed.data;
    try {
      if (!job.roomID || !job.messageID || !Number.isInteger(job.seq) ||
          !["receiveImages", "receiveVideo"].includes(job.eventKind)) {
        throw new Error("invalid_delivery_job");
      }
      const messageSnapshot = await db.collection("Rooms").doc(job.roomID)
        .collection("Messages").doc(job.messageID).get();
      const message = messageSnapshot.data() || {};
      if (!messageSnapshot.exists || message.ID !== job.messageID || message.seq !== job.seq ||
          message.moderationVisibilityState === "hiddenPendingReview" || message.isDeleted === true) {
        throw new Error("delivery_message_not_ready");
      }
      io.to(job.roomID).emit(job.eventKind, message);
      notifySenderReady(message, job);
      await fanoutChatPush({
        roomID: job.roomID,
        messageData: message,
        throwOnError: true
      });
      await complete(jobRef, claimed.token);
      return true;
    } catch (error) {
      logger.error("[media-delivery-watcher] delivery failed", {
        jobPath: jobRef.path,
        errorCode: error instanceof Error && error.message === "delivery_message_not_ready" ?
          "delivery_message_not_ready" : "delivery_failed"
      });
      await retry(jobRef, claimed);
      return false;
    }
  }

  async function drainOnce() {
    if (stopped) return;
    const now = admin.firestore.Timestamp.fromMillis(clock.nowMillis());
    const jobs = db.collection("chatMediaDeliveryJobs");
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
      .catch((error) => logger.error("[media-delivery-watcher] drain failed", error))
      .finally(() => { draining = null; });
    return draining;
  }

  function start() {
    if (unsubscribe || interval) return stop;
    stopped = false;
    unsubscribe = db.collection("chatMediaDeliveryJobs")
      .where("status", "in", ["pending", "retryPending", "processing"])
      .onSnapshot(
        () => { void requestDrain(); },
        (error) => logger.error("[media-delivery-watcher] snapshot failed", error)
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
