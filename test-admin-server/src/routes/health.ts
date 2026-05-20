import type {Express, Request, Response} from "express";
import type {ServerConfig} from "../config.js";
import type {FirebaseAdminContext} from "../firebaseAdmin.js";

export function registerHealthRoute(
  app: Express,
  config: ServerConfig,
  firebaseAdmin: FirebaseAdminContext
): void {
  app.get("/health", (_request: Request, response: Response) => {
    response.json({
      status: "ok",
      firebaseProjectID: config.firebaseProjectID,
      serviceAccountProjectID: firebaseAdmin.serviceAccountProjectID,
      firebaseAdminInitialized: true
    });
  });
}
