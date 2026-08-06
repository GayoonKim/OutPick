import type {Firestore} from "firebase-admin/firestore";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import type {Storage} from "firebase-admin/storage";

import {
  compareExtractionRuntimeVersions,
  extractionRuntimeVersionIsAtLeast,
  extractionIssueOccurrenceKey,
  isExtractionIssueEligible,
  type ExtractionFailureDisposition,
} from "./issue-contract.js";
import {
  extractionAdapterIdentity,
  nextIssueClusterOccurrence,
  representativeEvidenceScore,
  shouldReplaceRepresentativeEvidence,
} from "./issue-policy.js";
import {
  evidenceExpiresAt,
  extractionEvidenceID,
  extractionEvidenceStoragePath,
  extractionIssueIdentity,
  type RetainedExtractionEvidence,
} from "./retained-evidence.js";

const REPRESENTATIVE_EVIDENCE_PATH_PATTERN = new RegExp(
  "^lookbook-extraction-cluster-evidence/" +
  "[a-f0-9]{40}/[a-f0-9]{40}\\.json$",
);

export type ExtractionIssueRecorderDependencies = {
  firestore: Firestore;
  storage: Storage;
};

type StorageBucket = ReturnType<Storage["bucket"]>;
type StorageFile = ReturnType<StorageBucket["file"]>;
type StorageFileSaveOptions = NonNullable<Parameters<StorageFile["save"]>[1]>;

export type ExtractionIssueOccurrenceInput = {
  brandID: string;
  jobPath: string;
  generation: number;
  disposition: ExtractionFailureDisposition;
  blockedRuntimeVersion: string;
  evidence: RetainedExtractionEvidence;
};

export type ExtractionIssueOccurrenceResult = {
  recorded: boolean;
  duplicate: boolean;
  fingerprint: string | null;
  evidenceID: string | null;
};

