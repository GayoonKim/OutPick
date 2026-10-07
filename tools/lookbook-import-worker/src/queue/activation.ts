/* eslint-disable require-jsdoc, max-len */
import {createHash} from "node:crypto";
import type {Firestore} from "firebase-admin/firestore";
import {readOwnedBatch, type BatchOwnership} from "./coordinator.js";

type QueueItem = Record<string, unknown>;
type RepairEntry = {postID: string; sourceURL: string; proposedIndex: number};
type RepairAddEntry = RepairEntry & {
  alt: string | null;
  contentHash: string | null;
};

export async function activateQueueItem(input: {
  firestore: Firestore;
  brandID: string;
  jobID: string;
  executionID: string;
  ordinal: number;
  ownership: BatchOwnership;
  batchKind: string;
  mode: string | null;
  continuationInput: Record<string, unknown> | null;
  now?: number;
}): Promise<void> {
  const {firestore: db, ownership, brandID, jobID, executionID, ordinal} = input;
  const now = input.now ?? Date.now();
  const isDiscovery = input.batchKind === "discoverSeasons";
  const collection = isDiscovery ? "seasonDiscoveryJobs" : "importJobs";
  const brandRef = db.doc(`brands/${brandID}`);
  const jobRef = brandRef.collection(collection).doc(jobID);

  await db.runTransaction(async (transaction) => {
    const batch = await readOwnedBatch(db, transaction, ownership);
    const items = Array.isArray(batch.items) ? batch.items as QueueItem[] : [];
    const item = items[ordinal];
    if (batch.kind !== input.batchKind || batch.brandID !== brandID ||
        !item || item.admissionStatus !== "created" || item.jobID !== jobID ||
        item.executionID !== executionID) {
      throw new Error("QUEUE_ACTIVATION_ITEM_MISMATCH");
    }
    const executionRef = jobRef.collection("executions").doc(executionID);
    const continuationRef = executionRef.collection("continuations")
      .doc(ownership.batchID);
    const [jobSnapshot, executionSnapshot, continuationSnapshot, brandSnapshot] =
      await Promise.all([
        transaction.get(jobRef), transaction.get(executionRef),
        transaction.get(continuationRef), transaction.get(brandRef),
      ]);
    const job = jobSnapshot.data();
    const execution = executionSnapshot.data();
    const continuation = continuationSnapshot.data();
    const brand = brandSnapshot.data();
    if (!job || !execution || execution.status !== "active" ||
        execution.activeRunID !== ownership.runID ||
        (continuation && (continuation.status !== "active" ||
          continuation.mode !== input.mode)) ||
        (input.mode && execution.mode !== input.mode &&
          continuation?.mode !== input.mode)) {
      throw new Error("QUEUE_ACTIVATION_EXECUTION_MISMATCH");
    }
    if (continuation && continuation.activatedAt == null) {
      const expected = continuation.expected;
      if (!expected || typeof expected !== "object" || Array.isArray(expected)) {
        throw new Error("QUEUE_CONTINUATION_EXPECTED_MISSING");
      }
      const expectedFields = expected as Record<string, unknown>;
      const actual = Object.fromEntries(Object.keys(expectedFields)
        .map((key) => [key, job[key] ?? null]));
      if (canonicalJSON(actual) !== canonicalJSON(expectedFields)) {
        throw new Error("QUEUE_CONTINUATION_SOURCE_CHANGED");
      }
    }
    const values = input.continuationInput ??
      (continuation?.input && typeof continuation.input === "object" ?
        continuation.input as Record<string, unknown> : {});
    const queueFields = {
      queueContractVersion: 1,
      queueBatchID: ownership.batchID,
      queueExecutionID: executionID,
      queueActiveRunID: ownership.runID,
      dispatchMode: "batchQueue",
      queueActivationRequired: false,
      updatedAt: new Date(now),
    };

    // continuation의 도메인 변경은 최초 활성화 때만 적용한다.
    // 정상 분할·재개 때는 새 runID만 root에 반영해 기존 진행을 보존한다.
    if (continuation?.activatedAt != null) {
      transaction.update(jobRef, queueFields);
      return;
    }

    if (isDiscovery) {
      if (!brand) throw new Error("QUEUE_BRAND_NOT_FOUND");
      const activeID = typeof brand.activeSeasonDiscoveryJobID === "string" ?
        brand.activeSeasonDiscoveryJobID : null;
      if (activeID && activeID !== jobID) {
        const activeSnapshot = await transaction.get(
          brandRef.collection("seasonDiscoveryJobs").doc(activeID));
        const active = activeSnapshot.data();
        if (active && ["queued", "dispatching", "running"].includes(
          String(active.status))) {
          throw new Error("QUEUE_DISCOVERY_ACTIVE_CONFLICT");
        }
      }
      const patch: Record<string, unknown> = {
        ...queueFields, status: "queued", phase: "dispatching",
      };
      if (input.mode === "manualRetry") {
        patch.status = "queued";
        patch.phase = "dispatching";
        patch.failureClass = null;
        patch.errorCode = null;
        patch.errorMessage = null;
        patch.retryable = false;
        patch.lastTaskRetryCount = 0;
      }
      transaction.update(jobRef, patch);
      transaction.update(brandRef, {
        activeSeasonDiscoveryJobID: jobID,
        activeSeasonDiscoveryGeneration: job.generation ?? null,
        discoveryStatus: "queued",
        lastDiscoveryErrorMessage: null,
        updatedAt: new Date(now),
      });
      if (continuation) {
        transaction.update(continuationRef, {
          activatedAt: new Date(now), updatedAt: new Date(now),
        });
      }
      return;
    }

    const patch: Record<string, unknown> = {...queueFields};
    switch (input.mode) {
    case null:
      if (input.batchKind !== "importSeasons" || job.status !== "queued") {
        throw new Error("QUEUE_IMPORT_ACTIVATION_MISMATCH");
      }
      break;
    case "assetFailureRetry":
    {
      if (input.batchKind !== "assetRetry" || job.jobType !== "retrySeasonAssets") {
        throw new Error("QUEUE_ASSET_RETRY_ACTIVATION_MISMATCH");
      }
      if (typeof job.sourceImportJobID !== "string") {
        throw new Error("QUEUE_ASSET_RETRY_SOURCE_MISSING");
      }
      const sourceRef = brandRef.collection("importJobs")
        .doc(job.sourceImportJobID);
      const sourceSnapshot = await transaction.get(sourceRef);
      const source = sourceSnapshot.data();
      const alreadyActivated = job.queueActivatedForBatchID === ownership.batchID;
      if (!source || !["failed", "partialFailed"].includes(String(source.status)) ||
          source.sourceURL !== job.sourceURL ||
          source.targetSeasonID !== job.targetSeasonID ||
          JSON.stringify(Array.isArray(source.createdPostIDs) ?
            [...new Set(source.createdPostIDs)] : []) !==
              JSON.stringify(job.createdPostIDs ?? []) ||
          !alreadyActivated && assetRetrySourceDigest(source) !== values.sourceDigest) {
        throw new Error("QUEUE_ASSET_RETRY_SOURCE_CHANGED");
      }
      if (!alreadyActivated) {
        transaction.update(sourceRef, {
          assetRetryStatus: "processing",
          assetRetryStartedAt: new Date(now),
          assetRetryRequestID: ownership.batchID,
          updatedAt: new Date(now),
        });
      }
      patch.status = "queued";
      patch.phase = "dispatching";
      patch.resumeFrom = "materializing";
      patch.queueActivatedForBatchID = ownership.batchID;
      break;
    }
    case "reviewApproval":
      if (input.batchKind !== "reviewApproval" ||
          !Array.isArray(values.approvedCandidateKeys) ||
          !Number.isSafeInteger(values.reviewGeneration) ||
          typeof values.reviewSnapshotHash !== "string") {
        throw new Error("QUEUE_REVIEW_ACTIVATION_MISMATCH");
      }
      Object.assign(patch, {
        status: "queued", phase: "dispatching", reviewStatus: "approved",
        reviewDecision: values.decision ?? "approved",
        reviewNote: values.note ?? null,
        approvedCandidateKeys: values.approvedCandidateKeys,
        reviewGeneration: values.reviewGeneration,
        reviewSnapshotHash: values.reviewSnapshotHash,
        resumeFrom: "materializing",
      });
      break;
    case "manualRetry":
      if (input.batchKind !== "manualRetry" &&
          input.batchKind !== "discoverSeasons") {
        throw new Error("QUEUE_RETRY_ACTIVATION_MISMATCH");
      }
      Object.assign(patch, {
        status: "queued", phase: "dispatching", reviewStatus: "reanalyzing",
        reviewGeneration: values.reviewGeneration ?? job.reviewGeneration,
        retryRuntimeVersion: values.retryRuntimeVersion ?? null,
        resumeFrom: "parsing", errorMessage: null, parseStatus: "pending",
      });
      break;
    case "repairAnalyze":
      if (input.batchKind !== "repair" || typeof values.seasonID !== "string" ||
          !Number.isSafeInteger(values.repairGeneration)) {
        throw new Error("QUEUE_REPAIR_ANALYZE_ACTIVATION_MISMATCH");
      }
      Object.assign(patch, {
        status: "queued", phase: "dispatching", repairStatus: "analyzing",
        repairTargetSeasonID: values.seasonID,
        repairGeneration: values.repairGeneration, resumeFrom: "parsing",
      });
      break;
    case "repairApply":
      await activateRepairApply({db, transaction, brandID, jobID, jobRef,
        repairRef: continuationRef, values, queueFields, now});
      return;
    default:
      throw new Error("QUEUE_CONTINUATION_UNSUPPORTED");
    }
    transaction.update(jobRef, patch);
    if (continuation) {
      transaction.update(continuationRef, {
        activatedAt: new Date(now), updatedAt: new Date(now),
      });
    }
  });
}

