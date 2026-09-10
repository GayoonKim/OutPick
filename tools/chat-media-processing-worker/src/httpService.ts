import {randomUUID} from "node:crypto";
import {createServer, type IncomingMessage, type ServerResponse} from "node:http";

import {runCloudMediaJob} from "./cloudJob.js";
import {imageConcurrency} from "./boundedMap.js";

const MAX_BODY_BYTES = 16 * 1024;

export function startImageProcessingService(
  environment: NodeJS.ProcessEnv = process.env,
): void {
  const port = positiveInteger(environment.PORT, "PORT");
  const readyBucket = requiredValue(environment.CHAT_MEDIA_READY_BUCKET, "CHAT_MEDIA_READY_BUCKET");
  const concurrency = imageConcurrency(environment.CHAT_MEDIA_IMAGE_CONCURRENCY);
  const server = createServer(async (request, response) => {
    if (request.method === "GET" && (request.url === "/" || request.url === "/healthz")) {
      sendJSON(response, 200, {ok: true});
      return;
    }
    if (request.method !== "POST" || request.url !== "/process") {
      sendJSON(response, 404, {ok: false, error: "not_found"});
      return;
    }
    try {
      const body = await readJSONBody(request);
      const uploadPath = boundedString(body.uploadPath, "uploadPath");
      const leaseToken = boundedString(body.leaseToken, "leaseToken");
      if (body.kind !== "images" || !validUploadPath(uploadPath)) {
        sendJSON(response, 400, {ok: false, error: "invalid_request"});
        return;
      }
      const executionName = `service/${randomUUID()}`;
      await runCloudMediaJob({uploadPath, leaseToken, kind: "images", readyBucket, imageConcurrency: concurrency});
      sendJSON(response, 200, {ok: true, executionName});
    } catch (error) {
      process.stderr.write(`${JSON.stringify({
        event: "image_service_failed",
        message: error instanceof Error ? error.message : String(error),
      })}\n`);
      sendJSON(response, 500, {ok: false, error: "processing_failed"});
    }
  });
  server.listen(port, "0.0.0.0");
}

async function readJSONBody(request: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  let total = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    total += buffer.length;
    if (total > MAX_BODY_BYTES) throw new Error("request body가 너무 큽니다.");
    chunks.push(buffer);
  }
  const parsed: unknown = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("request body가 올바르지 않습니다.");
  }
  return parsed as Record<string, unknown>;
}

function validUploadPath(path: string): boolean {
  return /^Rooms\/[^/]+\/MediaUploads\/[^/]+$/.test(path);
}

function boundedString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.length < 1 || value.length > 1024) {
    throw new Error(`${name}이 올바르지 않습니다.`);
  }
  return value;
}

function requiredValue(value: string | undefined, name: string): string {
  const normalized = value?.trim();
  if (!normalized) throw new Error(`${name} 환경 변수가 없습니다.`);
  return normalized;
}

function positiveInteger(value: string | undefined, name: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error(`${name}이 올바르지 않습니다.`);
  return parsed;
}

function sendJSON(response: ServerResponse, status: number, body: Record<string, unknown>): void {
  response.writeHead(status, {"content-type": "application/json; charset=utf-8"});
  response.end(JSON.stringify(body));
}
