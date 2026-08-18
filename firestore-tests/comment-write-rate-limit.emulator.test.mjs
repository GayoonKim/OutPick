import assert from "node:assert/strict";
import {after, beforeEach, describe, test} from "node:test";
import {db} from "../functions/lib/core/firebase.js";
import {
  createCommentWriteService,
} from "../functions/lib/lookbook/comments/service.js";

const uid = "comment-writer";
const principalID = "principal-comment-writer";
const brandID = "comment-brand";
const seasonID = "comment-season";
const postID = "comment-post";
const now = new Date("2026-08-18T07:00:30.000Z");

function requestID(sequence) {
  return `123e4567-e89b-42d3-a456-${String(sequence).padStart(12, "0")}`;
}

function input(sequence, message, parentCommentID = null) {
  return {
    brandID,
    seasonID,
    postID,
    parentCommentID,
    message,
    clientRequestID: requestID(sequence),
  };
}

function postReference() {
  return db.collection("brands").doc(brandID)
    .collection("seasons").doc(seasonID)
    .collection("posts").doc(postID);
}

async function clearFixtures() {
  await Promise.all([
    db.recursiveDelete(db.collection("moderationAccounts").doc(uid)),
    db.recursiveDelete(db.collection("brands").doc(brandID)),
    db.recursiveDelete(db.collection("moderationCommentWriteRateLimitBuckets")),
  ]);
}

async function seedFixtures() {
  await Promise.all([
    db.collection("moderationAccounts").doc(uid).set({
      accountStatus: "active",
      moderationPrincipalID: principalID,
      moderationStatus: "active",
    }),
    postReference().set({metrics: {commentCount: 0}}),
  ]);
}

beforeEach(async () => {
  await clearFixtures();
  await seedFixtures();
});
after(clearFixtures);

describe("comment write quota transactions", () => {
  test("동시 동일 요청은 댓글·quota·metric을 한 번만 소비한다", async () => {
    const request = input(1, "동일 댓글");
    const receipts = await Promise.all([
      createCommentWriteService(uid, "createComment", request, now),
      createCommentWriteService(uid, "createComment", request, now),
      createCommentWriteService(uid, "createComment", request, now),
    ]);

    assert.equal(new Set(receipts.map((receipt) => receipt.commentID)).size, 1);
    assert.equal(receipts.filter((receipt) => !receipt.deduplicated).length, 1);
    assert.equal((await postReference().collection("comments").get()).size, 1);
    assert.equal((await postReference().get()).data()?.metrics?.commentCount, 1);
    const buckets = await db.collection("moderationCommentWriteRateLimitBuckets").get();
    assert.equal(buckets.size, 1);
    assert.equal(buckets.docs[0].data().count, 1);
  });

  test("댓글·답글 합산 20건 뒤 다음 요청은 다음 분까지 거부한다", async () => {
    const root = await createCommentWriteService(
      uid,
      "createComment",
      input(1, "원댓글"),
      now,
    );
    for (let sequence = 2; sequence <= 20; sequence += 1) {
      await createCommentWriteService(
        uid,
        "createReply",
        input(sequence, `답글 ${sequence}`, root.commentID),
        now,
      );
    }

    await assert.rejects(
      createCommentWriteService(
        uid,
        "createReply",
        input(21, "제한 대상", root.commentID),
        now,
      ),
      (error) => error?.code === "resource-exhausted" &&
        error?.details?.retryAt === "2026-08-18T07:01:00.000Z",
    );
    const rootSnapshot = await postReference().collection("comments")
      .doc(root.commentID).get();
    assert.equal(rootSnapshot.data()?.replyCount, 19);
    assert.equal((await postReference().get()).data()?.metrics?.commentCount, 20);
  });

  test("같은 request ID를 다른 본문에 재사용하면 충돌로 거부한다", async () => {
    await createCommentWriteService(
      uid,
      "createComment",
      input(1, "첫 본문"),
      now,
    );
    await assert.rejects(
      createCommentWriteService(
        uid,
        "createComment",
        input(1, "다른 본문"),
        now,
      ),
      (error) => error?.details?.errorCode === "IDEMPOTENCY_CONFLICT",
    );
  });
});
