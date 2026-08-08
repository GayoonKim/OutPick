/* eslint-disable require-jsdoc, max-len */
import {
  ModerationProvider,
  ProviderIdentity,
} from "./contracts.js";
import {providerIdentityFromUserRecord} from "./identity.js";

export const DEVELOPMENT_PROJECT_ID = "outpick-test";
export const PRODUCTION_PROJECT_ID = "outpick-664ae";
export const PRODUCTION_CONFIRMATION =
  "APPLY_MODERATION_PRINCIPAL_BACKFILL_TO_OUTPICK_664AE";
export const DEFAULT_HMAC_SECRET_NAME = "MODERATION_PRINCIPAL_HMAC_KEY_V1";
export const DEFAULT_KAKAO_ADMIN_SECRET_NAME = "KAKAO_ADMIN_KEY";

export type BackfillUserRecord = {
  uid: string;
  customClaims?: Record<string, unknown>;
  providerData: readonly {providerId: string; uid: string}[];
};

export type BackfillUnresolvedReason =
  "unsupported-provider" |
  "kakao-invalid-uid" |
  "kakao-identity-mismatch" |
  "kakao-unlinked" |
  "kakao-http-failure";

export type BackfillResolution = {
  identity: ProviderIdentity;
  unresolvedReason: null;
} | {
  identity: null;
  unresolvedReason: BackfillUnresolvedReason;
};

export type BackfillArguments = {
  projectID: string;
  apply: boolean;
  hmacSecretName: string;
  kakaoAdminSecretName: string;
  productionConfirmation: string | null;
  expectedTotal: number | null;
  expectedGoogle: number | null;
  expectedKakao: number | null;
};

export type BackfillCounts = {
  authUserCount: number;
  resolvedCount: number;
  unresolvedCount: number;
  providerCounts: Record<ModerationProvider, number>;
  unresolvedReasonCounts: Partial<Record<BackfillUnresolvedReason, number>>;
};

type Fetcher = typeof fetch;