async function activateRepairApply(input: {
  db: Firestore;
  transaction: FirebaseFirestore.Transaction;
  brandID: string;
  jobID: string;
  jobRef: FirebaseFirestore.DocumentReference;
  repairRef: FirebaseFirestore.DocumentReference;
  values: Record<string, unknown>;
  queueFields: Record<string, unknown>;
  now: number;
}): Promise<void> {
  const {db, transaction, brandID, jobID, jobRef, repairRef, values, now} = input;
  const generation = Number(values.repairGeneration);
  const snapshotHash = values.repairSnapshotHash;
  const seasonID = values.seasonID;
  const plan = repairPlan(values.plan);
  if (!Number.isSafeInteger(generation) || generation < 1 ||
      typeof snapshotHash !== "string" || typeof seasonID !== "string" ||
      plan.allPostIDs.length !== plan.resultingPostCount) {
    throw new Error("QUEUE_REPAIR_PLAN_INVALID");
  }
  const brandRef = db.doc(`brands/${brandID}`);
  const targetRepairRef = jobRef.collection("repairs").doc(String(generation));
  const seasonRef = brandRef.collection("seasons").doc(seasonID);
  const [jobSnapshot, repairSnapshot, seasonSnapshot] = await Promise.all([
    transaction.get(jobRef), transaction.get(targetRepairRef), transaction.get(seasonRef),
  ]);
  const job = jobSnapshot.data();
  const repair = repairSnapshot.data();
  const season = seasonSnapshot.data();
  if (!job || !repair || !season || job.repairGeneration !== generation ||
      job.repairSnapshotHash !== snapshotHash ||
      repair.repairSnapshotHash !== snapshotHash || repair.seasonID !== seasonID ||
      !["previewReady", "applying", "applied"].includes(String(repair.status))) {
    throw new Error("QUEUE_REPAIR_SNAPSHOT_STALE");
  }
  const addRefs = plan.add.map((entry) => seasonRef.collection("posts")
    .doc(entry.postID));
  const addSnapshots = [];
  for (const ref of addRefs) addSnapshots.push(await transaction.get(ref));
  const existingAddIDs = new Set(addSnapshots.filter((item) => item.exists)
    .map((item) => item.id));
  const timestamp = new Date(now);
  const postCollection = seasonRef.collection("posts");
  for (const entry of [...plan.keep, ...plan.reorder, ...plan.removeCandidates]) {
    transaction.set(postCollection.doc(entry.postID), {
      orderIndex: entry.proposedIndex, sourceSortIndex: entry.proposedIndex,
      repairedAt: timestamp, updatedAt: timestamp,
    }, {merge: true});
  }
  for (const entry of plan.add) {
    const ref = postCollection.doc(entry.postID);
    if (existingAddIDs.has(entry.postID)) {
      transaction.set(ref, {orderIndex: entry.proposedIndex,
        sourceSortIndex: entry.proposedIndex, repairedAt: timestamp,
        updatedAt: timestamp}, {merge: true});
    } else {
      transaction.create(ref, {
        brandID, seasonID, authorID: null,
        orderIndex: entry.proposedIndex, sourceSortIndex: entry.proposedIndex,
        status: "published", assetSyncStatus: "pending",
        sourceImportJobID: jobID,
        media: [{type: "image", remoteURL: entry.sourceURL,
          thumbPath: null, detailPath: null,
          sourcePageURL: season.sourceURL ?? null,
          contentHash: entry.contentHash}],
        caption: entry.alt, tagIDs: [],
        metrics: {likeCount: 0, commentCount: 0, replacementCount: 0,
          saveCount: 0, viewCount: 0},
        createdAt: timestamp, updatedAt: timestamp,
      });
    }
  }
  transaction.set(seasonRef, {
    postCount: plan.resultingPostCount, assetSyncStatus: "pending",
    repairGeneration: generation, lastRepairSourceImportJobID: jobID,
    repairedAt: timestamp, updatedAt: timestamp,
  }, {merge: true});
  const dispatchGeneration = Number(job.dispatchGeneration ?? 0) + 1;
  const coverExists = typeof season.coverRemoteURL === "string" &&
    season.coverRemoteURL.length > 0;
  transaction.update(jobRef, {
    ...input.queueFields,
    status: "queued", phase: "dispatching", resumeFrom: "materializing",
    reviewStatus: "approved", repairStatus: "applied",
    targetSeasonID: seasonID, createdPostIDs: plan.allPostIDs,
    createdPostCount: plan.resultingPostCount,
    assetTotalCount: plan.allPostIDs.length + (coverExists ? 1 : 0),
    assetCompletedCount: 0, assetFailedCount: 0, dispatchGeneration,
    leaseOwner: null, leaseExpiresAt: null, repairedAt: timestamp,
    updatedAt: timestamp,
  });
  transaction.update(targetRepairRef, {status: "applied", appliedAt: timestamp,
    updatedAt: timestamp});
  transaction.update(repairRef, {activatedAt: timestamp, updatedAt: timestamp});
}

