import assert from "node:assert/strict";
import test from "node:test";
import type {Firestore} from "firebase-admin/firestore";
import type {Storage} from "firebase-admin/storage";

import {
  markExtractionIssueVerifiedIfEligible,
  recordExtractionIssueOccurrence,
} from "./issue-recorder.js";
import {buildRetainedExtractionEvidence} from "./retained-evidence.js";
import {CURRENT_EXTRACTION_VERSIONS} from "./version.js";

type Document = Record<string, unknown>;
type Reference = {path: string};

class FakePersistence {
  readonly documents = new Map<string, Document>();
  readonly objects = new Map<string, Buffer>();
  failRepresentativeSave = false;

  readonly firestore = {
    collection: (path: string) => ({
      doc: (id: string): Reference => ({path: `${path}/${id}`}),
    }),
    doc: (path: string): Reference => ({path}),
    runTransaction: async <Result>(
      operation: (transaction: ReturnType<FakePersistence["transaction"]>) =>
        Promise<Result>,
    ): Promise<Result> => operation(this.transaction()),
  };

  readonly storage = {
    bucket: () => ({
      file: (path: string) => ({
        save: async (payload: Buffer): Promise<void> => {
          if (
            this.failRepresentativeSave &&
            path.startsWith("lookbook-extraction-cluster-evidence/")
          ) {
            throw new Error("representative save failed");
          }
          this.objects.set(path, payload);
        },
        delete: async (): Promise<void> => {
          this.objects.delete(path);
        },
      }),
    }),
  };

  dependencies(): {firestore: Firestore; storage: Storage} {
    return {
      firestore: this.firestore as unknown as Firestore,
      storage: this.storage as unknown as Storage,
    };
  }

  private transaction() {
    return {
      get: async (reference: Reference) => ({
        exists: this.documents.has(reference.path),
        data: () => this.documents.get(reference.path),
      }),
      create: (reference: Reference, value: Document) => {
        if (this.documents.has(reference.path)) {
          throw new Error("already exists");
        }
        this.documents.set(reference.path, {...value});
      },
      set: (
        reference: Reference,
        value: Document,
        options?: {merge?: boolean},
      ) => {
        const previous = options?.merge ?
          this.documents.get(reference.path) ?? {} : {};
        this.documents.set(reference.path, {...previous, ...value});
      },
      update: (reference: Reference, value: Document) => {
        const previous = this.documents.get(reference.path) ?? {};
        this.documents.set(reference.path, {...previous, ...value});
      },
    };
  }
}

function issueEvidence() {
  return buildRetainedExtractionEvidence({
    status: "needsReview",
    stage: "seasonImageImport",
    sourceURL: "https://brand.example/lookbook",
    strategy: "mainContent",
    qualityReasons: ["expected_count_mismatch"],
    templateSignature: "template",
    versions: CURRENT_EXTRACTION_VERSIONS,
  });
}

test("같은 job occurrence를 재처리해도 cluster count는 한 번만 증가한다", async () => {
  const fake = new FakePersistence();
  const input = {
    brandID: "brand-a",
    jobPath: "brands/brand-a/seasons/season-a/importJobs/job-a",
    generation: 3,
    disposition: "extractionLogicInsufficient" as const,
    blockedRuntimeVersion: "extractor:1.0.0",
    evidence: issueEvidence(),
  };
  const first = await recordExtractionIssueOccurrence(
    fake.dependencies(), input,
  );
  const second = await recordExtractionIssueOccurrence(
    fake.dependencies(), input,
  );

  assert.equal(first.recorded, true);
  assert.equal(first.duplicate, false);
  assert.equal(second.duplicate, true);
  const cluster = fake.documents.get(
    `lookbookExtractionIssueClusters/${first.fingerprint}`,
  );
  assert.equal(cluster?.occurrenceCount, 1);
  assert.equal(cluster?.representativeEvidenceStatus, "ready");
  assert.equal("affectedDomains" in (cluster ?? {}), false);
  assert.equal("affectedDomainCount" in (cluster ?? {}), false);
  const job = fake.documents.get(input.jobPath);
  assert.equal(job?.extractionIssueStatus, "open");
  assert.equal(job?.extractionIssueWontFixReason, null);
  assert.equal(fake.objects.size, 2);
});

