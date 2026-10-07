/* eslint-disable require-jsdoc, max-len */
import {randomUUID} from "node:crypto";
import type {Bucket, File} from "@google-cloud/storage";
import {FieldValue, type Firestore} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {db, defaultStorageBucket} from "../../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../../core/runtime.js";
import {QUEUE_POLICY} from "./contracts.js";

const LEASE_PATH = "lookbookImportMaintenance/fileCleanup";
const TERMINAL_ASSET_STATES = new Set(["failed", "unpublished", "replaced"]);
const MAX_RUNTIME_MS = QUEUE_POLICY.cleanupAdmissionMs;
const LEASE_MS = 10 * 60 * 1000;

type CleanupObject = {
  variant: "thumb" | "detail";
  path: string;
  generation: string;
};

export type AssetCleanupCounts = {
  scanned: number;
  eligible: number;
  protected: number;
  deleted: number;
  objectOperations: number;
  failed: number;
  remaining: number;
  oldestEligibleAgeMs: number | null;
};

export function assetWriteCleanupObjects(
  ledger: Record<string, unknown>,
): CleanupObject[] | null {
  const rawObjects = ledger.objects;
  if (!rawObjects || typeof rawObjects !== "object" || Array.isArray(rawObjects)) {
    return null;
  }
  const objects = rawObjects as Record<string, unknown>;
  const result: CleanupObject[] = [];
  for (const variant of ["thumb", "detail"] as const) {
    const rawObject = objects[variant];
    if (rawObject === undefined) continue;
    if (!rawObject || typeof rawObject !== "object" || Array.isArray(rawObject)) {
      return null;
    }
    const object = rawObject as Record<string, unknown>;
    if (object.deletedAt !== undefined) {
      continue;
    }
    const path = variant === "thumb" ? ledger.thumbPath : ledger.detailPath;
    if (typeof path !== "string" || !path.startsWith("brands/") ||
        typeof object.generation !== "string" &&
        typeof object.generation !== "number") return null;
    const generation = String(object.generation);
    if (!/^\d+$/.test(generation)) return null;
    result.push({variant, path, generation});
  }
  return result;
}

export function targetReferencesAssetPath(
  value: unknown, paths: readonly string[],
): boolean {
  if (typeof value === "string") {
    return paths.includes(value);
  }
  if (Array.isArray(value)) {
    return value.some((item) => targetReferencesAssetPath(item, paths));
  }
  if (!value || typeof value !== "object") return false;
  return Object.values(value as Record<string, unknown>).some((item) =>
    targetReferencesAssetPath(item, paths));
}

export function isAssetWriteCleanupDue(
  ledger: Record<string, unknown>, now: number,
): boolean {
  return TERMINAL_ASSET_STATES.has(String(ledger.status)) &&
    ledger.cleanupState !== "completed" &&
    Number.isSafeInteger(ledger.cleanupAfter) &&
    Number(ledger.cleanupAfter) <= now;
}

function apiCode(error: unknown): number | null {
  if (!error || typeof error !== "object") return null;
  const code = (error as {code?: unknown}).code;
  return typeof code === "number" ? code :
    typeof code === "string" && /^\d+$/.test(code) ? Number(code) : null;
}

async function claimLease(db: Firestore, now: number, owner: string) {
  const ref = db.doc(LEASE_PATH);
  return db.runTransaction(async (transaction) => {
    const current = (await transaction.get(ref)).data();
    if (typeof current?.leaseUntil === "number" && current.leaseUntil > now) {
      return false;
    }
    transaction.set(ref, {owner, leaseUntil: now + LEASE_MS,
      startedAt: now, updatedAt: now}, {merge: true});
    return true;
  });
}

async function releaseLease(db: Firestore, owner: string, now: number) {
  const ref = db.doc(LEASE_PATH);
  await db.runTransaction(async (transaction) => {
    const current = (await transaction.get(ref)).data();
    if (current?.owner !== owner) return;
    transaction.set(ref, {owner: null, leaseUntil: null, finishedAt: now,
      updatedAt: now}, {merge: true});
  });
}

