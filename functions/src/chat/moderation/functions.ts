/* eslint-disable require-jsdoc, max-len */
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {requiredAuthUID} from "../../core/callable.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {assertActivePlatformAdmin} from "../../moderation/admin/service.js";
import {requireRecentAdminAuth} from "../../moderation/admin/contracts.js";
import {assertAccountCapability} from "../../shared/accountStatus.js";
import {
  parseAcknowledgeRoomClosureInput,
  parseCloseOwnedChatRoomInput,
  parseCloseRoomByModerationInput,
  parseDeleteChatMessageInput,
  parseGetMyRoomAccessInput,
  parseListRoomBansInput,
  parseRemoveRoomMemberInput,
  parseUnbanRoomMemberInput,
} from "./contracts.js";
import {
  acknowledgeRoomClosureService,
  closeOwnedChatRoomService,
  closeRoomByModerationService,
  deleteChatMessageService,
} from "./service.js";
import {
  getMyRoomAccessService,
  listRoomBansService,
  removeRoomMemberService,
  unbanRoomMemberService,
} from "./roomBanService.js";

const options = {region: FUNCTIONS_REGION, enforceAppCheck: true};

function callableError(error: unknown, operation: string): never {
  if (error instanceof HttpsError) throw error;
  console.error(`[${operation}] unexpected error`, error);
  throw new HttpsError("internal", "채팅 안전 작업을 처리하지 못했습니다.");
}

export const deleteChatMessage = onCall(options, async (request) => {
  try {
    const uid = requiredAuthUID(request.auth?.uid);
    return await deleteChatMessageService(
      uid,
      request.auth?.token.auth_time,
      parseDeleteChatMessageInput(request.data),
    );
  } catch (error) {
    return callableError(error, "deleteChatMessage");
  }
});

export const closeOwnedChatRoom = onCall(options, async (request) => {
  try {
    const uid = requiredAuthUID(request.auth?.uid);
    return await closeOwnedChatRoomService(uid, parseCloseOwnedChatRoomInput(request.data));
  } catch (error) {
    return callableError(error, "closeOwnedChatRoom");
  }
});

export const closeRoomByModeration = onCall(options, async (request) => {
  try {
    const uid = requiredAuthUID(request.auth?.uid);
    await assertActivePlatformAdmin(uid);
    await assertAccountCapability(uid, "readAppContent");
    requireRecentAdminAuth(request.auth?.token.auth_time, new Date());
    return await closeRoomByModerationService(
      uid,
      parseCloseRoomByModerationInput(request.data),
    );
  } catch (error) {
    return callableError(error, "closeRoomByModeration");
  }
});

export const acknowledgeRoomClosure = onCall(options, async (request) => {
  try {
    const uid = requiredAuthUID(request.auth?.uid);
    return await acknowledgeRoomClosureService(
      uid,
      parseAcknowledgeRoomClosureInput(request.data),
    );
  } catch (error) {
    return callableError(error, "acknowledgeRoomClosure");
  }
});

export const removeRoomMember = onCall(options, async (request) => {
  try {
    const uid = requiredAuthUID(request.auth?.uid);
    return await removeRoomMemberService(uid, parseRemoveRoomMemberInput(request.data));
  } catch (error) {
    return callableError(error, "removeRoomMember");
  }
});

export const unbanRoomMember = onCall(options, async (request) => {
  try {
    const uid = requiredAuthUID(request.auth?.uid);
    return await unbanRoomMemberService(uid, parseUnbanRoomMemberInput(request.data));
  } catch (error) {
    return callableError(error, "unbanRoomMember");
  }
});

export const listRoomBans = onCall(options, async (request) => {
  try {
    const uid = requiredAuthUID(request.auth?.uid);
    return await listRoomBansService(uid, parseListRoomBansInput(request.data));
  } catch (error) {
    return callableError(error, "listRoomBans");
  }
});

export const getMyRoomAccess = onCall(options, async (request) => {
  try {
    const uid = requiredAuthUID(request.auth?.uid);
    return await getMyRoomAccessService(uid, parseGetMyRoomAccessInput(request.data));
  } catch (error) {
    return callableError(error, "getMyRoomAccess");
  }
});
