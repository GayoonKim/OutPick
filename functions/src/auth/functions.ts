/* eslint-disable max-len */
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {recordData, requiredString} from "../core/callable.js";
import {firebaseAuth} from "../core/firebase.js";
import {FUNCTIONS_REGION} from "../core/runtime.js";
import {exchangeKakaoAccessToken} from "./kakaoService.js";

export const exchangeKakaoToken = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    try {
      const data = recordData(request.data);
      const accessToken = requiredString(data, "accessToken", 4096);
      return await exchangeKakaoAccessToken(accessToken, {
        fetch,
        createCustomToken: (uid, claims) =>
          firebaseAuth.createCustomToken(uid, claims),
      });
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error("[exchangeKakaoToken] unexpected error", error);
      throw new HttpsError(
        "internal",
        "Kakao Firebase token exchange failed.",
        {message: error instanceof Error ? error.message : String(error)}
      );
    }
  }
);
