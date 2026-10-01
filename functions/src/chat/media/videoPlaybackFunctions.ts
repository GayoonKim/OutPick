/* eslint-disable require-jsdoc, max-len */
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {requiredAuthUID} from "../../core/callable.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {chatMediaServiceAccountEmailForEnvironment} from "./runtime.js";
import {parseIssueChatMediaURLInput, parseIssueChatVideoPlaybackURLInput} from "./videoPlaybackContracts.js";
import {issueChatVideoPlaybackURLService} from "./videoPlaybackService.js";

const runtimeServiceAccount = chatMediaServiceAccountEmailForEnvironment(
  process.env,
  "videoPlayback",
);

function readyBucket(): string {
  const value = process.env.CHAT_MEDIA_READY_BUCKET?.trim();
  if (!value) throw new Error("chat_media_ready_bucket_missing");
  return value;
}

export async function handleIssueChatVideoPlaybackURL(
  uid: string | undefined,
  data: unknown,
) {
  const actorUID = requiredAuthUID(uid);
  const request = parseIssueChatVideoPlaybackURLInput(data);
  return issueChatVideoPlaybackURLService({
    actorUID,
    request,
    readyBucket: readyBucket(),
  });
}

function callableError(error: unknown): never {
  if (error instanceof HttpsError) throw error;
  // URL·경로·signer 응답을 로그에 기록하지 않는다.
  console.error("[issueChatVideoPlaybackURL] unexpected error");
  throw new HttpsError("internal", "동영상 재생 링크를 발급하지 못했습니다.");
}

export const issueChatVideoPlaybackURL = onCall(
  {
    region: FUNCTIONS_REGION,
    enforceAppCheck: true,
    serviceAccount: runtimeServiceAccount,
  },
  async (request) => {
    try {
      return await handleIssueChatVideoPlaybackURL(request.auth?.uid, request.data);
    } catch (error) {
      return callableError(error);
    }
  },
);

export const issueChatMediaURL = onCall(
  {region: FUNCTIONS_REGION, enforceAppCheck: true, serviceAccount: runtimeServiceAccount},
  async (request) => {
    try {
      const actorUID = requiredAuthUID(request.auth?.uid);
      const input = parseIssueChatMediaURLInput(request.data);
      return await issueChatVideoPlaybackURLService({
        actorUID, request: input, variant: input.variant, readyBucket: readyBucket(),
      });
    } catch (error) {
      return callableError(error);
    }
  },
);
