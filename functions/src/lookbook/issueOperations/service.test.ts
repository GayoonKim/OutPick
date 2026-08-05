/* eslint-disable require-jsdoc, max-len */
import assert from "node:assert/strict";
import test from "node:test";
import type {Firestore} from "firebase-admin/firestore";

import {parseWriteRequest} from "./contract.js";
import {
  decodeIssueClusterCursor,
  encodeIssueClusterCursor,
  getIssueClustersBatch,
  mutateIssueCluster,
} from "./service.js";

type Data = Record<string, unknown>;
type Reference = {kind: "reference"; path: string; id: string};
type GroupQuery = {
  kind: "query";
  group: string;
  field?: string;
  value?: unknown;
};

class FakeFirestore {
  readonly documents = new Map<string, Data>();

  readonly api = {
    collection: (path: string) => ({
      doc: (id: string): Reference => ({
        kind: "reference", path: `${path}/${id}`, id,
      }),
    }),
    collectionGroup: (group: string): GroupQuery & {
      where: (field: string, operator: string, value: unknown) => GroupQuery & {
        limit: (limit: number) => GroupQuery;
      };
    } => {
      const query: GroupQuery = {kind: "query", group};
      return Object.assign(query, {
        where: (field: string, _operator: string, value: unknown) => {
          const filtered = {...query, field, value};
          return Object.assign(filtered, {limit: () => filtered});
        },
      });
    },
    getAll: async (...references: Reference[]) => references.map((reference) => ({
      id: reference.id,
      exists: this.documents.has(reference.path),
      data: () => this.documents.get(reference.path),
    })),
    runTransaction: async <Result>(operation: (
      transaction: ReturnType<FakeFirestore["transaction"]>
    ) => Promise<Result>): Promise<Result> => operation(this.transaction()),
  };

  firestore(): Firestore {
    return this.api as unknown as Firestore;
  }

  private transaction() {
    return {
      get: async (target: Reference | GroupQuery) => {
        if (target.kind === "reference") {
          return {
            exists: this.documents.has(target.path),
            data: () => this.documents.get(target.path),
          };
        }
        const docs = Array.from(this.documents.entries())
          .filter(([path, data]) =>
            path.split("/").at(-2) === target.group &&
            data[target.field ?? ""] === target.value)
          .map(([path, data]) => ({
            ref: {kind: "reference", path, id: path.split("/").at(-1) ?? ""},
            data: () => data,
          }));
        return {size: docs.length, docs};
      },
      update: (reference: Reference, patch: Data) => {
        this.documents.set(reference.path, {
          ...(this.documents.get(reference.path) ?? {}), ...patch,
        });
      },
      set: (reference: Reference, patch: Data) => {
        this.documents.set(reference.path, {
          ...(this.documents.get(reference.path) ?? {}), ...patch,
        });
      },
      create: (reference: Reference, value: Data) => {
        if (this.documents.has(reference.path)) throw new Error("exists");
        this.documents.set(reference.path, value);
      },
    };
  }
}

const fingerprint = "a".repeat(40);
const operatorEmail =
  "outpick-extraction-ops-dev@outpick-test.iam.gserviceaccount.com";

function startRequest(requestID = "request_12345678") {
  return parseWriteRequest({
    apiVersion: 1,
    environment: "development",
    requestID,
    action: "startProcessing",
    payload: {fingerprint, expectedStateVersion: 1},
  });
}

test("mutation은 CAS 상태와 해당 job projection을 함께 갱신한다", async () => {
  const fake = new FakeFirestore();
  fake.documents.set(`lookbookExtractionIssueClusters/${fingerprint}`, {
    stage: "seasonDiscovery",
    status: "open",
    stateVersion: 1,
  });
  const jobPath = "brands/brand-a/seasonDiscoveryJobs/job-a";
  fake.documents.set(jobPath, {extractionIssueFingerprint: fingerprint});
  const result = await mutateIssueCluster({
    firestore: fake.firestore(),
    request: startRequest(),
    operatorEmail,
  });
  assert.equal(result.status, "inProgress");
  assert.equal(fake.documents.get(jobPath)?.extractionIssueStatus, "inProgress");
  assert.equal(fake.documents.get(jobPath)?.extractionIssueWontFixReason, null);
});

