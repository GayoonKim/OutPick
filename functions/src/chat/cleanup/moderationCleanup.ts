/* eslint-disable require-jsdoc, max-len */
import {
  DocumentReference,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

// 참여자마다 member·joinedRooms·roomStates 3건을 삭제하므로 150명 × 3 = 450 writes로 제한한다.
const MEMBER_BATCH_LIMIT = 150;
const PAGE_LIMIT = 300;
const LEASE_MILLIS = 10 * 60 * 1000;
const COMPLETED_JOB_TTL_MILLIS = 7 * 24 * 60 * 60 * 1000;
export const ROOM_TOMBSTONE_TTL_MILLIS = 14 * 24 * 60 * 60 * 1000;
const MAX_ATTEMPTS = 20;

type CleanupKind = "message" | "room";

type StorageBucket = {
  deleteFiles(options: {prefix: string; force: boolean}): Promise<unknown>;
};

export type CleanupBucketResolver = {
  defaultBucket: StorageBucket;
  bucket: (name: string) => StorageBucket;
  roomBuckets: StorageBucket[];
};

function retryDelayMillis(attempt: number): number {
  return Math.min(6 * 60 * 60 * 1000, Math.max(60_000, 2 ** Math.min(attempt, 8) * 30_000));
}

function validDocumentID(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && !value.includes("/");
}

export function normalizedClosureRoomName(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length > 0 && normalized.length <= 20 ? normalized : null;
}

async function claimJob(
  reference: DocumentReference,
  now: Date,
): Promise<FirebaseFirestore.DocumentData | null> {
  return reference.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists || !snapshot.data()) return null;
    const data = snapshot.data();
    if (!data) return null;
    if (data.status === "completed" || data.status === "failed") return null;
    const nextAttemptAt = data.nextAttemptAt;
    if (nextAttemptAt instanceof Timestamp && nextAttemptAt.toMillis() > now.getTime()) {
      return null;
    }
    const attempt = typeof data.attempt === "number" && Number.isSafeInteger(data.attempt) ?
      data.attempt + 1 : 1;
    transaction.update(reference, {
      status: "processing",
      attempt,
      nextAttemptAt: Timestamp.fromMillis(now.getTime() + LEASE_MILLIS),
      leaseExpiresAt: Timestamp.fromMillis(now.getTime() + LEASE_MILLIS),
      updatedAt: Timestamp.fromDate(now),
    });
    return {...data, attempt};
  });
}

async function markCompleted(reference: DocumentReference, now: Date): Promise<void> {
  await reference.set({
    status: "completed",
    nextAttemptAt: Timestamp.fromDate(now),
    leaseExpiresAt: null,
    lastErrorCode: null,
    updatedAt: Timestamp.fromDate(now),
    expiresAt: Timestamp.fromMillis(now.getTime() + COMPLETED_JOB_TTL_MILLIS),
  }, {merge: true});
}

async function markAwaitingExpiry(
  reference: DocumentReference,
  expiresAt: Timestamp,
  now: Date,
): Promise<void> {
  await reference.set({
    cleanupPhase: "retention",
    status: "awaitingExpiry",
    nextAttemptAt: expiresAt,
    leaseExpiresAt: null,
    lastErrorCode: null,
    updatedAt: Timestamp.fromDate(now),
    expiresAt: null,
  }, {merge: true});
}

async function markRetry(
  reference: DocumentReference,
  attempt: number,
  now: Date,
): Promise<void> {
  if (attempt >= MAX_ATTEMPTS) {
    await reference.set({
      status: "failed",
      nextAttemptAt: null,
      leaseExpiresAt: null,
      lastErrorCode: "cleanup_failed",
      updatedAt: Timestamp.fromDate(now),
      expiresAt: null,
    }, {merge: true});
    return;
  }
  await reference.set({
    status: "retryPending",
    nextAttemptAt: Timestamp.fromMillis(now.getTime() + retryDelayMillis(attempt)),
    leaseExpiresAt: null,
    lastErrorCode: "cleanup_failed",
    updatedAt: Timestamp.fromDate(now),
    expiresAt: null,
  }, {merge: true});
}

