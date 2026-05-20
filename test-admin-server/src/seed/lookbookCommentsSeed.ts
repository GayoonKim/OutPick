import type {Auth} from "firebase-admin/auth";
import {Timestamp, type Firestore} from "firebase-admin/firestore";
import {
  commentStateDocumentID,
  lookbookTestEmails,
  lookbookTestIDs,
  markerFields,
  upsertAuthUser,
  userProfileDocument
} from "./lookbookSeedSupport.js";
import {
  seedLookbookBasic,
  type LookbookBasicSeedRequest
} from "./lookbookBasicSeed.js";

const representativeCommentID = "uitest-comment-representative";
const pinnedCommentID = "uitest-comment-pinned";
const replyID = "uitest-reply-representative-1";

export interface LookbookCommentsSeedResult {
  readonly brandID: string;
  readonly seasonID: string;
  readonly postID: string;
  readonly rootCommentIDs: string[];
  readonly replyIDs: string[];
  readonly userIDs: string[];
  readonly authUserEmails: string[];
  readonly commentUserStateIDs: string[];
  readonly commentCount: number;
  readonly testRunId?: string;
}

export async function seedLookbookComments(
  firestore: Firestore,
  auth: Auth,
  password: string,
  request: LookbookBasicSeedRequest
): Promise<LookbookCommentsSeedResult> {
  await seedLookbookBasic(firestore, auth, password, request);

  const {
    brandID,
    seasonID,
    postID,
    currentUserID,
    commenterUserID,
    replierUserID
  } = lookbookTestIDs;
  const {
    commenterUserEmail,
    replierUserEmail
  } = lookbookTestEmails;
  const marker = markerFields(request.testRunId);

  await upsertAuthUser(
    auth,
    commenterUserID,
    commenterUserEmail,
    password,
    "UI 테스트 댓글러"
  );
  await upsertAuthUser(
    auth,
    replierUserID,
    replierUserEmail,
    password,
    "UI 테스트 답글러"
  );

  await firestore.collection("users").doc(commenterUserID).set({
    ...userProfileDocument(commenterUserEmail, "UI 테스트 댓글러"),
    ...marker
  }, {merge: true});

  await firestore.collection("users").doc(replierUserID).set({
    ...userProfileDocument(replierUserEmail, "UI 테스트 답글러"),
    ...marker
  }, {merge: true});

  const createdAt = {
    pinned: Timestamp.fromDate(new Date("2026-05-20T00:01:00.000Z")),
    representative: Timestamp.fromDate(new Date("2026-05-20T00:02:00.000Z")),
    reply: Timestamp.fromDate(new Date("2026-05-20T00:03:00.000Z"))
  };
  const postRef = firestore
    .collection("brands")
    .doc(brandID)
    .collection("seasons")
    .doc(seasonID)
    .collection("posts")
    .doc(postID);
  const commentsRef = postRef.collection("comments");
  const commentUserStateRef = firestore
    .collection("users")
    .doc(currentUserID)
    .collection("commentStates")
    .doc(commentStateDocumentID(representativeCommentID));

  const batch = firestore.batch();

  batch.set(commentsRef.doc(pinnedCommentID), {
    postID,
    userID: commenterUserID,
    createdBy: commenterUserID,
    message: "고정 댓글 테스트 데이터",
    createdAt: createdAt.pinned,
    updatedAt: createdAt.pinned,
    isDeleted: false,
    likeCount: 1,
    replyCount: 0,
    isPinned: true,
    pinnedAt: createdAt.pinned,
    pinnedBy: lookbookTestIDs.authorUserID,
    parentCommentID: null,
    attachments: [],
    ...marker
  }, {merge: true});

  batch.set(commentsRef.doc(representativeCommentID), {
    postID,
    userID: commenterUserID,
    createdBy: commenterUserID,
    message: "대표 댓글 테스트 데이터",
    createdAt: createdAt.representative,
    updatedAt: createdAt.representative,
    isDeleted: false,
    likeCount: 5,
    replyCount: 1,
    isPinned: false,
    pinnedAt: null,
    pinnedBy: null,
    parentCommentID: null,
    attachments: [],
    ...marker
  }, {merge: true});

  batch.set(commentsRef.doc(replyID), {
    postID,
    userID: replierUserID,
    createdBy: replierUserID,
    message: "대표 댓글 답글 테스트 데이터",
    createdAt: createdAt.reply,
    updatedAt: createdAt.reply,
    isDeleted: false,
    likeCount: 0,
    replyCount: 0,
    isPinned: false,
    pinnedAt: null,
    pinnedBy: null,
    parentCommentID: representativeCommentID,
    attachments: [],
    ...marker
  }, {merge: true});

  batch.set(commentUserStateRef, {
    commentID: representativeCommentID,
    userID: currentUserID,
    isLiked: true,
    updatedAt: createdAt.reply,
    ...marker
  }, {merge: true});

  batch.set(postRef, {
    metrics: {
      likeCount: 3,
      commentCount: 3,
      replacementCount: 0,
      saveCount: 1,
      viewCount: 10
    },
    metricsUpdatedAt: createdAt.reply,
    updatedAt: createdAt.reply,
    ...marker
  }, {merge: true});

  await batch.commit();

  return {
    brandID,
    seasonID,
    postID,
    rootCommentIDs: [pinnedCommentID, representativeCommentID],
    replyIDs: [replyID],
    userIDs: [commenterUserID, replierUserID],
    authUserEmails: [commenterUserEmail, replierUserEmail],
    commentUserStateIDs: [commentUserStateRef.id],
    commentCount: 3,
    testRunId: request.testRunId
  };
}
