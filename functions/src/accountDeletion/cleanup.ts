/* eslint-disable require-jsdoc, max-len */
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {db, defaultStorageBucket} from "../core/firebase.js";
import {
  applyRoomMessageDeletionBatchMutation,
  DELETED_MESSAGE_PREVIEW,
  MessageDeletionTarget,
  messageCleanupJobID,
} from "../chat/deletion/mutation.js";
import {accountDeletionSuccessionJobID} from "../chat/moderation/roomMembershipSweep.js";
import {messageIncidentID} from "../moderation/messageEvidence/contracts.js";

const PAGE_SIZE = 100;
// 연관 컬렉션은 한 번에 여러 쿼리 결과를 단일 batch로 합치므로
// Firestore의 500 write 제한 안에 항상 머물도록 쿼리별 크기를 낮춘다.
const ASSOCIATION_PAGE_SIZE = 40;

function nonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim() : null;
}

async function deleteStoragePaths(paths: Iterable<string>): Promise<void> {
  const bucket = defaultStorageBucket();
  for (const path of new Set(paths)) {
    try {
      await bucket.file(path).delete();
    } catch (error) {
      const code = (error as {code?: number | string})?.code;
      if (code !== 404 && code !== "404") throw error;
    }
  }
}

function attachmentStoragePaths(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const paths: string[] = [];
  for (const item of value) {
    if (!item || typeof item !== "object" || Array.isArray(item)) continue;
    const record = item as Record<string, unknown>;
    for (const key of [
      "thumbPath",
      "detailPath",
      "originalPath",
      "pathThumb",
      "pathOriginal",
      "storagePath",
    ]) {
      const path = nonEmptyString(record[key]);
      if (path) paths.push(path);
    }
  }
  return paths;
}

export async function removePublicIdentity(uid: string): Promise<boolean> {
  const profileRef = db.collection("userPublicProfiles").doc(uid);
  const [profileSnapshot, nicknameSnapshot] = await Promise.all([
    profileRef.get(),
    db.collection("nicknameIndex").where("uid", "==", uid).limit(PAGE_SIZE).get(),
  ]);
  const profileData = profileSnapshot.data();
  const paths = [
    nonEmptyString(profileData?.avatarThumbPath),
    nonEmptyString(profileData?.avatarOriginalPath),
  ].filter((path): path is string => path !== null);
  await deleteStoragePaths(paths);

  const batch = db.batch();
  nicknameSnapshot.docs.forEach((document) => batch.delete(document.ref));
  if (profileSnapshot.exists) batch.delete(profileRef);
  if (nicknameSnapshot.size > 0 || profileSnapshot.exists) await batch.commit();
  return nicknameSnapshot.size < PAGE_SIZE;
}

async function removeEngagementState(
  state: FirebaseFirestore.QueryDocumentSnapshot,
): Promise<void> {
  const data = state.data();
  let targetPath: string | null = null;
  let patch: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> | null =
    null;
  if (state.ref.parent.id === "brandStates") {
    const brandID = nonEmptyString(data.brandID) ?? state.id;
    targetPath = `brands/${brandID}`;
    patch = {
      likeCount: FieldValue.increment(-1),
      updatedAt: FieldValue.serverTimestamp(),
    };
  } else if (state.ref.parent.id === "seasonStates") {
    targetPath = nonEmptyString(data.seasonPath) ??
      (nonEmptyString(data.brandID) && nonEmptyString(data.seasonID) ?
        `brands/${data.brandID}/seasons/${data.seasonID}` : null);
    patch = {
      likeCount: FieldValue.increment(-1),
      updatedAt: FieldValue.serverTimestamp(),
    };
  } else if (state.ref.parent.id === "postStates") {
    targetPath = nonEmptyString(data.postPath);
    patch = {
      ...(data.isLiked === true ?
        {"metrics.likeCount": FieldValue.increment(-1)} : {}),
      ...(data.isSaved === true ?
        {"metrics.saveCount": FieldValue.increment(-1)} : {}),
      metricsUpdatedAt: FieldValue.serverTimestamp(),
    };
  } else if (state.ref.parent.id === "commentStates") {
    targetPath = nonEmptyString(data.commentPath);
    patch = {
      likeCount: FieldValue.increment(-1),
      updatedAt: FieldValue.serverTimestamp(),
    };
  }

  await db.runTransaction(async (transaction) => {
    const currentState = await transaction.get(state.ref);
    if (!currentState.exists) return;
    if (targetPath && patch) {
      const targetRef = db.doc(targetPath);
      const target = await transaction.get(targetRef);
      if (target.exists) transaction.update(targetRef, patch);
    }
    transaction.delete(state.ref);
  });
}

