/* eslint-disable require-jsdoc */
import {OAuth2Client} from "google-auth-library";

import type {IssueOperationsEnvironment} from "./contract.js";

export type IssueOperationsEndpoint = "read" | "write" | "release";

export type VerifiedOperatorIdentity = {
  email: string;
};

export interface OperatorTokenVerifier {
  verify(token: string, audience: string): Promise<{
    email: string | null;
    emailVerified: boolean;
  }>;
}

export type OperatorAuthConfig = {
  environment: IssueOperationsEnvironment;
  projectID: string;
  audience: string;
  operatorEmail: string;
};

export class IssueOperationsAuthError extends Error {
  constructor(
    readonly statusCode: 401 | 403 | 503,
    message: string
  ) {
    super(message);
    this.name = "IssueOperationsAuthError";
  }
}

export class GoogleOperatorTokenVerifier implements OperatorTokenVerifier {
  private readonly client = new OAuth2Client();

  async verify(token: string, audience: string): Promise<{
    email: string | null;
    emailVerified: boolean;
  }> {
    const ticket = await this.client.verifyIdToken({
      idToken: token,
      audience,
    });
    const payload = ticket.getPayload();
    return {
      email: payload?.email?.toLowerCase() ?? null,
      emailVerified: payload?.email_verified === true,
    };
  }
}

export async function authenticateOperator(input: {
  authorizationHeader: string | undefined;
  requestedEnvironment: IssueOperationsEnvironment;
  config: OperatorAuthConfig;
  verifier: OperatorTokenVerifier;
}): Promise<VerifiedOperatorIdentity> {
  if (input.requestedEnvironment !== input.config.environment) {
    throw new IssueOperationsAuthError(403, "요청 환경이 실행 환경과 다릅니다.");
  }
  const token = bearerToken(input.authorizationHeader);
  let identity: Awaited<ReturnType<OperatorTokenVerifier["verify"]>>;
  try {
    identity = await input.verifier.verify(token, input.config.audience);
  } catch {
    throw new IssueOperationsAuthError(401, "유효한 OIDC 토큰이 필요합니다.");
  }
  if (
    !identity.emailVerified ||
    identity.email !== input.config.operatorEmail.toLowerCase()
  ) {
    throw new IssueOperationsAuthError(403, "허용되지 않은 운영자입니다.");
  }
  return {email: identity.email};
}

export function operatorAuthConfig(
  projectID: string,
  endpoint: IssueOperationsEndpoint,
  environment = process.env
): OperatorAuthConfig {
  const definitions = projectID === "outpick-test" ? {
    environment: "development" as const,
    operatorEmail:
      "outpick-extraction-ops-dev@outpick-test.iam.gserviceaccount.com",
  } : projectID === "outpick-664ae" ? {
    environment: "production" as const,
    operatorEmail:
      "outpick-extraction-ops-prod@outpick-664ae.iam.gserviceaccount.com",
  } : null;
  if (definitions === null) {
    throw new IssueOperationsAuthError(503, "지원하지 않는 Firebase project입니다.");
  }
  const variable = endpoint === "read" ?
    "OUTPICK_EXTRACTION_OPS_READ_AUDIENCE" : endpoint === "write" ?
      "OUTPICK_EXTRACTION_OPS_WRITE_AUDIENCE" :
      "OUTPICK_EXTRACTION_OPS_RELEASE_AUDIENCE";
  const audience = environment[variable]?.trim();
  if (!audience || !/^https:\/\//.test(audience)) {
    throw new IssueOperationsAuthError(503, `${variable} 설정이 필요합니다.`);
  }
  return {
    ...definitions,
    projectID,
    audience,
  };
}

function bearerToken(value: string | undefined): string {
  const match = value?.match(/^Bearer ([^\s]+)$/i);
  if (!match) {
    throw new IssueOperationsAuthError(401, "Bearer OIDC 토큰이 필요합니다.");
  }
  return match[1];
}
