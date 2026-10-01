/* eslint-disable require-jsdoc */
import {getStorage} from "firebase-admin/storage";
import type {Storage} from "firebase-admin/storage";
import type {ChatMediaExpiryObject} from "./retentionContracts.js";
import type {ChatMediaRetentionStorage} from "./retentionService.js";

function apiStatus(error: unknown): number | null {
  if (!error || typeof error !== "object") return null;
  const code = (error as {code?: unknown}).code;
  return typeof code === "number" ? code :
    typeof code === "string" && /^\d+$/.test(code) ? Number(code) : null;
}

function generationMismatch(): Error & {code: number} {
  return Object.assign(
    new Error("chat media generation mismatch"),
    {code: 412},
  );
}

type StorageBucket = ReturnType<ReturnType<typeof getStorage>["bucket"]>;

async function assertNoNewerGeneration(
  bucket: StorageBucket,
  object: ChatMediaExpiryObject,
): Promise<void> {
  try {
    const [metadata] = await bucket.file(object.path).getMetadata();
    if (String(metadata.generation) !== object.generation) {
      throw generationMismatch();
    }
    throw new Error("exact chat media generation still exists");
  } catch (error) {
    if (apiStatus(error) === 404) return;
    throw error;
  }
}

export function chatMediaRetentionStorage(
  storage: Storage,
): ChatMediaRetentionStorage {
  return {
    deleteExactGeneration: async (object) => {
      const bucket = storage.bucket(object.bucket);
      const file = bucket.file(object.path, {
        generation: object.generation,
        preconditionOpts: {ifGenerationMatch: object.generation},
      });
      try {
        const [metadata] = await file.getMetadata();
        if (String(metadata.generation) !== object.generation) {
          throw generationMismatch();
        }
      } catch (error) {
        if (apiStatus(error) !== 404) throw error;
        await assertNoNewerGeneration(bucket, object);
        return;
      }

      try {
        await file.delete();
      } catch (error) {
        if (apiStatus(error) !== 404) throw error;
        await assertNoNewerGeneration(bucket, object);
      }
    },
  };
}

export function firebaseChatMediaRetentionStorage(): ChatMediaRetentionStorage {
  return chatMediaRetentionStorage(getStorage());
}
