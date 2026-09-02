/* eslint-disable require-jsdoc, max-len */
import {HttpsError} from "firebase-functions/v2/https";
import {
  optionalDocumentID,
  optionalString,
  recordData,
  requiredDocumentID,
  requiredString,
} from "../../core/callable.js";
import {
  ReportReason,
  ReportTargetType,
  requiredReportReason,
} from "../../moderation/reports/contracts.js";

export type DeleteChatMessageInput = {
  roomID: string;
  messageID: string;
  expectedSeq: number;
  reasonCode: string | null;
  reportTargetType: ReportTargetType | null;
  reportTargetID: string | null;
  clientRequestID: string;
};

export type CloseOwnedChatRoomInput = {
  roomID: string;
  expectedLifecycleVersion: number;
  clientRequestID: string;
};

export type CloseRoomByModerationInput = CloseOwnedChatRoomInput & {
  reasonCode: string;
  reportTargetID: string | null;
};

export type AcknowledgeRoomClosureInput = {
  roomID: string;
  clientRequestID: string;
};

export type RemoveRoomMemberInput = {
  roomID: string;
  targetUID: string;
  reasonCode: ReportReason;
  clientRequestID: string;
};

export type UnbanRoomMemberInput = {
  roomID: string;
  banEntryToken: string;
  clientRequestID: string;
};

export type ListRoomBansInput = {
  roomID: string;
  pageSize: number;
  cursor: string | null;
};

export type GetMyRoomAccessInput = {
  roomID: string;
};

export type AssignRoomModeratorInput = {
  roomID: string;
  targetUID: string;
  clientRequestID: string;
};

export type RevokeRoomModeratorInput = AssignRoomModeratorInput;

export type ResignRoomModeratorInput = {
  roomID: string;
  clientRequestID: string;
};

export type LeaveChatRoomInput = ResignRoomModeratorInput;

export type TransferRoomOwnershipAndLeaveInput = {
  roomID: string;
  successorUID: string;
  clientRequestID: string;
};

function positiveInteger(data: Record<string, unknown>, key: string): number {
  const value = data[key];
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  return value;
}

function clientRequestID(data: Record<string, unknown>): string {
  const value = requiredString(data, "clientRequestID", 64).toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value)) {
    throw new HttpsError("invalid-argument", "clientRequestID 값이 올바르지 않습니다.");
  }
  return value;
}

function roomID(data: Record<string, unknown>): string {
  return requiredDocumentID(requiredString(data, "roomID", 128), "roomID");
}

function optionalReportReference(data: Record<string, unknown>): {
  reportTargetType: ReportTargetType | null;
  reportTargetID: string | null;
} {
  const rawType = optionalString(data, "reportTargetType", 16);
  const reportTargetType = rawType === "user" || rawType === "room" ? rawType : null;
  if (rawType !== null && reportTargetType === null) {
    throw new HttpsError("invalid-argument", "reportTargetType 값이 올바르지 않습니다.");
  }
  const reportTargetID = optionalDocumentID(
    optionalString(data, "reportTargetID", 128),
    "reportTargetID",
  );
  if ((reportTargetType === null) !== (reportTargetID === null)) {
    throw new HttpsError("invalid-argument", "신고 참조는 type과 ID를 함께 전달해야 합니다.");
  }
  return {reportTargetType, reportTargetID};
}

export function parseDeleteChatMessageInput(data: unknown): DeleteChatMessageInput {
  const record = recordData(data);
  return {
    roomID: roomID(record),
    messageID: requiredDocumentID(
      requiredString(record, "messageID", 128),
      "messageID",
    ),
    expectedSeq: positiveInteger(record, "expectedSeq"),
    reasonCode: optionalString(record, "reasonCode", 64),
    ...optionalReportReference(record),
    clientRequestID: clientRequestID(record),
  };
}

export function parseCloseOwnedChatRoomInput(data: unknown): CloseOwnedChatRoomInput {
  const record = recordData(data);
  return {
    roomID: roomID(record),
    expectedLifecycleVersion: positiveInteger(record, "expectedLifecycleVersion"),
    clientRequestID: clientRequestID(record),
  };
}

export function parseCloseRoomByModerationInput(data: unknown): CloseRoomByModerationInput {
  const record = recordData(data);
  return {
    roomID: roomID(record),
    expectedLifecycleVersion: positiveInteger(record, "expectedLifecycleVersion"),
    reasonCode: requiredString(record, "reasonCode", 64),
    reportTargetID: optionalDocumentID(
      optionalString(record, "reportTargetID", 128),
      "reportTargetID",
    ),
    clientRequestID: clientRequestID(record),
  };
}

export function parseAcknowledgeRoomClosureInput(data: unknown): AcknowledgeRoomClosureInput {
  const record = recordData(data);
  return {
    roomID: roomID(record),
    clientRequestID: clientRequestID(record),
  };
}

export function parseRemoveRoomMemberInput(data: unknown): RemoveRoomMemberInput {
  const record = recordData(data);
  return {
    roomID: roomID(record),
    targetUID: requiredDocumentID(
      requiredString(record, "targetUID", 128),
      "targetUID",
    ),
    reasonCode: requiredReportReason(requiredString(record, "reasonCode", 32)),
    clientRequestID: clientRequestID(record),
  };
}

export function parseUnbanRoomMemberInput(data: unknown): UnbanRoomMemberInput {
  const record = recordData(data);
  return {
    roomID: roomID(record),
    banEntryToken: requiredString(record, "banEntryToken", 128),
    clientRequestID: clientRequestID(record),
  };
}

export function parseListRoomBansInput(data: unknown): ListRoomBansInput {
  const record = recordData(data);
  const rawPageSize = record.pageSize;
  if (typeof rawPageSize !== "number" || !Number.isSafeInteger(rawPageSize) ||
    rawPageSize < 1 || rawPageSize > 50) {
    throw new HttpsError("invalid-argument", "pageSize 값이 올바르지 않습니다.");
  }
  return {
    roomID: roomID(record),
    pageSize: rawPageSize,
    cursor: optionalString(record, "cursor", 512),
  };
}

export function parseGetMyRoomAccessInput(data: unknown): GetMyRoomAccessInput {
  return {roomID: roomID(recordData(data))};
}

function targetUID(data: Record<string, unknown>, key = "targetUID"): string {
  return requiredDocumentID(requiredString(data, key, 128), key);
}

export function parseAssignRoomModeratorInput(data: unknown): AssignRoomModeratorInput {
  const record = recordData(data);
  return {
    roomID: roomID(record),
    targetUID: targetUID(record),
    clientRequestID: clientRequestID(record),
  };
}

export function parseRevokeRoomModeratorInput(data: unknown): RevokeRoomModeratorInput {
  return parseAssignRoomModeratorInput(data);
}

export function parseResignRoomModeratorInput(data: unknown): ResignRoomModeratorInput {
  const record = recordData(data);
  return {roomID: roomID(record), clientRequestID: clientRequestID(record)};
}

export function parseLeaveChatRoomInput(data: unknown): LeaveChatRoomInput {
  return parseResignRoomModeratorInput(data);
}

export function parseTransferRoomOwnershipAndLeaveInput(
  data: unknown,
): TransferRoomOwnershipAndLeaveInput {
  const record = recordData(data);
  return {
    roomID: roomID(record),
    successorUID: targetUID(record, "successorUID"),
    clientRequestID: clientRequestID(record),
  };
}