function requiredValue(argv: readonly string[], index: number, flag: string): string {
  const value = argv[index + 1];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} 값이 필요합니다.`);
  }
  return value;
}

function expectedCount(value: string, flag: string): number {
  const parsed = Number(value);
  if (!/^\d+$/.test(value) || !Number.isSafeInteger(parsed)) {
    throw new Error(`${flag}는 0 이상의 정수여야 합니다.`);
  }
  return parsed;
}

export function parseBackfillArguments(argv: readonly string[]): BackfillArguments {
  let projectID: string | null = null;
  let apply = false;
  let hmacSecretName = DEFAULT_HMAC_SECRET_NAME;
  let kakaoAdminSecretName = DEFAULT_KAKAO_ADMIN_SECRET_NAME;
  let productionConfirmation: string | null = null;
  let expectedTotal: number | null = null;
  let expectedGoogle: number | null = null;
  let expectedKakao: number | null = null;

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    switch (argument) {
    case "--project":
      projectID = requiredValue(argv, index, argument);
      index += 1;
      break;
    case "--secret-name":
      hmacSecretName = requiredValue(argv, index, argument);
      index += 1;
      break;
    case "--kakao-admin-secret-name":
      kakaoAdminSecretName = requiredValue(argv, index, argument);
      index += 1;
      break;
    case "--apply":
      apply = true;
      break;
    case "--confirm-production":
      productionConfirmation = requiredValue(argv, index, argument);
      index += 1;
      break;
    case "--expected-total":
      expectedTotal = expectedCount(requiredValue(argv, index, argument), argument);
      index += 1;
      break;
    case "--expected-google":
      expectedGoogle = expectedCount(requiredValue(argv, index, argument), argument);
      index += 1;
      break;
    case "--expected-kakao":
      expectedKakao = expectedCount(requiredValue(argv, index, argument), argument);
      index += 1;
      break;
    default:
      throw new Error(`지원하지 않는 인자입니다: ${argument}`);
    }
  }

  if (projectID !== DEVELOPMENT_PROJECT_ID && projectID !== PRODUCTION_PROJECT_ID) {
    throw new Error("허용된 Firebase project가 아닙니다.");
  }
  if (!hmacSecretName.trim() || !kakaoAdminSecretName.trim()) {
    throw new Error("Secret 이름이 비어 있습니다.");
  }
  if (projectID === PRODUCTION_PROJECT_ID && apply) {
    if (productionConfirmation !== PRODUCTION_CONFIRMATION) {
      throw new Error("Production 확인 문자열이 일치하지 않습니다.");
    }
    if (expectedTotal === null || expectedGoogle === null || expectedKakao === null) {
      throw new Error("Production apply에는 예상 계정 수가 모두 필요합니다.");
    }
    if (expectedTotal !== expectedGoogle + expectedKakao) {
      throw new Error("Production 예상 total과 provider별 합계가 일치하지 않습니다.");
    }
    if (
      hmacSecretName !== DEFAULT_HMAC_SECRET_NAME ||
      kakaoAdminSecretName !== DEFAULT_KAKAO_ADMIN_SECRET_NAME
    ) {
      throw new Error("Production apply는 canonical Secret 이름만 허용합니다.");
    }
  }

  return {
    projectID,
    apply,
    hmacSecretName: hmacSecretName.trim(),
    kakaoAdminSecretName: kakaoAdminSecretName.trim(),
    productionConfirmation,
    expectedTotal,
    expectedGoogle,
    expectedKakao,
  };
}

export function assertExpectedProductionCounts(
  options: BackfillArguments,
  counts: BackfillCounts,
): void {
  if (options.projectID !== PRODUCTION_PROJECT_ID || !options.apply) return;
  if (
    counts.authUserCount !== options.expectedTotal ||
    counts.providerCounts.google !== options.expectedGoogle ||
    counts.providerCounts.kakao !== options.expectedKakao ||
    counts.resolvedCount !== counts.authUserCount ||
    counts.unresolvedCount !== 0
  ) {
    throw new Error("Production 예상 계정 수 또는 provider 분포가 일치하지 않습니다.");
  }
}

export function kakaoSubjectCandidate(uid: string): string | null {
  const match = /^kakao:([1-9]\d*)$/.exec(uid);
  return match?.[1] ?? null;
}

async function verifyKakaoSubject(
  candidate: string,
  adminKey: string,
  fetcher: Fetcher,
): Promise<BackfillResolution> {
  const url = new URL("https://kapi.kakao.com/v2/user/me");
  url.searchParams.set("target_id_type", "user_id");
  url.searchParams.set("target_id", candidate);
  let response: Response;
  try {
    response = await fetcher(url, {
      method: "GET",
      headers: {
        "Authorization": `KakaoAK ${adminKey}`,
        "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
      },
    });
  } catch {
    return {identity: null, unresolvedReason: "kakao-http-failure"};
  }
  if (!response.ok) {
    return {
      identity: null,
      unresolvedReason: response.status === 400 || response.status === 404 ?
        "kakao-unlinked" : "kakao-http-failure",
    };
  }
  try {
    const payload = await response.json() as {id?: string | number};
    if (String(payload.id) !== candidate) {
      return {identity: null, unresolvedReason: "kakao-identity-mismatch"};
    }
  } catch {
    return {identity: null, unresolvedReason: "kakao-http-failure"};
  }
  return {
    identity: {provider: "kakao", subject: candidate},
    unresolvedReason: null,
  };
}

export async function resolveBackfillIdentity(
  user: BackfillUserRecord,
  kakaoAdminKey: string | null,
  fetcher: Fetcher = fetch,
): Promise<BackfillResolution> {
  const storedIdentity = providerIdentityFromUserRecord(user);
  if (storedIdentity?.provider === "google" || storedIdentity?.provider === "apple") {
    return {identity: storedIdentity, unresolvedReason: null};
  }

  const candidate = kakaoSubjectCandidate(user.uid);
  if (!candidate) {
    return {
      identity: null,
      unresolvedReason: user.uid.startsWith("kakao:") ?
        "kakao-invalid-uid" : "unsupported-provider",
    };
  }
  if (!kakaoAdminKey) {
    return {identity: null, unresolvedReason: "kakao-http-failure"};
  }
  if (storedIdentity?.provider === "kakao" && storedIdentity.subject !== candidate) {
    return {identity: null, unresolvedReason: "kakao-identity-mismatch"};
  }
  return verifyKakaoSubject(candidate, kakaoAdminKey, fetcher);
}

export function buildBackfillCounts(
  resolutions: readonly BackfillResolution[],
): BackfillCounts {
  const providerCounts: Record<ModerationProvider, number> = {
    google: 0,
    apple: 0,
    kakao: 0,
  };
  const unresolvedReasonCounts:
    Partial<Record<BackfillUnresolvedReason, number>> = {};
  let resolvedCount = 0;

  for (const resolution of resolutions) {
    if (resolution.identity) {
      providerCounts[resolution.identity.provider] += 1;
      resolvedCount += 1;
    } else {
      const reason = resolution.unresolvedReason;
      unresolvedReasonCounts[reason] = (unresolvedReasonCounts[reason] ?? 0) + 1;
    }
  }
  return {
    authUserCount: resolutions.length,
    resolvedCount,
    unresolvedCount: resolutions.length - resolvedCount,
    providerCounts,
    unresolvedReasonCounts,
  };
}
