/* eslint-disable require-jsdoc, max-len */
import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {
  recordData,
  requiredDocumentID,
  requiredString,
} from "../../core/callable.js";

export const COMMENT_WRITE_SCHEMA_VERSION = 1;
export const COMMENT_WRITE_LIMIT_PER_MINUTE = 20;
export const COMMENT_WRITE_BUCKET_TTL_MILLIS = 2 * 24 * 60 * 60 * 1000;

export type CommentWriteOperation = "createComment" | "createReply";

export type CreateCommentInput = {
  brandID: string;
  seasonID: string;
  postID: string;
  parentCommentID: string | null;
  message: string;
  clientRequestID: string;
};

function requiredClientRequestID(data: Record<string, unknown>): string {
  const value = requiredString(data, "clientRequestID", 64).toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value)) {
    throw new HttpsError(
      "invalid-argument",
      "clientRequestID 값이 올바르지 않습니다.",
    );
  }
  return value;
}

function commonInput(data: unknown): Omit<CreateCommentInput, "parentCommentID"> {
  const record = recordData(data);
  return {
    brandID: requiredDocumentID(requiredString(record, "brandID", 128), "brandID"),
    seasonID: requiredDocumentID(requiredString(record, "seasonID", 128), "seasonID"),
    postID: requiredDocumentID(requiredString(record, "postID", 128), "postID"),
    message: requiredString(record, "message", 1000),
    clientRequestID: requiredClientRequestID(record),
  };
}

export function parseCreateCommentInput(data: unknown): CreateCommentInput {
  return {...commonInput(data), parentCommentID: null};
}

export function parseCreateReplyInput(data: unknown): CreateCommentInput {
  const record = recordData(data);
  return {
    ...commonInput(record),
    parentCommentID: requiredDocumentID(
      requiredString(record, "parentCommentID", 128),
      "parentCommentID",
    ),
  };
}

export function commentWriteDocumentID(input: {
  moderationPrincipalID: string;
  operation: CommentWriteOperation;
  clientRequestID: string;
}): string {
  return createHash("sha256")
    .update([
      input.moderationPrincipalID,
      input.operation,
      input.clientRequestID,
    ].join(":"))
    .digest("hex");
}

export function commentWriteMinuteBucket(now: Date): number {
  return Math.floor(now.getTime() / 60_000);
}

export function commentWriteRateBucketID(
  moderationPrincipalID: string,
  now: Date,
): string {
  return `${moderationPrincipalID}_${commentWriteMinuteBucket(now)}`;
}

export function commentWriteRetryAt(now: Date): Date {
  return new Date((commentWriteMinuteBucket(now) + 1) * 60_000);
}

export function assertCommentWriteCapacity(count: number, now: Date): void {
  if (count < COMMENT_WRITE_LIMIT_PER_MINUTE) return;
  throw new HttpsError(
    "resource-exhausted",
    "댓글 작성 요청이 많습니다. 잠시 후 다시 시도해 주세요.",
    {
      errorCode: "RATE_LIMITED",
      retryAt: commentWriteRetryAt(now).toISOString(),
    },
  );
}
