/* eslint-disable require-jsdoc */
export type ExtractionEvidenceCleanupTarget = {
  evidenceID: string;
  storagePath: string;
};

export type ExtractionIssueClusterCleanupTarget = {
  fingerprint: string;
  representativeEvidenceID: string;
  representativeStoragePath: string;
};

export function extractionEvidenceCleanupTarget(input: {
  evidenceID: string;
  storagePath: unknown;
}): ExtractionEvidenceCleanupTarget | null {
  if (!/^[a-f0-9]{40}$/.test(input.evidenceID)) {
    return null;
  }
  const expectedPath =
    `lookbook-extraction-evidence/${input.evidenceID}.json`;
  if (input.storagePath !== expectedPath) {
    return null;
  }
  return {
    evidenceID: input.evidenceID,
    storagePath: expectedPath,
  };
}

export function extractionIssueClusterCleanupTarget(input: {
  fingerprint: string;
  representativeEvidenceID: unknown;
  representativeStoragePath: unknown;
}): ExtractionIssueClusterCleanupTarget | null {
  if (!/^[a-f0-9]{40}$/.test(input.fingerprint)) {
    return null;
  }
  if (
    typeof input.representativeEvidenceID !== "string" ||
    !/^[a-f0-9]{40}$/.test(input.representativeEvidenceID)
  ) {
    return null;
  }
  const expectedPath = "lookbook-extraction-cluster-evidence/" +
    `${input.fingerprint}/${input.representativeEvidenceID}.json`;
  if (input.representativeStoragePath !== expectedPath) {
    return null;
  }
  return {
    fingerprint: input.fingerprint,
    representativeEvidenceID: input.representativeEvidenceID,
    representativeStoragePath: expectedPath,
  };
}
