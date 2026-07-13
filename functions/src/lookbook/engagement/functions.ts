/* eslint-disable require-jsdoc, valid-jsdoc */
import {FieldValue} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  recordData,
  requiredAuthUID,
  requiredBoolean,
  requiredDocumentID,
  requiredString,
} from "../../core/callable.js";
import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
export function postStateDocumentID(
  brandID: string,
  seasonID: string,
  postID: string
): string {
  return `${brandID}_${seasonID}_${postID}`;
}

export function seasonStateDocumentID(
  brandID: string,
  seasonID: string
): string {
  return `${brandID}_${seasonID}`;
}

export function commentStateDocumentID(
  brandID: string,
  seasonID: string,
  postID: string,
  commentID: string
): string {
  return `${brandID}_${seasonID}_${postID}_${commentID}`;
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
export function numericMetric(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return 0;
  }
  return Math.max(0, Math.floor(value));
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
export const setBrandEngagement = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const isLiked = requiredBoolean(data, "isLiked");

    const brandRef = db.collection("brands").doc(brandID);
    const userStateRef = db
      .collection("users")
      .doc(uid)
      .collection("brandStates")
      .doc(brandID);

    return await db.runTransaction(async (transaction) => {
      const brandSnap = await transaction.get(brandRef);
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }

      const stateSnap = await transaction.get(userStateRef);
      const currentLiked = stateSnap.exists;
      const currentLikeCount = numericRootValue(brandSnap.data(), "likeCount");
      const likeDelta =
        currentLiked === isLiked ? 0 :
          isLiked ? 1 : -1;
      const nextLikeCount = Math.max(0, currentLikeCount + likeDelta);
      const now = FieldValue.serverTimestamp();

      if (likeDelta !== 0) {
        transaction.update(brandRef, {
          likeCount: nextLikeCount,
          updatedAt: now,
        });
      }

      if (isLiked) {
        transaction.set(userStateRef, {
          brandID,
          likedAt: now,
        }, {merge: true});
      } else if (stateSnap.exists) {
        transaction.delete(userStateRef);
      }

      return {
        brandID,
        userID: uid,
        isLiked,
        likeCount: nextLikeCount,
      };
    });
  }
);

export const setPostEngagement = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
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
    const kind = requiredString(data, "kind", 16);
    const isEnabled = requiredBoolean(data, "isEnabled");

    if (kind !== "like" && kind !== "save") {
      throw new HttpsError("invalid-argument", "kind 값이 올바르지 않습니다.");
    }

    const postRef = db
      .collection("brands")
      .doc(brandID)
      .collection("seasons")
      .doc(seasonID)
      .collection("posts")
      .doc(postID);
    const userStateRef = db
      .collection("users")
      .doc(uid)
      .collection("postStates")
      .doc(postStateDocumentID(brandID, seasonID, postID));

    return await db.runTransaction(async (transaction) => {
      const postSnap = await transaction.get(postRef);
      if (!postSnap.exists) {
        throw new HttpsError("not-found", "포스트를 찾을 수 없습니다.");
      }

      const stateSnap = await transaction.get(userStateRef);
      const stateData = stateSnap.data();
      const metrics = postMetrics(postSnap.data());
      const currentLiked = stateData?.isLiked === true;
      const currentSaved = stateData?.isSaved === true;
      let nextLiked = currentLiked;
      let nextSaved = currentSaved;
      let likeDelta = 0;
      let saveDelta = 0;

      if (kind === "like" && currentLiked !== isEnabled) {
        nextLiked = isEnabled;
        likeDelta = isEnabled ? 1 : -1;
      }
      if (kind === "save" && currentSaved !== isEnabled) {
        nextSaved = isEnabled;
        saveDelta = isEnabled ? 1 : -1;
      }

      const nextMetrics = {
        ...metrics,
        likeCount: Math.max(0, metrics.likeCount + likeDelta),
        saveCount: Math.max(0, metrics.saveCount + saveDelta),
      };

      if (likeDelta !== 0 || saveDelta !== 0) {
        transaction.update(postRef, {
          "metrics.likeCount": nextMetrics.likeCount,
          "metrics.saveCount": nextMetrics.saveCount,
          "metricsUpdatedAt": FieldValue.serverTimestamp(),
        });
      }

      if (nextLiked || nextSaved) {
        const statePatch: Record<string, unknown> = {
          brandID,
          seasonID,
          postID,
          postPath: postRef.path,
          userID: uid,
          isLiked: nextLiked,
          isSaved: nextSaved,
          updatedAt: FieldValue.serverTimestamp(),
        };

        if (kind === "like") {
          statePatch.likedAt = nextLiked ?
            FieldValue.serverTimestamp() :
            null;
        }
        if (kind === "save") {
          statePatch.savedAt = nextSaved ?
            FieldValue.serverTimestamp() :
            null;
        }

        transaction.set(userStateRef, statePatch, {merge: true});
      } else if (stateSnap.exists) {
        transaction.delete(userStateRef);
      }

      return {
        postID,
        userID: uid,
        isLiked: nextLiked,
        isSaved: nextSaved,
        metrics: nextMetrics,
      };
    });
  }
);

