import { randomUUID } from "node:crypto";
import { normalizeUID } from "../utils/strings.js";

const WRITE_BATCH_LIMIT = 400;
const MEMBER_PAGE_LIMIT = 500;
const ROOM_SUBCOLLECTIONS = [
  "Messages",
  "mediaIndex",
  "MediaUploads",
  "members"
];

async function deleteSnapshotDocs(db, docs) {
  if (!docs.length) return 0;

  let deleted = 0;
  for (let i = 0; i < docs.length; i += WRITE_BATCH_LIMIT) {
    const batch = db.batch();
    const slice = docs.slice(i, i + WRITE_BATCH_LIMIT);
    for (const doc of slice) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    deleted += slice.length;
  }
  return deleted;
}

async function deleteCollectionPageByPage(collectionRef) {
  let deleted = 0;

  while (true) {
    const snapshot = await collectionRef.limit(WRITE_BATCH_LIMIT).get();
    if (snapshot.empty) return deleted;
    deleted += await deleteSnapshotDocs(collectionRef.firestore, snapshot.docs);
  }
}

async function loadMemberUIDs(roomRef) {
  const memberUIDs = [];
  let query = roomRef
    .collection("members")
    .orderBy("__name__")
    .limit(MEMBER_PAGE_LIMIT);

  while (true) {
    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const doc of snapshot.docs) {
      const uid = normalizeUID(doc.id);
      if (uid && !uid.includes("/")) {
        memberUIDs.push(uid);
      }
    }

    if (snapshot.size < MEMBER_PAGE_LIMIT) break;
    query = roomRef
      .collection("members")
      .orderBy("__name__")
      .startAfter(snapshot.docs[snapshot.docs.length - 1])
      .limit(MEMBER_PAGE_LIMIT);
  }

  return [...new Set(memberUIDs)];
}

async function deleteUserRoomState({ db, roomID, userUIDs }) {
  let deletedUsers = 0;
  const uniqueUIDs = [...new Set(userUIDs.map(normalizeUID).filter(Boolean))]
    .filter((uid) => !uid.includes("/"));

  for (let i = 0; i < uniqueUIDs.length; i += WRITE_BATCH_LIMIT) {
    const batch = db.batch();
    const slice = uniqueUIDs.slice(i, i + WRITE_BATCH_LIMIT);
    for (const uid of slice) {
      const userRef = db.collection("users").doc(uid);
      batch.delete(userRef.collection("joinedRooms").doc(roomID));
      batch.delete(userRef.collection("roomStates").doc(roomID));
    }
    await batch.commit();
    deletedUsers += slice.length;
  }

  return deletedUsers;
}

async function deleteRoomStoragePrefix({ admin, roomID }) {
  const bucket = admin.storage().bucket();
  await bucket.deleteFiles({
    prefix: `rooms/${roomID}/`,
    force: true
  });
}

export function createRoomCleanup({ db, admin }) {
  async function leaveRoomMembership({ roomID, userUID }) {
    const normalizedUID = normalizeUID(userUID);
    if (!normalizedUID || normalizedUID.includes("/")) {
      return { ok: false, error: "unauthenticated" };
    }

    const roomRef = db.collection("Rooms").doc(roomID);
    const memberRef = roomRef.collection("members").doc(normalizedUID);
    const memberSnap = await memberRef.get();
    if (!memberSnap.exists) {
      return { ok: false, error: "not_joined" };
    }

    const batch = db.batch();
    batch.delete(memberRef);
    batch.delete(
      db.collection("users")
        .doc(normalizedUID)
        .collection("joinedRooms")
        .doc(roomID)
    );
    batch.delete(
      db.collection("users")
        .doc(normalizedUID)
        .collection("roomStates")
        .doc(roomID)
    );
    batch.set(roomRef, {
      memberCount: admin.firestore.FieldValue.increment(-1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    await batch.commit();
    return { ok: true };
  }

  async function closeRoomImmediately({ roomID, closedByUID }) {
    const normalizedUID = normalizeUID(closedByUID);
    if (!normalizedUID || normalizedUID.includes("/")) {
      return { ok: false, error: "unauthenticated" };
    }

    const roomRef = db.collection("Rooms").doc(roomID);
    const roomSnap = await roomRef.get();
    if (!roomSnap.exists) {
      return { ok: true, alreadyDeleted: true, memberUIDs: [] };
    }

    const roomData = roomSnap.data() || {};
    const creatorUID = normalizeUID(roomData.creatorUID);
    if (!creatorUID || creatorUID !== normalizedUID) {
      return { ok: false, error: "not_owner" };
    }

    const result = await db.runTransaction(async (transaction) => {
      const current = await transaction.get(roomRef);
      if (!current.exists) return { alreadyDeleted: true, lifecycleVersion: null };
      const data = current.data() || {};
      if (normalizeUID(data.creatorUID) !== normalizedUID) {
        return { error: "not_owner" };
      }
      if (data.isClosed === true ||
          (data.lifecycleStatus && data.lifecycleStatus !== "active")) {
        return {
          alreadyDeleted: false,
          lifecycleVersion: Number(data.lifecycleVersion || 1)
        };
      }
      const currentVersion = Number.isSafeInteger(data.lifecycleVersion) &&
        data.lifecycleVersion > 0 ? data.lifecycleVersion : 1;
      const lifecycleVersion = currentVersion + 1;
      const now = admin.firestore.Timestamp.now();
      const jobRef = db.collection("moderationRoomCleanupJobs").doc(roomID);
      transaction.update(roomRef, {
        isClosed: true,
        lifecycleStatus: "closedByOwner",
        lifecycleVersion,
        closedAt: now,
        closureNoticeCode: "ownerDeleted",
        updatedAt: now
      });
      transaction.set(jobRef, {
        schemaVersion: 1,
        roomID,
        lifecycleVersion,
        closureType: "closedByOwner",
        closureNoticeCode: "ownerDeleted",
        legacySocketRequestID: randomUUID(),
        status: "pending",
        attempt: 0,
        nextAttemptAt: now,
        leaseExpiresAt: null,
        lastErrorCode: null,
        createdAt: now,
        updatedAt: now,
        expiresAt: null
      }, { merge: false });
      return { alreadyDeleted: false, lifecycleVersion };
    });
    if (result.error) return { ok: false, error: result.error };
    return {
      ok: true,
      alreadyDeleted: result.alreadyDeleted === true,
      lifecycleVersion: result.lifecycleVersion,
      cleanupStatus: "pending"
    };
  }

  return {
    closeRoomImmediately,
    leaveRoomMembership
  };
}
