export const Q7_SERVICE = "lookbook-import-worker-development";
export const Q7_TAG = "q7-20261006";
export const Q7_FUNCTION = "requestSeasonImport";
export const Q7_QUEUES = ["lookbook-import-jobs", "lookbook-discovery-jobs"];

export function assertQ7DevelopmentSnapshot(snapshot, expectedVerificationDigest) {
  if (!/^[a-f0-9]{64}$/.test(expectedVerificationDigest ?? "")) {
    throw new Error("Q7_EXPECTED_WORKER_VERIFICATION_DIGEST_REQUIRED");
  }
  const {service, revision, functionConfig, queues} = snapshot;
  if (service?.metadata?.name !== Q7_SERVICE ||
      service?.metadata?.namespace !== "86635107099" ||
      service?.status?.latestReadyRevisionName !== revision?.metadata?.name) {
    throw new Error("Q7_SERVICE_TARGET_OR_READY_REVISION_MISMATCH");
  }
  const ready = revision?.status?.conditions?.some((condition) =>
    condition.type === "Ready" && condition.status === "True");
  if (!ready) throw new Error("Q7_CANDIDATE_NOT_READY");
  const tagged = service.status.traffic?.find((item) => item.tag === Q7_TAG);
  if (!tagged?.revisionName || tagged.percent != null || !tagged.url ||
      tagged.url !== functionConfig?.serviceConfig?.environmentVariables?.
        OUTPICK_LOOKBOOK_IMPORT_WORKER_URL) {
    throw new Error("Q7_FUNCTION_CANDIDATE_TAG_MISMATCH");
  }
  const base = service.status.traffic?.filter((item) => item.percent === 100) ?? [];
  if (base.length !== 1 || base[0].revisionName === tagged.revisionName) {
    throw new Error("Q7_BASE_TRAFFIC_NOT_PRESERVED");
  }
  if (service.metadata.annotations?.["run.googleapis.com/maxScale"] !== "5") {
    throw new Error("Q7_SERVICE_MAX_SCALE_CHANGED");
  }
  const revisionSpec = revision.spec;
  const container = revisionSpec?.containers?.[0];
  const annotations = revision.metadata?.annotations ?? {};
  const env = Object.fromEntries((container?.env ?? []).map((item) => [item.name, item.value]));
  if (annotations["autoscaling.knative.dev/maxScale"] !== "1" ||
      revisionSpec?.containerConcurrency !== 2 ||
      revisionSpec?.timeoutSeconds !== 900 ||
      revisionSpec?.serviceAccountName !==
        "outpick-lookbook-worker-dev@outpick-test.iam.gserviceaccount.com" ||
      container?.resources?.limits?.cpu !== "1" ||
      container?.resources?.limits?.memory !== "2Gi" ||
      env.OUTPICK_FIREBASE_PROJECT_ID !== "outpick-test" ||
      env.OUTPICK_FIREBASE_STORAGE_BUCKET !== "outpick-test.firebasestorage.app" ||
      env.OUTPICK_IMPORT_PERFORMANCE_ENABLED !== "true" ||
      env.OUTPICK_IMPORT_RECOVERY_SERVICE_ACCOUNT_EMAIL !==
        "lookbook-import-recovery@outpick-test.iam.gserviceaccount.com" ||
      env.OUTPICK_IMPORT_REMOTE_CAMPAIGN ||
      env.OUTPICK_WORKER_VERIFICATION_DIGEST !== expectedVerificationDigest) {
    throw new Error("Q7_CANDIDATE_CONFIGURATION_MISMATCH");
  }
  if (functionConfig?.state !== "ACTIVE") throw new Error("Q7_FUNCTION_NOT_ACTIVE");
  for (const queueID of Q7_QUEUES) {
    const queue = queues?.[queueID];
    if (queue?.state !== "RUNNING" || !Array.isArray(queue.tasks) || queue.tasks.length !== 0) {
      throw new Error("Q7_SHARED_TASK_QUEUE_NOT_IDLE:" + queueID);
    }
  }
  return {projectID: "outpick-test", service: Q7_SERVICE,
    candidateRevision: tagged.revisionName, candidateURL: tagged.url,
    candidateImage: container.image, baseRevision: base[0].revisionName,
    workerVerificationDigest: env.OUTPICK_WORKER_VERIFICATION_DIGEST,
    baseTrafficPercent: 100, serviceMaxScale: 5, revisionMaxScale: 1,
    cpu: container.resources.limits.cpu, memory: container.resources.limits.memory,
    concurrency: revisionSpec.containerConcurrency,
    timeoutSeconds: revisionSpec.timeoutSeconds,
    performanceEnabled: env.OUTPICK_IMPORT_PERFORMANCE_ENABLED === "true",
    recoveryServiceAccountEmail: env.OUTPICK_IMPORT_RECOVERY_SERVICE_ACCOUNT_EMAIL,
    taskQueues: Object.fromEntries(Q7_QUEUES.map((id) => [id, {
      state: queues[id].state, pendingTasks: queues[id].tasks.length,
    }])),
  };
}
