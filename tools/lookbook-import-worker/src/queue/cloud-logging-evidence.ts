import {GoogleAuth} from "google-auth-library";
import {type RecoveryEvidenceProvider} from "./recovery.js";

type LogEntry = {
  insertId?: string;
  timestamp?: string;
  textPayload?: string;
  jsonPayload?: unknown;
  labels?: Record<string, string>;
  resource?: {labels?: Record<string, string>};
};

const IDENTIFIER = /^[a-z][a-z0-9-]{0,62}[a-z0-9]$/;
const TRACE_ID = /^[a-f0-9]{32}$/;

export class CloudLoggingRecoveryEvidenceProvider
implements RecoveryEvidenceProvider {
  private readonly auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/logging.read"],
  });

  async findTerminatedInstance(input: {
    projectID: string;
    serviceName: string;
    revision: string;
    traceID: string;
    startedAt: number;
  }) {
    if (!IDENTIFIER.test(input.serviceName) ||
        !IDENTIFIER.test(input.revision) || !TRACE_ID.test(input.traceID) ||
        !Number.isSafeInteger(input.startedAt)) {
      return null;
    }
    const requestEntries = await this.listEntries(input.projectID,
      "resource.type=\"cloud_run_revision\" " +
      `AND resource.labels.service_name="${input.serviceName}" ` +
      `AND resource.labels.revision_name="${input.revision}" ` +
      `AND trace="projects/${input.projectID}/traces/${input.traceID}" ` +
      `AND logName="projects/${input.projectID}/logs/` +
        "run.googleapis.com%2Frequests\" " +
      `AND timestamp >= "${new Date(input.startedAt - 300000).toISOString()}"`);
    const instanceIDs = [...new Set(requestEntries.map((entry) =>
      entry.labels?.instanceId).filter((value): value is string =>
      typeof value === "string" && value.length > 0))];
    if (instanceIDs.length !== 1) return null;
    const instanceID = instanceIDs[0];
    const systemEntries = await this.listEntries(input.projectID,
      "resource.type=\"cloud_run_revision\" " +
      `AND resource.labels.service_name="${input.serviceName}" ` +
      `AND resource.labels.revision_name="${input.revision}" ` +
      `AND labels.instanceId="${instanceID}" ` +
      `AND logName="projects/${input.projectID}/logs/` +
        "run.googleapis.com%2Fvarlog%2Fsystem\" " +
      `AND timestamp >= "${new Date(input.startedAt).toISOString()}"`);
    const termination = systemEntries.find((entry) => {
      const timestamp = Date.parse(entry.timestamp ?? "");
      return Number.isFinite(timestamp) && timestamp >= input.startedAt &&
        isCloudRunTerminationMessage(entryText(entry));
    });
    if (!termination?.insertId || !termination.timestamp) return null;
    return {
      kind: "platformTermination" as const,
      projectID: input.projectID, serviceName: input.serviceName,
      revision: input.revision, instanceID, traceID: input.traceID,
      timestamp: termination.timestamp, insertID: termination.insertId,
    };
  }

  private async listEntries(
    projectID: string, filter: string,
  ): Promise<LogEntry[]> {
    const client = await this.auth.getClient();
    const access = await client.getAccessToken();
    const token = typeof access === "string" ? access : access.token;
    if (!token) throw new Error("CLOUD_LOGGING_AUTH_UNAVAILABLE");
    const entries: LogEntry[] = [];
    let pageToken: string | undefined;
    for (let page = 0; page < 3; page++) {
      const response = await fetch(
        "https://logging.googleapis.com/v2/entries:list",
        {
          method: "POST",
          headers: {"authorization": `Bearer ${token}`,
            "content-type": "application/json"},
          body: JSON.stringify({resourceNames: [`projects/${projectID}`],
            filter, orderBy: "timestamp desc", pageSize: 100,
            ...(pageToken ? {pageToken} : {})}),
          signal: AbortSignal.timeout(5000),
        });
      if (!response.ok) throw new Error("CLOUD_LOGGING_QUERY_FAILED");
      const body = await response.json() as {
        entries?: LogEntry[]; nextPageToken?: string;
      };
      entries.push(...(body.entries ?? []));
      pageToken = body.nextPageToken;
      if (!pageToken) return entries;
    }
    if (pageToken) throw new Error("CLOUD_LOGGING_RESULT_LIMIT");
    return entries;
  }
}

// 요청 timeout이나 종료 준비 안내를 인스턴스 종료 증거로 사용하지 않는다.
export function isCloudRunTerminationMessage(message: string): boolean {
  return /\b(?:container|instance)\b.{0,100}\b(?:was |has been )?terminated\b/i
    .test(message) ||
    /\bmemory limit(?: of \d+(?:\.\d+)?\s*(?:MiB|GiB|M|G))? exceeded\b/i
      .test(message) || /\boomkilled\b/i.test(message);
}

function entryText(entry: LogEntry): string {
  if (typeof entry.textPayload === "string") return entry.textPayload;
  const payload = entry.jsonPayload;
  if (typeof payload === "string") return payload;
  if (payload && typeof payload === "object") {
    const value = payload as Record<string, unknown>;
    return [value.message, value.msg, value.reason]
      .filter((item): item is string => typeof item === "string")
      .join(" ");
  }
  return "";
}
