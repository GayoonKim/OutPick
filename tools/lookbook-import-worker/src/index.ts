import {type Server} from "node:http";

import {loadConfig} from "./config.js";
import {initializeFirebaseClients} from "./firebase.js";
import {GoogleOIDCTokenVerifier} from "./oidc-auth.js";
import {createServer} from "./server.js";
import {workerRuntimeContract} from "./runtime-contract.js";

let httpServer: Server | null = null;

async function main(): Promise<void> {
  const config = loadConfig(process.env);
  const firebase = initializeFirebaseClients(
    config.projectID,
    config.storageBucket,
  );
  const app = createServer({
    projectID: config.projectID,
    assetSyncConcurrency: config.assetSyncConcurrency,
    firebase,
    auth: {
      audience: config.oidcAudience,
      taskServiceAccountEmail: config.taskServiceAccountEmail,
      functionsServiceAccountEmail: config.functionsServiceAccountEmail,
      verifier: new GoogleOIDCTokenVerifier(),
    },
    runtime: workerRuntimeContract(config),
  });

  httpServer = app.listen(config.port, () => {
    console.log(
      `lookbook-import-worker listening on port ${config.port}`,
    );
  });
}

function shutdown(signal: NodeJS.Signals): void {
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
