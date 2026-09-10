/* eslint-disable require-jsdoc, max-len */
import {CloudTasksClient} from "@google-cloud/tasks";
import {GoogleAuth} from "google-auth-library";
import {FieldValue, Timestamp, type Firestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import type {Request, Response} from "express";
import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import {onRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {
  deterministicMediaTaskID,
  isChatMediaKind,
  type ChatMediaKind,
} from "./contracts.js";
import {
  claimMediaUploadForExecution,
  completeSynchronousImageExecution,
  reconcileStaleMediaUpload,
  recordMediaExecutionName,
  settleMediaDispatchFailure,
} from "./orchestrationService.js";
import {publishCompletedMediaUpload} from "./readyService.js";
import {cleanupDirectUpload} from "./directUploadCleanup.js";
import {chatMediaServiceAccountEmailForEnvironment} from "./runtime.js";

const RECONCILE_LIMIT = 100;
let tasksClient: CloudTasksClient | null = null;
let googleAuth: GoogleAuth | null = null;

export const onChatMediaUploadQueued = onDocumentUpdated(
  {
    document: "Rooms/{roomID}/MediaUploads/{uploadID}",
    region: FUNCTIONS_REGION,
    retry: true,
    serviceAccount: chatMediaServiceAccountEmailForEnvironment(
      process.env, "orchestrator"
    ),
  },
  async (event) => {
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};
    if (after.contractVersion !== 2 || after.processingStatus !== "queued" ||
        !isChatMediaKind(after.kind)) return;
    if (before.processingStatus === "queued" &&
        before.dispatchGeneration === after.dispatchGeneration) return;
    const uploadPath = event.data?.after.ref.path;
    if (!uploadPath) return;
    const dispatchGeneration = nonNegativeInteger(after.dispatchGeneration);
    const receipt = await enqueueDispatcherTask({
      uploadPath,
      kind: after.kind,
      dispatchGeneration,
      scheduleMillis: timestampMillis(after.nextAttemptAt),
    });
    await event.data?.after.ref.set({
      lastDispatchTaskName: receipt.taskName,
      lastDispatchAlreadyExisted: receipt.alreadyExists,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
);

export const onChatMediaWorkerCompleted = onDocumentUpdated(
  {
    document: "Rooms/{roomID}/MediaUploads/{uploadID}",
    region: FUNCTIONS_REGION,
    retry: true,
    timeoutSeconds: 120,
    memory: "512MiB",
    serviceAccount: chatMediaServiceAccountEmailForEnvironment(
      process.env, "cleanup"
    ),
  },
  async (event) => {
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};
    if (after.contractVersion !== 2 || after.processingStatus !== "processing" ||
        !Array.isArray(after.normalizedManifest) ||
        Array.isArray(before.normalizedManifest)) return;
    const uploadRef = event.data?.after.ref;
    if (!uploadRef) return;
    const result = await publishCompletedMediaUpload({
      firestore: db,
      uploadRef,
      nowMillis: Date.now(),
    });
    const deleteReadyObjects = !result.published;
    await cleanupMediaObjects({
      uploadRef,
      quarantineBucket: result.quarantineBucket,
      quarantinePaths: result.quarantinePaths,
      readyObjects: deleteReadyObjects ? result.readyObjects : [],
      failureCode: deleteReadyObjects ?
        "orphan_ready_object_delete_failed" : "ready_source_delete_failed",
    });
  }
);

export const dispatchChatMediaProcessing = onRequest(
  {
    region: FUNCTIONS_REGION,
    invoker: "private",
    cors: false,
    timeoutSeconds: 3600,
    memory: "256MiB",
    serviceAccount: chatMediaServiceAccountEmailForEnvironment(
      process.env, "orchestrator"
    ),
  },
  createMediaDispatcherHandler()
);

export const reconcileChatMediaProcessing = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: "Asia/Seoul",
    region: FUNCTIONS_REGION,
    timeoutSeconds: 300,
    memory: "512MiB",
    serviceAccount: chatMediaServiceAccountEmailForEnvironment(
      process.env, "cleanup"
    ),
  },
  async () => {
    const now = Timestamp.now();
    const queries = [
      db.collectionGroup("MediaUploads")
        .where("contractVersion", "==", 2)
        .where("processingStatus", "==", "uploading")
        .where("uploadExpiresAt", "<=", now)
        .limit(RECONCILE_LIMIT),
      db.collectionGroup("MediaUploads")
        .where("contractVersion", "==", 2)
        .where("processingStatus", "==", "queued")
        .where("processingDeadlineAt", "<=", now)
        .limit(RECONCILE_LIMIT),
      db.collectionGroup("MediaUploads")
        .where("contractVersion", "==", 2)
        .where("processingStatus", "==", "processing")
        .where("leaseExpiresAt", "<=", now)
        .limit(RECONCILE_LIMIT),
    ];
    const snapshots = await Promise.all(queries.map((query) => query.get()));
    const refs = new Map<string, FirebaseFirestore.QueryDocumentSnapshot>();
    for (const snapshot of snapshots) {
      for (const document of snapshot.docs) refs.set(document.ref.path, document);
    }
    for (const document of refs.values()) {
      const result = await reconcileStaleMediaUpload({
        firestore: db,
        uploadRef: document.ref,
        nowMillis: now.toMillis(),
      });
      if (result.terminal && result.quarantinePaths.length > 0) {
        await cleanupQuarantinePaths(document.ref, result.quarantinePaths);
      }
    }
  }
);

export const reconcileChatMediaObjectCleanup = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Asia/Seoul",
    region: FUNCTIONS_REGION,
    timeoutSeconds: 300,
    memory: "512MiB",
    serviceAccount: chatMediaServiceAccountEmailForEnvironment(
      process.env, "cleanup"
    ),
  },
  async () => {
    const direct = await db.collectionGroup("MediaUploads")
      .where("contractVersion", "==", 3)
      .where("cleanupStatus", "==", "pending")
      .where("cleanupAfter", "<=", Timestamp.now())
      .orderBy("cleanupAfter").limit(RECONCILE_LIMIT).get();
    for (const document of direct.docs) {
      await cleanupDirectUpload({firestore: db, ref: document.ref, nowMillis: Date.now(),
        remove: async (bucket, path) => {
          const file = getStorage().bucket(bucket).file(path);
          try {
            const [metadata] = await file.getMetadata();
            await file.delete({ifGenerationMatch: metadata.generation});
          } catch (error) {
            if (Number((error as {code?: number}).code) !== 404) throw error;
          }
        }});
    }
    const snapshot = await db.collectionGroup("MediaUploads")
      .where("contractVersion", "==", 2)
      .where("cleanupStatus", "in", ["pending", "failed"])
      .limit(RECONCILE_LIMIT)
      .get();
    for (const document of snapshot.docs) {
      const data = document.data();
      if (!["ready", "canceled", "failed", "expired"].includes(data.processingStatus)) {
        continue;
      }
      const manifest = Array.isArray(data.normalizedManifest) ? data.normalizedManifest : [];
      const readyObjects = data.processingStatus === "ready" ? [] : manifest.flatMap((raw) => {
        const entry = objectBody(raw);
        return [
          {bucket: stringValue(entry.displayBucket), path: stringValue(entry.displayPath)},
          {bucket: stringValue(entry.thumbnailBucket), path: stringValue(entry.thumbnailPath)},
        ].filter((item) => item.bucket && item.path);
      });
      await cleanupMediaObjects({
        uploadRef: document.ref,
        quarantineBucket: stringValue(data.quarantineBucket),
        quarantinePaths: mediaCleanupPaths(data),
        readyObjects,
        failureCode: data.processingStatus === "ready" ?
          "ready_source_delete_failed" : "terminal_object_delete_failed",
      });
    }
  }
);

