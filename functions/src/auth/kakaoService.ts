/* eslint-disable require-jsdoc */
import {HttpsError} from "firebase-functions/v2/https";

interface KakaoAccessTokenInfoResponse {
  id?: number;
}

interface KakaoMeResponse {
  id?: number;
  kakao_account?: {email?: string};
}

export type KakaoTokenExchangeDependencies = {
  fetch: typeof fetch;
  createCustomToken: (
    uid: string,
    claims: Record<string, unknown>
  ) => Promise<string>;
};

async function fetchKakaoJSON<T>(
  url: string,
  accessToken: string,
  fetcher: typeof fetch
): Promise<T> {
  const response = await fetcher(url, {
    headers: {Authorization: `Bearer ${accessToken}`},
  });
  if (!response.ok) {
    throw new HttpsError("unauthenticated", "Kakao 토큰 검증에 실패했습니다.");
  }
  return await response.json() as T;
}

export async function exchangeKakaoAccessToken(
  accessToken: string,
  dependencies: KakaoTokenExchangeDependencies
) {
  const tokenInfo = await fetchKakaoJSON<KakaoAccessTokenInfoResponse>(
    "https://kapi.kakao.com/v1/user/access_token_info",
    accessToken,
    dependencies.fetch
  );
  const me = await fetchKakaoJSON<KakaoMeResponse>(
    "https://kapi.kakao.com/v2/user/me",
    accessToken,
    dependencies.fetch
  );

  const kakaoID = me.id ?? tokenInfo.id;
  if (!kakaoID || (tokenInfo.id && tokenInfo.id !== kakaoID)) {
    throw new HttpsError("unauthenticated", "Kakao 사용자 식별에 실패했습니다.");
  }

  const providerUserID = String(kakaoID);
  const identityKey = `kakao:${providerUserID}`;
  const email = me.kakao_account?.email?.trim().toLowerCase() || null;
  const firebaseCustomToken = await dependencies.createCustomToken(
    identityKey,
    {provider: "kakao", providerUserID}
  );

  return {
    firebaseCustomToken,
    identityKey,
    provider: "kakao",
    providerUserID,
    email,
  };
}
