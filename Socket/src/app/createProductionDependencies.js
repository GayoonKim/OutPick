import {
  RATE_BUCKET_IDLE_TTL_MS,
  RATE_BUCKET_SWEEP_INTERVAL_MS,
  RATE_MAX_ACTIVE_BUCKETS,
  RECONNECT_POLICY
} from "../config.js";
import {
  createFirebaseAuthMiddleware,
  createReconnectAttemptMiddleware
} from "../auth/socketAuthMiddleware.js";
import { registerConnectionHandlers } from "../handlers/connectionHandlers.js";
import { registerMediaHandlers } from "../handlers/mediaHandlers.js";
import { registerMessageHandlers } from "../handlers/messageHandlers.js";
import { registerRoomHandlers } from "../handlers/roomHandlers.js";
import { createLookbookShareHandler } from "../lookbookShare/lookbookShareHandler.js";
import { createDeletionDeliveryWatcher } from "../deletion/deletionDeliveryWatcher.js";
import { createMediaUploadService } from "../media/mediaUploadService.js";
import { createMediaDeliveryWatcher } from "../media/mediaDeliveryWatcher.js";
import { createRoleEventDeliveryWatcher } from "../roles/roleEventDeliveryWatcher.js";
import { createMessageDeliverySingleFlight } from "../messages/messageDeliverySingleFlight.js";
import { createSequenceStore } from "../messages/sequenceStore.js";
import { createChatPushService } from "../push/chatPushService.js";
import { createRoomAccess } from "../rooms/roomAccess.js";
import { createRoomBanWatcher } from "../rooms/roomBanWatcher.js";
import { createRoomCleanup } from "../rooms/roomCleanup.js";
import { createRoomClosureWatcher } from "../rooms/roomClosureWatcher.js";
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
  const { allowRate } = createRateLimiter({
    clock,
    idleTTLms: RATE_BUCKET_IDLE_TTL_MS,
    sweepIntervalMs: RATE_BUCKET_SWEEP_INTERVAL_MS,
    maxActiveBuckets: RATE_MAX_ACTIVE_BUCKETS,
    onCapacity: ({ activeBuckets, maxActiveBuckets }) => {
      logger.warn?.("[rate-limit] active bucket capacity reached", {
        activeBuckets,
        maxActiveBuckets
      });
    }
  });
  const messageDeliverySingleFlight = createMessageDeliverySingleFlight();
  const quarantineBucketName = String(env.CHAT_MEDIA_QUARANTINE_BUCKET || "").trim();
  const quarantineBucket = quarantineBucketName
    ? admin.storage().bucket(quarantineBucketName)
    : null;
  const mediaUploadService = createMediaUploadService({
    db,
    admin,
    clock,
    quarantineBucketName,
    loadQuarantineObject: quarantineBucket
      ? async (path) => {
        const [metadata] = await quarantineBucket.file(path).getMetadata();
        return {
          generation: metadata.generation,
          sizeBytes: Number(metadata.size),
          contentType: metadata.contentType,
          metadata: metadata.metadata || {}
        };
      }
      : undefined,
    deleteQuarantineObject: quarantineBucket
      ? async (path) => {
        await quarantineBucket.file(path).delete({ ignoreNotFound: true });
      }
      : undefined,
    createQuarantineSignedUploadTarget: quarantineBucket
      ? async ({
        path,
        attachmentID,
        uploadID,
        contentType,
        sizeBytes,
        sha256,
        expiresAtMillis
      }) => {
        const metadataHeaders = {
          "x-goog-if-generation-match": "0",
          "x-goog-meta-attachment-id": attachmentID,
          "x-goog-meta-upload-id": uploadID,
          "x-goog-meta-declared-size-bytes": String(sizeBytes),
          "x-goog-meta-sha256": sha256,
          "x-goog-meta-contract-version": "2"
        };
        const [signedURL] = await quarantineBucket.file(path).getSignedUrl({
          version: "v4",
          action: "write",
          expires: new Date(expiresAtMillis),
          contentType,
          extensionHeaders: metadataHeaders
        });
        return {
          signedURL,
          requiredHeaders: {
            "content-type": contentType,
            ...metadataHeaders
          }
        };
      }
      : undefined
  });
  const {
    findUserByUID,
    findModerationAccount,
    watchModerationAccount
  } = createUserLookup({ db });
  const { rooms, fetchRoomsFromFirebase, ensureRoomLoaded } = createRoomRegistry({
    db,
    isValidRoomID
  });
  const { loadRoomAccess } = createRoomAccess({ db });
  const { start: startRoomClosureWatcher } = createRoomClosureWatcher({
    db,
    io,
    rooms,
    logger
  });
  const stopRoomClosureWatcher = startRoomClosureWatcher();
  const { start: startRoomBanWatcher } = createRoomBanWatcher({
    db,
    io,
    rooms,
    logger
  });
  const stopRoomBanWatcher = startRoomBanWatcher();
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
  const { start: startMediaDeliveryWatcher } = createMediaDeliveryWatcher({
    db,
    admin,
    io,
    clock,
    fanoutChatPush,
    logger
  });
  const stopMediaDeliveryWatcher = startMediaDeliveryWatcher();
  const { start: startDeletionDeliveryWatcher } = createDeletionDeliveryWatcher({
    db,
    admin,
    io,
    clock,
    logger
  });
  const stopDeletionDeliveryWatcher = startDeletionDeliveryWatcher();
  const { start: startRoleEventDeliveryWatcher } = createRoleEventDeliveryWatcher({
    db,
    admin,
    io,
    clock,
    logger
  });
  const stopRoleEventDeliveryWatcher = startRoleEventDeliveryWatcher();
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
    verifyIDToken: (idToken) => admin.auth().verifyIdToken(idToken, true),
    findUserByUID,
    findModerationAccount,
    logger
  });

  function registerSocketHandlers(socket) {
    registerConnectionHandlers({
      socket,
      io,
      rooms,
      clock,
      reconnectPolicy: RECONNECT_POLICY,
      watchModerationAccount,
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
    rooms,
    stopBackgroundServices() {
      stopRoomClosureWatcher?.();
      stopRoomBanWatcher?.();
      stopMediaDeliveryWatcher?.();
      stopDeletionDeliveryWatcher?.();
      stopRoleEventDeliveryWatcher?.();
    }
  };
}
