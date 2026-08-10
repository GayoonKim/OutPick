/* eslint-disable require-jsdoc, max-len */
import {
  DocumentReference,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

// 참여자마다 안내 1건과 projection 삭제 2건까지 발생하므로 batch 500 writes 안에 둔다.
const MEMBER_BATCH_LIMIT = 150;
const PAGE_LIMIT = 300;
const LEASE_MILLIS = 10 * 60 * 1000;
const COMPLETED_JOB_TTL_MILLIS = 7 * 24 * 60 * 60 * 1000;
const CLOSURE_NOTICE_TTL_MILLIS = 30 * 24 * 60 * 60 * 1000;
const MAX_ATTEMPTS = 20;

type CleanupKind = "message" | "room";
type RoomClosureType = "closedByOwner" | "closedByModeration";

type StorageBucket = {
  deleteFiles(options: {prefix: string; force: boolean}): Promise<unknown>;
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

export function shouldCreateClosureNotice(
  uid: string,
  creatorUID: string,
  closureType: RoomClosureType,
): boolean {
  return closureType === "closedByModeration" || uid !== creatorUID;
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
  bucket: StorageBucket,
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
    const prefixes = Array.isArray(job.storagePrefixes) ? job.storagePrefixes : [];
    for (const prefix of prefixes) {
      if (prefix !== expectedPrefix) throw new Error("storage_prefix_mismatch");
      await bucket.deleteFiles({prefix: `${prefix}/`, force: true});
    }
    await markCompleted(reference, now);
    return true;
  } catch (error) {
    console.error("[processMessageCleanupJob] cleanup failed", {jobID, error});
    await markRetry(reference, job.attempt, now);
    return false;
  }
}

async function loadRoomMembers(
  firestore: Firestore,
  roomID: string,
): Promise<string[]> {
  const members = firestore.collection("Rooms").doc(roomID).collection("members");
  const result: string[] = [];
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  let hasMore = true;
  while (hasMore) {
    let query = members.orderBy("__name__").limit(PAGE_LIMIT);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) break;
    for (const document of snapshot.docs) {
      if (validDocumentID(document.id)) result.push(document.id);
    }
    cursor = snapshot.docs.at(-1) ?? null;
    hasMore = snapshot.size === PAGE_LIMIT;
  }
  return [...new Set(result)];
}

async function createClosureNoticesAndRemoveProjections(
  firestore: Firestore,
  roomID: string,
  memberUIDs: string[],
  creatorUID: string,
  roomName: string | null,
  closureType: RoomClosureType,
  closureNoticeCode: string,
  closedAt: Timestamp,
): Promise<void> {
  for (let index = 0; index < memberUIDs.length; index += MEMBER_BATCH_LIMIT) {
    const batch = firestore.batch();
    for (const uid of memberUIDs.slice(index, index + MEMBER_BATCH_LIMIT)) {
      const user = firestore.collection("users").doc(uid);
      if (shouldCreateClosureNotice(uid, creatorUID, closureType)) {
        batch.set(user.collection("roomClosureNotices").doc(roomID), {
          schemaVersion: 2,
          roomID,
          ...(roomName ? {roomName} : {}),
          closureType,
          closureNoticeCode,
          closedAt,
          expiresAt: Timestamp.fromMillis(closedAt.toMillis() + CLOSURE_NOTICE_TTL_MILLIS),
        });
      }
      batch.delete(user.collection("joinedRooms").doc(roomID));
      batch.delete(user.collection("roomStates").doc(roomID));
    }
    await batch.commit();
  }
}

export async function processRoomCleanupJob(
  roomID: string,
  firestore: Firestore,
  bucket: StorageBucket,
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
    if (room.exists) {
      const closedAt = room.get("closedAt") instanceof Timestamp ? room.get("closedAt") : Timestamp.fromDate(now);
      const memberUIDs = await loadRoomMembers(firestore, roomID);
      const creatorUID = room.get("creatorUID");
      const roomName = normalizedClosureRoomName(room.get("roomName"));
      if (!validDocumentID(creatorUID)) throw new Error("invalid_room_identity");
      if (!memberUIDs.includes(creatorUID)) memberUIDs.push(creatorUID);
      await createClosureNoticesAndRemoveProjections(
        firestore,
        roomID,
        memberUIDs,
        creatorUID,
        roomName,
        job.closureType,
        job.closureNoticeCode,
        closedAt,
      );
      for (const subcollection of ["Messages", "mediaIndex", "MediaUploads", "members", "bans"]) {
        await deleteCollection(roomRef.collection(subcollection));
      }
      await bucket.deleteFiles({prefix: `rooms/${roomID}/`, force: true});
      await roomRef.delete();
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
    .where("status", "in", ["pending", "retryPending", "processing"])
    .where("nextAttemptAt", "<=", Timestamp.fromDate(now))
    .orderBy("nextAttemptAt")
    .limit(limit)
    .get();
  return snapshot.docs.map((document) => kind === "room" ? document.get("roomID") : document.id)
    .filter(validDocumentID);
}
