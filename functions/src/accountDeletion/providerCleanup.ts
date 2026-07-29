/* eslint-disable require-jsdoc */
import {defineSecret} from "firebase-functions/params";
import {HttpsError} from "firebase-functions/v2/https";

export const kakaoAdminKey = defineSecret("KAKAO_ADMIN_KEY");
export const deletionLedgerHmacKey = defineSecret(
  "ACCOUNT_DELETION_LEDGER_HMAC_KEY",
);

export async function unlinkKakaoAccount(
  providerUserID: string,
  adminKey: string,
  fetcher: typeof fetch = fetch,
): Promise<void> {
  if (!adminKey) {
    throw new HttpsError(
      "failed-precondition",
      "Kakao 연결 해제 secret이 설정되지 않았습니다.",
    );
  }
  const body = new URLSearchParams({
    target_id_type: "user_id",
    target_id: providerUserID,
  });
  const response = await fetcher("https://kapi.kakao.com/v1/user/unlink", {
    method: "POST",
    headers: {
      "Authorization": `KakaoAK ${adminKey}`,
      "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
    },
    body,
  });
  if (!response.ok && response.status !== 400) {
    throw new Error(`kakao_unlink_failed:${response.status}`);
  }
}
