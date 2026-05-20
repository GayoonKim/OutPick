import type {Express, Request, Response} from "express";
import type {FirebaseAdminContext} from "../firebaseAdmin.js";
import {resetAuthTestUsers} from "../reset/authReset.js";
import {resetFirestoreTestData, type ResetRequest} from "../reset/firestoreReset.js";

interface ResetResponse {
  readonly status: "ok";
  readonly dryRun: boolean;
  readonly matchedDocumentPaths: string[];
  readonly deletedDocumentCount: number;
  readonly matchedAuthUserIDs: string[];
  readonly deletedAuthUserCount: number;
}

export function registerResetRoute(
  app: Express,
  firebaseAdmin: FirebaseAdminContext
): void {
  app.post("/reset", async (request: Request, response: Response) => {
    const resetRequest = parseResetRequest(request.body);
    const firestoreResult = await resetFirestoreTestData(
      firebaseAdmin.firestore,
      resetRequest
    );
    const authResult = await resetAuthTestUsers(
      firebaseAdmin.auth,
      resetRequest
    );
    const body: ResetResponse = {
      status: "ok",
      dryRun: resetRequest.dryRun === true,
      matchedDocumentPaths: firestoreResult.matchedDocumentPaths,
      deletedDocumentCount: firestoreResult.deletedDocumentCount,
      matchedAuthUserIDs: authResult.matchedAuthUserIDs,
      deletedAuthUserCount: authResult.deletedAuthUserCount
    };

    response.json(body);
  });
}

function parseResetRequest(body: unknown): ResetRequest {
  if (typeof body !== "object" || body === null) {
    return {};
  }

  const objectBody = body as Record<string, unknown>;
  return {
    testRunId: stringValue(objectBody.testRunId),
    dryRun: objectBody.dryRun === true
  };
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}
