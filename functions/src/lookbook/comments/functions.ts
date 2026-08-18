/* eslint-disable require-jsdoc, valid-jsdoc */
import {FieldValue} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  optionalString,
  recordData,
  requiredAuthUID,
  requiredDocumentID,
  requiredString,
} from "../../core/callable.js";
import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {
  hasBrandWriteAccessData,
  isTotalBrandAdmin,
} from "../../shared/brandAuthorization.js";
import {
  assertAccountCapability,
} from "../../shared/accountStatus.js";
import {
  parseCreateCommentInput,
  parseCreateReplyInput,
} from "./contracts.js";
import {createCommentWriteService} from "./service.js";

function numericMetric(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
function lookbookPostDocument(
  brandID: string,
  seasonID: string,
  postID: string
): FirebaseFirestore.DocumentReference {
  return db
    .collection("brands")
    .doc(brandID)
    .collection("seasons")
    .doc(seasonID)
    .collection("posts")
    .doc(postID);
}
function numericRootValue(
  data: FirebaseFirestore.DocumentData | undefined,
  key: string
): number {
  return numericMetric(data?.[key]);
}

export function postMetrics(data: FirebaseFirestore.DocumentData | undefined): {
  likeCount: number;
  commentCount: number;
  replacementCount: number;
  saveCount: number;
  viewCount: number;
} {
  const metrics =
    data?.metrics &&
    typeof data.metrics === "object" &&
    !Array.isArray(data.metrics) ?
      data.metrics as Record<string, unknown> :
      {};

  return {
    likeCount: numericMetric(metrics.likeCount),
    commentCount: numericMetric(metrics.commentCount),
    replacementCount: numericMetric(metrics.replacementCount),
    saveCount: numericMetric(metrics.saveCount),
    viewCount: numericMetric(metrics.viewCount),
  };
}
export const createComment = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    return createCommentWriteService(
      uid,
      "createComment",
      parseCreateCommentInput(request.data),
    );
  }
);

export const createReply = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    return createCommentWriteService(
      uid,
      "createReply",
      parseCreateReplyInput(request.data),
    );
  }
);

export const deleteComment = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    await assertAccountCapability(uid, "deleteOwnUGC");
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const seasonID = requiredDocumentID(
      requiredString(data, "seasonID", 128),
      "seasonID"
    );
    const postID = requiredDocumentID(
      requiredString(data, "postID", 128),
      "postID"
    );
    const commentID = requiredDocumentID(
      requiredString(data, "commentID", 128),
      "commentID"
    );
    const reason = optionalString(data, "reason", 500);

    const brandRef = db.collection("brands").doc(brandID);
    const managerRef = brandRef.collection("admins").doc(uid);
    const postRef = lookbookPostDocument(brandID, seasonID, postID);
    const commentRef = postRef.collection("comments").doc(commentID);
    const deletionLogRef = db.collection("commentDeletionLogs").doc();
    const isTotalAdmin = await isTotalBrandAdmin(uid);

    return await db.runTransaction(async (transaction) => {
      const brandSnap = await transaction.get(brandRef);
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }

      const postSnap = await transaction.get(postRef);
      if (!postSnap.exists) {
        throw new HttpsError("not-found", "포스트를 찾을 수 없습니다.");
      }

      const commentSnap = await transaction.get(commentRef);
      if (!commentSnap.exists) {
        throw new HttpsError("not-found", "댓글을 찾을 수 없습니다.");
      }

      const commentData = commentSnap.data();
      const authorID =
        typeof commentData?.userID === "string" ?
          commentData.userID :
          typeof commentData?.createdBy === "string" ?
            commentData.createdBy :
            "";
      if (authorID.length === 0) {
        throw new HttpsError("failed-precondition", "댓글 작성자 정보가 없습니다.");
      }

      let canDelete = authorID === uid || isTotalAdmin;
      if (!canDelete) {
        const managerSnap = await transaction.get(managerRef);
        canDelete = hasBrandWriteAccessData(managerSnap.data());
      }
      if (!canDelete) {
        throw new HttpsError("permission-denied", "댓글 삭제 권한이 없습니다.");
      }

      const parentCommentID =
        typeof commentData?.parentCommentID === "string" ?
          commentData.parentCommentID :
          null;
      const isReply = parentCommentID !== null;
      let deletedReplyCount = 0;

      if (isReply) {
        const parentRef = postRef.collection("comments").doc(parentCommentID);
        const parentSnap = await transaction.get(parentRef);
        if (parentSnap.exists) {
          const nextReplyCount = Math.max(
            0,
            numericRootValue(parentSnap.data(), "replyCount") - 1
          );
          transaction.update(parentRef, {
            replyCount: nextReplyCount,
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
      } else {
        const repliesSnap = await transaction.get(
          postRef
            .collection("comments")
            .where("parentCommentID", "==", commentID)
        );
        if (repliesSnap.size > 400) {
          throw new HttpsError(
            "resource-exhausted",
            "답글이 많은 댓글은 운영자 처리가 필요합니다."
          );
        }
        deletedReplyCount = repliesSnap.size;
        for (const replyDoc of repliesSnap.docs) {
          transaction.delete(replyDoc.ref);
        }
      }

      const metrics = postMetrics(postSnap.data());
      const deletedCommentCount = 1 + deletedReplyCount;
      const nextCommentCount = Math.max(
        0,
        metrics.commentCount - deletedCommentCount
      );
      const now = FieldValue.serverTimestamp();

      transaction.delete(commentRef);
      transaction.update(postRef, {
        "metrics.commentCount": nextCommentCount,
        "metricsUpdatedAt": now,
      });
      transaction.create(deletionLogRef, {
        logID: deletionLogRef.id,
        brandID,
        seasonID,
        postID,
        commentID,
        parentCommentID,
        targetType: isReply ? "reply" : "comment",
        deletedBy: uid,
        authorID,
        deletedReplyCount,
        deletedCommentCount,
        reason,
        messageSnapshot:
          typeof commentData?.message === "string" ?
            commentData.message.slice(0, 1000) :
            null,
        createdAtSnapshot: commentData?.createdAt ?? null,
        deletedAt: now,
      });

      return {
        brandID,
        seasonID,
        postID,
        commentID,
        userID: uid,
        parentCommentID,
        targetType: isReply ? "reply" : "comment",
        deletedReplyCount,
        deletedCommentCount,
        commentCount: nextCommentCount,
        replyCount: isReply ? 0 : deletedReplyCount,
      };
    });
  }
);
