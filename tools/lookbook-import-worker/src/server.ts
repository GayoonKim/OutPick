import express, {type Express, type Request, type Response} from "express";

import {type FirebaseClients} from "./firebase.js";
import {processWakeRequest, type WakeRequest} from "./processor.js";

interface ServerDependencies {
  projectID: string;
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
    // TODO: Phase 5에서 Cloud Run 호출 인증 방식을 확정한 뒤 검증을 추가한다.
    try {
      const result = await processWakeRequest(
        {
          firestore: dependencies.firebase.firestore,
          storage: dependencies.firebase.storage,
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

  return app;
}

function errorMessage(error: unknown): string {
  if (error instanceof Error && error.message.trim().length > 0) {
    return error.message;
  }
  return String(error);
}