export async function recordExtractionIssueOccurrence(
  dependencies: ExtractionIssueRecorderDependencies,
  input: ExtractionIssueOccurrenceInput,
): Promise<ExtractionIssueOccurrenceResult> {
  if (!isExtractionIssueEligible(input.disposition)) {
    return {
      recorded: false,
      duplicate: false,
      fingerprint: null,
      evidenceID: null,
    };
  }
  const issue = extractionIssueIdentity(input.evidence);
  const evidenceID = extractionEvidenceID({
    jobPath: input.jobPath,
    generation: input.generation,
    stage: input.evidence.stage,
    fingerprint: issue.fingerprint,
  });
  const occurrenceKey = extractionIssueOccurrenceKey({
    jobPath: input.jobPath,
    generation: input.generation,
    evidenceID,
  });
  const storagePath = extractionEvidenceStoragePath(evidenceID);
  const representativeStoragePath =
    extractionRepresentativeEvidenceStoragePath(issue.fingerprint, evidenceID);
  const nowDate = new Date();
  const expiresAtDate = evidenceExpiresAt(nowDate);
  const occurrencePayload = Buffer.from(JSON.stringify({
    evidenceID,
    occurrenceKey,
    brandID: input.brandID,
    jobPath: input.jobPath,
    generation: input.generation,
    createdAt: nowDate.toISOString(),
    expiresAt: expiresAtDate.toISOString(),
    evidence: input.evidence,
  }));
  await dependencies.storage.bucket().file(storagePath).save(
    occurrencePayload,
    privateJSONMetadata({
      evidenceID,
      expiresAt: expiresAtDate.toISOString(),
    }),
  );

  const evidenceRef = dependencies.firestore
    .collection("lookbookExtractionEvidence")
    .doc(evidenceID);
  const clusterRef = dependencies.firestore
    .collection("lookbookExtractionIssueClusters")
    .doc(issue.fingerprint);
  const jobRef = dependencies.firestore.doc(input.jobPath);
  const candidateScore = representativeEvidenceScore(input.evidence);
  const adapter = extractionAdapterIdentity(input.evidence.versions);

  const outcome = await dependencies.firestore.runTransaction(
    async (transaction) => {
      const [ledgerSnapshot, clusterSnapshot] = await Promise.all([
        transaction.get(evidenceRef),
        transaction.get(clusterRef),
      ]);
      const cluster = clusterSnapshot.data() ?? {};
      if (ledgerSnapshot.exists) {
        const status = issueStatus(cluster.status);
        transaction.set(jobRef, jobIssueProjectionForCluster({
          cluster,
          fingerprint: issue.fingerprint,
          status,
          blockedRuntimeVersion: input.blockedRuntimeVersion,
          evidenceID,
          storagePath,
          expiresAt: ledgerSnapshot.data()?.expiresAt ?? null,
        }), {merge: true});
        return {
          duplicate: true,
          previousRepresentativeStoragePath: null,
          copyRepresentative:
            cluster.representativeEvidenceID === evidenceID &&
            cluster.representativeEvidenceStatus !== "ready",
        };
      }

      const clusterState = nextIssueClusterOccurrence({
        previous: cluster,
        runtimeVersion: input.blockedRuntimeVersion,
      });
      const replaceRepresentative = shouldReplaceRepresentativeEvidence({
        status: cluster.representativeEvidenceStatus,
        previousScore: cluster.representativeEvidenceScore,
        candidateScore,
      });
      const now = FieldValue.serverTimestamp();
      const expiresAt = Timestamp.fromDate(expiresAtDate);
      const clusterBlockedRuntimeVersion = latestBlockedRuntimeVersion(
        cluster.blockedRuntimeVersion,
        input.blockedRuntimeVersion,
      );
      transaction.create(evidenceRef, {
        evidenceID,
        occurrenceKey,
        stage: input.evidence.stage,
        brandID: input.brandID,
        jobPath: input.jobPath,
        generation: input.generation,
        issueFingerprint: issue.fingerprint,
        storagePath,
        createdAt: now,
        updatedAt: now,
        expiresAt,
      });
      transaction.set(clusterRef, {
        fingerprint: issue.fingerprint,
        stage: issue.stage,
        adapterScope: adapter.scope,
        adapterKey: adapter.key,
        platform: issue.platform,
        parserStrategy: issue.strategy,
        failureReasons: issue.failureReasons,
        qualityReasons: issue.qualityReasons,
        templateSignature: issue.templateSignature,
        extractorMajorVersion: issue.extractorMajorVersion,
        blockedRuntimeVersion: clusterBlockedRuntimeVersion,
        status: clusterState.status,
        stateVersion: clusterState.stateVersion,
        occurrenceCount: clusterState.occurrenceCount,
        recurrenceCount: clusterState.recurrenceCount,
        firstSeenAt: cluster.firstSeenAt ?? now,
        lastSeenAt: now,
        updatedAt: now,
        ...(clusterState.clearExpiresAt ?
          {expiresAt: FieldValue.delete()} : {}),
        ...(replaceRepresentative ? {
          representativeEvidenceID: evidenceID,
          representativeEvidenceStoragePath: representativeStoragePath,
          representativeEvidenceStatus: "pending",
          representativeEvidenceScore: candidateScore,
          representativeBrandID: input.brandID,
          representativeJobPath: input.jobPath,
          representativeEvidenceUpdatedAt: now,
        } : {}),
      }, {merge: true});
      transaction.set(jobRef, jobIssueProjectionForCluster({
        cluster,
        fingerprint: issue.fingerprint,
        status: clusterState.status,
        blockedRuntimeVersion: input.blockedRuntimeVersion,
        evidenceID,
        storagePath,
        expiresAt,
      }), {merge: true});
      return {
        duplicate: false,
        copyRepresentative: replaceRepresentative,
        previousRepresentativeStoragePath: replaceRepresentative &&
          typeof cluster.representativeEvidenceStoragePath === "string" ?
          cluster.representativeEvidenceStoragePath : null,
      };
    },
  );

  if (outcome.copyRepresentative) {
    const representativeWritten = await writeRepresentativeEvidenceSafely(
      dependencies,
      {
        clusterRef,
        fingerprint: issue.fingerprint,
        evidenceID,
        storagePath: representativeStoragePath,
        payload: Buffer.from(JSON.stringify({
          fingerprint: issue.fingerprint,
          evidenceID,
          brandID: input.brandID,
          jobPath: input.jobPath,
          generation: input.generation,
          updatedAt: nowDate.toISOString(),
          evidence: input.evidence,
        })),
      },
    );
    if (representativeWritten) {
      await deleteSupersededRepresentativeSafely(
        dependencies.storage,
        outcome.previousRepresentativeStoragePath,
        representativeStoragePath,
      );
    }
  }
  return {
    recorded: true,
    duplicate: outcome.duplicate,
    fingerprint: issue.fingerprint,
    evidenceID,
  };
}

