/* eslint-disable require-jsdoc */
import {HttpsError} from "firebase-functions/v2/https";
import {
  optionalString,
  recordData,
  requiredDocumentID,
  requiredString,
} from "../../core/callable.js";

export const blockSources = ["comment", "reply", "profile", "chat"] as const;

export type BlockSource = typeof blockSources[number];

export type BlockUserInput = {
  targetUID: string;
  source: BlockSource;
  targetNicknameSnapshot: string | null;
  clientRequestID: string;
};

export type UnblockUserInput = {
  targetUID: string;
  clientRequestID: string;
};

function requiredClientRequestID(data: Record<string, unknown>): string {
  const value = requiredString(data, "clientRequestID", 64);
  const uuidPattern =
    // eslint-disable-next-line max-len
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!uuidPattern.test(value)) {
    throw new HttpsError(
      "invalid-argument",
      "clientRequestID 값이 올바르지 않습니다.",
    );
  }
  return value.toLowerCase();
}

function requiredBlockSource(value: string): BlockSource {
  if (!blockSources.includes(value as BlockSource)) {
    throw new HttpsError("invalid-argument", "source 값이 올바르지 않습니다.");
  }
  return value as BlockSource;
}

function rejectUnknownKeys(
  data: Record<string, unknown>,
  allowedKeys: readonly string[],
): void {
  const unknownKey = Object.keys(data).find(
    (key) => !allowedKeys.includes(key),
  );
  if (unknownKey) {
    throw new HttpsError(
      "invalid-argument",
      `${unknownKey} 필드는 지원하지 않습니다.`,
    );
  }
}

export function parseBlockUserInput(data: unknown): BlockUserInput {
  const record = recordData(data);
  rejectUnknownKeys(record, [
    "targetUID",
    "source",
    "targetNicknameSnapshot",
    "clientRequestID",
  ]);
  return {
    targetUID: requiredDocumentID(
      requiredString(record, "targetUID", 128),
      "targetUID",
    ),
    source: requiredBlockSource(requiredString(record, "source", 16)),
    targetNicknameSnapshot: optionalString(
      record,
      "targetNicknameSnapshot",
      80,
    ),
    clientRequestID: requiredClientRequestID(record),
  };
}

export function parseUnblockUserInput(data: unknown): UnblockUserInput {
  const record = recordData(data);
  rejectUnknownKeys(record, ["targetUID", "clientRequestID"]);
  return {
    targetUID: requiredDocumentID(
      requiredString(record, "targetUID", 128),
      "targetUID",
    ),
    clientRequestID: requiredClientRequestID(record),
  };
}
