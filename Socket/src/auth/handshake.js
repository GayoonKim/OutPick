import { normalizeEmail } from "../utils/strings.js";

export function getClientKey(handshake) {
  try {
    return (
      handshake.auth?.clientKey ||
      handshake.headers?.["x-outpick-client-key"] ||
      handshake.query?.clientKey ||
      handshake.address ||
      "unknown"
    );
  } catch {
    return "unknown";
  }
}

export function extractFirebaseIDToken(handshake) {
  const authToken = handshake.auth?.idToken || handshake.auth?.token;
  if (typeof authToken === "string" && authToken.trim()) {
    return authToken.trim();
  }

  const authorization = handshake.headers?.authorization;
  if (typeof authorization === "string") {
    const match = authorization.match(/^Bearer\s+(.+)$/i);
    if (match?.[1]) return match[1].trim();
  }

  return "";
}

export function emailFromDecodedToken(decodedToken) {
  const directEmail = normalizeEmail(decodedToken?.email);
  if (directEmail) return directEmail;

  const identityEmails = decodedToken?.firebase?.identities?.email;
  if (Array.isArray(identityEmails)) {
    for (const email of identityEmails) {
      const normalized = normalizeEmail(email);
      if (normalized) return normalized;
    }
  }

  return "";
}