export const setSeasonEngagement = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const seasonID = requiredDocumentID(
      requiredString(data, "seasonID", 128),
      "seasonID"
    );
    const isLiked = requiredBoolean(data, "isLiked");

    const seasonRef = db
      .collection("brands")
      .doc(brandID)
      .collection("seasons")
      .doc(seasonID);
    const userStateRef = db
      .collection("users")
      .doc(uid)
      .collection("seasonStates")
      .doc(seasonStateDocumentID(brandID, seasonID));

    return await db.runTransaction(async (transaction) => {
      const seasonSnap = await transaction.get(seasonRef);
      if (!seasonSnap.exists) {
        throw new HttpsError("not-found", "시즌을 찾을 수 없습니다.");
      }

      const stateSnap = await transaction.get(userStateRef);
      const currentLiked = stateSnap.exists;
      const currentLikeCount = numericRootValue(seasonSnap.data(), "likeCount");
      const likeDelta =
        currentLiked === isLiked ? 0 :
          isLiked ? 1 : -1;
      const nextLikeCount = Math.max(0, currentLikeCount + likeDelta);
      const now = FieldValue.serverTimestamp();

      if (likeDelta !== 0) {
        transaction.update(seasonRef, {
          likeCount: nextLikeCount,
          updatedAt: now,
        });
      }

      if (isLiked) {
        transaction.set(userStateRef, {
          brandID,
          seasonID,
          seasonPath: seasonRef.path,
          userID: uid,
          isLiked,
          likedAt: now,
          updatedAt: now,
        }, {merge: true});
      } else if (stateSnap.exists) {
        transaction.delete(userStateRef);
      }

      return {
        brandID,
        seasonID,
        userID: uid,
        isLiked,
        likeCount: nextLikeCount,
      };
    });
  }
);

export const setCommentEngagement = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
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
    const isLiked = requiredBoolean(data, "isLiked");

    const postRef = lookbookPostDocument(brandID, seasonID, postID);
    const commentRef = postRef.collection("comments").doc(commentID);
    const userStateRef = db
      .collection("users")
      .doc(uid)
      .collection("commentStates")
      .doc(commentStateDocumentID(brandID, seasonID, postID, commentID));

    return await db.runTransaction(async (transaction) => {
      const postSnap = await transaction.get(postRef);
      if (!postSnap.exists) {
        throw new HttpsError("not-found", "포스트를 찾을 수 없습니다.");
      }

      const commentSnap = await transaction.get(commentRef);
      if (!commentSnap.exists) {
        throw new HttpsError("not-found", "댓글을 찾을 수 없습니다.");
      }

      const commentData = commentSnap.data();
      if (commentData?.isDeleted === true) {
        throw new HttpsError(
          "failed-precondition",
          "삭제된 댓글에는 좋아요를 누를 수 없습니다."
        );
      }

      const stateSnap = await transaction.get(userStateRef);
      const currentLiked = stateSnap.data()?.isLiked === true;
      const currentLikeCount = numericRootValue(commentData, "likeCount");
      const likeDelta =
        currentLiked === isLiked ? 0 :
          isLiked ? 1 : -1;
      const nextLikeCount = Math.max(0, currentLikeCount + likeDelta);
      const parentCommentID =
        typeof commentData?.parentCommentID === "string" ?
          commentData.parentCommentID :
          null;
      const now = FieldValue.serverTimestamp();

      if (likeDelta !== 0) {
        transaction.update(commentRef, {
          likeCount: nextLikeCount,
          updatedAt: now,
        });
      }

      if (isLiked) {
        transaction.set(userStateRef, {
          brandID,
          seasonID,
          postID,
          commentID,
          commentPath: commentRef.path,
          userID: uid,
          parentCommentID,
          isLiked: true,
          likedAt: now,
          updatedAt: now,
        }, {merge: true});
      } else if (stateSnap.exists) {
        transaction.delete(userStateRef);
      }

      return {
        brandID,
        seasonID,
        postID,
        commentID,
        userID: uid,
        parentCommentID,
        isLiked,
        likeCount: nextLikeCount,
      };
    });
  }
);
