/* eslint-disable require-jsdoc, max-len */
import type {Request, Response} from "express";
import type {Firestore} from "firebase-admin/firestore";
import {onRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {
  authenticateOperator, GoogleOperatorTokenVerifier,
  IssueOperationsAuthError, operatorAuthConfig,
  type OperatorTokenVerifier,
} from "./auth.js";
import {IssueOperationsRequestError} from "./contract.js";
import {parseVerifyFixRequest} from "./releaseContract.js";
import {
  GoogleReleaseExternalVerifier, type ReleaseExternalVerifier,
} from "./releaseExternal.js";
import {
  reconcileFixReleaseProjections, verifyExtractionFix,
} from "./releaseService.js";
import {IssueOperationsServiceError} from "./service.js";

type Dependencies = {
  firestore: Firestore;
  projectID: string;
  verifier: OperatorTokenVerifier;
  external: ReleaseExternalVerifier;
  environment?: NodeJS.ProcessEnv;
};

export const verifyLookbookExtractionFix = onRequest(
  {
    region: FUNCTIONS_REGION,
    invoker: "private",
    cors: false,
    timeoutSeconds: 300,
    memory: "1GiB",
  },
  createVerifyFixHandler(runtimeDependencies()),
);

export const reconcileLookbookExtractionFixReleases = onSchedule(
  {
    region: FUNCTIONS_REGION,
    schedule: "every 10 minutes",
    timeZone: "Asia/Seoul",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    await reconcileFixReleaseProjections(db);
  },
);

export function createVerifyFixHandler(
  dependencies: Dependencies,
): (request: Request, response: Response) => Promise<void> {
  return async (request, response) => {
    try {
      if (request.method !== "POST" || !request.is("application/json")) {
        throw new IssueOperationsRequestError("POST application/json 요청이 필요합니다.");
      }
      const parsed = parseVerifyFixRequest(request.body);
      const config = operatorAuthConfig(
        dependencies.projectID, "release", dependencies.environment,
      );
      const identity = await authenticateOperator({
        authorizationHeader: request.get("authorization"),
        requestedEnvironment: parsed.environment,
        config,
        verifier: dependencies.verifier,
      });
      response.status(200).json({
        apiVersion: 1,
        requestID: parsed.requestID,
        result: await verifyExtractionFix({
          firestore: dependencies.firestore,
          request: parsed,
          operatorEmail: identity.email,
          external: dependencies.external,
        }),
      });
    } catch (error) {
      if (error instanceof IssueOperationsAuthError) {
        response.status(error.statusCode).json({error: {code: "unauthorized", message: error.message}});
      } else if (error instanceof IssueOperationsRequestError) {
        response.status(400).json({error: {code: "invalid_request", message: error.message}});
      } else if (error instanceof IssueOperationsServiceError) {
        response.status(error.statusCode).json({error: {code: error.code, message: error.message}});
      } else {
        response.status(500).json({error: {code: "internal", message: "검증 중 내부 오류가 발생했습니다."}});
      }
    }
  };
}

function runtimeDependencies(): Dependencies {
  const projectID = process.env.GCLOUD_PROJECT ?? "";
  return {
    firestore: db,
    projectID,
    verifier: new GoogleOperatorTokenVerifier(),
    external: new GoogleReleaseExternalVerifier(projectID),
  };
}
