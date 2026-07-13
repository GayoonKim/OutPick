import {
  emailFromDecodedToken,
  extractFirebaseIDToken,
  getClientKey
} from "./handshake.js";
import { normalizeEmail } from "../utils/strings.js";

export function createReconnectAttemptMiddleware({
  clock,
  reconnectPolicy,
  logger = console
}) {
  const connectAttempts = new Map();

  return function reconnectAttemptMiddleware(socket, next) {
    const key = getClientKey(socket.handshake);
    const now = clock.nowMillis();
    const record = connectAttempts.get(key) || { times: [] };
    record.times = record.times.filter((time) => now - time <= reconnectPolicy.windowMs);
    record.times.push(now);
    connectAttempts.set(key, record);

    if (record.times.length > reconnectPolicy.maxAttempts) {
      const error = new Error("max_connect_attempts_exceeded");
      error.data = {
        message: "연결 시도 횟수를 초과했습니다. 잠시 후 다시 시도하세요.",
        maxAttempts: reconnectPolicy.maxAttempts,
        retryAfterMs: Math.min(
          reconnectPolicy.maxDelayMs,
          reconnectPolicy.baseDelayMs * 16
        )
      };
      logger.warn?.("[auth] reconnect attempt limit exceeded", { clientKey: key });
      return next(error);
    }

    return next();
  };
}

export function createFirebaseAuthMiddleware({
  verifyIDToken,
  findUserByUID,
  logger = console
}) {
  return async function firebaseAuthMiddleware(socket, next) {
    const idToken = extractFirebaseIDToken(socket.handshake);
    if (!idToken) {
      logger.warn("[auth] missing Firebase ID Token", {
        clientKey: getClientKey(socket.handshake)
      });
      const error = new Error("unauthenticated");
      error.data = { message: "Firebase ID Token이 필요합니다.", error: "missing_id_token" };
      return next(error);
    }

    try {
      const decodedToken = await verifyIDToken(idToken);
      const userUID = typeof decodedToken.uid === "string" ? decodedToken.uid.trim() : "";
      if (!userUID) {
        logger.warn("[auth] verified token without uid", {
          clientKey: getClientKey(socket.handshake)
        });
        const error = new Error("unauthenticated");
        error.data = {
          message: "Firebase ID Token에 uid가 없습니다.",
          error: "missing_token_uid"
        };
        return next(error);
      }

      const tokenEmail = emailFromDecodedToken(decodedToken);
      const userProfile = await findUserByUID(userUID);
      const profileEmail = normalizeEmail(userProfile?.data?.email);

      socket.userUID = userUID;
      socket.userDocumentID = userProfile?.ref?.id || userUID;
      socket.userEmail = profileEmail || tokenEmail || "";
      socket.userEmailSource = profileEmail ? "profile" : "token";
      return next();
    } catch (error) {
      logger.warn("[auth] Firebase ID Token verification failed", {
        code: error?.code,
        message: error?.message
      });
      const authError = new Error("unauthenticated");
      authError.data = {
        message: "Firebase ID Token 검증에 실패했습니다.",
        error: "invalid_id_token"
      };
      return next(authError);
    }
  };
}
