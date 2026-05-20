import express, {type Express} from "express";
import {registerHealthRoute} from "./routes/health.js";
import {registerResetRoute} from "./routes/reset.js";
import {registerLookbookSeedRoute} from "./routes/lookbookSeed.js";
import type {ServerConfig} from "./config.js";
import type {FirebaseAdminContext} from "./firebaseAdmin.js";

export function makeApp(
  config: ServerConfig,
  firebaseAdmin: FirebaseAdminContext
): Express {
  const app = express();

  app.use(express.json({limit: "1mb"}));

  registerHealthRoute(app, config, firebaseAdmin);
  registerResetRoute(app, firebaseAdmin);
  registerLookbookSeedRoute(app, config, firebaseAdmin);

  return app;
}
