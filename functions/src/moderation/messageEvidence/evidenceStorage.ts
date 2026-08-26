/* eslint-disable require-jsdoc, max-len */
import {getStorage} from "firebase-admin/storage";
import type {FileMetadata} from "@google-cloud/storage";
import {
  MessageEvidenceCopyError,
  MessageEvidenceObject,
  MessageEvidenceStorage,
} from "./evidenceCopy.js";

function numericMetadata(value: unknown): number {
  const parsed = typeof value === "string" || typeof value === "number" ? Number(value) : NaN;
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new MessageEvidenceCopyError("INVALID_STORAGE_METADATA", "storage object size is invalid");
  }
  return parsed;
}

function stringMetadata(value: unknown, field: string): string {
  if (typeof value !== "string" || !value) {
    throw new MessageEvidenceCopyError("INVALID_STORAGE_METADATA", `storage ${field} is invalid`);
  }
  return value;
}

function apiStatus(error: unknown): number | null {
  if (!error || typeof error !== "object") return null;
  const code = (error as {code?: unknown}).code;
  return typeof code === "number" ? code : typeof code === "string" && /^\d+$/.test(code) ? Number(code) : null;
}

function customMetadata(metadata: FileMetadata): Record<string, string> {
  const value = metadata.metadata;
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, String(item)]));
}

function assertDestinationOwnership(input: {
  metadata: FileMetadata;
  bundleID: string;
  attachmentID: string;
  attemptGeneration: number;
  sourceGeneration?: string;
}): void {
  const custom = customMetadata(input.metadata);
  if (custom.outpickEvidenceBundleID !== input.bundleID ||
      custom.outpickEvidenceAttachmentID !== input.attachmentID ||
      custom.outpickEvidenceAttemptGeneration !== String(input.attemptGeneration) ||
      (input.sourceGeneration !== undefined && custom.outpickEvidenceSourceGeneration !== input.sourceGeneration)) {
    throw new MessageEvidenceCopyError("EVIDENCE_DESTINATION_CONFLICT", "evidence destination belongs to another attempt");
  }
}

function evidenceObject(input: {
  metadata: FileMetadata;
  attachmentID: string;
  bucket: string;
  path: string;
  sourceGeneration: string;
}): MessageEvidenceObject {
  return {
    attachmentID: input.attachmentID,
    bucket: input.bucket,
    path: input.path,
    destinationGeneration: stringMetadata(input.metadata.generation, "generation"),
    sourceGeneration: input.sourceGeneration,
    bytes: numericMetadata(input.metadata.size),
    contentType: stringMetadata(input.metadata.contentType, "contentType"),
    crc32c: typeof input.metadata.crc32c === "string" ? input.metadata.crc32c : null,
  };
}

async function assertObjectPathAbsent(input: {bucket: string; path: string}): Promise<void> {
  try {
    await getStorage().bucket(input.bucket).file(input.path).getMetadata();
  } catch (error) {
    if (apiStatus(error) === 404) return;
    throw error;
  }
  throw new MessageEvidenceCopyError("EVIDENCE_DESTINATION_CONFLICT", "evidence destination has another generation");
}

export function firebaseMessageEvidenceStorage(): MessageEvidenceStorage {
  const storage = getStorage();
  return {
    copy: async (input) => {
      const source = storage.bucket(input.source.bucket).file(input.source.path, {generation: input.source.generation});
      const [sourceMetadata] = await source.getMetadata();
      if (String(sourceMetadata.generation) !== input.source.generation ||
          numericMetadata(sourceMetadata.size) !== input.source.bytes ||
          sourceMetadata.contentType !== input.source.contentType) {
        throw new MessageEvidenceCopyError("EVIDENCE_SOURCE_CHANGED", "evidence source metadata changed");
      }
      const destination = storage.bucket(input.destinationBucket).file(input.destinationPath);
      const ownership = {
        outpickEvidenceBundleID: input.bundleID,
        outpickEvidenceAttachmentID: input.source.attachmentID,
        outpickEvidenceAttemptGeneration: String(input.attemptGeneration),
        outpickEvidenceSourceGeneration: input.source.generation,
      };
      let metadata: FileMetadata;
      try {
        const [copied] = await source.copy(destination, {
          contentType: input.source.contentType,
          cacheControl: "private, no-store, max-age=0",
          metadata: ownership,
          preconditionOpts: {ifGenerationMatch: 0},
        });
        [metadata] = await copied.getMetadata();
      } catch (error) {
        if (apiStatus(error) !== 412) throw error;
        [metadata] = await destination.getMetadata();
      }
      assertDestinationOwnership({metadata, bundleID: input.bundleID, attachmentID: input.source.attachmentID, attemptGeneration: input.attemptGeneration, sourceGeneration: input.source.generation});
      const object = evidenceObject({metadata, attachmentID: input.source.attachmentID, bucket: input.destinationBucket, path: input.destinationPath, sourceGeneration: input.source.generation});
      if (object.bytes !== input.source.bytes || object.contentType !== input.source.contentType ||
          (typeof sourceMetadata.crc32c === "string" && object.crc32c !== sourceMetadata.crc32c)) {
        throw new MessageEvidenceCopyError("EVIDENCE_DESTINATION_MISMATCH", "evidence destination metadata mismatch");
      }
      return object;
    },
    deleteAttemptObject: async (input) => {
      const destination = storage.bucket(input.destinationBucket).file(input.destinationPath);
      let metadata: FileMetadata;
      try {
        [metadata] = await destination.getMetadata();
      } catch (error) {
        if (apiStatus(error) === 404) return;
        throw error;
      }
      assertDestinationOwnership({metadata, bundleID: input.bundleID, attachmentID: input.attachmentID, attemptGeneration: input.attemptGeneration});
      const generation = stringMetadata(metadata.generation, "generation");
      try {
        await storage.bucket(input.destinationBucket).file(input.destinationPath, {
          generation,
          preconditionOpts: {ifGenerationMatch: generation},
        }).delete();
      } catch (error) {
        if (apiStatus(error) === 404) return;
        throw error;
      }
    },
    deleteEvidenceObject: async (input) => {
      const destination = storage.bucket(input.object.bucket).file(input.object.path, {generation: input.object.destinationGeneration});
      let metadata: FileMetadata;
      try {
        [metadata] = await destination.getMetadata();
      } catch (error) {
        if (apiStatus(error) === 404) {
          await assertObjectPathAbsent({bucket: input.object.bucket, path: input.object.path});
          return;
        }
        throw error;
      }
      assertDestinationOwnership({metadata, bundleID: input.bundleID, attachmentID: input.object.attachmentID, attemptGeneration: input.attemptGeneration, sourceGeneration: input.object.sourceGeneration});
      if (String(metadata.generation) !== input.object.destinationGeneration) {
        throw new MessageEvidenceCopyError("EVIDENCE_DESTINATION_CONFLICT", "evidence destination generation changed");
      }
      try {
        await storage.bucket(input.object.bucket).file(input.object.path, {
          generation: input.object.destinationGeneration,
          preconditionOpts: {ifGenerationMatch: input.object.destinationGeneration},
        }).delete();
      } catch (error) {
        if (apiStatus(error) === 404) {
          await assertObjectPathAbsent({bucket: input.object.bucket, path: input.object.path});
          return;
        }
        throw error;
      }
    },
  };
}