test("wont-fix 사유를 해당 job projection에 함께 기록한다", async () => {
  const fake = new FakeFirestore();
  fake.documents.set(`lookbookExtractionIssueClusters/${fingerprint}`, {
    stage: "seasonDiscovery",
    status: "open",
    stateVersion: 1,
  });
  const jobPath = "brands/brand-a/seasonDiscoveryJobs/job-a";
  fake.documents.set(jobPath, {extractionIssueFingerprint: fingerprint});
  await mutateIssueCluster({
    firestore: fake.firestore(),
    request: parseWriteRequest({
      apiVersion: 1,
      environment: "development",
      requestID: "request_wont_fix_123",
      action: "markWontFix",
      payload: {
        fingerprint,
        expectedStateVersion: 1,
        wontFixReason: "sourceUnavailable",
        note: "원본 페이지가 삭제됨",
      },
    }),
    operatorEmail,
  });
  assert.equal(fake.documents.get(jobPath)?.extractionIssueStatus, "wontFix");
  assert.equal(
    fake.documents.get(jobPath)?.extractionIssueWontFixReason,
    "sourceUnavailable",
  );
});

test("같은 request ID는 audit과 stateVersion을 중복 변경하지 않는다", async () => {
  const fake = new FakeFirestore();
  const clusterPath = `lookbookExtractionIssueClusters/${fingerprint}`;
  fake.documents.set(clusterPath, {
    stage: "seasonImageImport",
    status: "open",
    stateVersion: 1,
  });
  const input = {
    firestore: fake.firestore(),
    request: startRequest(),
    operatorEmail,
  };
  await mutateIssueCluster(input);
  const duplicate = await mutateIssueCluster(input);
  assert.equal(duplicate.duplicate, true);
  assert.equal(fake.documents.get(clusterPath)?.stateVersion, 2);
  const audits = Array.from(fake.documents.keys())
    .filter((path) => path.startsWith("lookbookExtractionIssueAuditLogs/"));
  assert.equal(audits.length, 1);
});

test("stale stateVersion은 mutation과 audit 없이 거부한다", async () => {
  const fake = new FakeFirestore();
  fake.documents.set(`lookbookExtractionIssueClusters/${fingerprint}`, {
    stage: "seasonDiscovery",
    status: "open",
    stateVersion: 2,
  });
  await assert.rejects(mutateIssueCluster({
    firestore: fake.firestore(),
    request: startRequest("request_stale_123"),
    operatorEmail,
  }), /stateVersion 충돌/);
});

test("cursor는 timestamp와 fingerprint를 결정적으로 왕복한다", () => {
  const value = {fingerprint, lastSeenAtMillis: 123456};
  assert.deepEqual(
    decodeIssueClusterCursor(encodeIssueClusterCursor(value)),
    value,
  );
  assert.throws(() => decodeIssueClusterCursor("unsafe"), /cursor/);
});

test("batch는 요청 순서대로 found와 missing을 구분한다", async () => {
  const fake = new FakeFirestore();
  const found = "b".repeat(40);
  const missing = "c".repeat(40);
  fake.documents.set(`lookbookExtractionIssueClusters/${found}`, {
    stage: "seasonDiscovery",
    status: "open",
    stateVersion: 1,
    representativeEvidenceStatus: "missing",
  });
  const result = await getIssueClustersBatch({
    firestore: fake.firestore(),
    bucket: {} as never,
    fingerprints: [missing, found],
  });
  assert.deepEqual(result.map((item) => item.status), [
    "missing", "evidenceExpired",
  ]);
});
