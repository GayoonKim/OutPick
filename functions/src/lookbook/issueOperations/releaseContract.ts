/* eslint-disable require-jsdoc, max-len */
import type {ExtractionIssueStage} from "../import/extractionIssueContract.js";
import {extractionRuntimeVersionMatchesStage} from "../import/extractionIssueContract.js";
import {
  IssueOperationsRequestError,
  type IssueOperationsEnvironment,
} from "./contract.js";

export type VerifyFixRequest = {
  environment: IssueOperationsEnvironment;
  requestID: string;
  action: "verifyFix";
  payload: {
    fingerprint: string;
    expectedStateVersion: number;
    stage: ExtractionIssueStage;
    targetRuntimeVersion: string;
    workerRevision: string;
    workerSourceRevision: string;
  };
};

export function parseVerifyFixRequest(value: unknown): VerifyFixRequest {
  const record = object(value, "request");
  exactKeys(record, ["apiVersion", "environment", "requestID", "action", "payload"]);
  if (record.apiVersion !== 1 || record.action !== "verifyFix") {
    throw new IssueOperationsRequestError("verifyFix API 계약이 올바르지 않습니다.");
  }
  if (record.environment !== "development" && record.environment !== "production") {
    throw new IssueOperationsRequestError("environment가 올바르지 않습니다.");
  }
  const requestID = string(record.requestID, /^[A-Za-z0-9_-]{8,128}$/, "requestID");
  const payload = object(record.payload, "payload");
  exactKeys(payload, [
    "fingerprint", "expectedStateVersion", "stage", "targetRuntimeVersion",
    "workerRevision", "workerSourceRevision",
  ]);
  if (payload.stage !== "seasonDiscovery" && payload.stage !== "seasonImageImport") {
    throw new IssueOperationsRequestError("stage가 올바르지 않습니다.");
  }
  const targetRuntimeVersion = string(
    payload.targetRuntimeVersion, /^(?:contract:\d+|extractor:\d+\.\d+\.\d+)$/,
    "targetRuntimeVersion",
  );
  if (!extractionRuntimeVersionMatchesStage(payload.stage, targetRuntimeVersion)) {
    throw new IssueOperationsRequestError("runtime version과 stage가 일치하지 않습니다.");
  }
  if (!Number.isSafeInteger(payload.expectedStateVersion) || Number(payload.expectedStateVersion) < 0) {
    throw new IssueOperationsRequestError("expectedStateVersion이 올바르지 않습니다.");
  }
  return {
    environment: record.environment,
    requestID,
    action: "verifyFix",
    payload: {
      fingerprint: string(payload.fingerprint, /^[a-f0-9]{40}$/, "fingerprint"),
      expectedStateVersion: Number(payload.expectedStateVersion),
      stage: payload.stage,
      targetRuntimeVersion,
      workerRevision: string(
        payload.workerRevision, /^[a-z0-9][a-z0-9-]{2,126}$/, "workerRevision",
      ),
      workerSourceRevision: string(
        payload.workerSourceRevision, /^[a-f0-9]{7,40}$/, "workerSourceRevision",
      ),
    },
  };
}

function object(value: unknown, label: string): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new IssueOperationsRequestError(`${label}가 객체여야 합니다.`);
  }
  return value as Record<string, unknown>;
}

function exactKeys(value: Record<string, unknown>, allowed: string[]): void {
  const set = new Set(allowed);
  const unknown = Object.keys(value).find((key) => !set.has(key));
  if (unknown) throw new IssueOperationsRequestError(`허용되지 않은 field입니다: ${unknown}`);
}

function string(value: unknown, pattern: RegExp, label: string): string {
  if (typeof value !== "string" || !pattern.test(value)) {
    throw new IssueOperationsRequestError(`${label} 형식이 올바르지 않습니다.`);
  }
  return value;
}
