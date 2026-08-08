/* eslint-disable require-jsdoc, max-len */
import {createHmac} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {firebaseAuth} from "../core/firebase.js";
import {
  MODERATION_HMAC_KEY_VERSION,
  ModerationProvider,
  ProviderIdentity,
} from "./contracts.js";

type CallableAuth = {
  uid: string;
  token: Record<string, unknown>;
} | undefined;

type ProviderUserRecord = {
  uid: string;
  customClaims?: Record<string, unknown>;
  providerData: readonly {providerId: string; uid: string}[];
};

function nonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim() : null;
}

function firebaseClaims(token: Record<string, unknown>): Record<string, unknown> {
  const value = token.firebase;
  return value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> : {};
}

function firstIdentitySubject(
  token: Record<string, unknown>,
  providerID: string,
): string | null {
  const identities = firebaseClaims(token).identities;
  if (!identities || typeof identities !== "object" || Array.isArray(identities)) {
    return null;
  }
  const value = (identities as Record<string, unknown>)[providerID];
  if (!Array.isArray(value)) return null;
  return value.map(nonEmptyString).find((subject) => subject !== null) ?? null;
}

function canonicalProvider(providerID: string | null): ModerationProvider | null {
  switch (providerID) {
  case "google.com": return "google";
  case "apple.com": return "apple";
  case "kakao": return "kakao";
  default: return null;
  }
}

export function providerIdentityFromUserRecord(
  user: ProviderUserRecord,
): ProviderIdentity | null {
  const customProvider = canonicalProvider(
    nonEmptyString(user.customClaims?.provider),
  );
  const customSubject = nonEmptyString(user.customClaims?.providerUserID);
  if (customProvider === "kakao" && customSubject) {
    return {provider: "kakao", subject: customSubject};
  }

  const identities = user.providerData.flatMap((entry) => {
    const provider = canonicalProvider(entry.providerId);
    const subject = nonEmptyString(entry.uid);
    return (provider === "google" || provider === "apple") && subject ?
      [{provider, subject}] : [];
  });
  return identities.length === 1 ? identities[0] : null;
}

export async function resolveProviderIdentity(
  auth: CallableAuth,
): Promise<{uid: string; identity: ProviderIdentity}> {
  if (!auth?.uid) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  }

  const customProvider = canonicalProvider(nonEmptyString(auth.token.provider));
  const customSubject = nonEmptyString(auth.token.providerUserID);
  if (customProvider === "kakao" && customSubject) {
    return {uid: auth.uid, identity: {provider: "kakao", subject: customSubject}};
  }

  const signInProvider = nonEmptyString(
    firebaseClaims(auth.token).sign_in_provider,
  );
  const provider = canonicalProvider(signInProvider);
  if (provider === "google" || provider === "apple") {
    const providerID = `${provider}.com`;
    const tokenSubject = firstIdentitySubject(auth.token, providerID);
    if (tokenSubject) {
      return {uid: auth.uid, identity: {provider, subject: tokenSubject}};
    }
    const user = await firebaseAuth.getUser(auth.uid);
    const providerSubject = user.providerData.find(
      (entry) => entry.providerId === providerID,
    )?.uid;
    if (providerSubject) {
      return {uid: auth.uid, identity: {provider, subject: providerSubject}};
    }
  }

  throw new HttpsError(
    "failed-precondition",
    "지원되는 로그인 제공자 식별 정보를 확인할 수 없습니다.",
  );
}

export function moderationAliasID(
  identity: ProviderIdentity,
  secret: string,
  keyVersion = MODERATION_HMAC_KEY_VERSION,
): string {
  if (!secret) {
    throw new HttpsError(
      "failed-precondition",
      "moderation principal secret이 설정되지 않았습니다.",
    );
  }
  const digest = createHmac("sha256", secret)
    .update(`${identity.provider}:${identity.subject}`, "utf8")
    .digest("base64url");
  return `v${keyVersion}_${digest}`;
}