test("logic issue가 아닌 결과는 ledger와 storage에 기록하지 않는다", async () => {
  const fake = new FakePersistence();
  const result = await recordExtractionIssueOccurrence(fake.dependencies(), {
    brandID: "brand-a",
    jobPath: "brands/brand-a/seasonDiscoveryJobs/job-a",
    generation: 1,
    disposition: "identityReview",
    blockedRuntimeVersion: "contract:1",
    evidence: issueEvidence(),
  });
  assert.deepEqual(result, {
    recorded: false,
    duplicate: false,
    fingerprint: null,
    evidenceID: null,
  });
  assert.equal(fake.documents.size, 0);
  assert.equal(fake.objects.size, 0);
});

test("대표 evidence 저장 실패는 occurrence를 실패시키지 않는다", async () => {
  const fake = new FakePersistence();
  fake.failRepresentativeSave = true;
  const result = await recordExtractionIssueOccurrence(fake.dependencies(), {
    brandID: "brand-a",
    jobPath: "brands/brand-a/seasonDiscoveryJobs/job-a",
    generation: 1,
    disposition: "extractionLogicInsufficient",
    blockedRuntimeVersion: "contract:1",
    evidence: issueEvidence(),
  });
  assert.equal(result.recorded, true);
  const cluster = fake.documents.get(
    `lookbookExtractionIssueClusters/${result.fingerprint}`,
  );
  assert.equal(cluster?.representativeEvidenceStatus, "missing");
  assert.equal(fake.objects.size, 1);
});

test("늦게 도착한 구형 occurrence가 cluster blocked runtime을 낮추지 않는다", async () => {
  const fake = new FakePersistence();
  const first = await recordExtractionIssueOccurrence(fake.dependencies(), {
    brandID: "brand-a",
    jobPath: "brands/brand-a/importJobs/job-new",
    generation: 1,
    disposition: "extractionLogicInsufficient",
    blockedRuntimeVersion: "extractor:1.3.0",
    evidence: issueEvidence(),
  });
  await recordExtractionIssueOccurrence(fake.dependencies(), {
    brandID: "brand-a",
    jobPath: "brands/brand-a/importJobs/job-old",
    generation: 1,
    disposition: "extractionLogicInsufficient",
    blockedRuntimeVersion: "extractor:1.2.0",
    evidence: issueEvidence(),
  });

  const cluster = fake.documents.get(
    `lookbookExtractionIssueClusters/${first.fingerprint}`,
  );
  assert.equal(cluster?.blockedRuntimeVersion, "extractor:1.3.0");
  assert.equal(cluster?.occurrenceCount, 2);
  assert.equal(
    fake.documents.get("brands/brand-a/importJobs/job-old")
      ?.blockedRuntimeVersion,
    "extractor:1.2.0",
  );
});

test("fixed 뒤 도착한 구형 occurrence와 duplicate에 재시도 runtime을 투영한다", async () => {
  const fake = new FakePersistence();
  const originalInput = {
    brandID: "brand-a",
    jobPath: "brands/brand-a/importJobs/job-original",
    generation: 1,
    disposition: "extractionLogicInsufficient" as const,
    blockedRuntimeVersion: "extractor:1.2.0",
    evidence: issueEvidence(),
  };
  const original = await recordExtractionIssueOccurrence(
    fake.dependencies(),
    originalInput,
  );
  const clusterPath =
    `lookbookExtractionIssueClusters/${original.fingerprint}`;
  fake.documents.set(clusterPath, {
    ...fake.documents.get(clusterPath),
    status: "fixed",
    stateVersion: 2,
    fixedRuntimeVersion: "extractor:1.3.0",
    fixedAt: "fixed-at",
  });

  const lateJobPath = "brands/brand-a/importJobs/job-late";
  await recordExtractionIssueOccurrence(fake.dependencies(), {
    ...originalInput,
    jobPath: lateJobPath,
  });
  await recordExtractionIssueOccurrence(fake.dependencies(), originalInput);

  for (const jobPath of [lateJobPath, originalInput.jobPath]) {
    const job = fake.documents.get(jobPath);
    assert.equal(job?.extractionIssueStatus, "fixed");
    assert.equal(job?.blockedRuntimeVersion, "extractor:1.2.0");
    assert.equal(job?.retryAvailableRuntimeVersion, "extractor:1.3.0");
    assert.equal(job?.retryAvailableAt, "fixed-at");
  }
  assert.equal(fake.documents.get(clusterPath)?.status, "fixed");
  assert.equal(
    fake.documents.get(clusterPath)?.blockedRuntimeVersion,
    "extractor:1.2.0",
  );
});

