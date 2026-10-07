/* eslint-disable require-jsdoc */
import {createHash} from "node:crypto";
import type {QueueBatchState, QueueRequestEnvelope} from "./contracts.js";

export const QUEUE_PATH = "lookbookImportQueue/main";
export const BATCH_COLLECTION = "lookbookImportBatches";
export type QueueKind = "importSeasons" | "discoverSeasons" |
  "reviewApproval" | "manualRetry" | "assetRetry" | "repair";
export type AdmissionStatus =
  "pending" | "created" | "duplicate" | "failed" | "skipped";
export type QueueItem = {
  itemID: string;
  targetID: string;
  ordinal: number;
  admissionStatus: AdmissionStatus;
  processingStatus?: string;
  jobID: string | null;
  executionID: string | null;
  errorCode: string | null;
};
export type QueueBatch = {
  contractVersion: 1;
  requestID: string;
  requestCreatedAt: number;
  requestedBy: string;
  brandID: string;
  kind: QueueKind;
  payloadDigest: string;
  sequence: number;
  state: QueueBatchState;
  stateRevision: number;
  items: QueueItem[];
  preparationAttempts: number;
  preparationOwner: string | null;
  dispatchGeneration: number;
  dispatchState: "pending" | "delivered" | "none";
  dispatchDeliveryCount?: number;
  dispatchDeliveredAt?: number;
  createdAt: number;
  updatedAt: number;
  releasedAt?: number;
  detailCleanupAfter?: number;
  receiptExpiresAt?: number;
  retentionNextAt?: number;
  detailsPruned?: boolean;
  runID?: string;
  owner?: string | null;
  bootID?: string | null;
  epoch?: number;
};
export type AdmissionRequest = QueueRequestEnvelope & {
  brandID: string;
  kind: QueueKind;
  payload: Record<string, unknown>;
};
// 서버 adapter만 생성한다. 클라이언트의 jobData/claimKey를 직접 전달하지 않는다.
export type AdmissionTarget = {
  targetID: string;
  claimKey: string;
  collection: "importJobs" | "seasonDiscoveryJobs";
  jobData: Record<string, unknown>;
  // 서버가 중복으로 판정한 기존 job은 새 실행을 만들지 않고 참조한다.
  existingJobID?: string;
  existingExecutionID?: string;
  assetRetry?: {
    jobID: string;
    sourceDigest: string;
    sourceURL: string;
    targetSeasonID: string;
    createdPostIDs: string[];
  };
  continuation?: {
    jobID: string;
    mode: "reviewApproval" | "manualRetry" | "repairAnalyze" | "repairApply";
    expected: Record<string, unknown>;
    input: Record<string, unknown>;
    executionID: string | null;
  };
  errorCode?: string;
};

export const queueHash = (value: unknown): string =>
  createHash("sha256").update(canonicalJSON(value)).digest("hex");
export const queueBatchID = (uid: string, requestID: string): string =>
  queueHash([uid, requestID]);

export function canonicalJSON(value: unknown): string {
  if (value === null || typeof value === "string" ||
      typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number" && Number.isFinite(value)) {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJSON).join(",")}]`;
  }
  if (value && typeof value === "object" &&
      Object.getPrototypeOf(value) === Object.prototype) {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJSON(
        (value as Record<string, unknown>)[key])}`).join(",")}}`;
  }
  throw new Error("INVALID_CONTRACT");
}

export function queueDocumentID(value: unknown): string {
  if (typeof value !== "string" || value.length === 0 || value.length > 128 ||
      value === "." || value === ".." || value.includes("/") ||
      [...value].some((character) => character.charCodeAt(0) < 32)) {
    throw new Error("INVALID_CONTRACT");
  }
  return value;
}
