import express, {type Express, type Request, type Response} from "express";

import {type FirebaseClients} from "./firebase.js";
import {
  processImportJobTaskRequest,
  processWakeRequest,
  type ImportJobTaskRequest,
  type WakeRequest,
} from "./processor.js";
import {isRetryableImportError} from "./import-error.js";

interface ServerDependencies {
  projectID: string;
  assetSyncConcurrency: number;
  firebase: FirebaseClients;
}

export function createServer(dependencies: ServerDependencies): Express {
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json({limit: "64kb"}));

  app.get("/healthz", (_request: Request, response: Response) => {
    response.status(200).json({
      ok: true,
      service: "lookbook-import-worker",
      projectID: dependencies.projectID,
    });
  });

  app.post("/wake", async (request: Request, response: Response) => {
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
  });

  app.post(
    "/tasks/import-job",
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

  return app;
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
