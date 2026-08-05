/* eslint-disable require-jsdoc, max-len */
import {
  EXTRACTION_ISSUE_STAGES,
  EXTRACTION_ISSUE_STATUSES,
  type ExtractionIssueStage,
  type ExtractionIssueStatus,
} from "../import/extractionIssueContract.js";

export type IssueOperationsEnvironment = "development" | "production";
export type IssueOperationsReadAction =
  "listClusters" | "getCluster" | "getClustersBatch";
export type IssueOperationsWriteAction =
  "startProcessing" |
  "markNeedsGroundTruth" |
  "recordGroundTruthAndResume" |
  "reopen" |
  "markWontFix";

export type ListClustersInput = {
  limit: number;
  statuses: ExtractionIssueStatus[];
  stage: ExtractionIssueStage | null;
  seenAfter: Date | null;
  recurrenceOnly: boolean;
  cursor: string | null;
};

export type GroundTruthInput = {
  expectedCandidateCount: number | null;
  candidateKeys: string[];
  sourceClassification:
    "completeGallery" | "partialGallery" | "nonGallery" | "unknown";
  note: string | null;
};

export type WontFixReason =
  "sourceUnavailable" |
  "accessRestricted" |
  "ambiguousGroundTruth" |
  "unsupportedStructure" |
  "lowOperationalValue";

type ReadEnvelope = {
  environment: IssueOperationsEnvironment;
  requestID: string;
};

export type ParsedReadRequest = ReadEnvelope & (
  {action: "listClusters"; payload: ListClustersInput} |
  {action: "getCluster"; payload: {fingerprint: string}} |
  {action: "getClustersBatch"; payload: {fingerprints: string[]}}
);

export type ParsedWriteRequest = {
  environment: IssueOperationsEnvironment;
  requestID: string;
  action: IssueOperationsWriteAction;
  payload: {
    fingerprint: string;
    expectedStateVersion: number;
    groundTruth?: GroundTruthInput;
    reason?: string;
    wontFixReason?: WontFixReason;
    note?: string;
  };
};

export class IssueOperationsRequestError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "IssueOperationsRequestError";
  }
}

export function parseReadRequest(value: unknown): ParsedReadRequest {
  const envelope = parseEnvelope(value);
  if (envelope.action === "listClusters") {
    const payload = objectValue(envelope.payload, "payload");
    assertAllowedKeys(payload, [
      "limit", "statuses", "stage", "seenAfter", "recurrenceOnly", "cursor",
    ]);
    return {
      ...envelope,
      action: "listClusters",
      payload: {
        limit: optionalInteger(payload.limit, 20, 1, 50, "limit"),
        statuses: optionalStatuses(payload.statuses),
        stage: optionalStage(payload.stage),
        seenAfter: optionalDate(payload.seenAfter, "seenAfter"),
        recurrenceOnly: optionalBoolean(payload.recurrenceOnly, false),
        cursor: optionalString(payload.cursor, 512, "cursor"),
      },
    };
  }
  if (envelope.action === "getCluster") {
    const payload = objectValue(envelope.payload, "payload");
    assertAllowedKeys(payload, ["fingerprint"]);
    return {
      ...envelope,
      action: "getCluster",
      payload: {fingerprint: fingerprint(payload.fingerprint)},
    };
  }
  if (envelope.action === "getClustersBatch") {
    const payload = objectValue(envelope.payload, "payload");
    assertAllowedKeys(payload, ["fingerprints"]);
    if (!Array.isArray(payload.fingerprints) ||
        payload.fingerprints.length < 1 || payload.fingerprints.length > 20) {
      throw new IssueOperationsRequestError(
        "fingerprints는 1~20개 배열이어야 합니다."
      );
    }
    return {
      ...envelope,
      action: "getClustersBatch",
      payload: {fingerprints: payload.fingerprints.map(fingerprint)},
    };
  }
  throw new IssueOperationsRequestError("허용되지 않은 read action입니다.");
}