function pathValue(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

async function deleteExactGeneration(bucket: Bucket, object: CleanupObject) {
  const file: File = bucket.file(object.path, {
    generation: object.generation,
    preconditionOpts: {ifGenerationMatch: object.generation},
  });
  try {
    await file.delete();
    return true;
  } catch (error) {
    if (apiCode(error) === 404) return false;
    throw error;
  }
}

async function markDeferred(
  ref: FirebaseFirestore.DocumentReference,
  now: number,
  reason: string,
) {
  await ref.set({cleanupState: "pending",
    cleanupAfter: now + QUEUE_POLICY.fileCleanupIntervalMs,
    cleanupBlocker: reason, updatedAt: now}, {merge: true});
}

async function markObjectDeleted(
  ref: FirebaseFirestore.DocumentReference,
  variant: "thumb" | "detail",
  now: number,
) {
  const data = (await ref.get()).data();
  const current = data?.objects && typeof data.objects === "object" ?
    data.objects as Record<string, unknown> : {};
  const object = current[variant] && typeof current[variant] === "object" ?
    current[variant] as Record<string, unknown> : {};
  await ref.update({objects: {...current,
    [variant]: {...object, deletedAt: now}}, updatedAt: now});
}

// 프로세스 종료 전에 전송된 객체는 원장에 generation이 없을 수 있다.
// 정리 시점에 종료가 증명된 고유 경로만 다시 조회한다.
async function resolveMissingCleanupObjects(input: {
  db: Firestore; bucket: Bucket; ref: FirebaseFirestore.DocumentReference;
  ledger: Record<string, unknown>; counts: AssetCleanupCounts; now: number;
}): Promise<Record<string, unknown> | null> {
  const {ledger, counts} = input;
  const objects = ledger.objects && typeof ledger.objects === "object" ?
    {...ledger.objects as Record<string, unknown>} : {};
  const missing = (["thumb", "detail"] as const).filter((variant) => objects[variant] === undefined);
  if (missing.length === 0) return ledger;
  if (typeof ledger.batchID !== "string" || typeof ledger.runID !== "string" ||
      ledger.runID !== `${ledger.batchID}-${ledger.epoch}` ||
      typeof ledger.executionID !== "string" || typeof ledger.targetSeasonPath !== "string") return null;
  const runRef = input.db.doc(`lookbookImportBatches/${ledger.batchID}/runs/${ledger.runID}`);
  const auditRef = input.db.doc(`lookbookImportRecoveryAudits/termination-${ledger.runID}`);
  const [runSnapshot, auditSnapshot] = await Promise.all([runRef.get(), auditRef.get()]);
  const projectID = process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT;
  const hasProof = (run: FirebaseFirestore.DocumentData | undefined,
    audit: FirebaseFirestore.DocumentData | undefined) =>
    Boolean(run && (run.terminalConfirmed === true && run.inFlight === 0 ||
      run.terminationEvidence && typeof run.terminationVerifiedAt === "number") ||
      audit?.action === "automaticTerminationRetry" && audit.batchID === ledger.batchID &&
      audit.runID === ledger.runID && audit.evidence?.kind === "platformTermination" &&
      typeof projectID === "string" && audit.evidence?.projectID === projectID &&
      audit.expiresAt > input.now);
  // 상세 run이24시간 후 정리돼도90일 종료 감사로 정확한 실행 증거를 대조한다.
  if (!hasProof(runSnapshot.data(), auditSnapshot.data())) return null;
  for (const variant of missing) {
    if (counts.objectOperations >= QUEUE_POLICY.cleanupMaxOperations) return null;
    const path = ledger[variant === "thumb" ? "thumbPath" : "detailPath"];
    if (typeof path !== "string" || !path.startsWith(`${ledger.targetSeasonPath}/imports/${ledger.executionID}/${ledger.epoch}/`)) return null;
    counts.objectOperations++;
    try {
      const [metadata] = await input.bucket.file(path).getMetadata();
      const generation = String(metadata.generation);
      const size = Number(metadata.size);
      if (!/^\d+$/.test(generation) || !Number.isSafeInteger(size) || size < 0) return null;
      objects[variant] = {generation, size};
    } catch (error) {
      if (apiCode(error) !== 404) throw error;
      objects[variant] = {deletedAt: input.now, absentAtCleanup: true};
    }
  }
  return input.db.runTransaction(async (tx) => {
    const [latestSnapshot, latestRunSnapshot, latestAuditSnapshot] = await Promise.all([
      tx.get(input.ref), tx.get(runRef), tx.get(auditRef),
    ]);
    const latest = latestSnapshot.data();
    if (!latest || latest.status !== ledger.status || latest.updatedAt !== ledger.updatedAt ||
        latest.thumbPath !== ledger.thumbPath || latest.detailPath !== ledger.detailPath ||
        !hasProof(latestRunSnapshot.data(), latestAuditSnapshot.data())) return null;
    tx.update(input.ref, {objects, updatedAt: input.now});
    return {...latest, objects, updatedAt: input.now};
  });
}

export async function cleanupLookbookAssetWrites(input: {
  firestore: Firestore;
  bucket: Bucket;
  now?: () => number;
}): Promise<AssetCleanupCounts> {
  const clock = input.now ?? Date.now;
  const startedAt = clock();
  const owner = randomUUID();
  const counts: AssetCleanupCounts = {scanned: 0, eligible: 0, protected: 0,
    deleted: 0, objectOperations: 0, failed: 0, remaining: 0,
    oldestEligibleAgeMs: null};
  if (!await claimLease(input.firestore, startedAt, owner)) return counts;
  try {
    for (let page = 0; page < QUEUE_POLICY.cleanupMaxPages; page++) {
      if (clock() - startedAt >= MAX_RUNTIME_MS ||
          counts.objectOperations >= QUEUE_POLICY.cleanupMaxOperations) break;
      const snapshot = await input.firestore.collectionGroup("writes")
        .where("cleanupAfter", "<=", clock())
        .orderBy("cleanupAfter")
        .limit(QUEUE_POLICY.cleanupPageSize)
        .get();
      if (snapshot.empty) break;
      let processedInPage = 0;
      for (const document of snapshot.docs) {
        if (clock() - startedAt >= MAX_RUNTIME_MS ||
            counts.objectOperations >= QUEUE_POLICY.cleanupMaxOperations) break;
        processedInPage++;
        counts.scanned++;
        let ledger = document.data();
        if (!isAssetWriteCleanupDue(ledger, clock())) {
          await markDeferred(document.ref, clock(), "invalid_or_nonterminal_ledger");
          counts.protected++;
          continue;
        }
        counts.eligible++;
        const oldestAge = Math.max(0, clock() - Number(ledger.cleanupAfter));
        counts.oldestEligibleAgeMs = Math.max(counts.oldestEligibleAgeMs ?? 0,
          oldestAge);
        try {
          const resolved = await resolveMissingCleanupObjects({db: input.firestore,
            bucket: input.bucket, ref: document.ref, ledger, counts, now: clock()});
          if (!resolved) {
            await markDeferred(document.ref, clock(), "missing_generation_or_termination_proof");
            counts.protected++;
            continue;
          }
          ledger = resolved;
        } catch {
          counts.failed++;
          await markDeferred(document.ref, clock(), "storage_metadata_failed");
          continue;
        }
        const objects = assetWriteCleanupObjects(ledger);
        const targetPath = pathValue(ledger.targetPath);
        if (!objects || !targetPath) {
          await markDeferred(document.ref, clock(), "missing_generation_or_target");
          counts.protected++;
          continue;
        }
        const paths = objects.map((object) => object.path);
        const target = await input.firestore.doc(targetPath).get();
        if (target.exists && targetReferencesAssetPath(target.data(), paths)) {
          await markDeferred(document.ref, clock(), "still_referenced");
          counts.protected++;
          continue;
        }
        let blocked = false;
        for (const object of objects) {
          if (clock() - startedAt >= MAX_RUNTIME_MS ||
              counts.objectOperations >= QUEUE_POLICY.cleanupMaxOperations) {
            blocked = true;
            break;
          }
          // 경로를 다시 읽어 삭제 직전에도 현재 참조가 없음을 확인한다.
          const latestTarget = await input.firestore.doc(targetPath).get();
          if (latestTarget.exists && targetReferencesAssetPath(
            latestTarget.data(), [object.path])) {
            blocked = true;
            await markDeferred(document.ref, clock(), "reference_changed");
            counts.protected++;
            break;
          }
          try {
            counts.objectOperations++;
            const deleted = await deleteExactGeneration(input.bucket, object);
            if (deleted) counts.deleted++;
            await markObjectDeleted(document.ref, object.variant, clock());
          } catch (error) {
            if (apiCode(error) === 412) {
              blocked = true;
              await markDeferred(document.ref, clock(), "generation_changed");
              counts.protected++;
            } else {
              blocked = true;
              counts.failed++;
              await document.ref.set({cleanupState: "retry",
                cleanupAfter: clock() + QUEUE_POLICY.fileCleanupIntervalMs,
                cleanupErrorCode: "storage_delete_failed", updatedAt: clock()},
              {merge: true});
              console.error("[lookbook-asset-cleanup] object deletion failed", {
                ledgerPath: document.ref.path, variant: object.variant,
              });
            }
            break;
          }
        }
        if (!blocked) {
          await document.ref.set({cleanupState: "completed",
            cleanupCompletedAt: clock(), cleanupBlocker: null,
            cleanupAfter: FieldValue.delete(),
            updatedAt: clock()}, {merge: true});
        }
      }
      if (processedInPage === 0) break;
    }
    const oldest = await input.firestore.collectionGroup("writes")
      .where("cleanupAfter", "<=", clock())
      .orderBy("cleanupAfter").limit(1).get();
    counts.remaining = oldest.size;
    if (!oldest.empty) {
      counts.oldestEligibleAgeMs = Math.max(0,
        clock() - Number(oldest.docs[0].data().cleanupAfter));
    }
    return counts;
  } finally {
    await releaseLease(input.firestore, owner, clock());
  }
}

export const cleanupExpiredLookbookImportAssets = onSchedule(
  {schedule: "0 * * * *", timeZone: "Asia/Seoul",
    region: FUNCTIONS_REGION, timeoutSeconds: 540, memory: "256MiB",
    maxInstances: 1},
  async () => {
    const counts = await cleanupLookbookAssetWrites({
      firestore: db, bucket: defaultStorageBucket(),
    });
    console.info("[lookbook-asset-cleanup] completed", counts);
  }
);
