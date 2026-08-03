import {OAuth2Client} from "google-auth-library";

export type WorkerCaller = "functions" | "task";

export interface VerifiedOIDCIdentity {
  email: string | null;
  emailVerified: boolean;
}

export interface OIDCTokenVerifier {
  verify(token: string, audience: string): Promise<VerifiedOIDCIdentity>;
}

export interface WorkerAuthConfig {
  audience: string;
  taskServiceAccountEmail: string;
  functionsServiceAccountEmail: string;
}

export class OIDCAuthenticationError extends Error {
  constructor(
    readonly statusCode: 401 | 403,
    message: string,
  ) {
    super(message);
    this.name = "OIDCAuthenticationError";
  }
}

export class GoogleOIDCTokenVerifier implements OIDCTokenVerifier {
  private readonly client = new OAuth2Client();

  async verify(
    token: string,
    audience: string,
  ): Promise<VerifiedOIDCIdentity> {
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

export async function authenticateOIDCRequest(
  authorizationHeader: string | undefined,
  caller: WorkerCaller,
  config: WorkerAuthConfig,
  verifier: OIDCTokenVerifier,
): Promise<VerifiedOIDCIdentity> {
  const token = bearerToken(authorizationHeader);
  let identity: VerifiedOIDCIdentity;
  try {
    identity = await verifier.verify(token, config.audience);
  } catch {
    throw new OIDCAuthenticationError(401, "유효한 OIDC 토큰이 필요합니다.");
  }

  const expectedEmail = allowedEmailForCaller(caller, config);
  if (!identity.emailVerified || identity.email !== expectedEmail) {
    throw new OIDCAuthenticationError(403, "허용되지 않은 호출자입니다.");
  }
  return identity;
}

export function allowedEmailForCaller(
  caller: WorkerCaller,
  config: WorkerAuthConfig,
): string {
  return caller === "task" ?
    config.taskServiceAccountEmail :
    config.functionsServiceAccountEmail;
}

function bearerToken(authorizationHeader: string | undefined): string {
  const match = authorizationHeader?.match(/^Bearer ([^\s]+)$/i);
  if (!match) {
    throw new OIDCAuthenticationError(401, "Bearer OIDC 토큰이 필요합니다.");
  }
  return match[1];
}
