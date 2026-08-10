/* eslint-disable require-jsdoc, max-len */
import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";

export type ModerationAuditAction =
  "startReview" |
  "resolveReview" |
  "dismissReview" |
  "deleteMessage" |
  "closeRoomByOwner" |
  "closeRoomByModeration" |
  "temporarilyRestrictAccount" |
  "permanentlySuspendAccount" |
  "liftAccountModeration";

export function moderationAuditActionID(actorUID: string, clientRequestID: string): string {
  return createHash("sha256")
    .update(`${actorUID}:${clientRequestID}`)
    .digest("hex");
}

export function assertAuditReplay(
  audit: FirebaseFirestore.DocumentData,
  expected: {
    action: ModerationAuditAction;
    targetType: string;
    targetID: string;
    requestID: string;
  },
): Record<string, unknown> {
  if (audit.action !== expected.action || audit.targetType !== expected.targetType ||
    audit.targetID !== expected.targetID || audit.requestID !== expected.requestID) {
    throw new HttpsError(
      "already-exists",
      "같은 clientRequestID가 다른 관리자 작업에 사용됐습니다.",
    );
  }
  const after = audit.after;
  if (!after || typeof after !== "object" || Array.isArray(after)) {
    throw new HttpsError("failed-precondition", "기존 감사 결과가 올바르지 않습니다.");
  }
  return after as Record<string, unknown>;
}