export async function markExtractionIssueVerifiedIfEligible(input: {
  firestore: Firestore;
  jobPath: string;
  generation: number;
  runtimeVersion: string;
}): Promise<boolean> {
  const jobRef = input.firestore.doc(input.jobPath);
  return input.firestore.runTransaction(async (transaction) => {
    const jobSnapshot = await transaction.get(jobRef);
    const job = jobSnapshot.data() ?? {};
    const fingerprint = job.extractionIssueFingerprint;
    if (
      !jobSnapshot.exists ||
      typeof fingerprint !== "string" ||
      !/^[a-f0-9]{40}$/.test(fingerprint) ||
      job.extractionIssueStatus !== "fixed" ||
      typeof job.retryAvailableRuntimeVersion !== "string" ||
      !extractionRuntimeVersionIsAtLeast(
        input.runtimeVersion,
        job.retryAvailableRuntimeVersion,
      )
    ) {
      return false;
    }
    const clusterRef = input.firestore
      .collection("lookbookExtractionIssueClusters")
      .doc(fingerprint);
    const clusterSnapshot = await transaction.get(clusterRef);
    const cluster = clusterSnapshot.data() ?? {};
    if (
      !clusterSnapshot.exists ||
      (cluster.status !== "fixed" && cluster.status !== "verified") ||
      typeof cluster.fixedRuntimeVersion !== "string" ||
      !extractionRuntimeVersionIsAtLeast(
        input.runtimeVersion,
        cluster.fixedRuntimeVersion,
      )
    ) {
      return false;
    }
    const now = FieldValue.serverTimestamp();
    if (cluster.status === "fixed") {
      transaction.update(clusterRef, {
        status: "verified",
        stateVersion: nonNegativeInteger(cluster.stateVersion, 1) + 1,
        verifiedAt: now,
        verifiedByJobPath: input.jobPath,
        verifiedByGeneration: input.generation,
        updatedAt: now,
        expiresAt: Timestamp.fromMillis(
          Date.now() + 60 * 24 * 60 * 60 * 1000,
        ),
      });
    }
    transaction.set(jobRef, {
      extractionIssueStatus: FieldValue.delete(),
      extractionIssueWontFixReason: FieldValue.delete(),
      resolvedByGeneration: input.generation,
      updatedAt: now,
    }, {merge: true});
    return true;
  });
}

export function extractionRepresentativeEvidenceStoragePath(
  fingerprint: string,
  evidenceID: string,
): string {
  if (
    !/^[a-f0-9]{40}$/.test(fingerprint) ||
    !/^[a-f0-9]{40}$/.test(evidenceID)
  ) {
    throw new Error("issue fingerprint 또는 evidence ID가 올바르지 않습니다.");
  }
  return "lookbook-extraction-cluster-evidence/" +
    `${fingerprint}/${evidenceID}.json`;
}

async function deleteSupersededRepresentativeSafely(
  storage: Storage,
  previousPath: string | null,
  currentPath: string,
): Promise<void> {
  if (
    previousPath === null ||
    previousPath === currentPath ||
    !REPRESENTATIVE_EVIDENCE_PATH_PATTERN.test(previousPath)
  ) {
    return;
  }
  await storage.bucket().file(previousPath)
    .delete({ignoreNotFound: true})
    .catch(() => {
      // 현재 대표 증거는 이미 기록됐으므로 이전 object 정리 실패를 전파하지 않는다.
    });
}

