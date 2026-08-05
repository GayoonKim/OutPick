/* eslint-disable require-jsdoc, max-len */
import type {Request, Response} from "express";
import type {Firestore} from "firebase-admin/firestore";
import type {Storage} from "firebase-admin/storage";
import {onRequest} from "firebase-functions/v2/https";

import {db, defaultStorageBucket} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {
  authenticateOperator,
  GoogleOperatorTokenVerifier,
  IssueOperationsAuthError,
  operatorAuthConfig,
  type OperatorTokenVerifier,
} from "./auth.js";
import {
  IssueOperationsRequestError,
  parseReadRequest,
  parseWriteRequest,
} from "./contract.js";
import {
  getIssueCluster,
  getIssueClustersBatch,
  IssueOperationsServiceError,
  listIssueClusters,
  mutateIssueCluster,
} from "./service.js";

type Bucket = ReturnType<Storage["bucket"]>;

type HandlerDependencies = {
  firestore: Firestore;
  bucket: () => Bucket;
  projectID: string;
  verifier: OperatorTokenVerifier;
  environment?: NodeJS.ProcessEnv;
};

const verifier = new GoogleOperatorTokenVerifier();

export const lookbookExtractionIssueOpsRead = onRequest(
  {
    region: FUNCTIONS_REGION,
    invoker: "private",
    cors: false,
    timeoutSeconds: 60,
    memory: "512MiB",
  },
  createIssueOperationsReadHandler(runtimeDependencies())
);

export const lookbookExtractionIssueOpsWrite = onRequest(
  {
    region: FUNCTIONS_REGION,
    invoker: "private",
    cors: false,
    timeoutSeconds: 60,
    memory: "512MiB",
  },
  createIssueOperationsWriteHandler(runtimeDependencies())
);

export function createIssueOperationsReadHandler(
  dependencies: HandlerDependencies
): (request: Request, response: Response) => Promise<void> {
  return async (request, response) => {
    try {
      assertPOSTJSONRequest(request);
      const parsed = parseReadRequest(request.body);
      const config = operatorAuthConfig(
        dependencies.projectID,
        "read",
        dependencies.environment
      );
      await authenticateOperator({
        authorizationHeader: request.get("authorization"),
        requestedEnvironment: parsed.environment,
        config,
        verifier: dependencies.verifier,
      });
      if (parsed.action === "listClusters") {
        response.status(200).json({
          apiVersion: 1,
          requestID: parsed.requestID,
          result: await listIssueClusters({
            firestore: dependencies.firestore,
            query: parsed.payload,
          }),
        });
        return;
      }
      if (parsed.action === "getCluster") {
        response.status(200).json({
          apiVersion: 1,
          requestID: parsed.requestID,
          result: await getIssueCluster({
            firestore: dependencies.firestore,
            bucket: dependencies.bucket(),
            fingerprint: parsed.payload.fingerprint,
          }),
        });
        return;
      }
      response.status(200).json({
        apiVersion: 1,
        requestID: parsed.requestID,
        result: await getIssueClustersBatch({
          firestore: dependencies.firestore,
          bucket: dependencies.bucket(),
          fingerprints: parsed.payload.fingerprints,
        }),
      });
    } catch (error) {
      writeError(response, error);
    }
  };
}

export function createIssueOperationsWriteHandler(
  dependencies: HandlerDependencies
): (request: Request, response: Response) => Promise<void> {
  return async (request, response) => {
    try {
      assertPOSTJSONRequest(request);
      const parsed = parseWriteRequest(request.body);
      const config = operatorAuthConfig(
        dependencies.projectID,
        "write",
        dependencies.environment
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
        result: await mutateIssueCluster({
          firestore: dependencies.firestore,
          request: parsed,
          operatorEmail: identity.email,
        }),
      });
    } catch (error) {
      writeError(response, error);
    }
  };
}

function runtimeDependencies(): HandlerDependencies {
  return {
    firestore: db,
    bucket: defaultStorageBucket,
    projectID: process.env.GCLOUD_PROJECT ?? "",
    verifier,
  };
}

function assertPOSTJSONRequest(request: Request): void {
  if (request.method !== "POST") {
    throw new HTTPRequestError(405, "method_not_allowed", "POST만 허용됩니다.");
  }
  const contentLength = Number(request.get("content-length") ?? 0);
  if (Number.isFinite(contentLength) && contentLength > 64 * 1024) {
    throw new HTTPRequestError(413, "request_too_large", "요청 크기 제한을 초과했습니다.");
  }
  if (!request.is("application/json")) {
    throw new HTTPRequestError(
      415, "unsupported_media_type", "application/json이 필요합니다."
    );
  }
}

class HTTPRequestError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
    message: string
  ) {
    super(message);
  }
}

function writeError(response: Response, error: unknown): void {
  if (error instanceof IssueOperationsAuthError) {
    response.status(error.statusCode).json({error: {code: "unauthorized", message: error.message}});
    return;
  }
  if (error instanceof IssueOperationsRequestError) {
    response.status(400).json({error: {code: "invalid_request", message: error.message}});
    return;
  }
  if (error instanceof IssueOperationsServiceError || error instanceof HTTPRequestError) {
    response.status(error.statusCode).json({error: {code: error.code, message: error.message}});
    return;
  }
  response.status(500).json({
    error: {code: "internal", message: "내부 오류가 발생했습니다."},
  });
}
