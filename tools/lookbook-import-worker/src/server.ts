import express, {type Express, type Request, type Response} from "express";

import {type FirebaseClients} from "./firebase.js";

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

  app.post("/wake", (_request: Request, response: Response) => {
    // TODO: Phase 5에서 Cloud Run 호출 인증 방식을 확정한 뒤 검증을 추가한다.
    response.status(202).json({
      accepted: true,
      jobProcessingEnabled: false,
    });
  });

  return app;
}
