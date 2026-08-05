/* eslint-disable max-len */
import {createHash} from "node:crypto";

import type {WorkerConfig} from "./config.js";
import {
  CURRENT_ADAPTER_VERSIONS,
} from "./extraction/adapters/registry.js";
import {CURRENT_EXTRACTION_VERSIONS} from "./extraction/version.js";
import {extractionCandidateKey} from "./extraction/evidence.js";
import {imageExtractionIssueDisposition, seasonDiscoveryIssueDisposition} from "./extraction/issue-policy.js";
import {processDiscoverSeasonsDiagnosticRequest} from "./season-discovery.js";
import {runImageExtractionSmoke} from "./processor.js";

export type ExtractionSmokeStage = "seasonDiscovery" | "seasonImageImport";

export type WorkerRuntimeContract = {
  schemaVersion: 1;
  projectID: string;
  workerRevision: string;
  workerSourceRevision: string;
  seasonDiscoveryContractRevision: number;
  seasonDiscoveryExtractorVersion: string;
  imageExtractorVersion: string;
  adapterVersions: Record<string, string>;
};

export type ExtractionSmokeRequest = {
  fingerprint?: unknown;
  stage?: unknown;
  sourceURL?: unknown;
  sourceJobPath?: unknown;
};

export type ExtractionSmokeResult = {
  fingerprint: string;
  stage: ExtractionSmokeStage;
  sourceJobPathHash: string;
  candidateCount: number;
  candidateKeys: string[];
  logicIssueDetected: boolean;
  failureReasons: string[];
  qualityReasons: string[];
  runtime: WorkerRuntimeContract;
};

export function workerRuntimeContract(config: WorkerConfig): WorkerRuntimeContract {
  return {
    schemaVersion: 1,
    projectID: config.projectID,
    workerRevision: config.workerRevision,
    workerSourceRevision: config.workerSourceRevision,
    seasonDiscoveryContractRevision: config.seasonDiscoveryContractRevision,
    seasonDiscoveryExtractorVersion: config.seasonDiscoveryExtractorVersion,
    imageExtractorVersion: CURRENT_EXTRACTION_VERSIONS.extractorVersion,
    adapterVersions: {...CURRENT_ADAPTER_VERSIONS},
  };
}

export async function processExtractionSmoke(
  request: ExtractionSmokeRequest,
  runtime: WorkerRuntimeContract,
): Promise<ExtractionSmokeResult> {
  const fingerprint = requiredPattern(
    request.fingerprint, /^[a-f0-9]{40}$/, "fingerprint",
  );
  const stage = request.stage;
  if (stage !== "seasonDiscovery" && stage !== "seasonImageImport") {
    throw new Error("stage 값이 올바르지 않습니다.");
  }
  const sourceURL = requiredHTTPSURL(request.sourceURL);
  const sourceJobPath = requiredPattern(
    request.sourceJobPath,
    /^brands\/[A-Za-z0-9_-]+\/(?:seasonDiscoveryJobs|importJobs)\/[A-Za-z0-9_-]+$/,
    "sourceJobPath",
  );
  if (stage === "seasonDiscovery") {
    const diagnostic = await processDiscoverSeasonsDiagnosticRequest({
      brandID: sourceJobPath.split("/")[1],
      archiveURL: sourceURL,
      requestedBy: "fix-verifier",
      diagnosticID: fingerprint,
    });
    const disposition = seasonDiscoveryIssueDisposition({
      failureReasons: diagnostic.diagnostic.failureReasons,
      unresolvedExpansion: diagnostic.diagnostic.unresolvedExpansion === true,
    });
    return {
      fingerprint,
      stage,
      sourceJobPathHash: hash(sourceJobPath, 40),
      candidateCount: diagnostic.candidates.length,
      candidateKeys: diagnostic.candidates.map((candidate) =>
        extractionCandidateKey(candidate.seasonURL)),
      logicIssueDetected: disposition === "extractionLogicInsufficient",
      failureReasons: diagnostic.diagnostic.failureReasons,
      qualityReasons: [],
      runtime,
    };
  }
  const result = await runImageExtractionSmoke(sourceURL);
  return {
    fingerprint,
    stage,
    sourceJobPathHash: hash(sourceJobPath, 40),
    candidateCount: result.candidateKeys.length,
    candidateKeys: result.candidateKeys,
    logicIssueDetected:
      imageExtractionIssueDisposition(result.evidence) ===
      "extractionLogicInsufficient",
    failureReasons: result.evidence.failureReasons,
    qualityReasons: result.evidence.qualityReasons,
    runtime,
  };
}

function requiredPattern(
  value: unknown, pattern: RegExp, label: string,
): string {
  if (typeof value !== "string" || !pattern.test(value)) {
    throw new Error(`${label} 값이 올바르지 않습니다.`);
  }
  return value;
}

function requiredHTTPSURL(value: unknown): string {
  if (typeof value !== "string" || value.length > 2048) {
    throw new Error("sourceURL 값이 올바르지 않습니다.");
  }
  const url = new URL(value);
  if (url.protocol !== "https:" || url.username || url.password) {
    throw new Error("sourceURL은 credential 없는 HTTPS URL이어야 합니다.");
  }
  return url.toString();
}

function hash(value: string, length: number): string {
  return createHash("sha256").update(value).digest("hex").slice(0, length);
}
