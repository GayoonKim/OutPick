import assert from "node:assert/strict";
import test from "node:test";

import {
  extractionEvidenceCleanupTarget,
  extractionIssueClusterCleanupTarget,
} from "./evidenceCleanup.js";

test("evidence cleanup은 결정적 전용 prefix만 허용한다", () => {
  const evidenceID = "a".repeat(40);
  assert.deepEqual(
    extractionEvidenceCleanupTarget({
      evidenceID,
      storagePath: `lookbook-extraction-evidence/${evidenceID}.json`,
    }),
    {
      evidenceID,
      storagePath: `lookbook-extraction-evidence/${evidenceID}.json`,
    }
  );
});

test("cluster cleanup은 대표 증거 전용 prefix만 허용한다", () => {
  const fingerprint = "c".repeat(40);
  const evidenceID = "d".repeat(40);
  const representativeStoragePath =
    `lookbook-extraction-cluster-evidence/${fingerprint}/${evidenceID}.json`;
  assert.deepEqual(
    extractionIssueClusterCleanupTarget({
      fingerprint,
      representativeEvidenceID: evidenceID,
      representativeStoragePath,
    }),
    {
      fingerprint,
      representativeEvidenceID: evidenceID,
      representativeStoragePath,
    }
  );
  assert.equal(
    extractionIssueClusterCleanupTarget({
      fingerprint,
      representativeEvidenceID: evidenceID,
      representativeStoragePath:
        `lookbook-extraction-evidence/${fingerprint}.json`,
    }),
    null
  );
});

test("evidence cleanup은 다른 Storage path를 거부한다", () => {
  const evidenceID = "b".repeat(40);
  assert.equal(
    extractionEvidenceCleanupTarget({
      evidenceID,
      storagePath: `brands/${evidenceID}/cover.jpg`,
    }),
    null
  );
  assert.equal(
    extractionEvidenceCleanupTarget({
      evidenceID: "../unsafe",
      storagePath: "lookbook-extraction-evidence/../unsafe.json",
    }),
    null
  );
});
