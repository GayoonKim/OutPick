/* eslint-disable max-len */
import * as admin from "firebase-admin";
import {FieldValue} from "firebase-admin/firestore";
import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {db, defaultStorageBucket} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {
  cleanupExpiredMediaUploads,
  didRoomTransitionToClosed,
  type ExpiredMediaUpload,
} from "./cleanupService.js";

const MEDIA_UPLOAD_CLEANUP_LIMIT = 100;

export const onRoomClosed = onDocumentUpdated(
  {document: "Rooms/{roomId}", region: FUNCTIONS_REGION},
  async (event) => {
    const beforeSnap = event.data?.before;
    const afterSnap = event.data?.after;
    if (!beforeSnap || !afterSnap) {
      console.log("[onRoomClosed] No before/after snapshot. Skip.");
      return;
    }

    const before = beforeSnap.data() as {isClosed?: boolean} | undefined;
    const after = afterSnap.data() as {isClosed?: boolean} | undefined;
    if (!before || !after) {
      console.log("[onRoomClosed] Empty data. Skip.");
      return;
    }
    if (!didRoomTransitionToClosed(before, after)) {
      console.log(
        "[onRoomClosed] isClosed did not change from false to true. Skip.",
        {beforeClosed: !!before.isClosed, afterClosed: !!after.isClosed}
      );
      return;
    }
    console.log(
      "[onRoomClosed] Room close cleanup is handled synchronously by the Socket close path. Skip trigger cleanup.",
      {roomId: event.params.roomId}
    );
  }
);

export const cleanupExpiredChatMediaUploads = onSchedule(
  {
    schedule: "0 4 * * *",
    region: FUNCTIONS_REGION,
    timeZone: "Asia/Seoul",
  },
  async () => {
    const snapshot = await db
      .collectionGroup("MediaUploads")
      .where("status", "==", "pending")
      .where("expiresAt", "<=", admin.firestore.Timestamp.now())
      .limit(MEDIA_UPLOAD_CLEANUP_LIMIT)
      .get();
    if (snapshot.empty) {
      console.log("[cleanupExpiredChatMediaUploads] No expired uploads.");
      return;
    }

    const bucket = defaultStorageBucket();
    const refs = new Map<string, FirebaseFirestore.QueryDocumentSnapshot>();
    const uploads = snapshot.docs.map((doc): ExpiredMediaUpload => {
      const data = doc.data();
      const roomID = doc.ref.parent.parent?.id ?? null;
      const messageID = typeof data.messageID === "string" ? data.messageID : doc.id;
      refs.set(`${roomID ?? ""}:${messageID}`, doc);
      return {
        roomID,
        messageID,
        storagePrefix: typeof data.storagePrefix === "string" ? data.storagePrefix : "",
      };
    });
    const refFor = (upload: ExpiredMediaUpload) => {
      const ref = refs.get(`${upload.roomID ?? ""}:${upload.messageID}`);
      if (!ref) throw new Error("Media upload reservation reference is missing.");
      return ref;
    };

    await cleanupExpiredMediaUploads(uploads, {
      messageExists: async (upload) => {
        const roomRef = refFor(upload).ref.parent.parent;
        if (!roomRef) return false;
        return (await roomRef.collection("Messages").doc(upload.messageID).get()).exists;
      },
      deleteReservation: async (upload) => {
        await refFor(upload).ref.delete();
      },
      markCleanupFailed: async (upload, reason) => {
        await refFor(upload).ref.set({
          status: "cleanupFailed",
          lastError: reason,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      },
      deleteStoragePrefix: async (upload) => {
        await bucket.deleteFiles({prefix: `${upload.storagePrefix}/`, force: true});
      },
      logDeleted: (upload) => console.log(
        "[cleanupExpiredChatMediaUploads] Deleted expired media prefix",
        upload
      ),
      logFailure: (upload, error) => console.error(
        "[cleanupExpiredChatMediaUploads] Failed to delete media prefix",
        {...upload, err: error}
      ),
    });
  }
);