async function deleteCollection(collection: FirebaseFirestore.CollectionReference): Promise<void> {
  let hasMore = true;
  while (hasMore) {
    const snapshot = await collection.orderBy("__name__").limit(PAGE_LIMIT).get();
    if (snapshot.empty) return;
    const batch = collection.firestore.batch();
    for (const document of snapshot.docs) batch.delete(document.ref);
    await batch.commit();
    hasMore = snapshot.size === PAGE_LIMIT;
  }
}

async function scrubReplyPreviews(
  firestore: Firestore,
  roomID: string,
  messageID: string,
): Promise<void> {
  const messages = firestore.collection("Rooms").doc(roomID).collection("Messages");
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  let hasMore = true;
  while (hasMore) {
    let query = messages
      .where("replyPreview.messageID", "==", messageID)
      .orderBy("__name__")
      .limit(PAGE_LIMIT);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) return;
    const batch = firestore.batch();
    for (const document of snapshot.docs) {
      batch.update(document.ref, {
        replyPreview: {
          messageID,
          sender: "",
          text: "",
          imagesCount: 0,
          videosCount: 0,
          isDeleted: true,
        },
      });
    }
    await batch.commit();
    cursor = snapshot.docs.at(-1) ?? null;
    hasMore = snapshot.size === PAGE_LIMIT;
  }
}

async function deleteMediaIndex(
  firestore: Firestore,
  roomID: string,
  messageID: string,
): Promise<void> {
  const mediaIndex = firestore.collection("Rooms").doc(roomID).collection("mediaIndex");
  let hasMore = true;
  while (hasMore) {
    const snapshot = await mediaIndex.where("messageID", "==", messageID).limit(PAGE_LIMIT).get();
    if (snapshot.empty) return;
    const batch = firestore.batch();
    for (const document of snapshot.docs) batch.delete(document.ref);
    await batch.commit();
    hasMore = snapshot.size === PAGE_LIMIT;
  }
}

export async function processMessageCleanupJob(
  jobID: string,
  firestore: Firestore,
  buckets: CleanupBucketResolver,
  now = new Date(),
): Promise<boolean> {
  const reference = firestore.collection("chatMessageCleanupJobs").doc(jobID);
  const job = await claimJob(reference, now);
  if (!job) return false;
  try {
    if (!validDocumentID(job.roomID) || !validDocumentID(job.messageID)) {
      throw new Error("invalid_message_cleanup_target");
    }
    await scrubReplyPreviews(firestore, job.roomID, job.messageID);
    await deleteMediaIndex(firestore, job.roomID, job.messageID);
    const expectedPrefix = `rooms/${job.roomID}/messages/${job.messageID}`;
    const targets = Array.isArray(job.storageTargets) ? job.storageTargets : null;
    if (targets) {
      for (const target of targets) {
        if (!target || typeof target !== "object" || target.prefix !== expectedPrefix) {
          throw new Error("storage_target_mismatch");
        }
        const targetBucket = typeof target.bucket === "string" && target.bucket ?
          buckets.bucket(target.bucket) : buckets.defaultBucket;
        await targetBucket.deleteFiles({prefix: `${target.prefix}/`, force: true});
      }
    } else {
      const prefixes = Array.isArray(job.storagePrefixes) ? job.storagePrefixes : [];
      for (const prefix of prefixes) {
        if (prefix !== expectedPrefix) throw new Error("storage_prefix_mismatch");
        await buckets.defaultBucket.deleteFiles({prefix: `${prefix}/`, force: true});
      }
    }
    await markCompleted(reference, now);
    return true;
  } catch (error) {
    console.error("[processMessageCleanupJob] cleanup failed", {jobID, error});
    await markRetry(reference, job.attempt, now);
    return false;
  }
}

async function removeMemberships(
  firestore: Firestore,
  roomID: string,
): Promise<void> {
  const members = firestore.collection("Rooms").doc(roomID).collection("members");
  let hasMembers = true;
  while (hasMembers) {
    const snapshot = await members.orderBy("__name__").limit(MEMBER_BATCH_LIMIT).get();
    if (snapshot.empty) {
      hasMembers = false;
      continue;
    }
    const batch = firestore.batch();
    for (const document of snapshot.docs) {
      const uid = document.id;
      if (!validDocumentID(uid)) {
        batch.delete(document.ref);
        continue;
      }
      const user = firestore.collection("users").doc(uid);
      batch.delete(user.collection("joinedRooms").doc(roomID));
      batch.delete(user.collection("roomStates").doc(roomID));
      batch.delete(document.ref);
    }
    await batch.commit();
  }
}

