/* eslint-disable max-len */
import express, {
  type Express,
  type NextFunction,
  type Request,
  type Response,
} from "express";

import {type FirebaseClients} from "./firebase.js";
import {
  processImportJobTaskRequest,
  processWakeRequest,
  type ImportJobTaskRequest,
  type WakeRequest,
} from "./processor.js";
import {
  processDiscoverSeasonsDiagnosticRequest,
  type DiscoverSeasonsDiagnosticRequest,
} from "./season-discovery.js";
import {
  processSeasonDiscoveryTaskRequest,
  type SeasonDiscoveryTaskRequest,
} from "./season-discovery-processor.js";
import {isRetryableImportError} from "./import-error.js";
import {
  authenticateOIDCRequest,
  OIDCAuthenticationError,
  type OIDCTokenVerifier,
  type WorkerAuthConfig,
  type WorkerCaller,
} from "./oidc-auth.js";
import {
  processExtractionSmoke,
  type WorkerRuntimeContract,
} from "./runtime-contract.js";

interface ServerDependencies {
  projectID: string;
  assetSyncConcurrency: number;
  firebase: FirebaseClients;
  auth: WorkerAuthConfig & {verifier: OIDCTokenVerifier};
  runtime: WorkerRuntimeContract;
}

export function createServer(dependencies: ServerDependencies): Express {
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json({limit: "64kb"}));

  app.get(["/healthz", "/readyz"], (_request: Request, response: Response) => {
    response.status(200).json({
      ok: true,
      service: "lookbook-import-worker",
      projectID: dependencies.projectID,
    });
  });

  app.get(
    "/runtime-contract",
    requireCaller("functions", dependencies.auth),
    (_request: Request, response: Response) => {
      response.status(200).json(dependencies.runtime);
    },
  );

  app.post(
    "/smoke/extraction",
    requireCaller("functions", dependencies.auth),
    async (request: Request, response: Response) => {
      try {
        response.status(200).json(await processExtractionSmoke(
          request.body, dependencies.runtime,
        ));
      } catch (error) {
        response.status(400).json({
          accepted: false,
          errorMessage: errorMessage(error),
        });
      }
    },
  );

  app.post(
    "/wake",
    requireCaller("functions", dependencies.auth),
    async (request: Request, response: Response) => {
      try {
        const result = await processWakeRequest(
          {
            firestore: dependencies.firebase.firestore,
            storage: dependencies.firebase.storage,
            assetSyncConcurrency: dependencies.assetSyncConcurrency,
          },
        request.body as WakeRequest,
        );
        response.status(200).json(result);
      } catch (error) {
        response.status(400).json({
          accepted: false,
          errorMessage: errorMessage(error),
        });
      }
    },
  );

  app.post(
    "/tasks/import-job",
    requireCaller("task", dependencies.auth),
    async (request: Request, response: Response) => {
      try {
        const result = await processImportJobTaskRequest(
          {
            firestore: dependencies.firebase.firestore,
            storage: dependencies.firebase.storage,
            assetSyncConcurrency: dependencies.assetSyncConcurrency,
          },
          request.body as ImportJobTaskRequest,
          cloudTasksRetryCount(request),
        );
        response.status(200).json(result);
      } catch (error) {
        console.error("[lookbook-import-worker] task request failed", error);
        response.status(isRetryableImportError(error) ? 503 : 500).json({
          accepted: false,
          errorMessage: errorMessage(error),
        });
      }
    },
  );

  app.post(
    "/tasks/discover-seasons",
    requireCaller("task", dependencies.auth),
    async (request: Request, response: Response) => {
      try {
        const result = await processSeasonDiscoveryTaskRequest(
          {
            firestore: dependencies.firebase.firestore,
            storage: dependencies.firebase.storage,
          },
          request.body as SeasonDiscoveryTaskRequest,
          cloudTasksRetryCount(request),
        );
        response.status(200).json(result);
      } catch (error) {
        console.error("[lookbook-import-worker] season discovery task failed", error);
        response.status(isRetryableImportError(error) ? 503 : 500).json({
          accepted: false,
          errorMessage: errorMessage(error),
        });
      }
    },
  );

  app.post(
    "/tasks/discover-seasons-diagnostic",
    requireCaller("functions", dependencies.auth),
    async (request: Request, response: Response) => {
      try {
        const result = await processDiscoverSeasonsDiagnosticRequest(
          request.body as DiscoverSeasonsDiagnosticRequest,
        );
        response.status(200).json(result);
      } catch (error) {
        console.error(
          "[lookbook-import-worker] season discovery diagnostic failed",
          error,
        );
        response.status(isRetryableImportError(error) ? 503 : 500).json({
          accepted: false,
          errorMessage: errorMessage(error),
        });
      }
    },
  );

  return app;
}

function requireCaller(
  caller: WorkerCaller,
  auth: WorkerAuthConfig & {verifier: OIDCTokenVerifier},
) {
  return async (
    request: Request,
    response: Response,
    next: NextFunction,
  ): Promise<void> => {
    try {
      await authenticateOIDCRequest(
        request.header("authorization"),
        caller,
        auth,
        auth.verifier,
      );
      next();
    } catch (error) {
      if (error instanceof OIDCAuthenticationError) {
        response.status(error.statusCode).json({
          accepted: false,
          errorMessage: error.message,
        });
        return;
      }
      response.status(401).json({
        accepted: false,
        errorMessage: "OIDC 인증에 실패했습니다.",
      });
    }
  };
}

function errorMessage(error: unknown): string {
  if (error instanceof Error && error.message.trim().length > 0) {
    return error.message;
  }
  return String(error);
}

function cloudTasksRetryCount(request: Request): number {
  const rawValue = request.header("x-cloudtasks-taskretrycount") ?? "0";
  const value = Number(rawValue);
  return Number.isInteger(value) && value >= 0 ? value : 0;
}
