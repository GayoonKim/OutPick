import type {Express, Request, Response} from "express";
import type {ServerConfig} from "../config.js";
import type {FirebaseAdminContext} from "../firebaseAdmin.js";
import {
  seedLookbookBasic,
  type LookbookBasicSeedRequest
} from "../seed/lookbookBasicSeed.js";
import {seedLookbookComments} from "../seed/lookbookCommentsSeed.js";

export function registerLookbookSeedRoute(
  app: Express,
  config: ServerConfig,
  firebaseAdmin: FirebaseAdminContext
): void {
  app.post("/seed/lookbook-basic", async (request: Request, response: Response) => {
    const password = requireTestUserPassword(config);
    const seedRequest = parseSeedRequest(request.body);
    const result = await seedLookbookBasic(
      firebaseAdmin.firestore,
      firebaseAdmin.auth,
      password,
      seedRequest
    );

    response.json({
      status: "ok",
      ...result
    });
  });

  app.post("/seed/lookbook-comments", async (request: Request, response: Response) => {
    const password = requireTestUserPassword(config);
    const seedRequest = parseSeedRequest(request.body);
    const result = await seedLookbookComments(
      firebaseAdmin.firestore,
      firebaseAdmin.auth,
      password,
      seedRequest
    );

    response.json({
      status: "ok",
      ...result
    });
  });
}

function parseSeedRequest(body: unknown): LookbookBasicSeedRequest {
  if (typeof body !== "object" || body === null) {
    return {};
  }

  const objectBody = body as Record<string, unknown>;
  return {
    testRunId: stringValue(objectBody.testRunId)
  };
}

function requireTestUserPassword(config: ServerConfig): string {
  if (config.testUserPassword === undefined) {
    throw new Error("TEST_FIREBASE_TEST_USER_PASSWORD 환경 변수가 필요합니다.");
  }

  return config.testUserPassword;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}