async function removeOwnerMembership(
  firestore: Firestore,
  roomID: string,
  creatorUID: string,
): Promise<void> {
  const batch = firestore.batch();
  const user = firestore.collection("users").doc(creatorUID);
  batch.delete(user.collection("joinedRooms").doc(roomID));
  batch.delete(user.collection("roomStates").doc(roomID));
  batch.delete(firestore.collection("Rooms").doc(roomID).collection("members").doc(creatorUID));
  await batch.commit();
}

export async function processRoomCleanupJob(
  roomID: string,
  firestore: Firestore,
  buckets: CleanupBucketResolver,
  now = new Date(),
): Promise<boolean> {
  const reference = firestore.collection("moderationRoomCleanupJobs").doc(roomID);
  const job = await claimJob(reference, now);
  if (!job) return false;
  try {
    if (!validDocumentID(job.roomID) || job.roomID !== roomID ||
      (job.closureType !== "closedByOwner" && job.closureType !== "closedByModeration") ||
      typeof job.closureNoticeCode !== "string") {
      throw new Error("invalid_room_cleanup_target");
    }
    const roomRef = firestore.collection("Rooms").doc(roomID);
    const room = await roomRef.get();
    if (job.cleanupPhase === "retention") {
      if (room.exists) {
        await removeMemberships(firestore, roomID);
        await roomRef.delete();
      }
      await markCompleted(reference, now);
      return true;
    }
    if (room.exists) {
      const closedAt = room.get("closedAt") instanceof Timestamp ? room.get("closedAt") : Timestamp.fromDate(now);
      const creatorUID = room.get("creatorUID");
      if (!validDocumentID(creatorUID)) throw new Error("invalid_room_identity");
      if (job.closureType === "closedByOwner") {
        await removeOwnerMembership(firestore, roomID, creatorUID);
      }
      for (const subcollection of ["Messages", "mediaIndex", "MediaUploads", "bans"]) {
        await deleteCollection(roomRef.collection(subcollection));
      }
      for (const bucket of buckets.roomBuckets) {
        await bucket.deleteFiles({prefix: `rooms/${roomID}/`, force: true});
      }
      const createdAt = room.get("createdAt") instanceof Timestamp ? room.get("createdAt") : closedAt;
      const lastMessageAt = room.get("lastMessageAt") instanceof Timestamp ? room.get("lastMessageAt") : createdAt;
      const expiresAt = Timestamp.fromMillis(closedAt.toMillis() + ROOM_TOMBSTONE_TTL_MILLIS);
      const tombstone: Record<string, unknown> = {
        tombstoneSchemaVersion: 1,
        roomName: normalizedClosureRoomName(room.get("roomName")) ?? "채팅방",
        roomDescription: "",
        creatorUID,
        createdAt,
        lastMessageAt,
        memberCount: Math.max(0, Number(room.get("memberCount")) || 0),
        seq: Math.max(0, Number(room.get("seq")) || 0),
        isClosed: true,
        lifecycleStatus: job.closureType,
        lifecycleVersion: Number(job.lifecycleVersion) || 1,
        closureNoticeCode: job.closureNoticeCode,
        closedAt,
        expiresAt,
        updatedAt: Timestamp.fromDate(now),
      };
      await roomRef.set(tombstone);
      await markAwaitingExpiry(reference, expiresAt, now);
      return true;
    }
    await markCompleted(reference, now);
    return true;
  } catch (error) {
    console.error("[processRoomCleanupJob] cleanup failed", {roomID, error});
    await markRetry(reference, job.attempt, now);
    return false;
  }
}

export async function dueCleanupJobIDs(
  firestore: Firestore,
  collection: string,
  kind: CleanupKind,
  now = new Date(),
  limit = 25,
): Promise<string[]> {
  const snapshot = await firestore.collection(collection)
    .where("status", "in", ["pending", "retryPending", "processing", "awaitingExpiry"])
    .where("nextAttemptAt", "<=", Timestamp.fromDate(now))
    .orderBy("nextAttemptAt")
    .limit(limit)
    .get();
  return snapshot.docs.map((document) => kind === "room" ? document.get("roomID") : document.id)
    .filter(validDocumentID);
}