function repairPlan(value: unknown): {
  keep: RepairEntry[]; reorder: RepairEntry[]; add: RepairAddEntry[];
  removeCandidates: RepairEntry[]; allPostIDs: string[];
  resultingPostCount: number;
} {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("QUEUE_REPAIR_PLAN_INVALID");
  }
  const plan = value as Record<string, unknown>;
  const entries = (key: string): RepairEntry[] => {
    const rows = plan[key];
    if (!Array.isArray(rows) || rows.length > 240) {
      throw new Error("QUEUE_REPAIR_PLAN_INVALID");
    }
    return rows.map((row) => {
      if (!row || typeof row !== "object" || Array.isArray(row)) {
        throw new Error("QUEUE_REPAIR_PLAN_INVALID");
      }
      const item = row as Record<string, unknown>;
      if (typeof item.postID !== "string" || typeof item.sourceURL !== "string" ||
          !Number.isSafeInteger(item.proposedIndex) ||
          Number(item.proposedIndex) < 0) throw new Error("QUEUE_REPAIR_PLAN_INVALID");
      return {postID: item.postID, sourceURL: item.sourceURL,
        proposedIndex: Number(item.proposedIndex)};
    });
  };
  const rawAdd = plan.add;
  if (!Array.isArray(rawAdd) || rawAdd.length > 240) {
    throw new Error("QUEUE_REPAIR_PLAN_INVALID");
  }
  const add = rawAdd.map((row) => {
    if (!row || typeof row !== "object" || Array.isArray(row)) {
      throw new Error("QUEUE_REPAIR_PLAN_INVALID");
    }
    const item = row as Record<string, unknown>;
    if (typeof item.postID !== "string" || typeof item.sourceURL !== "string" ||
        !Number.isSafeInteger(item.proposedIndex) ||
        Number(item.proposedIndex) < 0 ||
        !(item.alt === null || typeof item.alt === "string") ||
        !(item.contentHash === null || typeof item.contentHash === "string")) {
      throw new Error("QUEUE_REPAIR_PLAN_INVALID");
    }
    return {postID: item.postID, sourceURL: item.sourceURL,
      proposedIndex: Number(item.proposedIndex), alt: item.alt as string | null,
      contentHash: item.contentHash as string | null};
  });
  if (!Array.isArray(plan.allPostIDs) || plan.allPostIDs.length > 240 ||
      !plan.allPostIDs.every((item) => typeof item === "string") ||
      !Number.isSafeInteger(plan.resultingPostCount) ||
      Number(plan.resultingPostCount) < 0) throw new Error("QUEUE_REPAIR_PLAN_INVALID");
  const allPostIDs = plan.allPostIDs as string[];
  if (new Set(allPostIDs).size !== allPostIDs.length ||
      Number(plan.resultingPostCount) !== allPostIDs.length) {
    throw new Error("QUEUE_REPAIR_PLAN_INVALID");
  }
  const liveEntries = [...entries("keep"), ...entries("reorder"), ...add];
  const allEntries = [...liveEntries, ...entries("removeCandidates")];
  const allEntryIDs = allEntries.map((entry) => entry.postID);
  if (allEntryIDs.length > 496 || new Set(allEntryIDs).size !== allEntryIDs.length ||
      liveEntries.length !== allPostIDs.length ||
      liveEntries.some((entry) => !allPostIDs.includes(entry.postID))) {
    throw new Error("QUEUE_REPAIR_PLAN_INVALID");
  }
  return {keep: entries("keep"), reorder: entries("reorder"), add,
    removeCandidates: entries("removeCandidates"), allPostIDs,
    resultingPostCount: Number(plan.resultingPostCount)};
}

function assetRetrySourceDigest(source: Record<string, unknown>): string | null {
  if (source.jobType !== "importSeasonFromURL" ||
      !["failed", "partialFailed"].includes(String(source.status)) ||
      typeof source.sourceURL !== "string" ||
      typeof source.targetSeasonID !== "string" ||
      !Array.isArray(source.createdPostIDs) ||
      source.createdPostIDs.some((value) => typeof value !== "string")) return null;
  const createdPostIDs = [...new Set(source.createdPostIDs as string[])];
  const value = {
    status: source.status,
    targetSeasonID: source.targetSeasonID,
    createdPostIDs,
    sourceURL: source.sourceURL,
    queueExecutionID: source.queueExecutionID ?? null,
    assetRetryRequestID: source.assetRetryRequestID ?? null,
  };
  return createHash("sha256").update(canonicalJSON(value)).digest("hex");
}

function canonicalJSON(value: unknown): string {
  if (value === null || typeof value === "string" ||
      typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number" && Number.isFinite(value)) {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  if (value && typeof value === "object" &&
      Object.getPrototypeOf(value) === Object.prototype) {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJSON(record[key])}`).join(",")}}`;
  }
  throw new Error("QUEUE_CANONICAL_VALUE_INVALID");
}