type DispatcherDependencies = {
  firestore: Firestore;
  nowMillis: () => number;
  projectID: () => string;
  startExecution: (input: {
    projectID: string;
    kind: ChatMediaKind;
    uploadPath: string;
    leaseToken: string;
  }) => Promise<string>;
  completeImageExecution: (input: {
    uploadPath: string;
    leaseToken: string;
    slotID: string;
  }) => Promise<void>;
};

export function createMediaDispatcherHandler(
  dependencies: DispatcherDependencies = runtimeDispatcherDependencies()
): (request: Request, response: Response) => Promise<void> {
  return async (request, response) => {
    if (request.method !== "POST" || !isJSONRequest(request)) {
      response.status(405).json({ok: false, error: "method_not_allowed"});
      return;
    }
    const body = objectBody(request.body);
    const uploadPath = typeof body.uploadPath === "string" ? body.uploadPath : "";
    const kind = body.kind;
    if (!validUploadPath(uploadPath) || !isChatMediaKind(kind)) {
      response.status(400).json({ok: false, error: "invalid_request"});
      return;
    }
    const firestore = dependencies.firestore;
    const uploadRef = firestore.doc(uploadPath);
    const projectID = dependencies.projectID();
    const claim = await claimMediaUploadForExecution({
      firestore,
      uploadRef,
      projectID,
      nowMillis: dependencies.nowMillis(),
    });
    if (!claim.claimed) {
      response.status(claim.reason === "capacity_exhausted" ? 429 : 200).json({
        ok: claim.duplicate === true,
        claimed: false,
        reason: claim.reason,
      });
      return;
    }
    try {
      const executionName = await dependencies.startExecution({
        projectID,
        kind: claim.kind,
        uploadPath,
        leaseToken: claim.leaseToken,
      });
      const recorded = await recordMediaExecutionName({
        firestore,
        uploadRef,
        leaseToken: claim.leaseToken,
        executionName,
      });
      if (claim.kind === "images") {
        // 다음 Task가 실행되기 전에 성공 확정과 slot 반환 transaction을 완료한다.
        await dependencies.completeImageExecution({uploadPath, leaseToken: claim.leaseToken, slotID: claim.slotID});
      }
      response.status(200).json({ok: claim.kind === "images" || recorded, claimed: true, executionName});
    } catch (error) {
      console.error("[dispatchChatMediaProcessing] Cloud Run Job start failed", {
        uploadPath,
        error: error instanceof Error ? error.message : String(error),
      });
      await settleMediaDispatchFailure({
        firestore,
        uploadRef,
        leaseToken: claim.leaseToken,
        nowMillis: dependencies.nowMillis(),
        failureCode: "job_start_failed",
      });
      response.status(503).json({ok: false, error: "job_start_failed"});
    }
  };
}

