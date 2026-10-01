/* eslint-disable require-jsdoc */
import {HttpsError} from "firebase-functions/v2/https";
import {
  recordData,
  requiredDocumentID,
  requiredString,
} from "../../core/callable.js";

export type IssueChatVideoPlaybackURLInput = {
  roomID: string;
  messageID: string;
  attachmentID: string;
};

export type IssueChatMediaURLInput = IssueChatVideoPlaybackURLInput & {
  variant: "original" | "thumbnail";
};

export function parseIssueChatMediaURLInput(
  value: unknown,
): IssueChatMediaURLInput {
  const data = recordData(value);
  const allowedKeys = ["roomID", "messageID", "attachmentID", "variant"];
  if (Object.keys(data).some((key) => !allowedKeys.includes(key)) ||
      !["original", "thumbnail"].includes(String(data.variant))) {
    throw new HttpsError("invalid-argument", "미디어 요청 필드가 올바르지 않습니다.");
  }
  const {variant, ...identifiers} = data;
  return {
    ...parseIssueChatVideoPlaybackURLInput(identifiers),
    variant: variant as "original" | "thumbnail",
  };
}

export function parseIssueChatVideoPlaybackURLInput(
  value: unknown,
): IssueChatVideoPlaybackURLInput {
  const data = recordData(value);
  if (Object.keys(data).some((key) =>
    !["roomID", "messageID", "attachmentID"].includes(key)
  )) {
    throw new HttpsError(
      "invalid-argument",
      "영상 요청 필드는 roomID, messageID, attachmentID만 허용합니다.",
    );
  }
  return {
    roomID: requiredDocumentID(
      requiredString(data, "roomID", 512), "roomID",
    ),
    messageID: requiredDocumentID(
      requiredString(data, "messageID", 512), "messageID",
    ),
    attachmentID: requiredDocumentID(
      requiredString(data, "attachmentID", 512), "attachmentID",
    ),
  };
}