export async function removeEngagementPage(uid: string): Promise<boolean> {
  const userRef = db.collection("users").doc(uid);
  const snapshots = await Promise.all([
    userRef.collection("brandStates").limit(25).get(),
    userRef.collection("seasonStates").limit(25).get(),
    userRef.collection("postStates").limit(25).get(),
    userRef.collection("commentStates").limit(25).get(),
  ]);
  for (const snapshot of snapshots) {
    for (const state of snapshot.docs) await removeEngagementState(state);
  }
  return snapshots.every((snapshot) => snapshot.size < 25);
}

export async function scrubCommentPage(uid: string): Promise<boolean> {
  const snapshot = await db
    .collectionGroup("comments")
    .where("userID", "==", uid)
    .limit(PAGE_SIZE)
    .get();
  if (snapshot.empty) return true;

  const postCounts = new Map<string, {
    ref: FirebaseFirestore.DocumentReference;
    count: number;
  }>();
  const parentCounts = new Map<string, {
    ref: FirebaseFirestore.DocumentReference;
    count: number;
  }>();
  const storagePaths: string[] = [];
  const commentPatches = new Map<string, {
    ref: FirebaseFirestore.DocumentReference;
    patch: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>;
  }>();

  for (const document of snapshot.docs) {
    const data = document.data();
    storagePaths.push(...attachmentStoragePaths(data.attachments));
    commentPatches.set(document.ref.path, {ref: document.ref, patch: {
      userID: FieldValue.delete(),
      createdBy: FieldValue.delete(),
      message: "",
      attachments: [],
      isDeleted: true,
      pinnedBy: FieldValue.delete(),
      pinnedAt: null,
      updatedAt: FieldValue.serverTimestamp(),
      deletionReason: "account_deleted",
    }});
    const postRef = document.ref.parent.parent;
    if (postRef) {
      const key = postRef.path;
      const existing = postCounts.get(key);
      postCounts.set(key, {ref: postRef, count: (existing?.count ?? 0) + 1});
      const parentID = nonEmptyString(data.parentCommentID);
      if (parentID) {
        const parentRef = document.ref.parent.doc(parentID);
        const parentKey = parentRef.path;
        const parent = parentCounts.get(parentKey);
        parentCounts.set(parentKey, {
          ref: parentRef,
          count: (parent?.count ?? 0) + 1,
        });
      }
    }
  }
  for (const value of parentCounts.values()) {
    const authoredParent = commentPatches.get(value.ref.path);
    if (authoredParent) {
      authoredParent.patch.replyCount = FieldValue.increment(-value.count);
    } else {
      commentPatches.set(value.ref.path, {ref: value.ref, patch: {
        replyCount: FieldValue.increment(-value.count),
        updatedAt: FieldValue.serverTimestamp(),
      }});
    }
  }

  const batch = db.batch();
  for (const value of commentPatches.values()) {
    batch.update(value.ref, value.patch);
  }
  for (const value of postCounts.values()) {
    batch.update(value.ref, {
      "metrics.commentCount": FieldValue.increment(-value.count),
      "metricsUpdatedAt": FieldValue.serverTimestamp(),
    });
  }
  await deleteStoragePaths(storagePaths);
  await batch.commit();
  return snapshot.size < PAGE_SIZE;
}