test("fixed runtime의 실제 재추출 성공만 cluster를 verified로 바꾼다", async () => {
  const fake = new FakePersistence();
  const fingerprint = "f".repeat(40);
  const jobPath = "brands/brand-a/importJobs/job-a";
  fake.documents.set(jobPath, {
    extractionIssueFingerprint: fingerprint,
    extractionIssueStatus: "fixed",
    retryAvailableRuntimeVersion: "extractor:1.3.0",
  });
  fake.documents.set(`lookbookExtractionIssueClusters/${fingerprint}`, {
    status: "fixed",
    stateVersion: 4,
    fixedRuntimeVersion: "extractor:1.3.0",
  });
  assert.equal(await markExtractionIssueVerifiedIfEligible({
    firestore: fake.firestore as unknown as Firestore,
    jobPath,
    generation: 7,
    runtimeVersion: "extractor:1.3.0",
  }), true);
  const cluster = fake.documents.get(
    `lookbookExtractionIssueClusters/${fingerprint}`,
  );
  assert.equal(cluster?.status, "verified");
  assert.equal(cluster?.stateVersion, 5);
  assert.equal(cluster?.verifiedByJobPath, jobPath);
});

test("이미 verified인 cluster의 늦은 재시도 성공은 job projection만 닫는다", async () => {
  const fake = new FakePersistence();
  const original = await recordExtractionIssueOccurrence(fake.dependencies(), {
    brandID: "brand-a",
    jobPath: "brands/brand-a/importJobs/job-original",
    generation: 1,
    disposition: "extractionLogicInsufficient",
    blockedRuntimeVersion: "extractor:1.2.0",
    evidence: issueEvidence(),
  });
  assert.ok(original.fingerprint);
  const fingerprint = original.fingerprint;
  const jobPath = "brands/brand-a/importJobs/job-late";
  fake.documents.set(`lookbookExtractionIssueClusters/${fingerprint}`, {
    ...fake.documents.get(`lookbookExtractionIssueClusters/${fingerprint}`),
    status: "verified",
    stateVersion: 5,
    fixedRuntimeVersion: "extractor:1.3.0",
    fixedAt: "fixed-at",
    verifiedByJobPath: "brands/brand-b/importJobs/job-first",
  });
  await recordExtractionIssueOccurrence(fake.dependencies(), {
    brandID: "brand-a",
    jobPath,
    generation: 1,
    disposition: "extractionLogicInsufficient",
    blockedRuntimeVersion: "extractor:1.2.0",
    evidence: issueEvidence(),
  });
  assert.equal(
    fake.documents.get(jobPath)?.extractionIssueStatus,
    "fixed",
  );
  assert.equal(
    fake.documents.get(jobPath)?.retryAvailableRuntimeVersion,
    "extractor:1.3.0",
  );

  assert.equal(await markExtractionIssueVerifiedIfEligible({
    firestore: fake.firestore as unknown as Firestore,
    jobPath,
    generation: 8,
    runtimeVersion: "extractor:1.3.0",
  }), true);
  const cluster = fake.documents.get(
    `lookbookExtractionIssueClusters/${fingerprint}`,
  );
  assert.equal(cluster?.status, "verified");
  assert.equal(cluster?.stateVersion, 5);
  assert.equal(
    cluster?.verifiedByJobPath,
    "brands/brand-b/importJobs/job-first",
  );
  const job = fake.documents.get(jobPath);
  assert.equal(job?.resolvedByGeneration, 8);
  assert.notEqual(job?.extractionIssueStatus, "fixed");
});
