/* eslint-disable require-jsdoc */
import {defineSecret} from "firebase-functions/params";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {FUNCTIONS_REGION} from "../core/runtime.js";
import {resolveProviderIdentity} from "./identity.js";
import {allowedCapabilities, bindModerationPrincipal} from "./state.js";

export const moderationPrincipalHmacKey = defineSecret(
  "MODERATION_PRINCIPAL_HMAC_KEY_V1",
);

export async function handleGetMyModerationState(
  auth: Parameters<typeof resolveProviderIdentity>[0],
  secret: string,
) {
  const {uid, identity} = await resolveProviderIdentity(auth);
  const state = await bindModerationPrincipal(uid, identity, secret);
  return {
    moderationStatus: state.moderationStatus,
    restrictedUntil: state.restrictedUntil?.toISOString() ?? null,
    allowedCapabilities: allowedCapabilities(state.moderationStatus),
    noticeReasonCode: state.noticeReasonCode,
    supportURL: null,
  };
}

export const getMyModerationState = onCall(
  {
    region: FUNCTIONS_REGION,
    enforceAppCheck: true,
    secrets: [moderationPrincipalHmacKey],
  },
  async (request) => {
    try {
      return await handleGetMyModerationState(
        request.auth,
        moderationPrincipalHmacKey.value(),
      );
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error("[getMyModerationState] unexpected error", error);
      throw new HttpsError("internal", "제재 상태를 확인하지 못했습니다.");
    }
  },
);