async function scrubMessageRoomBatch(
  uid: string,
  accountDeletionRequestID: string,
  accountGenerationID: string,
  documents: FirebaseFirestore.QueryDocumentSnapshot[],
  now: Timestamp,
): Promise<void> {
  const first = documents[0];
  const roomRef = first?.ref.parent.parent;
  if (!roomRef || documents.some((document) => document.ref.parent.parent?.path !== roomRef.path)) {
    throw new Error("account_deletion_message_room_mismatch");
  }
  const userRef = db.collection("users").doc(uid);
  await db.runTransaction(async (transaction) => {
    const messageRefs = documents.map((document) => document.ref);
    const cleanupRefs = documents.map((document) =>
      db.collection("chatMessageCleanupJobs").doc(messageCleanupJobID(roomRef.id, document.id)));
    const guardRefs = documents.map((document) =>
      db.collection("moderationMessageGuards").doc(messageIncidentID(roomRef.id, document.id)));
    const [room, user, messages, cleanups, guards] = await Promise.all([
      transaction.get(roomRef),
      transaction.get(userRef),
      Promise.all(messageRefs.map((reference) => transaction.get(reference))),
      Promise.all(cleanupRefs.map((reference) => transaction.get(reference))),
      Promise.all(guardRefs.map((reference) => transaction.get(reference))),
    ]);
    if (!user.exists || user.get("accountStatus") !== "deletionPending" ||
        user.get("accountGenerationID") !== accountGenerationID) {
      throw new Error("account_deletion_fence_lost");
    }
    const targets: MessageDeletionTarget[] = [];
    messages.forEach((message, index) => {
      if (!message.exists || message.get("senderUID") !== uid) return;
      targets.push({
        messageRef: messageRefs[index],
        message,
        cleanupRef: cleanupRefs[index],
        cleanup: cleanups[index],
        guardRef: guardRefs[index],
        guard: guards[index],
      });
    });
    if (targets.length === 0) return;
    applyRoomMessageDeletionBatchMutation(
      transaction,
      db,
      roomRef,
      room,
      targets,
      roomRef.id,
      now,
      accountDeletionRequestID,
    );
  });
}

