/* eslint-disable require-jsdoc */
export type ExtractionEvidenceCleanupTarget = {
  evidenceID: string;
  storagePath: string;
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
