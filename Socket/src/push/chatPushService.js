import {
  DEVICES_SUBCOLLECTION,
  MAX_MULTICAST_TOKENS
} from "../config.js";
import {
  chunkArray,
  normalizeUID,
  trimPushText
} from "../utils/strings.js";
import { buildPushPreview } from "../messages/preview.js";

function toMillis(value) {
  if (!value) return 0;
  if (typeof value?.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  return 0;
}

function isInvalidPushTokenCode(code) {
  return code === "messaging/registration-token-not-registered"
    || code === "messaging/invalid-registration-token";
}

function uniqueMemberUIDFromDoc(doc) {
  const data = doc.data() || {};
  const dataUID = normalizeUID(data.userID || "");
  const docUID = normalizeUID(doc.id || "");
  return dataUID || docUID;
}

function buildChatPushMulticast({
  roomID,
  roomName,
  messageID,
  messageType,
  senderUID,
  senderEmail,
  senderNickname,
  preview,
  tokens
}) {
  const safeRoomName = trimPushText(roomName || roomID || "채팅");
  const safeSenderNickname = trimPushText(senderNickname || "새 메시지");
  const safePreview = trimPushText(preview || "새 메시지가 도착했어요");

  return {
    tokens,
    notification: {
      title: safeRoomName,
      body: `${safeSenderNickname}: ${safePreview}`
    },
    data: {
      type: "chat",
      roomID: String(roomID || ""),
      roomName: String(roomName || ""),
      messageID: String(messageID || ""),
      senderUID: String(senderUID || ""),
      senderEmail: String(senderEmail || ""),
      senderNickname: String(senderNickname || ""),
      messageType: String(messageType || "Text"),
      preview: String(safePreview)
    },
    apns: {
      payload: {
        aps: {
          sound: "default"
        }
      }
    }
  };
}

export function createChatPushService({ db, admin }) {
  async function loadDeviceDocsByUserUID(userUID) {
    const normalizedUID = normalizeUID(userUID);
    if (!normalizedUID || normalizedUID.includes("/")) return [];

    const snapshot = await db.collection("users")
      .doc(normalizedUID)
      .collection(DEVICES_SUBCOLLECTION)
      .get();
    return snapshot.docs.map((doc) => ({
      ref: doc.ref,
      ...doc.data()
    }));
  }

  async function cleanupInvalidPushTokens(deviceRefs) {
    if (!deviceRefs.length) return;

    const batch = db.batch();
    for (const deviceRef of deviceRefs) {
      batch.set(deviceRef, {
        fcmToken: admin.firestore.FieldValue.delete(),
        pushEnabled: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastPushTokenInvalidAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
    }
    await batch.commit();
  }

  async function sendChatPushToUser({
    userUID,
    roomID,
    roomName,
    messageID,
    messageType,
    senderUID,
    senderEmail,
    senderNickname,
    preview
  }) {
    const devices = await loadDeviceDocsByUserUID(userUID);
    if (!devices.length) {
      return { sent: 0, skippedReason: "no_devices" };
    }

    const hasForegroundDevice = devices.some((device) =>
      device?.pushEnabled !== false && device?.appState === "foreground"
    );
    if (hasForegroundDevice) {
      return { sent: 0, skippedReason: "foreground_present" };
    }

    const byToken = new Map();
    for (const device of devices) {
      const token = typeof device?.fcmToken === "string" ? device.fcmToken.trim() : "";
      if (!token) continue;
      if (device?.pushEnabled === false) continue;

      const ageMs = Date.now() - toMillis(device?.updatedAt);
      const normalizedState = typeof device?.appState === "string" ? device.appState : "offline";
      const effectiveState = ageMs > 90_000 ? "offline" : normalizedState;
      if (effectiveState === "foreground") continue;

      byToken.set(token, {
        ref: device.ref,
        token
      });
    }

    const targets = [...byToken.values()];
    if (!targets.length) {
      return { sent: 0, skippedReason: "no_push_targets" };
    }

    let sent = 0;
    for (const chunk of chunkArray(targets, MAX_MULTICAST_TOKENS)) {
      const multicast = buildChatPushMulticast({
        roomID,
        roomName,
        messageID,
        messageType,
        senderUID,
        senderEmail,
        senderNickname,
        preview,
        tokens: chunk.map((item) => item.token)
      });

      const response = await admin.messaging().sendEachForMulticast(multicast);
      sent += response.successCount;

      const invalidRefs = response.responses
        .map((result, index) => (
          isInvalidPushTokenCode(result?.error?.code) ? chunk[index].ref : null
        ))
        .filter(Boolean);

      if (invalidRefs.length) {
        await cleanupInvalidPushTokens(invalidRefs);
      }
    }

    return { sent, skippedReason: null };
  }

  async function fanoutChatPush({
    roomID,
    messageData
  }) {
    try {
      const roomSnapshot = await db.collection("Rooms").doc(roomID).get();
      if (!roomSnapshot.exists) return;

      const roomData = roomSnapshot.data() || {};
      const senderUID = normalizeUID(messageData?.senderUID || "");
      const roomName = typeof roomData.roomName === "string" && roomData.roomName.trim()
        ? roomData.roomName.trim()
        : roomID;
      const preview = buildPushPreview(messageData);

      // TODO(chat-push-worker): members pagination removes participantUIDs,
      // but long-term large-room fanout should move to a queue/worker.
      const summary = { recipients: 0, sent: 0, skipped: {} };
      let query = db.collection("Rooms")
        .doc(roomID)
        .collection("members")
        .orderBy("__name__")
        .limit(250);

      while (true) {
        const memberSnapshot = await query.get();
        if (memberSnapshot.empty) break;

        const recipients = [...new Set(
          memberSnapshot.docs
            .map(uniqueMemberUIDFromDoc)
            .filter((uid) => uid && uid !== senderUID)
        )];
        summary.recipients += recipients.length;

        const results = await Promise.all(recipients.map(async (recipientUID) => {
          return sendChatPushToUser({
            userUID: recipientUID,
            roomID,
            roomName,
            messageID: messageData?.ID,
            messageType: messageData?.messageType,
            senderUID: messageData?.senderUID,
            senderEmail: messageData?.senderEmail,
            senderNickname: messageData?.senderNickname,
            preview
          });
        }));

        for (const item of results) {
          summary.sent += item.sent || 0;
          if (item.skippedReason) {
            summary.skipped[item.skippedReason] = (summary.skipped[item.skippedReason] || 0) + 1;
          }
        }

        if (memberSnapshot.size < 250) break;
        query = db.collection("Rooms")
          .doc(roomID)
          .collection("members")
          .orderBy("__name__")
          .startAfter(memberSnapshot.docs[memberSnapshot.docs.length - 1])
          .limit(250);
      }

      if (summary.recipients === 0) return;

      console.log("[push] fanout complete", {
        roomID,
        messageID: messageData?.ID,
        recipients: summary.recipients,
        sent: summary.sent,
        skipped: summary.skipped
      });
    } catch (error) {
      console.error("[push] fanout failed", {
        roomID,
        messageID: messageData?.ID,
        error
      });
    }
  }

  return { fanoutChatPush };
}
