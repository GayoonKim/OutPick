/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  assertCommentWriteCapacity,
  commentWriteDocumentID,
  commentWriteMinuteBucket,
  commentWriteRateBucketID,
  commentWriteRetryAt,
  parseCreateCommentInput,
  parseCreateReplyInput,
} from "./contracts.js";

const requestID = "123e4567-e89b-12d3-a456-426614174000";

test("댓글 입력은 trim 후 UTF-16 1000 code unit까지 허용한다", () => {
  const message = "😀".repeat(500);
  const parsed = parseCreateCommentInput({
    brandID: "brand",
    seasonID: "season",
    postID: "post",
    message: `  ${message}  `,
    clientRequestID: requestID.toUpperCase(),
  });
  assert.equal(parsed.message, message);
  assert.equal(parsed.message.length, 1000);
  assert.equal(parsed.clientRequestID, requestID);

  assert.throws(() => parseCreateCommentInput({
    brandID: "brand",
    seasonID: "season",
    postID: "post",
    message: `${message}a`,
    clientRequestID: requestID,
  }), HttpsError);
});

test("답글은 parentCommentID와 UUID clientRequestID를 요구한다", () => {
  const parsed = parseCreateReplyInput({
    brandID: "brand",
    seasonID: "season",
    postID: "post",
    parentCommentID: "parent",
    message: " 답글 ",
    clientRequestID: requestID,
  });
  assert.equal(parsed.parentCommentID, "parent");
  assert.equal(parsed.message, "답글");
  assert.throws(() => parseCreateReplyInput({
    brandID: "brand",
    seasonID: "season",
    postID: "post",
    parentCommentID: "parent",
    message: "답글",
    clientRequestID: "not-a-uuid",
  }), HttpsError);
});

test("멱등 문서 ID는 principal·operation·request 조합별로 결정된다", () => {
  const first = commentWriteDocumentID({
    moderationPrincipalID: "principal",
    operation: "createComment",
    clientRequestID: requestID,
  });
  assert.equal(first.length, 64);
  assert.equal(first, commentWriteDocumentID({
    moderationPrincipalID: "principal",
    operation: "createComment",
    clientRequestID: requestID,
  }));
  assert.notEqual(first, commentWriteDocumentID({
    moderationPrincipalID: "principal",
    operation: "createReply",
    clientRequestID: requestID,
  }));
});

test("분 단위 bucket과 retryAt은 UTC epoch 경계로 계산한다", () => {
  const now = new Date("2026-08-18T12:34:56.789Z");
  assert.equal(commentWriteMinuteBucket(now), Math.floor(now.getTime() / 60_000));
  assert.equal(commentWriteRateBucketID("principal", now),
    `principal_${commentWriteMinuteBucket(now)}`);
  assert.equal(commentWriteRetryAt(now).toISOString(), "2026-08-18T12:35:00.000Z");
});

test("댓글·답글 합산 분당 20회를 넘으면 retryAt과 함께 거부한다", () => {
  const now = new Date("2026-08-18T12:34:56.789Z");
  assert.doesNotThrow(() => assertCommentWriteCapacity(19, now));
  assert.throws(
    () => assertCommentWriteCapacity(20, now),
    (error: unknown) => {
      assert.ok(error instanceof HttpsError);
      assert.equal(error.code, "resource-exhausted");
      assert.deepEqual(error.details, {
        errorCode: "RATE_LIMITED",
        retryAt: "2026-08-18T12:35:00.000Z",
      });
      return true;
    },
  );
});
