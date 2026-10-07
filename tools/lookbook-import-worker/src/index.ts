import {type Server} from "node:http";
import {createHash, randomUUID} from "node:crypto";

import {loadConfig} from "./config.js";
import {initializeFirebaseClients} from "./firebase.js";
import {GoogleOIDCTokenVerifier} from "./oidc-auth.js";
import {createServer} from "./server.js";
import {workerRuntimeContract} from "./runtime-contract.js";
import {loadRemoteCorpus, outputRoot, remoteRunKey, requestedPlan}
  from "./performance/remote-contract.js";
import {remoteFirebasePorts, configureRemoteFirestore}
  from "./performance/remote-firebase.js";
import {RemoteRunStore} from "./performance/remote-store.js";
import {runRemote} from "./performance/remote-runner.js";
import {assertRemoteGoldenRuntime}
  from "./performance/remote-golden-profile.js";
import {CloudLoggingRecoveryEvidenceProvider}
  from "./queue/cloud-logging-evidence.js";
import {retryFaultCampaign, createDevelopmentRetryFault}
  from "./queue/development-retry-fault.js";

let httpServer: Server | null = null;
const shutdownSignal = new AbortController();

async function main(): Promise<void> {
  const config = loadConfig(process.env);
  // 첫 작업의 동기 모듈 로딩이 보호 표본을 늦추지 않도록 Ready 전에 준비한다.
  // Chromium 프로세스는 기존 작업 차례에서만 실행한다.
  await import("playwright");
  if (config.remoteCampaign) assertRemoteGoldenRuntime();
  const firebase = initializeFirebaseClients(
    config.projectID,
    config.storageBucket,
  );
  const instanceID = randomUUID();
  const retryCampaign = retryFaultCampaign(process.env);
  const campaign = config.remoteCampaign;
  const corpus = campaign ? await loadRemoteCorpus() : undefined;
  if (campaign) configureRemoteFirestore(firebase);
  const app = createServer({
    projectID: config.projectID,
    assetSyncConcurrency: config.assetSyncConcurrency,
    performance: {
      enabled: config.performanceEnabled,
      sourceRevision: config.workerSourceRevision,
      instanceID,
      settingsDigest: createHash("sha256").update(JSON.stringify({
        assetSyncConcurrency: config.assetSyncConcurrency,
        uvThreadpoolSize: process.env.UV_THREADPOOL_SIZE ?? null,
        nodeOptions: process.env.NODE_OPTIONS ?? null,
      })).digest("hex"),
    },
    firebase,
    ...(retryCampaign ? {developmentRetryFault: createDevelopmentRetryFault({
      firestore: firebase.firestore, campaignID: retryCampaign,
      projectID: config.projectID, serviceName: String(process.env.K_SERVICE),
      revision: config.workerRevision,
      verificationDigest: String(
        process.env.OUTPICK_WORKER_VERIFICATION_DIGEST),
    })} : {}),
    queueOwner: instanceID,
    bootID: instanceID,
    shutdownSignal: shutdownSignal.signal,
    auth: {
      audience: config.oidcAudience,
      taskServiceAccountEmail: config.taskServiceAccountEmail,
      functionsServiceAccountEmail: config.functionsServiceAccountEmail,
      ...(config.recoveryServiceAccountEmail ? {
        recoveryServiceAccountEmail: config.recoveryServiceAccountEmail,
      } : {}),
      verifier: new GoogleOIDCTokenVerifier(),
    },
    ...(config.recoveryServiceAccountEmail && process.env.K_SERVICE ? {
      recovery: {serviceName: process.env.K_SERVICE,
        evidenceProvider: new CloudLoggingRecoveryEvidenceProvider()},
    } : {}),
    runtime: workerRuntimeContract(config),
    ...(campaign && corpus ? {remoteExperiment: async (body: unknown,
      signal: AbortSignal) => {
      const plan = requestedPlan(body);
      return runRemote(body, {campaign, input: corpus,
        ports: remoteFirebasePorts(firebase, outputRoot(campaign, plan),
          `lookbookImportPerformanceRuns/${remoteRunKey(campaign, plan)}`),
        store: new RemoteRunStore(firebase.firestore), instanceID,
        revision: config.workerRevision,
        signal: AbortSignal.any([signal, shutdownSignal.signal])});
    }} : {}),
  });

  httpServer = app.listen(config.port, () => {
    console.log(
      `lookbook-import-worker listening on port ${config.port}`,
    );
  });
}

function shutdown(signal: NodeJS.Signals): void {
  shutdownSignal.abort(new Error(`Worker 종료: ${signal}`));
  console.log(`lookbook-import-worker received ${signal}`);
  httpServer?.close((error?: Error) => {
    if (error) {
      console.error("lookbook-import-worker failed to close", error);
      process.exit(1);
    }
    process.exit(0);
  });
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);

main().catch((error: unknown) => {
  console.error("lookbook-import-worker failed to start", error);
  process.exit(1);
});
