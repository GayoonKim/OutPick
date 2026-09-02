import {defineBoolean} from "firebase-functions/params";
import {HttpsError} from "firebase-functions/v2/https";

export const chatRoomModeratorDelegationEnabled = defineBoolean(
  "CHAT_ROOM_MODERATOR_DELEGATION_ENABLED",
  {
    default: false,
    description: "새 관리자 임명과 관리자를 후임으로 하는 방장 이전을 활성화합니다.",
  },
);

/**
 * 새 관리자 또는 후임 owner를 만드는 mutation의 rollout gate입니다.
 * @param {boolean} enabled 현재 배포 환경의 활성화 값입니다.
 */
export function assertModeratorDelegationCreationEnabled(
  enabled = chatRoomModeratorDelegationEnabled.value(),
): void {
  if (enabled) return;
  throw new HttpsError(
    "failed-precondition",
    "채팅방 관리자 위임 기능이 아직 활성화되지 않았습니다.",
    {errorCode: "FEATURE_NOT_AVAILABLE"},
  );
}