export function parseWriteRequest(value: unknown): ParsedWriteRequest {
  const envelope = parseEnvelope(value);
  const actions: IssueOperationsWriteAction[] = [
    "startProcessing",
    "markNeedsGroundTruth",
    "recordGroundTruthAndResume",
    "reopen",
    "markWontFix",
  ];
  if (!actions.includes(envelope.action as IssueOperationsWriteAction)) {
    throw new IssueOperationsRequestError("허용되지 않은 write action입니다.");
  }
  const action = envelope.action as IssueOperationsWriteAction;
  const payload = objectValue(envelope.payload, "payload");
  const commonKeys = ["fingerprint", "expectedStateVersion"];
  const result: ParsedWriteRequest["payload"] = {
    fingerprint: fingerprint(payload.fingerprint),
    expectedStateVersion: requiredInteger(
      payload.expectedStateVersion, 0, Number.MAX_SAFE_INTEGER,
      "expectedStateVersion"
    ),
  };
  if (action === "recordGroundTruthAndResume") {
    assertAllowedKeys(payload, [...commonKeys, "groundTruth"]);
    result.groundTruth = parseGroundTruth(payload.groundTruth);
  } else if (action === "reopen") {
    assertAllowedKeys(payload, [...commonKeys, "reason"]);
    result.reason = requiredString(payload.reason, 500, "reason");
  } else if (action === "markWontFix") {
    assertAllowedKeys(payload, [...commonKeys, "wontFixReason", "note"]);
    result.wontFixReason = wontFixReason(payload.wontFixReason);
    result.note = requiredString(payload.note, 500, "note");
  } else {
    assertAllowedKeys(payload, commonKeys);
  }
  return {...envelope, action, payload: result};
}

function parseEnvelope(value: unknown): {
  apiVersion: 1;
  environment: IssueOperationsEnvironment;
  requestID: string;
  action: string;
  payload: unknown;
} {
  const record = objectValue(value, "request");
  assertAllowedKeys(record, [
    "apiVersion", "environment", "requestID", "action", "payload",
  ]);
  if (record.apiVersion !== 1) {
    throw new IssueOperationsRequestError("apiVersion은 1이어야 합니다.");
  }
  const environment = record.environment;
  if (environment !== "development" && environment !== "production") {
    throw new IssueOperationsRequestError("environment가 올바르지 않습니다.");
  }
  const requestID = requiredString(record.requestID, 128, "requestID");
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(requestID)) {
    throw new IssueOperationsRequestError("requestID 형식이 올바르지 않습니다.");
  }
  return {
    apiVersion: 1,
    environment,
    requestID,
    action: requiredString(record.action, 64, "action"),
    payload: record.payload,
  };
}

function parseGroundTruth(value: unknown): GroundTruthInput {
  const record = objectValue(value, "groundTruth");
  assertAllowedKeys(record, [
    "expectedCandidateCount", "candidateKeys", "sourceClassification", "note",
  ]);
  const expectedCandidateCount = record.expectedCandidateCount === null ||
    record.expectedCandidateCount === undefined ? null :
    requiredInteger(record.expectedCandidateCount, 0, 10000,
      "expectedCandidateCount");
  if (!Array.isArray(record.candidateKeys) || record.candidateKeys.length > 120) {
    throw new IssueOperationsRequestError(
      "candidateKeys는 최대 120개 배열이어야 합니다."
    );
  }
  const candidateKeys = Array.from(new Set(record.candidateKeys.map((item) => {
    if (typeof item !== "string" || !/^[a-f0-9]{24}$/.test(item)) {
      throw new IssueOperationsRequestError("candidate key 형식이 올바르지 않습니다.");
    }
    return item;
  })));
  const classifications = [
    "completeGallery", "partialGallery", "nonGallery", "unknown",
  ] as const;
  if (!classifications.includes(record.sourceClassification as never)) {
    throw new IssueOperationsRequestError(
      "sourceClassification이 올바르지 않습니다."
    );
  }
  return {
    expectedCandidateCount,
    candidateKeys,
    sourceClassification:
      record.sourceClassification as GroundTruthInput["sourceClassification"],
    note: optionalString(record.note, 1000, "note"),
  };
}

