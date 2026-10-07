/* eslint-disable max-len */
import express, {
  type Express,
  type NextFunction,
  type Request,
  type Response,
} from "express";

import {type FirebaseClients} from "./firebase.js";
import {
  processImportBatchTaskRequest,
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
import {withMeasurement, type PerformanceOptions} from "./performance/session.js";
import type {PipelineRuntime} from "./pipeline/resources.js";
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
import {
  inspectQueueRecovery, parseRecoveryTarget, resumeQueueRecovery,
  settleCorrectionQueueRecovery,
  type RecoveryEvidenceProvider,
} from "./queue/recovery.js";
import {QUEUE_POLICY} from "./queue/contracts.js";
import {waitForQueueBatchResponse} from "./queue/http-deadline.js";
import {settleTerminatedSeasonRun} from "./queue/termination-retry.js";
import type {DevelopmentRetryFault} from "./queue/development-retry-fault.js";

interface ServerDependencies {
  projectID: string;
  assetSyncConcurrency: number;
  firebase: FirebaseClients;
  auth: WorkerAuthConfig & {verifier: OIDCTokenVerifier};
  runtime: WorkerRuntimeContract;
  performance?: PerformanceOptions;
  pipeline?: PipelineRuntime;
  queueOwner?: string;
  bootID?: string;
  shutdownSignal?: AbortSignal;
  remoteExperiment?: (body: unknown, signal: AbortSignal) => Promise<unknown>;
  recovery?: {serviceName: string; evidenceProvider: RecoveryEvidenceProvider};
  developmentRetryFault?: DevelopmentRetryFault;
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

  if (dependencies.remoteExperiment) {
    if (dependencies.projectID !== "outpick-test") {
      throw new Error("원격 실험 서버는 Development만 허용합니다.");
    }
    const execute = dependencies.remoteExperiment;
    app.post("/experiments/lookbook-transfer",
      requireCaller("functions", dependencies.auth), async (request, response) => {
        const controller = new AbortController();
        const abort = () => {
          if (!response.writableFinished) controller.abort();
        };
        response.once("close", abort);
        try {
          response.status(200).json(await execute(request.body, controller.signal));
        } catch (error) {
          response.status(409).json({accepted: false, errorMessage: errorMessage(error)});
        } finally {
          response.off("close", abort);
        }
      });
    // 실험 리비전에 잘못 전달된 제품 요청은 이미지 작업을 시작하지 않는다.
    return app;
  }

  app.post("/recovery/inspect", requireCaller("recovery", dependencies.auth),
    async (request: Request, response: Response) => {
      if (!dependencies.recovery) {
        response.status(503).json({accepted: false,
          errorMessage: "복구 증거 조회를 설정하지 않았습니다."});
        return;
      }
      try {
        const target = parseRecoveryTarget(recoveryTargetFromBody(request.body));
        const report = await inspectQueueRecovery({
          firestore: dependencies.firebase.firestore,
          evidenceProvider: dependencies.recovery.evidenceProvider,
          target, projectID: dependencies.projectID,
          serviceName: dependencies.recovery.serviceName,
          revision: dependencies.runtime.workerRevision,
        });
        response.status(200).json(report);
      } catch (error) {
        const invalid = errorMessage(error) === "INVALID_RECOVERY_REQUEST";
        response.status(invalid ? 400 : 503).json({accepted: false,
          errorMessage: invalid ? "복구 요청 형식이 올바르지 않습니다." :
            "복구 상태를 안전하게 확인하지 못했습니다."});
      }
    });

  app.post("/recovery/resume", requireCaller("recovery", dependencies.auth),
    async (request: Request, response: Response) => {
      if (!dependencies.recovery) {
        response.status(503).json({accepted: false,
          errorMessage: "복구 증거 조회를 설정하지 않았습니다."});
        return;
      }
      try {
        const input = recoveryResumeFromBody(request.body);
        const actorEmail = response.locals.oidcIdentity?.email;
        if (typeof actorEmail !== "string") {
          response.status(403).json({accepted: false,
            errorMessage: "복구 운영 주체를 확인하지 못했습니다."});
          return;
        }
        const result = await resumeQueueRecovery({
          firestore: dependencies.firebase.firestore,
          evidenceProvider: dependencies.recovery.evidenceProvider,
          target: input.target, projectID: dependencies.projectID,
          serviceName: dependencies.recovery.serviceName,
          revision: dependencies.runtime.workerRevision,
          reportDigest: input.reportDigest,
          expectedStateRevision: input.expectedStateRevision,
          decisionID: input.decisionID, actorEmail,
        });
        response.status(200).json(result);
      } catch (error) {
        const invalid = errorMessage(error) === "INVALID_RECOVERY_REQUEST";
        const stale = errorMessage(error) === "RECOVERY_REPORT_STALE_OR_BLOCKED";
        const conflict = errorMessage(error) === "RECOVERY_DECISION_CONFLICT";
        response.status(invalid ? 400 : stale ? 409 : conflict ? 409 : 503)
          .json({accepted: false,
            errorMessage: invalid ? "복구 요청 형식이 올바르지 않습니다." :
              stale ? "검사 보고서가 바뀌었거나 재개 조건을 충족하지 않습니다." :
                conflict ? "같은 결정 ID가 다른 복구 보고서에 사용됐습니다." :
                  "복구 상태를 안전하게 갱신하지 못했습니다."});
      }
    });

  app.post("/recovery/settle-correction",
    requireCaller("recovery", dependencies.auth),
    async (request: Request, response: Response) => {
      if (!dependencies.recovery) {
        response.status(503).json({accepted: false,
          errorMessage: "복구 증거 조회를 설정하지 않았습니다."});
        return;
      }
      try {
        const input = recoveryResumeFromBody(request.body);
        const actorEmail = response.locals.oidcIdentity?.email;
        if (typeof actorEmail !== "string") {
          response.status(403).json({accepted: false,
            errorMessage: "복구 운영 주체를 확인하지 못했습니다."});
          return;
        }
        const result = await settleCorrectionQueueRecovery({
          firestore: dependencies.firebase.firestore,
          evidenceProvider: dependencies.recovery.evidenceProvider,
          target: input.target, projectID: dependencies.projectID,
          serviceName: dependencies.recovery.serviceName,
          revision: dependencies.runtime.workerRevision,
          reportDigest: input.reportDigest,
          expectedStateRevision: input.expectedStateRevision,
          decisionID: input.decisionID, actorEmail,
        });
        response.status(200).json(result);
      } catch (error) {
        const invalid = errorMessage(error) === "INVALID_RECOVERY_REQUEST";
        const stale = errorMessage(error) === "RECOVERY_REPORT_STALE_OR_BLOCKED";
        const conflict = errorMessage(error) === "RECOVERY_DECISION_CONFLICT";
        response.status(invalid ? 400 : stale ? 409 : conflict ? 409 : 503)
          .json({accepted: false,
            errorMessage: invalid ? "복구 요청 형식이 올바르지 않습니다." :
              stale ? "검사 보고서가 바뀌었거나 정산 조건을 충족하지 않습니다." :
                conflict ? "같은 결정 ID가 다른 복구 보고서에 사용됐습니다." :
                  "복구 상태를 안전하게 갱신하지 못했습니다."});
      }
    });

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
        const result = await withMeasurement(dependencies.performance, "wake", () => processWakeRequest(
          {
            firestore: dependencies.firebase.firestore,
            storage: dependencies.firebase.storage,
            assetSyncConcurrency: dependencies.assetSyncConcurrency,
            pipeline: dependencies.pipeline,
          },
          request.body as WakeRequest,
        ));
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
    "/tasks/import-batch",
    requireCaller("task", dependencies.auth),
    async (request: Request, response: Response) => {
      const queueOwner = dependencies.queueOwner;
      const bootID = dependencies.bootID;
      if (!queueOwner || !bootID) {
        response.status(503).json({accepted: false,
          errorMessage: "batch 실행권을 초기화하지 않았습니다."});
        return;
      }
      const requestController = new AbortController();
      const stopAdmission = () => {
        if (!response.writableFinished) {
          requestController.abort(new Error("batch 요청 연결 종료"));
        }
      };
      response.once("close", stopAdmission);
      const signals = [requestController.signal];
      if (dependencies.shutdownSignal) signals.push(dependencies.shutdownSignal);
      const admissionSignal = AbortSignal.any(signals);
      try {
        const result = await waitForQueueBatchResponse({response,
          controller: requestController,
          deadlineMs: QUEUE_POLICY.drainTargetAfterMs,
          operation: withMeasurement(dependencies.performance, "task", async () => {
            const delivery = dependencies.recovery ? await settleTerminatedSeasonRun({
              firestore: dependencies.firebase.firestore, delivery: request.body,
              projectID: dependencies.projectID, serviceName: dependencies.recovery.serviceName,
              evidenceProvider: dependencies.recovery.evidenceProvider,
            }) : request.body;
            return processImportBatchTaskRequest(
              {
                firestore: dependencies.firebase.firestore,
                storage: dependencies.firebase.storage,
                assetSyncConcurrency: dependencies.assetSyncConcurrency,
                developmentRetryFault: dependencies.developmentRetryFault,
              },
              delivery,
              queueOwner,
              bootID,
              admissionSignal,
              {projectID: dependencies.projectID,
                revision: dependencies.runtime.workerRevision,
                traceID: cloudTraceID(request.header("x-cloud-trace-context"))},
            );
          }, {
            batchID: typeof request.body?.batchID === "string" ?
              request.body.batchID : undefined,
          }),
        });
        if (response.headersSent) return;
        if (result.status === "unsupported") {
          response.status(503).json({accepted: false,
            errorMessage: result.reason ?? "batch kind is not connected"});
          return;
        }
        response.status(200).json(result);
      } catch (error) {
        console.error("[lookbook-import-worker] batch task request failed", error);
        if (response.headersSent) return;
        const status = errorMessage(error) === "INVALID_QUEUE_CONTRACT" ? 400 :
          isRetryableImportError(error) ? 503 : 500;
        response.status(status).json({
          accepted: false,
          errorMessage: errorMessage(error),
        });
      } finally {
        response.off("close", stopAdmission);
      }
    },
  );

  app.post(
    "/tasks/import-job",
    requireCaller("task", dependencies.auth),
    async (request: Request, response: Response) => {
      try {
        const result = await withMeasurement(dependencies.performance, "task", () => processImportJobTaskRequest(
          {
            firestore: dependencies.firebase.firestore,
            storage: dependencies.firebase.storage,
            assetSyncConcurrency: dependencies.assetSyncConcurrency,
            pipeline: dependencies.pipeline,
          },
          request.body as ImportJobTaskRequest,
          cloudTasksRetryCount(request),
        ));
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
      const identity = await authenticateOIDCRequest(
        request.header("authorization"),
        caller,
        auth,
        auth.verifier,
      );
      response.locals.oidcIdentity = identity;
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

function recoveryTargetFromBody(body: unknown): unknown {
  if (!body || typeof body !== "object" || Array.isArray(body) ||
      Object.keys(body).length !== 1 || !("target" in body)) {
    throw new Error("INVALID_RECOVERY_REQUEST");
  }
  return (body as {target: unknown}).target;
}

function recoveryResumeFromBody(body: unknown): {
  target: ReturnType<typeof parseRecoveryTarget>;
  reportDigest: string;
  expectedStateRevision: number;
  decisionID: string;
} {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new Error("INVALID_RECOVERY_REQUEST");
  }
  const value = body as Record<string, unknown>;
  const allowed = ["target", "reportDigest", "expectedStateRevision", "decisionID"];
  if (Object.keys(value).some((key) => !allowed.includes(key)) ||
      typeof value.reportDigest !== "string" ||
      !Number.isSafeInteger(value.expectedStateRevision) ||
      typeof value.decisionID !== "string") {
    throw new Error("INVALID_RECOVERY_REQUEST");
  }
  return {target: parseRecoveryTarget(value.target),
    reportDigest: value.reportDigest,
    expectedStateRevision: Number(value.expectedStateRevision),
    decisionID: value.decisionID};
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

function cloudTraceID(value: string | undefined): string | null {
  const traceID = value?.match(/^([a-f0-9]{32})(?:\/\d+)?(?:;o=[01])?$/i)?.[1];
  return traceID?.toLowerCase() ?? null;
}
