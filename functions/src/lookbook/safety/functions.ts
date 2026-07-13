/* eslint-disable require-jsdoc, valid-jsdoc */
import {FieldValue} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  optionalDocumentID,
  optionalString,
  recordData,
  requiredAuthUID,
  requiredDocumentID,
  requiredString,
} from "../../core/callable.js";
import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
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

export function commentReportDocumentID(
  reporterUserID: string,
  targetType: string,
  brandID: string,
  seasonID: string,
  postID: string,
  commentID: string
): string {
  return [
    reporterUserID,
    targetType,
    brandID,
    seasonID,
    postID,
    commentID,
  ].join("__");
}
export const reportComment = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const reporterUserID = requiredDocumentID(
      requiredString(data, "reporterUserID", 128),
      "reporterUserID"
    );
    const targetType = requiredString(data, "targetType", 16);
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
    const parentCommentID = optionalDocumentID(
      optionalString(data, "parentCommentID", 128),
      "parentCommentID"
    );
    const reason = requiredString(data, "reason", 64);
    const detail = optionalString(data, "detail", 500);
    const authorNicknameSnapshot = optionalString(
      data,
      "targetAuthorNicknameSnapshot",
      80
    );

    if (reporterUserID !== uid) {
      throw new HttpsError("permission-denied", "신고자 정보가 올바르지 않습니다.");
    }
    if (targetType !== "comment" && targetType !== "reply") {
      throw new HttpsError("invalid-argument", "targetType 값이 올바르지 않습니다.");
    }

    const postRef = lookbookPostDocument(brandID, seasonID, postID);
    const targetRef = postRef.collection("comments").doc(commentID);
    const reportID = commentReportDocumentID(
      uid,
      targetType,
      brandID,
      seasonID,
      postID,
      commentID
    );
    const reportRef = db.collection("commentReports").doc(reportID);
    const createdAtMillis = Date.now();

    return await db.runTransaction(async (transaction) => {
      const reportSnap = await transaction.get(reportRef);
      if (reportSnap.exists) {
        throw new HttpsError("already-exists", "이미 신고한 댓글입니다.");
      }

      const postSnap = await transaction.get(postRef);
      if (!postSnap.exists) {
        throw new HttpsError("not-found", "포스트를 찾을 수 없습니다.");
      }

      const targetSnap = await transaction.get(targetRef);
      if (!targetSnap.exists) {
        throw new HttpsError("not-found", "신고 대상을 찾을 수 없습니다.");
      }

      const targetData = targetSnap.data();
      if (targetData?.isDeleted === true) {
        throw new HttpsError("failed-precondition", "삭제된 댓글은 신고할 수 없습니다.");
      }

      const storedParentCommentID =
        typeof targetData?.parentCommentID === "string" ?
          targetData.parentCommentID :
          null;
      if (targetType === "comment" && storedParentCommentID !== null) {
        throw new HttpsError("invalid-argument", "신고 대상 유형이 올바르지 않습니다.");
      }
      if (targetType === "reply" && storedParentCommentID === null) {
        throw new HttpsError("invalid-argument", "신고 대상 유형이 올바르지 않습니다.");
      }
      if (parentCommentID !== storedParentCommentID) {
        throw new HttpsError(
          "invalid-argument",
          "parentCommentID 값이 올바르지 않습니다."
        );
      }

      const targetAuthorID =
        typeof targetData?.userID === "string" ?
          targetData.userID :
          typeof targetData?.createdBy === "string" ?
            targetData.createdBy :
            "";
      if (targetAuthorID.length === 0) {
        throw new HttpsError("failed-precondition", "댓글 작성자 정보가 없습니다.");
      }
      if (targetAuthorID === uid) {
        throw new HttpsError("failed-precondition", "본인 댓글은 신고할 수 없습니다.");
      }

      const targetContentSnapshot =
        typeof targetData?.message === "string" ?
          targetData.message.slice(0, 1000) :
          "";
      if (targetContentSnapshot.trim().length === 0) {
        throw new HttpsError("failed-precondition", "신고 대상 내용이 없습니다.");
      }

      const now = FieldValue.serverTimestamp();
      transaction.create(reportRef, {
        reportID,
        reporterUserID: uid,
        targetAuthorID,
        targetType,
        targetCommentID: commentID,
        parentCommentID: storedParentCommentID,
        brandID,
        seasonID,
        postID,
        reason,
        detail,
        targetContentSnapshot,
        targetAuthorNicknameSnapshot: authorNicknameSnapshot,
        status: "pending",
        createdAt: now,
        updatedAt: now,
      });

      return {
        reportID,
        reporterUserID: uid,
        targetAuthorID,
        targetType,
        targetCommentID: commentID,
        parentCommentID: storedParentCommentID,
        brandID,
        seasonID,
        postID,
        reason,
        detail,
        targetContentSnapshot,
        targetAuthorNicknameSnapshot: authorNicknameSnapshot,
        status: "pending",
        createdAtMillis,
      };
    });
  }
);

export const blockUser = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const blockerUserID = requiredDocumentID(
      requiredString(data, "blockerUserID", 128),
      "blockerUserID"
    );
    const blockedUserID = requiredDocumentID(
      requiredString(data, "blockedUserID", 128),
      "blockedUserID"
    );
    const blockedUserNicknameSnapshot = optionalString(
      data,
      "blockedUserNicknameSnapshot",
      80
    );
    const source = requiredString(data, "source", 16);

    if (blockerUserID !== uid) {
      throw new HttpsError("permission-denied", "차단 요청자 정보가 올바르지 않습니다.");
    }
    if (blockedUserID === uid) {
      throw new HttpsError("failed-precondition", "본인은 차단할 수 없습니다.");
    }
    if (source !== "comment" && source !== "reply" && source !== "profile") {
      throw new HttpsError("invalid-argument", "source 값이 올바르지 않습니다.");
    }

    const createdAtMillis = Date.now();
    const now = FieldValue.serverTimestamp();
    await db
      .collection("users")
      .doc(uid)
      .collection("blockedUsers")
      .doc(blockedUserID)
      .set(
        {
          blockerUserID: uid,
          blockedUserID,
          blockedUserNicknameSnapshot,
          source,
          createdAt: now,
          updatedAt: now,
        },
        {merge: true}
      );

    return {
      blockerUserID: uid,
      blockedUserID,
      blockedUserNicknameSnapshot,
      source,
      createdAtMillis,
    };
  }
);

export const loadHiddenCommentUserIDs = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);
    const currentUserID = requiredDocumentID(
      requiredString(data, "currentUserID", 128),
      "currentUserID"
    );

    if (currentUserID !== uid) {
      throw new HttpsError("permission-denied", "사용자 정보가 올바르지 않습니다.");
    }

    const blockedByMeSnapshot = await db
      .collection("users")
      .doc(uid)
      .collection("blockedUsers")
      .get();
    const blockedByMeIDs = blockedByMeSnapshot.docs.map((doc) => doc.id);

    const blockingMeSnapshot = await db
      .collectionGroup("blockedUsers")
      .where("blockedUserID", "==", uid)
      .get();
    const blockingMeIDs = blockingMeSnapshot.docs
      .map((doc) => doc.data().blockerUserID)
      .filter(
        (value): value is string =>
          typeof value === "string" && value.length > 0
      );

    return {
      hiddenUserIDs: Array.from(new Set([...blockedByMeIDs, ...blockingMeIDs])),
    };
  }
);
