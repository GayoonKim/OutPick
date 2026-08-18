/* eslint-disable require-jsdoc, max-len */
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../../core/firebase.js";
import {requireAccountCapabilityData} from "../../shared/accountStatus.js";
import {
  COMMENT_WRITE_BUCKET_TTL_MILLIS,
  COMMENT_WRITE_SCHEMA_VERSION,
  CommentWriteOperation,
  CreateCommentInput,
  assertCommentWriteCapacity,
  commentWriteDocumentID,
  commentWriteMinuteBucket,
  commentWriteRateBucketID,
} from "./contracts.js";

export type CommentMutationReceipt = {
  brandID: string;
  seasonID: string;
  postID: string;
  commentID: string;
  userID: string;
  parentCommentID: string | null;
  commentCount: number;
  replyCount: number;
  deduplicated: boolean;
};

function integerValue(value: unknown): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ?
    value : 0;
}

function postMetrics(data: FirebaseFirestore.DocumentData | undefined): {
  commentCount: number;
} {
  const metrics = data?.metrics && typeof data.metrics === "object" &&
    !Array.isArray(data.metrics) ? data.metrics as Record<string, unknown> : {};
  return {commentCount: integerValue(metrics.commentCount)};
}

function principalID(data: FirebaseFirestore.DocumentData): string {
  const value = data.moderationPrincipalID;
  if (typeof value !== "string" || value.trim().length === 0 || value.includes("/")) {
    throw new HttpsError(
      "failed-precondition",
      "안전 계정 연결 정보를 확인할 수 없습니다.",
    );
  }
  return value.trim();
}

function assertExistingMatches(
  data: FirebaseFirestore.DocumentData | undefined,
  uid: string,
  input: CreateCommentInput,
): void {
  if (!data || data.userID !== uid || data.createdBy !== uid ||
    (data.parentCommentID ?? null) !== input.parentCommentID ||
    data.message !== input.message) {
    throw new HttpsError(
      "already-exists",
      "같은 clientRequestID가 다른 댓글 요청에 사용됐습니다.",
      {errorCode: "IDEMPOTENCY_CONFLICT"},
    );
  }
}

function assertParentWritable(data: FirebaseFirestore.DocumentData | undefined): void {
  if (!data) throw new HttpsError("not-found", "원댓글을 찾을 수 없습니다.");
  if (data.isDeleted === true) {
    throw new HttpsError("failed-precondition", "삭제된 댓글에는 답글을 달 수 없습니다.");
  }
  if (data.parentCommentID !== null && data.parentCommentID !== undefined) {
    throw new HttpsError("failed-precondition", "답글에는 다시 답글을 달 수 없습니다.");
  }
}

function lookbookPostDocument(
  firestore: Firestore,
  input: CreateCommentInput,
): FirebaseFirestore.DocumentReference {
  return firestore.collection("brands").doc(input.brandID)
    .collection("seasons").doc(input.seasonID)
    .collection("posts").doc(input.postID);
}

export async function createCommentWriteService(
  uid: string,
  operation: CommentWriteOperation,
  input: CreateCommentInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<CommentMutationReceipt> {
  const accountRef = firestore.collection("moderationAccounts").doc(uid);
  const postRef = lookbookPostDocument(firestore, input);
  const parentRef = input.parentCommentID ?
    postRef.collection("comments").doc(input.parentCommentID) : null;
  const nowTimestamp = Timestamp.fromDate(now);

  return firestore.runTransaction(async (transaction) => {
    const accountSnapshot = await transaction.get(accountRef);
    const accountData = requireAccountCapabilityData(
      accountSnapshot.exists ? accountSnapshot.data() : undefined,
      "createUGC",
      now,
    );
    const moderationPrincipalID = principalID(accountData);
    const commentID = commentWriteDocumentID({
      moderationPrincipalID,
      operation,
      clientRequestID: input.clientRequestID,
    });
    const commentRef = postRef.collection("comments").doc(commentID);
    const [postSnapshot, existingComment] = await Promise.all([
      transaction.get(postRef),
      transaction.get(commentRef),
    ]);
    if (!postSnapshot.exists) {
      throw new HttpsError("not-found", "포스트를 찾을 수 없습니다.");
    }

    if (existingComment.exists) {
      assertExistingMatches(existingComment.data(), uid, input);
      const parentSnapshot = parentRef ? await transaction.get(parentRef) : null;
      const currentPostMetrics = postMetrics(postSnapshot.data());
      return {
        brandID: input.brandID,
        seasonID: input.seasonID,
        postID: input.postID,
        commentID,
        userID: uid,
        parentCommentID: input.parentCommentID,
        commentCount: currentPostMetrics.commentCount,
        replyCount: parentSnapshot ? integerValue(parentSnapshot.get("replyCount")) :
          integerValue(existingComment.get("replyCount")),
        deduplicated: true,
      };
    }

    const parentSnapshot = parentRef ? await transaction.get(parentRef) : null;
    if (input.parentCommentID) assertParentWritable(parentSnapshot?.data());

    const rateRef = firestore.collection("moderationCommentWriteRateLimitBuckets")
      .doc(commentWriteRateBucketID(moderationPrincipalID, now));
    const rateSnapshot = await transaction.get(rateRef);
    const count = integerValue(rateSnapshot.get("count"));
    assertCommentWriteCapacity(count, now);

    const currentPostMetrics = postMetrics(postSnapshot.data());
    const nextCommentCount = currentPostMetrics.commentCount + 1;
    const nextReplyCount = parentSnapshot ?
      integerValue(parentSnapshot.get("replyCount")) + 1 : 0;

    transaction.set(rateRef, {
      schemaVersion: COMMENT_WRITE_SCHEMA_VERSION,
      moderationPrincipalID,
      minuteBucket: commentWriteMinuteBucket(now),
      count: count + 1,
      updatedAt: nowTimestamp,
      expiresAt: Timestamp.fromMillis(now.getTime() + COMMENT_WRITE_BUCKET_TTL_MILLIS),
    });
    transaction.create(commentRef, {
      postID: input.postID,
      userID: uid,
      createdBy: uid,
      message: input.message,
      createdAt: nowTimestamp,
      updatedAt: nowTimestamp,
      isDeleted: false,
      likeCount: 0,
      replyCount: 0,
      isPinned: false,
      pinnedAt: null,
      pinnedBy: null,
      parentCommentID: input.parentCommentID,
      attachments: [],
    });
    if (parentRef) {
      transaction.update(parentRef, {
        replyCount: nextReplyCount,
        updatedAt: nowTimestamp,
      });
    }
    transaction.update(postRef, {
      "metrics.commentCount": nextCommentCount,
      "metricsUpdatedAt": nowTimestamp,
    });

    return {
      brandID: input.brandID,
      seasonID: input.seasonID,
      postID: input.postID,
      commentID,
      userID: uid,
      parentCommentID: input.parentCommentID,
      commentCount: nextCommentCount,
      replyCount: nextReplyCount,
      deduplicated: false,
    };
  });
}
