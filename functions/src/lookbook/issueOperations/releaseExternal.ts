/* eslint-disable require-jsdoc, max-len */
export type CloudRunServiceState = {
  uri: string;
  ready: boolean;
  reconciling: boolean;
  traffic: Array<{revision: string; percent: number}>;
};

export type RuntimeContractDTO = {
  schemaVersion: 1;
  projectID: string;
  workerRevision: string;
  workerSourceRevision: string;
  seasonDiscoveryContractRevision: number;
  seasonDiscoveryExtractorVersion: string;
  imageExtractorVersion: string;
  adapterVersions: Record<string, string>;
};

export type SmokeResultDTO = {
  fingerprint: string;
  stage: "seasonDiscovery" | "seasonImageImport";
  sourceJobPathHash: string;
  candidateCount: number;
  candidateKeys: string[];
  logicIssueDetected: boolean;
  failureReasons: string[];
  qualityReasons: string[];
  runtime: RuntimeContractDTO;
};

export interface ReleaseExternalVerifier {
  cloudRunService(): Promise<CloudRunServiceState>;
  runtimeContract(uri: string): Promise<RuntimeContractDTO>;
  extractionSmoke(uri: string, request: Record<string, unknown>): Promise<SmokeResultDTO>;
}

export class GoogleReleaseExternalVerifier implements ReleaseExternalVerifier {
  private readonly projectID: string;

  constructor(projectID: string) {
    this.projectID = projectID;
  }

  async cloudRunService(): Promise<CloudRunServiceState> {
    const token = await metadataToken("token");
    const response = await fetch(
      releaseWorkerServiceResource(this.projectID),
      {headers: {authorization: `Bearer ${token}`}},
    );
    const body = await jsonResponse(response, "Cloud Run service 조회");
    const terminal = body.terminalCondition as Record<string, unknown> | undefined;
    return {
      uri: requiredHTTPSURL(body.uri),
      ready: terminal?.state === "CONDITION_SUCCEEDED",
      reconciling: body.reconciling === true,
      traffic: Array.isArray(body.trafficStatuses) ? body.trafficStatuses.map((item) => {
        const record = item as Record<string, unknown>;
        return {revision: String(record.revision ?? ""), percent: Number(record.percent ?? 0)};
      }) : [],
    };
  }

  async runtimeContract(uri: string): Promise<RuntimeContractDTO> {
    return this.workerJSON(uri, "/runtime-contract", "GET") as Promise<RuntimeContractDTO>;
  }

  async extractionSmoke(uri: string, request: Record<string, unknown>): Promise<SmokeResultDTO> {
    return this.workerJSON(uri, "/smoke/extraction", "POST", request) as Promise<SmokeResultDTO>;
  }

  private async workerJSON(
    uri: string, path: string, method: "GET" | "POST", body?: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const token = await metadataToken(`identity?audience=${encodeURIComponent(uri)}`);
    const response = await fetch(`${uri}${path}`, {
      method,
      headers: {
        authorization: `Bearer ${token}`,
        ...(body ? {"content-type": "application/json"} : {}),
      },
      ...(body ? {body: JSON.stringify(body)} : {}),
    });
    return jsonResponse(response, `Worker ${path}`);
  }
}

export function releaseWorkerServiceResource(projectID: string): string {
  const service = projectID === "outpick-test" ?
    "lookbook-import-worker-development" : projectID === "outpick-664ae" ?
      "lookbook-import-worker" : null;
  if (service === null) {
    throw new Error("지원하지 않는 release verifier project입니다.");
  }
  return `https://run.googleapis.com/v2/projects/${projectID}` +
    `/locations/asia-northeast3/services/${service}`;
}

async function metadataToken(suffix: string): Promise<string> {
  const response = await fetch(
    `http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/${suffix}`,
    {headers: {"Metadata-Flavor": "Google"}},
  );
  if (!response.ok) throw new Error(`metadata token 발급 실패: HTTP ${response.status}`);
  if (suffix === "token") {
    const body = await response.json() as {access_token?: unknown};
    if (typeof body.access_token !== "string") throw new Error("access token이 없습니다.");
    return body.access_token;
  }
  return (await response.text()).trim();
}

async function jsonResponse(response: Response, label: string): Promise<Record<string, unknown>> {
  const text = await response.text();
  if (!response.ok) throw new Error(`${label} 실패: HTTP ${response.status}`);
  const value: unknown = JSON.parse(text);
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} 응답이 올바르지 않습니다.`);
  }
  return value as Record<string, unknown>;
}

function requiredHTTPSURL(value: unknown): string {
  if (typeof value !== "string" || !/^https:\/\//.test(value)) {
    throw new Error("Cloud Run service URI가 올바르지 않습니다.");
  }
  return value.replace(/\/+$/, "");
}