async function enqueueDispatcherTask(input: {
  uploadPath: string;
  kind: ChatMediaKind;
  dispatchGeneration: number;
  scheduleMillis: number | null;
}): Promise<{taskName: string; alreadyExists: boolean}> {
  const config = taskConfig(input.kind);
  tasksClient ??= new CloudTasksClient();
  const parent = tasksClient.queuePath(config.projectID, FUNCTIONS_REGION, config.queue);
  const taskName = tasksClient.taskPath(
    config.projectID,
    FUNCTIONS_REGION,
    config.queue,
    deterministicMediaTaskID(input.uploadPath, input.dispatchGeneration)
  );
  try {
    const [task] = await tasksClient.createTask({
      parent,
      task: {
        name: taskName,
        dispatchDeadline: input.kind === "images" ? {seconds: 1800} : {seconds: 120},
        ...(input.scheduleMillis && input.scheduleMillis > Date.now() ? {
          scheduleTime: {seconds: Math.floor(input.scheduleMillis / 1000)},
        } : {}),
        httpRequest: {
          httpMethod: "POST",
          url: config.dispatcherURL,
          headers: {"Content-Type": "application/json"},
          body: Buffer.from(JSON.stringify(input)),
          oidcToken: {
            serviceAccountEmail: config.serviceAccount,
            audience: config.audience,
          },
        },
      },
    });
    return {taskName: task.name ?? taskName, alreadyExists: false};
  } catch (error) {
    const code = Number((error as {code?: unknown})?.code);
    if (code === 6) return {taskName, alreadyExists: true};
    throw error;
  }
}

function runtimeDispatcherDependencies(): DispatcherDependencies {
  return {
    firestore: db,
    nowMillis: () => Date.now(),
    projectID: projectID,
    startExecution: startChatMediaExecution,
    completeImageExecution: async ({uploadPath, leaseToken, slotID}) => {
      await completeSynchronousImageExecution({
        firestore: db, uploadRef: db.doc(uploadPath), leaseToken, slotID, nowMillis: Date.now(),
      });
    },
  };
}

async function startChatMediaExecution(input: {
  projectID: string;
  kind: ChatMediaKind;
  uploadPath: string;
  leaseToken: string;
}): Promise<string> {
  if (input.kind === "images") return invokeImageProcessingService(input);
  return startCloudRunJobExecution(input);
}

async function invokeImageProcessingService(input: {
  uploadPath: string;
  leaseToken: string;
}): Promise<string> {
  const serviceURL = requiredEnv("CHAT_MEDIA_IMAGE_SERVICE_URL").replace(/\/+$/, "");
  googleAuth ??= new GoogleAuth();
  const client = await googleAuth.getIdTokenClient(
    process.env.CHAT_MEDIA_IMAGE_SERVICE_AUDIENCE?.trim() || serviceURL
  );
  const response = await client.request<{executionName?: string}>({
    url: `${serviceURL}/process`,
    method: "POST",
    data: {
      uploadPath: input.uploadPath,
      leaseToken: input.leaseToken,
      kind: "images",
    },
    timeout: 3_590_000,
  });
  const executionName = response.data?.executionName;
  if (typeof executionName !== "string" || !executionName) {
    throw new Error("Cloud Run image service execution name이 없습니다.");
  }
  return executionName;
}