async function writeRepresentativeEvidenceSafely(
  dependencies: ExtractionIssueRecorderDependencies,
  input: {
    clusterRef: FirebaseFirestore.DocumentReference;
    fingerprint: string;
    evidenceID: string;
    storagePath: string;
    payload: Buffer;
  },
): Promise<boolean> {
  try {
    await dependencies.storage.bucket().file(input.storagePath).save(
      input.payload,
      privateJSONMetadata({fingerprint: input.fingerprint}),
    );
    await updateRepresentativeStatus(
      dependencies.firestore,
      input.clusterRef,
      input.evidenceID,
      "ready",
    );
    return true;
  } catch {
    await updateRepresentativeStatus(
      dependencies.firestore,
      input.clusterRef,
      input.evidenceID,
      "missing",
    ).catch(() => {
      // occurrence/cluster 기록은 완료됐으므로 보조 상태 갱신 실패를 전파하지 않는다.
    });
    return false;
  }
}

async function updateRepresentativeStatus(
  firestore: Firestore,
  clusterRef: FirebaseFirestore.DocumentReference,
  evidenceID: string,
  status: "ready" | "missing",
): Promise<void> {
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(clusterRef);
    if (
      snapshot.exists &&
      snapshot.data()?.representativeEvidenceID === evidenceID
    ) {
      transaction.update(clusterRef, {
        representativeEvidenceStatus: status,
        representativeEvidenceUpdatedAt: FieldValue.serverTimestamp(),
      });
    }
  });
}

function jobIssueProjection(input: {
  fingerprint: string;
  status: string;
  blockedRuntimeVersion: string;
  evidenceID: string;
  storagePath: string;
  expiresAt: unknown;
  retryAvailableRuntimeVersion?: string | null;
  retryAvailableAt?: unknown;
}): Record<string, unknown> {
  return {
    extractionIssueFingerprint: input.fingerprint,
    extractionIssueStatus: input.status,
    extractionIssueWontFixReason: null,
    blockedRuntimeVersion: input.blockedRuntimeVersion,
    retryAvailableRuntimeVersion:
      input.retryAvailableRuntimeVersion ?? null,
    retryAvailableAt: input.retryAvailableAt ?? null,
    evidenceRetentionStatus: "stored",
    evidenceID: input.evidenceID,
    evidenceStoragePath: input.storagePath,
    evidenceExpiresAt: input.expiresAt,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function jobIssueProjectionForCluster(input: {
  cluster: Record<string, unknown>;
  fingerprint: string;
  status: string;
  blockedRuntimeVersion: string;
  evidenceID: string;
  storagePath: string;
  expiresAt: unknown;
}): Record<string, unknown> {
  const fixedRuntimeVersion = typeof input.cluster.fixedRuntimeVersion ===
    "string" ? input.cluster.fixedRuntimeVersion : null;
  const fixedForOccurrence =
    (input.status === "fixed" || input.status === "verified") &&
    fixedRuntimeVersion !== null &&
    compareExtractionRuntimeVersions(
      input.blockedRuntimeVersion,
      fixedRuntimeVersion,
    ) === -1;
  return jobIssueProjection({
    fingerprint: input.fingerprint,
    status: fixedForOccurrence ? "fixed" : input.status,
    blockedRuntimeVersion: input.blockedRuntimeVersion,
    evidenceID: input.evidenceID,
    storagePath: input.storagePath,
    expiresAt: input.expiresAt,
    retryAvailableRuntimeVersion:
      fixedForOccurrence ? fixedRuntimeVersion : null,
    retryAvailableAt: fixedForOccurrence ?
      input.cluster.fixedAt ?? FieldValue.serverTimestamp() : null,
  });
}

function latestBlockedRuntimeVersion(
  previous: unknown,
  occurrence: string,
): string {
  if (typeof previous !== "string") return occurrence;
  return compareExtractionRuntimeVersions(previous, occurrence) === -1 ?
    occurrence : previous;
}

function issueStatus(value: unknown): string {
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim() :
    "open";
}

function nonNegativeInteger(value: unknown, fallback: number): number {
  return Number.isSafeInteger(value) && Number(value) >= 0 ?
    Number(value) : fallback;
}

function privateJSONMetadata(
  metadata: Record<string, string>,
): StorageFileSaveOptions {
  return {
    resumable: false,
    contentType: "application/json",
    metadata: {
      cacheControl: "private, no-store",
      metadata,
    },
  };
}
