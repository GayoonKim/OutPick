import assert from "node:assert/strict";
import {REMOTE_PROJECT, REMOTE_BUCKET} from "./remote-contract.js";
import {validateRemoteExecution, type RemoteExecution}
  from "./remote-campaign.js";

export const REMOTE_REGION = "asia-northeast3";
export const REMOTE_SERVICE = "lookbook-import-worker-development";
export const REMOTE_AUDIENCE =
  "https://lookbook-import-worker-development-xyenspjiwa-du.a.run.app";
export const REMOTE_CALLER =
  "86635107099-compute@developer.gserviceaccount.com";
type CloudRun = {
  metadata: {name: string; annotations?: Record<string, string>};
  spec?: {containers?: Array<{image: string;
    env?: Array<{name: string; value?: string}>;
    resources: {limits: {cpu: string; memory: string}}}>;
    containerConcurrency?: number; timeoutSeconds?: number;
    serviceAccountName?: string};
  status?: {imageDigest?: string; traffic?: Array<{
    revisionName: string; percent?: number; url?: string; tag?: string}>};
};

// 배포하지 않고 실제 후보 리비전/트래픽을 확인한다. 계측 호환성은 smoke에서 확인한다.
export function assertRemoteTarget(execution: RemoteExecution,
  service: CloudRun, revision: CloudRun) {
  validateRemoteExecution(execution);
  assert.equal(service.metadata.name, REMOTE_SERVICE);
  assert.equal(revision.metadata.name, execution.revision);
  const traffic = service.status?.traffic ?? [];
  const target = traffic.find((t) => t.url === execution.targetURL);
  assert.ok(target?.tag && target.revisionName === execution.revision);
  assert.ok(traffic.every((t) => t.revisionName !== execution.revision ||
    (t.percent ?? 0) === 0));
  assert.equal(traffic.reduce((n, t) => n + (t.percent ?? 0), 0), 100);
  const annotations = revision.metadata.annotations ?? {};
  assert.equal(annotations["autoscaling.knative.dev/maxScale"], "1");
  assert.equal(annotations["autoscaling.knative.dev/minScale"] ?? "0", "0");
  assert.equal(service.metadata.annotations?.["run.googleapis.com/minScale"] ??
    "0", "0");
  assert.notEqual(annotations["run.googleapis.com/cpu-throttling"], "false");
  assert.equal(revision.spec?.containerConcurrency, 2);
  assert.equal(revision.spec?.timeoutSeconds, 900);
  assert.equal(revision.spec?.serviceAccountName,
    "outpick-lookbook-worker-dev@outpick-test.iam.gserviceaccount.com");
  const containers = revision.spec?.containers ?? [];
  assert.equal(containers.length, 1);
  const container = containers[0];
  assert.deepEqual(container.resources.limits, {cpu: "1", memory: "2Gi"});
  assert.ok((revision.status?.imageDigest ?? container.image)
    .endsWith(`@${execution.imageDigest}`));
  const env = Object.fromEntries((container.env ?? []).map((e) =>
    [e.name, e.value]));
  assert.equal(env.OUTPICK_FIREBASE_PROJECT_ID, REMOTE_PROJECT);
  assert.equal(env.OUTPICK_FIREBASE_STORAGE_BUCKET, REMOTE_BUCKET);
  assert.equal(env.OUTPICK_IMPORT_OIDC_AUDIENCE, REMOTE_AUDIENCE);
  assert.equal(env.OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL,
    REMOTE_CALLER);
  assert.deepEqual(JSON.parse(env.OUTPICK_IMPORT_REMOTE_CAMPAIGN ?? "null"),
    execution.campaign);
}