async function startCloudRunJobExecution(input: {
  projectID: string;
  kind: ChatMediaKind;
  uploadPath: string;
  leaseToken: string;
}): Promise<string> {
  const job = requiredEnv("CHAT_MEDIA_VIDEO_JOB_NAME");
  googleAuth ??= new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/cloud-platform"],
  });
  const token = await googleAuth.getAccessToken();
  if (!token) throw new Error("Cloud Run Jobs access token이 없습니다.");
  const url = `https://run.googleapis.com/v2/projects/${input.projectID}` +
    `/locations/${FUNCTIONS_REGION}/jobs/${job}:run`;
  const timeout = "720s";
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "authorization": `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      overrides: {
        taskCount: 1,
        timeout,
        containerOverrides: [{
          env: [
            {name: "CHAT_MEDIA_UPLOAD_PATH", value: input.uploadPath},
            {name: "CHAT_MEDIA_LEASE_TOKEN", value: input.leaseToken},
            {name: "CHAT_MEDIA_KIND", value: input.kind},
          ],
        }],
      },
    }),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`Cloud Run Jobs API HTTP ${response.status}`);
  const body = JSON.parse(text) as {name?: unknown};
  if (typeof body.name !== "string" || !body.name) {
    throw new Error("Cloud Run Jobs execution name이 없습니다.");
  }
  return body.name;
}

async function cleanupQuarantinePaths(
  uploadRef: FirebaseFirestore.DocumentReference,
  paths: string[]
): Promise<void> {
  try {
    const bucket = getStorage().bucket(requiredEnv("CHAT_MEDIA_QUARANTINE_BUCKET"));
    await Promise.all(paths.map((path) =>
      bucket.file(path).delete({ignoreNotFound: true})
    ));
    await uploadRef.set({
      cleanupStatus: "completed",
      cleanupCompletedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  } catch (error) {
    await uploadRef.set({
      cleanupStatus: "failed",
      cleanupFailureCode: "quarantine_delete_failed",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    console.error("[reconcileChatMediaProcessing] quarantine cleanup failed", {
      uploadPath: uploadRef.path,
      pathCount: paths.length,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

export async function cleanupMediaObjects(input: {
  uploadRef: FirebaseFirestore.DocumentReference;
  quarantineBucket: string;
  quarantinePaths: string[];
  readyObjects: Array<{bucket: string; path: string}>;
  failureCode: string;
}): Promise<void> {
  try {
    const deletions: Array<Promise<unknown>> = [];
    if (input.quarantineBucket) {
      const bucket = getStorage().bucket(input.quarantineBucket);
      deletions.push(...input.quarantinePaths.map((path) =>
        bucket.file(path).delete({ignoreNotFound: true})
      ));
    }
    deletions.push(...input.readyObjects.map(({bucket, path}) =>
      getStorage().bucket(bucket).file(path).delete({ignoreNotFound: true})
    ));
    await Promise.all(deletions);
    await input.uploadRef.set({
      cleanupStatus: "completed",
      cleanupFailureCode: null,
      cleanupCompletedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  } catch (error) {
    await input.uploadRef.set({
      cleanupStatus: "failed",
      cleanupFailureCode: input.failureCode,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    console.error("[chat-media-cleanup] media object cleanup failed", {
      uploadPath: input.uploadRef.path,
      failureCode: input.failureCode,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

function mediaCleanupPaths(data: FirebaseFirestore.DocumentData): string[] {
  return [...new Set(stringArray(data.quarantinePaths))];
}

function taskConfig(kind: ChatMediaKind) {
  const dispatcherURL = requiredEnv("CHAT_MEDIA_DISPATCHER_URL").replace(/\/+$/, "");
  return {
    projectID: projectID(),
    queue: requiredEnv(kind === "images" ?
      "CHAT_MEDIA_IMAGE_TASKS_QUEUE" : "CHAT_MEDIA_VIDEO_TASKS_QUEUE"),
    dispatcherURL,
    serviceAccount: requiredEnv("CHAT_MEDIA_TASKS_SERVICE_ACCOUNT_EMAIL"),
    audience: process.env.CHAT_MEDIA_DISPATCHER_AUDIENCE?.trim() || dispatcherURL,
  };
}

function projectID(): string {
  return requiredEnv("GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT", "GCP_PROJECT");
}

function requiredEnv(...names: string[]): string {
  for (const name of names) {
    const value = process.env[name]?.trim();
    if (value) return value;
  }
  throw new Error(`필수 환경 변수가 없습니다: ${names.join(" | ")}`);
}

function nonNegativeInteger(value: unknown): number {
  return Number.isInteger(value) && Number(value) >= 0 ? Number(value) : 0;
}

function timestampMillis(value: unknown): number | null {
  if (value && typeof value === "object" && "toMillis" in value &&
      typeof value.toMillis === "function") {
    return value.toMillis();
  }
  return null;
}

function objectBody(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> : {};
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter(
    (item): item is string => typeof item === "string" && item.length > 0
  ) : [];
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function isJSONRequest(request: Request): boolean {
  const type = request.get("content-type")?.toLowerCase() ?? "";
  return type.startsWith("application/json");
}

function validUploadPath(value: string): boolean {
  return /^Rooms\/[^/]+\/MediaUploads\/[^/]+$/.test(value) &&
    !value.includes("..");
}
