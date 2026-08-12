/* eslint-disable require-jsdoc, max-len */
import {FieldValue} from "firebase-admin/firestore";
import {db, defaultStorageBucket} from "../core/firebase.js";
import {resolveRoomMembershipPage} from "../chat/moderation/roomMembershipSweep.js";

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

export async function scrubMessagePage(uid: string): Promise<boolean> {
  const [snapshot, roomPreviews] = await Promise.all([
    db.collectionGroup("Messages")
      .where("senderUID", "==", uid)
      .limit(30)
      .get(),
    db.collection("Rooms")
      .where("lastMessage.senderUID", "==", uid)
      .limit(PAGE_SIZE)
      .get(),
  ]);
  if (snapshot.empty && roomPreviews.empty) return true;

  const storagePaths: string[] = [];
  const messagePatches = new Map<string, {
    ref: FirebaseFirestore.DocumentReference;
    patch: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>;
  }>();
  for (const document of snapshot.docs) {
    const data = document.data();
    storagePaths.push(...attachmentStoragePaths(data.attachments));
    messagePatches.set(document.ref.path, {ref: document.ref, patch: {
      senderUID: FieldValue.delete(),
      senderEmail: FieldValue.delete(),
      senderNickname: "탈퇴한 사용자",
      senderAvatarPath: FieldValue.delete(),
      msg: "",
      message: "",
      attachments: [],
      sharedContent: FieldValue.delete(),
      replyPreview: null,
      isDeleted: true,
      deletionReason: "account_deleted",
    }});
  }
  const messageIDs = snapshot.docs.map((document) => document.id);
  for (let index = 0; index < messageIDs.length; index += 10) {
    const replySnapshots = await db.collectionGroup("Messages")
      .where("replyPreview.messageID", "in", messageIDs.slice(index, index + 10))
      .limit(PAGE_SIZE)
      .get();
    replySnapshots.docs.forEach((document) => {
      const existing = messagePatches.get(document.ref.path);
      const replyPreview = {
        messageID: document.data().replyPreview?.messageID ?? "",
        sender: "탈퇴한 사용자",
        text: "",
        imagesCount: 0,
        videosCount: 0,
        isDeleted: true,
      };
      if (existing) {
        existing.patch.replyPreview = replyPreview;
      } else {
        messagePatches.set(document.ref.path, {
          ref: document.ref,
          patch: {replyPreview},
        });
      }
    });
  }
  const batch = db.batch();
  for (const value of messagePatches.values()) {
    batch.update(value.ref, value.patch);
  }
  roomPreviews.docs.forEach((document) => batch.update(document.ref, {
    "lastMessage.senderUID": FieldValue.delete(),
    "lastMessage.senderEmail": FieldValue.delete(),
    "lastMessage.senderNickname": "탈퇴한 사용자",
    "lastMessage.senderAvatarPath": FieldValue.delete(),
    "lastMessage.msg": "",
    "lastMessage.message": "",
    "lastMessage.attachments": [],
    "lastMessage.sharedContent": FieldValue.delete(),
    "lastMessage.isDeleted": true,
  }));
  await deleteStoragePaths(storagePaths);
  await batch.commit();
  return snapshot.size < 30 && roomPreviews.size < PAGE_SIZE;
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

export async function resolveRoomPage(uid: string): Promise<boolean> {
  return resolveRoomMembershipPage(uid, "accountDeletion", new Date(), db);
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
