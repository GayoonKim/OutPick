import { RECONNECT_POLICY } from "../config.js";
import {
  createFirebaseAuthMiddleware,
  createReconnectAttemptMiddleware
} from "../auth/socketAuthMiddleware.js";
import { registerConnectionHandlers } from "../handlers/connectionHandlers.js";
import { registerMediaHandlers } from "../handlers/mediaHandlers.js";
import { registerMessageHandlers } from "../handlers/messageHandlers.js";
import { registerRoomHandlers } from "../handlers/roomHandlers.js";
import { createLookbookShareHandler } from "../lookbookShare/lookbookShareHandler.js";
import { createMediaUploadService } from "../media/mediaUploadService.js";
import { createMessageDeliverySingleFlight } from "../messages/messageDeliverySingleFlight.js";
import { createSequenceStore } from "../messages/sequenceStore.js";
import { createChatPushService } from "../push/chatPushService.js";
import { createRoomAccess } from "../rooms/roomAccess.js";
import { createRoomCleanup } from "../rooms/roomCleanup.js";
import { createRoomLifecycleService } from "../rooms/roomLifecycleService.js";
import { createRoomRegistry } from "../rooms/roomRegistry.js";
import { createSocketRoomAuthorizer } from "../rooms/socketRoomAuthorizer.js";
import { isValidRoomID } from "../rooms/roomValidation.js";
import { createMessageIDGenerator } from "../runtime/messageIDGenerator.js";
import { createUserLookup } from "../users/userLookup.js";
import { createRateLimiter } from "../utils/rateLimit.js";

export function createProductionDependencies({
  admin,
  db,
  clock,
  io,
  env = process.env,
  logger = console
}) {
  const generateMessageID = createMessageIDGenerator({ clock });
  const { allowRate } = createRateLimiter({ clock });
  const messageDeliverySingleFlight = createMessageDeliverySingleFlight();
  const mediaUploadService = createMediaUploadService({ db, admin, clock });
  const { findUserByUID } = createUserLookup({ db });
  const { rooms, fetchRoomsFromFirebase, ensureRoomLoaded } = createRoomRegistry({
    db,
    isValidRoomID
  });
  const { loadRoomAccess } = createRoomAccess({ db });
  const { closeRoomImmediately, leaveRoomMembership } = createRoomCleanup({ db, admin });
  const { leaveOrClose } = createRoomLifecycleService({
    db,
    closeRoomImmediately,
    leaveRoomMembership
  });
  const authorizeSocketRoom = createSocketRoomAuthorizer({
    rooms,
    ensureRoomLoaded,
    loadRoomAccess,
    logger
  });
  const { allocateSeqAndPersist } = createSequenceStore({ db, admin });
  const { fanoutChatPush } = createChatPushService({ db, admin, clock });
  const handleLookbookShare = createLookbookShareHandler({
    io,
    rooms,
    isValidRoomID,
    ensureRoomLoaded,
    loadRoomAccess,
    allocateSeqAndPersist,
    messageDeliverySingleFlight,
    fanoutChatPush,
    allowRate,
    clock,
    generateMessageID,
    logger
  });

  const reconnectMiddleware = createReconnectAttemptMiddleware({
    clock,
    reconnectPolicy: RECONNECT_POLICY,
    logger
  });
  const firebaseAuthMiddleware = createFirebaseAuthMiddleware({
    verifyIDToken: (idToken) => admin.auth().verifyIdToken(idToken),
    findUserByUID,
    logger
  });

  function registerSocketHandlers(socket) {
    registerConnectionHandlers({
      socket,
      io,
      rooms,
      clock,
      reconnectPolicy: RECONNECT_POLICY,
      logger
    });
    registerRoomHandlers({
      socket,
      io,
      rooms,
      isValidRoomID,
      ensureRoomLoaded,
      loadRoomAccess,
      leaveOrCloseRoom: leaveOrClose,
      logger
    });
    registerMessageHandlers({
      socket,
      io,
      isValidRoomID,
      authorizeSocketRoom,
      allowRate,
      generateMessageID,
      clock,
      allocateSeqAndPersist,
      messageDeliverySingleFlight,
      fanoutChatPush,
      handleLookbookShare,
      logger
    });
    registerMediaHandlers({
      socket,
      io,
      isValidRoomID,
      authorizeSocketRoom,
      allowRate,
      generateMessageID,
      clock,
      mediaUploadService,
      allocateSeqAndPersist,
      messageDeliverySingleFlight,
      fanoutChatPush,
      imageCdnBase: env.IMAGE_CDN_BASE,
      logger
    });
  }

  return {
    fetchRoomsFromFirebase,
    firebaseAuthMiddleware,
    reconnectMiddleware,
    registerSocketHandlers,
    rooms
  };
}