export async function scrubMessagePage(
  uid: string,
  accountDeletionRequestID: string,
  accountGenerationID: string,
  now = new Date(),
): Promise<boolean> {
  const [snapshot, roomPreviews, roleEvents] = await Promise.all([
    db.collectionGroup("Messages")
      .where("senderUID", "==", uid)
      .limit(30)
      .get(),
    db.collection("Rooms")
      .where("lastMessage.senderUID", "==", uid)
      .limit(PAGE_SIZE)
      .get(),
    db.collectionGroup("Messages")
      .where("roleEvent.subjectUID", "==", uid)
      .limit(30)
      .get(),
  ]);
  if (snapshot.empty && roomPreviews.empty && roleEvents.empty) return true;
  const byRoom = new Map<string, FirebaseFirestore.QueryDocumentSnapshot[]>();
  for (const document of snapshot.docs) {
    const roomRef = document.ref.parent.parent;
    if (!roomRef) throw new Error("account_deletion_message_room_missing");
    const existing = byRoom.get(roomRef.path) ?? [];
    existing.push(document);
    byRoom.set(roomRef.path, existing);
  }
  const nowTimestamp = Timestamp.fromDate(now);
  for (const documents of byRoom.values()) {
    await scrubMessageRoomBatch(
      uid,
      accountDeletionRequestID,
      accountGenerationID,
      documents,
      nowTimestamp,
    );
  }
  if (!roomPreviews.empty) {
    const user = await db.collection("users").doc(uid).get();
    if (!user.exists || user.get("accountStatus") !== "deletionPending" ||
        user.get("accountGenerationID") !== accountGenerationID) {
      throw new Error("account_deletion_fence_lost");
    }
    const batch = db.batch();
    roomPreviews.docs.forEach((document) => batch.set(document.ref, {
      lastMessage: DELETED_MESSAGE_PREVIEW,
      updatedAt: nowTimestamp,
    }, {merge: true}));
    await batch.commit();
  }
  if (!roleEvents.empty) {
    const user = await db.collection("users").doc(uid).get();
    if (!user.exists || user.get("accountStatus") !== "deletionPending" ||
        user.get("accountGenerationID") !== accountGenerationID) {
      throw new Error("account_deletion_fence_lost");
    }
    const batch = db.batch();
    roleEvents.docs.forEach((document) => {
      const roomRef = document.ref.parent.parent;
      if (!roomRef) throw new Error("account_deletion_role_event_room_missing");
      batch.update(document.ref, {
        "roleEvent.subjectUID": FieldValue.delete(),
        "roleEvent.subjectNicknameSnapshot": "알 수 없는 사용자",
      });
      const outboxRef = db.collection("chatRoleEventDeliveryJobs")
        .doc(`${document.id}-privacy`);
      batch.create(outboxRef, {
        schemaVersion: 1,
        roomID: roomRef.id,
        eventID: document.id,
        seq: document.get("seq"),
        status: "pending",
        attempt: 0,
        nextAttemptAt: nowTimestamp,
        leaseOwner: null,
        leaseExpiresAt: null,
        lastErrorCode: null,
        createdAt: nowTimestamp,
        updatedAt: nowTimestamp,
        expiresAt: null,
      });
    });
    await batch.commit();
  }
  return snapshot.size < 30 && roomPreviews.size < PAGE_SIZE && roleEvents.size < 30;
}

export async function hasIncompleteAccountDeletionMessageCleanup(
  accountDeletionRequestID: string,
): Promise<boolean> {
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  let hasMore = true;
  while (hasMore) {
    let query = db.collection("chatMessageCleanupJobs")
      .where("accountDeletionRequestID", "==", accountDeletionRequestID)
      .orderBy("__name__")
      .limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.docs.some((document) => document.get("status") !== "completed")) {
      return true;
    }
    hasMore = snapshot.size === PAGE_SIZE;
    cursor = snapshot.docs.at(-1) ?? null;
  }
  return false;
}

async function activeUserIDs(userIDs: string[]): Promise<Set<string>> {
  if (userIDs.length === 0) return new Set();
  const snapshots = await db.getAll(
    ...userIDs.map((uid) => db.collection("users").doc(uid)),
  );
  return new Set(snapshots
    .filter((snapshot) => snapshot.exists && snapshot.data()?.accountStatus === "active")
    .map((snapshot) => snapshot.id));
}

export async function resolveRoomPage(accountDeletionRequestID: string): Promise<boolean> {
  const job = await db.collection("roomOwnershipSuccessionJobs")
    .doc(accountDeletionSuccessionJobID(accountDeletionRequestID))
    .get();
  if (!job.exists) throw new Error("room_succession_job_missing");
  if (job.get("status") === "failed") throw new Error("room_succession_failed");
  return job.get("status") === "completed" && job.get("result") === "resolved";
}

