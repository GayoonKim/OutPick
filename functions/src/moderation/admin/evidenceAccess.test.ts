/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {assertEvidenceStorageOwnership, EvidenceObjectDescriptor} from "./evidenceAccess.js";

const object: EvidenceObjectDescriptor = {
  bundleID: "bundle-1",
  attachmentID: "attachment-1",
  bucket: "evidence-bucket",
  path: "bundle-1/g2/attachment-1/display",
  destinationGeneration: "123",
  sourceGeneration: "12",
  bytes: 1024,
  contentType: "image/jpeg",
  attemptGeneration: 2,
};

test("Evidence Storage metadata는 bundle·attachment·attempt·generation을 모두 일치시킨다", () => {
  assert.doesNotThrow(() => assertEvidenceStorageOwnership(object, {
    generation: "123",
    size: 1024,
    contentType: "image/jpeg",
    metadata: {
      outpickEvidenceBundleID: "bundle-1",
      outpickEvidenceAttachmentID: "attachment-1",
      outpickEvidenceAttemptGeneration: "2",
      outpickEvidenceSourceGeneration: "12",
    },
  }));
  assert.throws(() => assertEvidenceStorageOwnership(object, {
    generation: "124",
    size: 1024,
    contentType: "image/jpeg",
    metadata: {
      outpickEvidenceBundleID: "bundle-1",
      outpickEvidenceAttachmentID: "attachment-1",
      outpickEvidenceAttemptGeneration: "2",
      outpickEvidenceSourceGeneration: "12",
    },
  }), (error) => error instanceof HttpsError && error.code === "failed-precondition");
});