function wontFixReason(value: unknown): WontFixReason {
  const reasons: WontFixReason[] = [
    "sourceUnavailable",
    "accessRestricted",
    "ambiguousGroundTruth",
    "unsupportedStructure",
    "lowOperationalValue",
  ];
  if (!reasons.includes(value as WontFixReason)) {
    throw new IssueOperationsRequestError("wontFixReason이 올바르지 않습니다.");
  }
  return value as WontFixReason;
}

function optionalStatuses(value: unknown): ExtractionIssueStatus[] {
  if (value === undefined) return ["open", "inProgress", "needsGroundTruth"];
  if (!Array.isArray(value) || value.length < 1 || value.length > 6) {
    throw new IssueOperationsRequestError("statuses가 올바르지 않습니다.");
  }
  const statuses = Array.from(new Set(value));
  if (statuses.some((item) =>
    typeof item !== "string" ||
    !EXTRACTION_ISSUE_STATUSES.includes(item as ExtractionIssueStatus))) {
    throw new IssueOperationsRequestError("statuses가 올바르지 않습니다.");
  }
  return statuses as ExtractionIssueStatus[];
}

function optionalStage(value: unknown): ExtractionIssueStage | null {
  if (value === undefined || value === null) return null;
  if (!EXTRACTION_ISSUE_STAGES.includes(value as ExtractionIssueStage)) {
    throw new IssueOperationsRequestError("stage가 올바르지 않습니다.");
  }
  return value as ExtractionIssueStage;
}

function fingerprint(value: unknown): string {
  if (typeof value !== "string" || !/^[a-f0-9]{40}$/.test(value)) {
    throw new IssueOperationsRequestError("fingerprint가 올바르지 않습니다.");
  }
  return value;
}

function objectValue(value: unknown, name: string): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new IssueOperationsRequestError(`${name}는 객체여야 합니다.`);
  }
  return value as Record<string, unknown>;
}

function assertAllowedKeys(
  value: Record<string, unknown>,
  allowed: string[]
): void {
  const allowedSet = new Set(allowed);
  if (Object.keys(value).some((key) => !allowedSet.has(key))) {
    throw new IssueOperationsRequestError("허용되지 않은 필드가 있습니다.");
  }
}

function requiredString(value: unknown, max: number, name: string): string {
  if (typeof value !== "string") {
    throw new IssueOperationsRequestError(`${name} 값이 필요합니다.`);
  }
  const result = value.trim();
  if (
    result.length < 1 ||
    result.length > max ||
    Array.from(result).some((character) => character.charCodeAt(0) < 32)
  ) {
    throw new IssueOperationsRequestError(`${name} 값이 올바르지 않습니다.`);
  }
  return result;
}

function optionalString(
  value: unknown, max: number, name: string
): string | null {
  if (value === undefined || value === null) return null;
  return requiredString(value, max, name);
}

function requiredInteger(
  value: unknown, min: number, max: number, name: string
): number {
  if (!Number.isSafeInteger(value) || Number(value) < min || Number(value) > max) {
    throw new IssueOperationsRequestError(`${name} 값이 올바르지 않습니다.`);
  }
  return Number(value);
}

function optionalInteger(
  value: unknown, fallback: number, min: number, max: number, name: string
): number {
  return value === undefined ? fallback : requiredInteger(value, min, max, name);
}

function optionalBoolean(value: unknown, fallback: boolean): boolean {
  if (value === undefined) return fallback;
  if (typeof value !== "boolean") {
    throw new IssueOperationsRequestError("boolean 값이 올바르지 않습니다.");
  }
  return value;
}

function optionalDate(value: unknown, name: string): Date | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string" || value.length > 64) {
    throw new IssueOperationsRequestError(`${name} 값이 올바르지 않습니다.`);
  }
  const result = new Date(value);
  if (!Number.isFinite(result.getTime())) {
    throw new IssueOperationsRequestError(`${name} 값이 올바르지 않습니다.`);
  }
  return result;
}