export async function removeRolePage(uid: string): Promise<boolean> {
  const managerSnapshot = await db
    .collectionGroup("admins")
    .where("uid", "==", uid)
    .limit(25)
    .get();

  for (const manager of managerSnapshot.docs) {
    const brandRef = manager.ref.parent.parent;
    if (!brandRef) continue;
    let successor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
    if (manager.data().role === "owner") {
      const candidates = await brandRef.collection("admins").get();
      const adminDocs = candidates.docs
        .filter((candidate) =>
          candidate.id !== uid && candidate.data().role === "admin")
        .sort((lhs, rhs) => {
          const left = lhs.data().addedAt?.toMillis?.() ?? Number.MAX_SAFE_INTEGER;
          const right = rhs.data().addedAt?.toMillis?.() ?? Number.MAX_SAFE_INTEGER;
          return left === right ? lhs.id.localeCompare(rhs.id) : left - right;
        });
      const active = await activeUserIDs(adminDocs.map((document) => document.id));
      successor = adminDocs.find((document) => active.has(document.id));
    }
    await db.runTransaction(async (transaction) => {
      const currentManager = await transaction.get(manager.ref);
      if (!currentManager.exists) return;
      if (currentManager.data()?.role === "owner") {
        if (successor) {
          const currentSuccessor = await transaction.get(successor.ref);
          if (!currentSuccessor.exists || currentSuccessor.data()?.role !== "admin") {
            throw new Error("brand_owner_successor_changed");
          }
          transaction.set(successor.ref, {
            role: "owner",
            updatedBy: "account-deletion-worker",
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
          transaction.set(brandRef, {
            ownerless: false,
            ownerlessAt: FieldValue.delete(),
            updatedBy: "account-deletion-worker",
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        } else {
          transaction.set(brandRef, {
            ownerless: true,
            ownerlessAt: FieldValue.serverTimestamp(),
            updatedBy: "account-deletion-worker",
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        }
      }
      transaction.delete(manager.ref);
    });
  }
  await db.collection("brandAdmins").doc(uid).delete();
  return managerSnapshot.size < 25;
}

export async function scrubAssociationPage(uid: string): Promise<boolean> {
  const [
    blocked,
    requestedReports,
    targetReports,
    brandRequests,
    deletionRequests,
    deletionAudits,
    createdBrands,
    updatedBrands,
  ] = await Promise.all([
    db.collectionGroup("blockedUsers")
      .where("blockedUserID", "==", uid).limit(ASSOCIATION_PAGE_SIZE).get(),
    db.collection("commentReports")
      .where("reporterUserID", "==", uid).limit(ASSOCIATION_PAGE_SIZE).get(),
    db.collection("commentReports")
      .where("targetAuthorID", "==", uid).limit(ASSOCIATION_PAGE_SIZE).get(),
    db.collection("brandRequests")
      .where("requesterUID", "==", uid).limit(ASSOCIATION_PAGE_SIZE).get(),
    db.collection("lookbookDeletionRequests")
      .where("requestedBy", "==", uid).limit(ASSOCIATION_PAGE_SIZE).get(),
    db.collection("lookbookDeletionAuditLogs")
      .where("actorUID", "==", uid).limit(ASSOCIATION_PAGE_SIZE).get(),
    db.collection("brands")
      .where("createdBy", "==", uid).limit(ASSOCIATION_PAGE_SIZE).get(),
    db.collection("brands")
      .where("updatedBy", "==", uid).limit(ASSOCIATION_PAGE_SIZE).get(),
  ]);
  const patches = new Map<string, {
    ref: FirebaseFirestore.DocumentReference;
    patch: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>;
  }>();
  const mergePatch = (
    ref: FirebaseFirestore.DocumentReference,
    patch: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>,
  ) => {
    const existing = patches.get(ref.path);
    if (existing) Object.assign(existing.patch, patch);
    else patches.set(ref.path, {ref, patch});
  };
  requestedReports.docs.forEach((document) => mergePatch(document.ref, {
    reporterUserID: FieldValue.delete(),
    detail: "",
    updatedAt: FieldValue.serverTimestamp(),
  }));
  targetReports.docs.forEach((document) => mergePatch(document.ref, {
    targetAuthorID: FieldValue.delete(),
    targetContentSnapshot: "",
    targetAuthorNicknameSnapshot: "",
    updatedAt: FieldValue.serverTimestamp(),
  }));
  brandRequests.docs.forEach((document) => mergePatch(document.ref, {
    requesterUID: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  }));
  deletionRequests.docs.forEach((document) => mergePatch(document.ref, {
    requestedBy: "deleted-user",
    updatedBy: document.data().updatedBy === uid ?
      "deleted-user" : document.data().updatedBy,
    updatedAt: FieldValue.serverTimestamp(),
  }));
  deletionAudits.docs.forEach((document) => mergePatch(document.ref, {
    actorUID: FieldValue.delete(),
  }));
  createdBrands.docs.forEach((document) => mergePatch(document.ref, {
    createdBy: "deleted-user",
    updatedAt: FieldValue.serverTimestamp(),
  }));
  updatedBrands.docs.forEach((document) => mergePatch(document.ref, {
    updatedBy: "deleted-user",
    updatedAt: FieldValue.serverTimestamp(),
  }));

  const batch = db.batch();
  blocked.docs.forEach((document) => batch.delete(document.ref));
  for (const value of patches.values()) batch.update(value.ref, value.patch);
  batch.delete(db.collection("brandRequestUserLimits").doc(uid));
  await batch.commit();
  await db.recursiveDelete(db.collection("brandRequestDailyCounters").doc(uid));
  return [
    blocked,
    requestedReports,
    targetReports,
    brandRequests,
    deletionRequests,
    deletionAudits,
    createdBrands,
    updatedBrands,
  ].every((snapshot) => snapshot.size < ASSOCIATION_PAGE_SIZE);
}

export async function removePrivateState(uid: string): Promise<void> {
  await Promise.all([
    db.recursiveDelete(db.collection("users").doc(uid)),
    db.collection("moderationAccounts").doc(uid).delete(),
  ]);
}

export async function hasRemainingUIDReferences(uid: string): Promise<boolean> {
  const [
    comments,
    messages,
    members,
    managers,
    profile,
    totalAdmin,
    blocked,
    reportsBy,
    reportsTarget,
    brandRequests,
    deletionRequests,
    deletionAudits,
    createdBrands,
    updatedBrands,
    privateUser,
  ] =
    await Promise.all([
      db.collectionGroup("comments").where("userID", "==", uid).limit(1).get(),
      db.collectionGroup("Messages").where("senderUID", "==", uid).limit(1).get(),
      db.collectionGroup("members").where("userID", "==", uid).limit(1).get(),
      db.collectionGroup("admins").where("uid", "==", uid).limit(1).get(),
      db.collection("userPublicProfiles").doc(uid).get(),
      db.collection("brandAdmins").doc(uid).get(),
      db.collectionGroup("blockedUsers")
        .where("blockedUserID", "==", uid).limit(1).get(),
      db.collection("commentReports")
        .where("reporterUserID", "==", uid).limit(1).get(),
      db.collection("commentReports")
        .where("targetAuthorID", "==", uid).limit(1).get(),
      db.collection("brandRequests")
        .where("requesterUID", "==", uid).limit(1).get(),
      db.collection("lookbookDeletionRequests")
        .where("requestedBy", "==", uid).limit(1).get(),
      db.collection("lookbookDeletionAuditLogs")
        .where("actorUID", "==", uid).limit(1).get(),
      db.collection("brands").where("createdBy", "==", uid).limit(1).get(),
      db.collection("brands").where("updatedBy", "==", uid).limit(1).get(),
      db.collection("users").doc(uid).get(),
    ]);
  return !comments.empty ||
    !messages.empty ||
    !members.empty ||
    !managers.empty ||
    profile.exists ||
    totalAdmin.exists ||
    !blocked.empty ||
    !reportsBy.empty ||
    !reportsTarget.empty ||
    !brandRequests.empty ||
    !deletionRequests.empty ||
    !deletionAudits.empty ||
    !createdBrands.empty ||
    !updatedBrands.empty ||
    privateUser.exists;
}
