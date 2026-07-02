import express from "express";
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Server } from "socket.io";
import {
  MAX_CHAT_MESSAGE_BYTES,
  MAX_IMAGES_PER_MESSAGE,
  MAX_THUMB_PAYLOAD_BYTES,
  PER_ITEM_THUMB_MAX_BYTES,
  PORT,
  RATE_MAX_CHAT,
  RATE_MAX_IMAGES,
  RATE_MAX_VIDEOS,
  RATE_WINDOW_MS,
  RECONNECT_POLICY
} from "./src/config.js";
import { admin, db } from "./src/firebaseAdmin.js";
import { createLookbookShareHandler } from "./src/lookbookShare/lookbookShareHandler.js";
import { createSequenceStore } from "./src/messages/sequenceStore.js";
import { createChatPushService } from "./src/push/chatPushService.js";
import { createRoomAccess } from "./src/rooms/roomAccess.js";
import { createRoomRegistry } from "./src/rooms/roomRegistry.js";
import { createUserLookup } from "./src/users/userLookup.js";
import { allowRate } from "./src/utils/rateLimit.js";
import { normalizeEmail, normalizeUID } from "./src/utils/strings.js";

const app = express();
const server = createServer(app);
const io = new Server(server, {
  maxHttpBufferSize: 2 * 1024 * 1024,           // 최대 2MB까지 허용 (썸네일 버퍼 여유)
  perMessageDeflate: { threshold: 1024 }        // 작은 메시지에는 비활성(이미지엔 효과 제한)
});
let isShuttingDown = false;

// Track connection attempts per client key (auth.clientKey | query.clientKey | remote address)
const connectAttempts = new Map();
function getClientKey(handshake) {
  try {
    return (
      handshake.auth?.clientKey ||
      handshake.headers?.['x-outpick-client-key'] ||
      handshake.query?.clientKey ||
      handshake.address || // e.g., "::ffff:127.0.0.1"
      'unknown'
    );
  } catch {
    return 'unknown';
  }
}

function extractFirebaseIDToken(handshake) {
  const authToken = handshake.auth?.idToken || handshake.auth?.token;
  if (typeof authToken === 'string' && authToken.trim()) {
    return authToken.trim();
  }

  const authorization = handshake.headers?.authorization;
  if (typeof authorization === 'string') {
    const match = authorization.match(/^Bearer\s+(.+)$/i);
    if (match?.[1]) {
      return match[1].trim();
    }
  }

  return '';
}

function emailFromDecodedToken(decodedToken) {
  const directEmail = normalizeEmail(decodedToken?.email);
  if (directEmail) return directEmail;

  const identityEmails = decodedToken?.firebase?.identities?.email;
  if (Array.isArray(identityEmails)) {
    for (const email of identityEmails) {
      const normalized = normalizeEmail(email);
      if (normalized) return normalized;
    }
  }

  return '';
}

// 이미지 메시지 중복 방지 및 용량 가드
const deliveredImageKeys = new Set(); // key: `${roomID}:${clientMessageID}`

// Video meta de-dup & rate
const deliveredVideoKeys = new Set(); // key: `${roomID}:${messageID}`

// If the client does not send per-image URL, server can derive it via env:
//   export IMAGE_CDN_BASE="https://cdn.example.com/images"
// Then withDerivedUrls() will emit both `url` and `originalUrl` based on storagePath/fileName.

function isValidRoomID(roomID) {
  return (typeof roomID === 'string') && /^[A-Za-z0-9_-]{1,64}$/.test(roomID);
}

function sanitizeImageItem(item) {
  if (typeof item === 'string') {
    // URL 문자열만 넘어온 경우
    return { url: item };
  }
  if (item && typeof item === 'object') {
    const {
      url,
      fileName,
      width,
      height,
      size,
      mimeType,
      storagePath,
      thumbUrl,
      thumbData
    } = item;

    // thumbData: Buffer(노드) 또는 base64 문자열(일부 클라이언트)만 허용
    let safeThumb;
    if (thumbData) {
      if (Buffer.isBuffer(thumbData)) {
        if (thumbData.length <= PER_ITEM_THUMB_MAX_BYTES) safeThumb = thumbData;
      } else if (typeof thumbData === 'string') {
        try {
          const buf = Buffer.from(thumbData, 'base64');
          if (buf.length <= PER_ITEM_THUMB_MAX_BYTES) safeThumb = buf;
        } catch {}
      }
    }

    return {
      ...(url ? { url } : {}),
      ...(fileName ? { fileName } : {}),
      ...(typeof width === 'number' ? { width } : {}),
      ...(typeof height === 'number' ? { height } : {}),
      ...(typeof size === 'number' ? { size } : {}),
      ...(mimeType ? { mimeType } : {}),
      ...(storagePath ? { storagePath } : {}),
      ...(thumbUrl ? { thumbUrl } : {}),
      ...(safeThumb ? { thumbData: safeThumb } : {})
    };
  }
  return undefined;
}

function withDerivedUrls(it) {
  // If the client didn't provide a URL, attempt to derive from env base + storagePath/fileName
  const base = process.env.IMAGE_CDN_BASE; // e.g., https://cdn.example.com/images
  let url = it && it.url;
  if (!url && base) {
    if (it && typeof it.storagePath === 'string' && it.storagePath) {
      url = `${base}/${encodeURIComponent(it.storagePath)}`;
    } else if (it && typeof it.fileName === 'string' && it.fileName) {
      url = `${base}/${encodeURIComponent(it.fileName)}`;
    }
  }
  // Provide both `url` and `originalUrl` for wider client compatibility
  return {
    ...it,
    ...(url ? { url, originalUrl: url } : {})
  };
}

// ---- New meta-only attachments helpers ----
function normalizeAttachment(a, i) {
  // Accepts both new keys and a few legacy aliases
  return {
    type: 'image',
    index: Number(a?.index ?? i),
    pathThumb: String(a?.pathThumb ?? a?.thumbPath ?? ''),
    pathOriginal: String(a?.pathOriginal ?? a?.originalPath ?? a?.url ?? a?.originalUrl ?? ''),
    w: Number(a?.w ?? a?.width ?? 0),
    h: Number(a?.h ?? a?.height ?? 0),
    bytesOriginal: Number(a?.bytesOriginal ?? a?.size ?? 0),
    hash: String(a?.hash ?? ''),
    blurhash: a?.blurhash ?? null
  };
}

function validateMetaMessage(body) {
  if (!body) return 'empty_body';
  if (!body.roomID) return 'missing_roomID';
  if (!Array.isArray(body.attachments) || body.attachments.length === 0) return 'attachments_not_array';
  return null;
}

function buildServerImageMessage(body) {
  const {
    roomID,
    messageID,
    type = 'image',
    msg = '',
    attachments = [],
    senderUID = '',
    senderEmail = '',
    senderNickname = '',
    senderAvatarPath = '',
    sentAt
  } = body || {};

  const normalized = attachments.map((a, i) => normalizeAttachment(a, i));

  return {
    ID: messageID,                 // mirror client messageID
    roomID,
    roomName: roomID,
    senderUID,
    ...(senderEmail ? { senderEmail } : {}),
    senderNickname,
    ...(senderAvatarPath ? { senderAvatarPath } : {}),
    msg,
    message: msg,
    sentAt: sentAt || new Date().toISOString(),
    messageType: 'Image',
    attachments: normalized,
    replyPreview: null,
    isFailed: false
  };
}

// ---- Video attachments helpers ----
function normalizeVideoAttachment(a, i) {
  return {
    type: 'video',
    index: Number(a?.index ?? i),
    pathThumb: String(a?.pathThumb ?? a?.thumbnailPath ?? ''),
    pathOriginal: String(a?.pathOriginal ?? a?.storagePath ?? ''),
    w: Number(a?.w ?? a?.width ?? 0),
    h: Number(a?.h ?? a?.height ?? 0),
    bytesOriginal: Number(a?.bytesOriginal ?? a?.sizeBytes ?? 0),
    hash: String(a?.hash ?? ''),
    blurhash: a?.blurhash ?? null,
    ...(typeof a?.duration === 'number' ? { duration: a.duration } : {}),
    ...(typeof a?.approxBitrateMbps === 'number' ? { approxBitrateMbps: a.approxBitrateMbps } : {}),
    ...(typeof a?.preset === 'string' ? { preset: a.preset } : {})
  };
}

function buildServerVideoMessage(body) {
  const {
    roomID,
    messageID,
    msg = '',
    attachments = [],
    senderUID = '',
    senderEmail = '',
    senderNickname = '',
    senderAvatarPath = '',
    sentAt
  } = body || {};

  const normalized = attachments.map((a, i) => normalizeVideoAttachment(a, i));

  return {
    ID: messageID,
    roomID,
    roomName: roomID,
    senderUID,
    ...(senderEmail ? { senderEmail } : {}),
    senderNickname,
    ...(senderAvatarPath ? { senderAvatarPath } : {}),
    msg,
    message: msg,
    sentAt: sentAt || new Date().toISOString(),
    messageType: 'Video',
    attachments: normalized,
    replyPreview: null,
    isFailed: false
  };
}

function enforceThumbBudget(images, budgetBytes) {
  let thumbTrimmed = false;
  let thumbBytes = 0;
  for (const it of images) {
    if (it && it.thumbData && Buffer.isBuffer(it.thumbData)) {
      thumbBytes += it.thumbData.length;
    }
  }
  if (thumbBytes > budgetBytes) {
    let over = thumbBytes - budgetBytes;
    // 뒤에서부터 제거(최근/하위 이미지를 우선적으로 썸네일 제외)
    for (let i = images.length - 1; i >= 0 && over > 0; i--) {
      const it = images[i];
      if (it && it.thumbData && Buffer.isBuffer(it.thumbData)) {
        over -= it.thumbData.length;
        delete it.thumbData;
        thumbTrimmed = true;
      }
    }
  }
  return { images, thumbTrimmed };
}

const __dirname = dirname(fileURLToPath(import.meta.url));

function sendHealthResponse(req, res) {
  res.status(isShuttingDown ? 503 : 200).json({
    ok: !isShuttingDown,
    service: 'outpick-socket',
    uptimeSeconds: Math.round(process.uptime()),
    serverTime: new Date().toISOString()
  });
}

app.get('/readyz', sendHealthResponse);

app.get('/healthz', (req, res) => {
  // Cloud Run/Google Frontend can reserve /healthz on public URLs.
  // Keep this for local compatibility and use /readyz for external checks.
  sendHealthResponse(req, res);
});

app.get('/', (req, res) => {
  res.status(200).json({
    service: 'outpick-socket',
    health: '/readyz'
  });
});

const {
  findUserByUID
} = createUserLookup({ db });

const {
  rooms,
  fetchRoomsFromFirebase,
  ensureRoomLoaded
} = createRoomRegistry({ db, isValidRoomID });

const { loadRoomAccess } = createRoomAccess({ db });
const { allocateSeqAndPersist } = createSequenceStore({ db, admin });
const { fanoutChatPush } = createChatPushService({
  db,
  admin
});

const handleLookbookShare = createLookbookShareHandler({
  io,
  rooms,
  isValidRoomID,
  ensureRoomLoaded,
  loadRoomAccess,
  allocateSeqAndPersist,
  fanoutChatPush,
  allowRate
});

const MEDIA_UPLOAD_RESERVATION_TTL_MS = 24 * 60 * 60 * 1000;

function mediaUploadStoragePrefix(roomID, messageID) {
  return `rooms/${roomID}/messages/${messageID}`;
}

function mediaUploadRef(roomID, messageID) {
  return db
    .collection("Rooms")
    .doc(roomID)
    .collection("MediaUploads")
    .doc(messageID);
}

function messageRef(roomID, messageID) {
  return db
    .collection("Rooms")
    .doc(roomID)
    .collection("Messages")
    .doc(messageID);
}

function normalizeMediaKind(kind) {
  if (kind === "image" || kind === "images") return "images";
  if (kind === "video") return "video";
  return "";
}

function reservationExpiresAt() {
  return admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + MEDIA_UPLOAD_RESERVATION_TTL_MS)
  );
}

function timestampMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return null;
}

function validateMediaUploadContract(kind, attachmentCount, expectedPathCount) {
  const count = Number(attachmentCount);
  const pathCount = Number(expectedPathCount);
  if (!Number.isInteger(count) || !Number.isInteger(pathCount)) {
    return { ok: false, error: "invalid_attachment_count" };
  }
  if (kind === "images") {
    if (count < 1 || count > MAX_IMAGES_PER_MESSAGE) {
      return { ok: false, error: "invalid_attachment_count" };
    }
    if (pathCount !== count * 2) {
      return { ok: false, error: "invalid_expected_path_count" };
    }
    return { ok: true, attachmentCount: count, expectedPathCount: pathCount };
  }
  if (kind === "video") {
    if (count !== 1) {
      return { ok: false, error: "invalid_attachment_count" };
    }
    if (pathCount !== 2) {
      return { ok: false, error: "invalid_expected_path_count" };
    }
    return { ok: true, attachmentCount: count, expectedPathCount: pathCount };
  }
  return { ok: false, error: "invalid_media_kind" };
}

async function loadExistingMessage(roomID, messageID) {
  const snap = await messageRef(roomID, messageID).get();
  if (!snap.exists) return null;
  return snap.data() || {};
}

async function assertMediaUploadReservation({
  roomID,
  messageID,
  senderUID,
  kind,
  attachmentCount,
  expectedPathCount,
  storagePaths
}) {
  const ref = mediaUploadRef(roomID, messageID);
  const snap = await ref.get();
  if (!snap.exists) {
    return { ok: false, error: "media_reservation_not_found" };
  }

  const data = snap.data() || {};
  if (data.status !== "pending") {
    return { ok: false, error: "media_reservation_not_pending" };
  }
  if (normalizeUID(data.senderUID) !== normalizeUID(senderUID)) {
    return { ok: false, error: "media_reservation_sender_mismatch" };
  }
  if (data.kind !== kind) {
    return { ok: false, error: "media_reservation_kind_mismatch" };
  }
  if (Number(data.attachmentCount) !== attachmentCount) {
    return { ok: false, error: "media_reservation_attachment_count_mismatch" };
  }
  if (Number(data.expectedPathCount) !== expectedPathCount) {
    return { ok: false, error: "media_reservation_path_count_mismatch" };
  }

  const expiresAtMillis = timestampMillis(data.expiresAt);
  if (expiresAtMillis && expiresAtMillis <= Date.now()) {
    return { ok: false, error: "media_reservation_expired" };
  }

  const prefix = String(data.storagePrefix || "");
  if (!prefix) {
    return { ok: false, error: "media_reservation_missing_prefix" };
  }
  const actualStoragePaths = storagePaths.filter(Boolean).map(String);
  if (actualStoragePaths.length !== expectedPathCount) {
    return { ok: false, error: "media_reservation_path_count_mismatch" };
  }
  const allPathsMatch = actualStoragePaths
    .every((path) => String(path).startsWith(`${prefix}/`));
  if (!allPathsMatch) {
    return { ok: false, error: "media_reservation_prefix_mismatch" };
  }

  return { ok: true, ref, data };
}

async function stageRoomMembershipCleanup(batch, roomID, userUID) {
  const normalizedUID = normalizeUID(userUID);
  if (!normalizedUID || normalizedUID.includes("/")) return false;

  const userRef = db.collection("users").doc(normalizedUID);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    console.warn("[room-membership] user doc not found", { roomID, userUID: normalizedUID });
    return false;
  }

  batch.set(userRef, {
    joinedRooms: admin.firestore.FieldValue.arrayRemove(roomID),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });
  batch.delete(userRef.collection("roomStates").doc(roomID));
  return true;
}

// Allow up to maxAttempts handshake tries within a moving window; otherwise reject with a descriptive error
io.use((socket, next) => {
  const key = getClientKey(socket.handshake);
  const now = Date.now();
  const rec = connectAttempts.get(key) || { times: [] };

  // drop stale attempts
  rec.times = rec.times.filter(t => now - t <= RECONNECT_POLICY.windowMs);
  rec.times.push(now);
  connectAttempts.set(key, rec);

  if (rec.times.length > RECONNECT_POLICY.maxAttempts) {
    const err = new Error('max_connect_attempts_exceeded');
    err.data = {
      message: '연결 시도 횟수를 초과했습니다. 잠시 후 다시 시도하세요.',
      maxAttempts: RECONNECT_POLICY.maxAttempts,
      retryAfterMs: Math.min(RECONNECT_POLICY.maxDelayMs, RECONNECT_POLICY.baseDelayMs * 16)
    };
    return next(err); // client will receive 'connect_error' with err.message & err.data
  }
  return next();
});

io.use(async (socket, next) => {
  const idToken = extractFirebaseIDToken(socket.handshake);
  if (!idToken) {
    console.warn('[auth] missing Firebase ID Token', {
      clientKey: getClientKey(socket.handshake)
    });
    const err = new Error('unauthenticated');
    err.data = { message: 'Firebase ID Token이 필요합니다.', error: 'missing_id_token' };
    return next(err);
  }

  try {
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    const userUID = typeof decodedToken.uid === 'string' ? decodedToken.uid.trim() : '';
    if (!userUID) {
      console.warn('[auth] verified token without uid', {
        clientKey: getClientKey(socket.handshake)
      });
      const err = new Error('unauthenticated');
      err.data = { message: 'Firebase ID Token에 uid가 없습니다.', error: 'missing_token_uid' };
      return next(err);
    }

    const tokenEmail = emailFromDecodedToken(decodedToken);
    const userProfile = await findUserByUID(userUID);
    const profileEmail = normalizeEmail(userProfile?.data?.email);
    const userEmail = profileEmail || tokenEmail || '';

    socket.userUID = userUID;
    socket.userDocumentID = userProfile?.ref?.id || userUID;
    socket.userEmail = userEmail;
    socket.userEmailSource = profileEmail ? 'profile' : 'token';
    return next();
  } catch (error) {
    console.warn('[auth] Firebase ID Token verification failed', {
      code: error?.code,
      message: error?.message
    });
    const err = new Error('unauthenticated');
    err.data = { message: 'Firebase ID Token 검증에 실패했습니다.', error: 'invalid_id_token' };
    return next(err);
  }
});

io.on('connection', (socket) => {
    console.log('User connected:', socket.userUID);

    // Advertise server reconnect policy & perform a lightweight hello/ack
    socket.emit('server:connect:ready', {
      policy: RECONNECT_POLICY,
      serverTime: Date.now(),
      socketId: socket.id
    });

    socket.on('client:hello', (payload = {}, cb) => {
      const attempt = Number(payload.attempt ?? 0);
      const key = getClientKey(socket.handshake);
      const now = Date.now();
      cb && cb({
        ok: true,
        attempt,
        policy: RECONNECT_POLICY,
        serverTime: now,
        key
      });
    });

    // Optional ping/pong for client health checks
    socket.on('client:ping', (cb) => {
      cb && cb({ pong: true, serverTime: Date.now() });
    });

    // 새 클라이언트 연결 시 방 목록 전송
    socket.emit("room list", Object.keys(rooms));

    // 사용자 ID 설정
    socket.on('set username', (username) => {
        socket.username = username || "Anonymous";
        console.log(`Username set: ${socket.username}`);
        socket.emit("username set", socket.username)
    });

    // 새 방 만들기
    socket.on('create room', (roomID, callback) => {
        if (!roomID || !isValidRoomID(roomID)) {
            callback && callback({ ok: false, message: 'invalid_room_id' });
            return;
        }

        if (!rooms[roomID]) {
            rooms[roomID] = [];
            console.log(`Room created: ${roomID}`);
        }

        socket.join(roomID);
        if (!rooms[roomID].includes(socket.username || "Anonymous")) {
          rooms[roomID].push(socket.username || "Anonymous");
        }

        callback && callback({ ok: true, roomID });
    });

    // 방 참여
    socket.on('join room', async (roomID, callback) => {
        const username = socket.username || "Anonymous";
        console.log(`Join request: ${username} → ${roomID}`);

        if (!roomID || !isValidRoomID(roomID)) {
            callback && callback({ ok: false, message: 'invalid_room_id' });
            return;
        }

        const roomExists = await ensureRoomLoaded(roomID);

        if (roomExists) {
            const access = await loadRoomAccess(roomID, socket.userUID);
            if (!access.ok) {
              callback && callback({ ok: false, message: access.error, error: access.error });
              return;
            }
            socket.join(roomID);
            if (!rooms[roomID].includes(username)) {
              rooms[roomID].push(username);
            }
            console.log(`${username} joined room: ${roomID}`);
//            io.to(roomID).emit("user list", rooms[roomID]); // 해당 방 사용자 목록 전송
            socket.emit("joined room", roomID); // 클라이언트에 성공 알림
            callback && callback({ ok: true, roomID });
        } else {
            console.warn(`Join failed: ${username} → ${roomID} (room does not exist)`);
            socket.emit("error", `Room ${roomID} does not exist`);
            callback && callback({ ok: false, message: 'room_not_found' });
        }
    });

    socket.on('leave room', (roomID, callback) => {
      if (!roomID || !isValidRoomID(roomID)) {
        callback && callback({ ok: false, message: 'invalid_room_id' });
        return;
      }

      socket.leave(roomID);

      if (rooms[roomID]) {
        rooms[roomID] = rooms[roomID].filter((name) => name !== socket.username);
        io.to(roomID).emit('user list', rooms[roomID]);
      }

      console.log(`Leave room request: ${socket.username || "Anonymous"} → ${roomID}`);
      callback && callback({ ok: true, roomID });
    });

    // 방 나가기 / 방 종료 (서버가 Firestore 상태로 판단)
    // 클라는 roomID + intent만 보냄: { roomID, intent: "leave-or-close" }
    socket.on('room:leave-or-close', async (payload = {}, callback) => {
      const { roomID } = payload || {};
      const userUID = normalizeUID(socket.userUID);

      console.log('[room:leave-or-close] requested', { roomID, userUID });

      // --- 기본 검증 ---
      if (!roomID || !isValidRoomID(roomID)) {
        console.warn('[room:leave-or-close] invalid roomID', roomID);
        callback && callback({ ok: false, error: 'invalid_room_id' });
        return;
      }

      if (!userUID) {
        console.warn('[room:leave-or-close] missing userUID on socket');
        callback && callback({ ok: false, error: 'unauthenticated' });
        return;
      }

      try {
        const roomRef = db.collection('Rooms').doc(roomID);
        const snap = await roomRef.get();

        if (!snap.exists) {
          console.warn('[room:leave-or-close] room not found in Firestore', roomID);
          callback && callback({ ok: false, error: 'room_not_found' });
          return;
        }

        const roomData = snap.data() || {};
        const participantUIDs = Array.isArray(roomData.participantUIDs)
          ? [...new Set(roomData.participantUIDs.map(normalizeUID).filter(Boolean))]
          : [];
        if (userUID && !participantUIDs.includes(userUID)) {
          participantUIDs.push(userUID);
        }

        const creatorUID = typeof roomData.creatorUID === 'string'
          ? normalizeUID(roomData.creatorUID)
          : null;
        const isOwner = !!creatorUID && creatorUID === userUID;

        // =========================
        // 1) 방장인 경우 → 방 종료
        // =========================
        if (isOwner) {
          console.log('[room:leave-or-close] owner closing room', { roomID, creatorUID });

          const cleanupBatch = db.batch();
          cleanupBatch.set(roomRef, {
            isClosed: true,
            closedAt: admin.firestore.FieldValue.serverTimestamp(),
            closedByUID: userUID,
            participantUIDs: []
          }, { merge: true });

          for (const participantUID of participantUIDs) {
            await stageRoomMembershipCleanup(
              cleanupBatch,
              roomID,
              participantUID
            );
          }

          await cleanupBatch.commit();

          // 클라이언트들에게 "room closed" 알림
          io.to(roomID).emit('room:closed', {
            roomID,
            closedByUID: userUID
          });

          // 서버 메모리 rooms 캐시 정리
          if (rooms[roomID]) {
            delete rooms[roomID];
          }

          // 방에 참여 중인 소켓들을 모두 방에서 제거
          const roomSet = io.sockets.adapter.rooms.get(roomID);
          if (roomSet) {
            for (const sid of roomSet) {
              const s = io.sockets.sockets.get(sid);
              if (s) s.leave(roomID);
            }
          }

          callback && callback({ ok: true, mode: 'closed' });
          return;
        }

        // =========================
        // 2) 일반 참여자인 경우 → 방 나가기
        // =========================
        console.log('[room:leave-or-close] participant leaving room', { roomID, userUID });

        const cleanupBatch = db.batch();
        cleanupBatch.set(roomRef, {
          participantUIDs: admin.firestore.FieldValue.arrayRemove(userUID)
        }, { merge: true });
        await stageRoomMembershipCleanup(cleanupBatch, roomID, userUID);
        await cleanupBatch.commit();

        // Socket.IO 방 탈퇴
        socket.leave(roomID);

        // 서버 메모리 사용자 목록 갱신
        if (rooms[roomID]) {
          rooms[roomID] = rooms[roomID].filter((name) => name !== socket.username);
          io.to(roomID).emit('user list', rooms[roomID]);
        }

        callback && callback({ ok: true, mode: 'left' });
      } catch (err) {
        console.error('[room:leave-or-close] internal error', err);
        callback && callback({ ok: false, error: 'internal_error' });
      }
    });

    // 방에 메시지 전송 (ChatMessage 스키마 기반)
    socket.on("chat message", async (data, callback) => {  // ✅ callback 유지 (ACK)
      try {
        const {
          ID,
          roomID: rawRoomID,
          roomName,
          msg: rawMsg,
          message,
          senderNickname,
          senderNickName,
          senderAvatarPath,   // 새 필드 지원
          replyPreview,
          sentAt
        } = data || {};

        const roomID = rawRoomID || roomName;
        const msg = typeof rawMsg === 'string' ? rawMsg : (typeof message === 'string' ? message : '');
        const nickname = senderNickname || senderNickName || '';
        const senderUID = normalizeUID(socket.userUID);
        const senderEmail = normalizeEmail(socket.userEmail);

        // ===== 기본 검증 =====
        if (!roomID || typeof msg !== 'string' || msg.trim().length === 0) {
          console.error("[Chat] Invalid data received:", data);
          callback && callback({ ok: false, message: "Invalid data", error: "invalid_data" });
          return;
        }
        if (!isValidRoomID(roomID)) {
          console.warn(`[Chat] invalid roomID: ${roomID}`);
          callback && callback({ ok: false, message: "invalid_room_id", error: "invalid_room_id" });
          return;
        }
        if (!rooms[roomID]) {
          console.warn(`[Chat] room not found: ${roomID}`);
          callback && callback({ ok: false, message: "room_not_found", error: "room_not_found" });
          return;
        }
        if (!socket.rooms.has(roomID)) {
          console.warn(`[Chat] socket not joined to room: ${roomID}`);
          callback && callback({ ok: false, message: "not_joined", error: "not_joined" });
          return;
        }
        const roomAccess = await loadRoomAccess(roomID, senderUID);
        if (!roomAccess.ok) {
          callback && callback({ ok: false, message: roomAccess.error, error: roomAccess.error });
          return;
        }
        const msgBytes = Buffer.byteLength(msg, "utf8");
        if (msgBytes > MAX_CHAT_MESSAGE_BYTES) {
          console.warn(`[Chat] message too long: ${msgBytes} bytes`);
          callback && callback({ ok: false, message: "message_too_long", error: "message_too_long" });
          return;
        }
        const chatRateKey = `${socket.id}:${roomID}:chat`;
        if (!allowRate(chatRateKey, RATE_MAX_CHAT, RATE_WINDOW_MS)) {
          console.warn(`[Chat] rate limited: ${socket.id} @ ${roomID}`);
          callback && callback({ ok: false, message: "rate_limited", error: "rate_limited" });
          return;
        }

        // ===== sentAt 정규화 (ISO8601) =====
        const sentAtISO = (() => {
          if (!sentAt) return undefined;
          try {
            if (typeof sentAt === 'string') return new Date(sentAt).toISOString();
            if (typeof sentAt === 'number') return new Date(sentAt > 3e9 ? sentAt : sentAt * 1000).toISOString();
          } catch {}
          return undefined;
        })();

        // ===== replyPreview 정규화(확장 스키마) =====
        let normalizedReplyPreview;
        if (replyPreview && typeof replyPreview === 'object') {
          const mid = String(replyPreview.messageID || '');
          if (mid) {
            const rpSentAtISO = (() => {
              const v = replyPreview.sentAt;
              if (!v) return undefined;
              try {
                if (typeof v === 'string') return new Date(v).toISOString();
                if (typeof v === 'number') return new Date(v > 3e9 ? v : v * 1000).toISOString();
              } catch {}
              return undefined;
            })();
            normalizedReplyPreview = {
              messageID: mid,
              sender: String(replyPreview.sender || ''),
              text: String(replyPreview.text || ''),
              imagesCount: Number(replyPreview.imagesCount ?? replyPreview.images ?? 0),
              videosCount: Number(replyPreview.videosCount ?? replyPreview.videos ?? 0),
              ...(replyPreview.firstThumbPath ? { firstThumbPath: String(replyPreview.firstThumbPath) } : {}),
              ...(replyPreview.senderAvatarPath ? { senderAvatarPath: String(replyPreview.senderAvatarPath) } : {}),
              ...(rpSentAtISO ? { sentAt: rpSentAtISO } : {}),
              isDeleted: Boolean(replyPreview.isDeleted)
            };
          }
        }

        // ===== 서버 전송 페이로드 =====
        const payload = {
          ID,
          roomID,
          roomName: roomID,
          senderUID,
          ...(senderEmail ? { senderEmail } : {}),
          senderNickname: nickname,
          ...(senderAvatarPath ? { senderAvatarPath } : {}),
          msg,
          message: msg,
          messageType: 'Text',
          ...(normalizedReplyPreview ? { replyPreview: normalizedReplyPreview } : {}),
          ...(sentAtISO ? { sentAt: sentAtISO } : {})
        };

        // ===== 서버 권위 seq 할당 + 영속화(Firestore 트랜잭션) =====
        const messageID = String(ID || `${Date.now()}-${Math.random().toString(16).slice(2)}`);
        const messageDoc = {
          ...payload,
          ID: messageID,
          // 메시지 문서 기본 필드 보강
          isFailed: false,
          isDeleted: false,
          sentAt: sentAtISO || new Date().toISOString(),
          attachments: [] // 일반 텍스트는 첨부 없음(일관성 유지용)
        };

        let seq = 0;
        try {
          seq = await allocateSeqAndPersist(roomID, messageID, messageDoc);
        } catch (e) {
          console.error('[Chat] seq allocation/persist error:', e);
          callback && callback({ ok: false, message: 'seq_persist_error', error: 'seq_persist_error' });
          return;
        }

        const serverMsg = { ...messageDoc, seq };

        // ===== 방으로 브로드캐스트 =====
        io.to(roomID).emit("chat message", serverMsg);
//        io.to(roomID).emit(`chat message:${roomID}`, serverMsg);
        void fanoutChatPush({
          roomID,
          messageData: serverMsg
        });

        console.log(`[Chat][${roomID}] ${nickname || "Anonymous"}: ${msg}`, serverMsg);
        callback && callback({ ok: true, success: true, seq, messageID });
      } catch (error) {
        console.error("[Chat] Error processing message:", error);
        callback && callback({ ok: false, message: error.message, error: error.message });
      }
    });

    // 룩북 브랜드/시즌/포스트 공유 메시지 전송
    socket.on("chat:lookbookShare", async (data, callback) => {
      return handleLookbookShare(socket, data, callback);
    });

    socket.on('chat:mediaPreflight', async (data, callback) => {
      try {
        const {
          roomID,
          messageID,
          kind,
          attachmentCount,
          expectedPathCount
        } = data || {};

        if (!roomID || !isValidRoomID(String(roomID))) {
          return callback && callback({ ok: false, error: 'invalid_room_id' });
        }
        if (!messageID || String(messageID).includes('/')) {
          return callback && callback({ ok: false, error: 'invalid_message_id' });
        }
        if (!socket.rooms.has(roomID)) {
          return callback && callback({ ok: false, error: 'not_joined' });
        }

        const mediaKind = normalizeMediaKind(kind);
        if (!mediaKind) {
          return callback && callback({ ok: false, error: 'invalid_media_kind' });
        }
        const contract = validateMediaUploadContract(mediaKind, attachmentCount, expectedPathCount);
        if (!contract.ok) {
          return callback && callback({ ok: false, error: contract.error });
        }

        const senderUID = normalizeUID(socket.userUID);
        const senderEmail = normalizeEmail(socket.userEmail);
        const access = await loadRoomAccess(roomID, senderUID);
        if (!access.ok) {
          return callback && callback({ ok: false, error: access.error });
        }

        const rateKey = `${socket.id}:${roomID}:mediaPreflight:${mediaKind}`;
        const rateMax = mediaKind === "video" ? RATE_MAX_VIDEOS : RATE_MAX_IMAGES;
        if (!allowRate(rateKey, rateMax, RATE_WINDOW_MS)) {
          return callback && callback({ ok: false, error: 'rate_limited' });
        }

        const ref = mediaUploadRef(roomID, String(messageID));
        const existing = await ref.get();
        const storagePrefix = mediaUploadStoragePrefix(roomID, String(messageID));
        const now = admin.firestore.FieldValue.serverTimestamp();
        const expiresAt = reservationExpiresAt();

        const existingMessage = await loadExistingMessage(roomID, String(messageID));
        if (existingMessage) {
          return callback && callback({
            ok: true,
            duplicate: true,
            messageID: String(messageID),
            storagePrefix
          });
        }

        if (existing.exists) {
          const reservation = existing.data() || {};
          if (
            reservation.status === "pending" &&
            normalizeUID(reservation.senderUID) === senderUID &&
            reservation.kind === mediaKind &&
            Number(reservation.attachmentCount) === contract.attachmentCount &&
            Number(reservation.expectedPathCount) === contract.expectedPathCount
          ) {
            await ref.set({
              expiresAt,
              updatedAt: now
            }, { merge: true });
            return callback && callback({
              ok: true,
              duplicate: true,
              status: "pending",
              messageID: String(messageID),
              storagePrefix: reservation.storagePrefix || storagePrefix,
              attachmentCount: contract.attachmentCount,
              expectedPathCount: contract.expectedPathCount
            });
          }
          return callback && callback({ ok: false, error: "media_reservation_conflict" });
        }

        await ref.set({
          roomID,
          messageID: String(messageID),
          senderUID,
          ...(senderEmail ? { senderEmail } : {}),
          kind: mediaKind,
          status: "pending",
          storagePrefix,
          attachmentCount: contract.attachmentCount,
          expectedPathCount: contract.expectedPathCount,
          createdAt: now,
          updatedAt: now,
          expiresAt
        });

        return callback && callback({
          ok: true,
          status: "pending",
          messageID: String(messageID),
          storagePrefix,
          attachmentCount: contract.attachmentCount,
          expectedPathCount: contract.expectedPathCount
        });
      } catch (error) {
        console.error('[chat:mediaPreflight] handler error:', error);
        return callback && callback({ ok: false, error: 'internal_error' });
      }
    });

    async function handleMediaFinalize(data, callback, forcedKind) {
      const mediaKind = normalizeMediaKind(forcedKind || data?.kind || data?.mediaKind || data?.type);

      if (mediaKind === "images") {
        try {
          const {
            roomID,
            messageID,
            clientMessageID,
            attachments,
            images,
            senderNickname,
            senderNickName,
            senderAvatarPath,
            sentAt,
            type,
            msg
          } = data || {};

          if (!roomID) return callback && callback({ ok: false, error: 'invalid_room_id' });
          if (!rooms[roomID]) return callback && callback({ ok: false, error: 'room_not_found' });
          if (!socket.rooms.has(roomID)) return callback && callback({ ok: false, error: 'not_joined' });
          const imageSenderUID = normalizeUID(socket.userUID);
          const imageSenderEmail = normalizeEmail(socket.userEmail);
          const roomAccess = await loadRoomAccess(roomID, imageSenderUID);
          if (!roomAccess.ok) {
            return callback && callback({ ok: false, error: roomAccess.error });
          }

          const incoming = Array.isArray(attachments)
            ? attachments
            : (Array.isArray(images) ? images : []);

          if (incoming.length === 0) {
            return callback && callback({ ok: false, error: 'no_images' });
          }
          if (incoming.length > MAX_IMAGES_PER_MESSAGE) {
            return callback && callback({ ok: false, error: 'invalid_attachment_count' });
          }

          const imgRateKey = `${socket.id}:${roomID}:images`;
          if (!allowRate(imgRateKey, RATE_MAX_IMAGES, RATE_WINDOW_MS)) {
            return callback && callback({ ok: false, error: 'rate_limited' });
          }

          let effectiveMessageID = (messageID && String(messageID))
            || (clientMessageID && String(clientMessageID))
            || `${Date.now()}-${Math.random().toString(16).slice(2)}`;

          const dedupKey = `${roomID}:${effectiveMessageID}`;
          if (deliveredImageKeys.has(dedupKey)) {
            const existing = await loadExistingMessage(roomID, effectiveMessageID);
            if (existing) {
              return callback && callback({
                ok: true,
                duplicate: true,
                messageID: effectiveMessageID,
                seq: existing.seq
              });
            }
          }
          deliveredImageKeys.add(dedupKey);
          if (deliveredImageKeys.size > 50000) deliveredImageKeys.clear();

          const prepared = (Array.isArray(attachments) ? incoming : incoming.map(sanitizeImageItem).map(withDerivedUrls));
          const { images: budgeted, thumbTrimmed } = enforceThumbBudget(prepared, MAX_THUMB_PAYLOAD_BYTES);

          const normalized = budgeted.map((it, i) => normalizeAttachment({
            index: it.index ?? i,
            pathThumb: it.pathThumb ?? it.thumbUrl ?? it.thumbURL,
            pathOriginal: it.pathOriginal ?? it.originalUrl ?? it.originalURL ?? it.storagePath ?? it.url,
            w: it.w ?? it.width,
            h: it.h ?? it.height,
            bytesOriginal: it.bytesOriginal ?? it.size,
            hash: it.hash,
            blurhash: it.blurhash
          }, i)).filter(att => att.pathThumb || att.pathOriginal);

          if (normalized.length === 0) {
            deliveredImageKeys.delete(dedupKey);
            return callback && callback({ ok: false, error: 'no_valid_attachments' });
          }

          const existingMessage = await loadExistingMessage(roomID, effectiveMessageID);
          if (existingMessage) {
            return callback && callback({
              ok: true,
              duplicate: true,
              messageID: effectiveMessageID,
              seq: existingMessage.seq
            });
          }

          const storagePaths = normalized.flatMap((attachment) => [
            attachment.pathThumb,
            attachment.pathOriginal
          ]);
          const actualPathCount = storagePaths.filter(Boolean).length;
          const contract = validateMediaUploadContract("images", normalized.length, actualPathCount);
          if (!contract.ok) {
            deliveredImageKeys.delete(dedupKey);
            return callback && callback({ ok: false, error: contract.error });
          }

          const reservation = await assertMediaUploadReservation({
            roomID,
            messageID: effectiveMessageID,
            senderUID: imageSenderUID,
            kind: "images",
            attachmentCount: contract.attachmentCount,
            expectedPathCount: contract.expectedPathCount,
            storagePaths
          });
          if (!reservation.ok) {
            deliveredImageKeys.delete(dedupKey);
            return callback && callback({ ok: false, error: reservation.error });
          }

          const nickname = senderNickname || senderNickName || '';
          const finalType = type || 'image';
          const finalMsg = typeof msg === 'string' ? msg : '';
          const when = (() => {
            try {
              if (!sentAt) return new Date();
              if (typeof sentAt === 'string') return new Date(sentAt);
              if (typeof sentAt === 'number') return new Date(sentAt > 3e9 ? sentAt : sentAt * 1000);
              return new Date();
            } catch (_) {
              return new Date();
            }
          })();

          const serverMsg = buildServerImageMessage({
            roomID,
            messageID: effectiveMessageID,
            type: finalType,
            msg: finalMsg,
            attachments: normalized,
            senderUID: imageSenderUID,
            senderEmail: imageSenderEmail,
            senderNickname: nickname,
            senderAvatarPath,
            sentAt: when.toISOString()
          });

          try {
            const seq = await allocateSeqAndPersist(roomID, effectiveMessageID, serverMsg, {
              mediaUploadRef: reservation.ref
            });
            serverMsg.seq = seq;
          } catch (e) {
            deliveredImageKeys.delete(dedupKey);
            console.error('[chat:mediaFinalize/images] seq allocation/persist error:', e);
            return callback && callback({ ok: false, error: 'seq_persist_error' });
          }

          console.log(`[Chat][${roomID}] ${senderNickname || "Anonymous"}: ${msg}`, serverMsg);
          io.to(roomID).emit(`receiveImages`, serverMsg);
          void fanoutChatPush({
            roomID,
            messageData: serverMsg
          });
          return callback && callback({ ok: true, messageID: effectiveMessageID, thumbTrimmed });
        } catch (error) {
          console.error('[chat:mediaFinalize/images] handler error:', error);
          return callback && callback({ ok: false, error: 'internal_error' });
        }
      }

      if (mediaKind === "video") {
        try {
          const {
            roomID,
            messageID,
            storagePath,
            thumbnailPath,
            duration,
            width,
            height,
            sizeBytes,
            approxBitrateMbps,
            preset,
            senderNickname,
            senderNickName,
            senderAvatarPath,
            sentAt,
            msg
          } = data || {};

          if (!roomID) return callback && callback({ ok: false, error: 'invalid_room_id' });
          if (!rooms[roomID]) return callback && callback({ ok: false, error: 'room_not_found' });
          if (!socket.rooms.has(roomID)) return callback && callback({ ok: false, error: 'not_joined' });
          const videoSenderUID = normalizeUID(socket.userUID);
          const videoSenderEmail = normalizeEmail(socket.userEmail);
          const roomAccess = await loadRoomAccess(roomID, videoSenderUID);
          if (!roomAccess.ok) {
            return callback && callback({ ok: false, error: roomAccess.error });
          }

          const vidRateKey = `${socket.id}:${roomID}:video`;
          if (!allowRate(vidRateKey, RATE_MAX_VIDEOS, RATE_WINDOW_MS)) {
            return callback && callback({ ok: false, error: 'rate_limited' });
          }

          const effectiveMessageID = (messageID && String(messageID)) || `${Date.now()}-${Math.random().toString(16).slice(2)}`;
          const dedupKey = `${roomID}:${effectiveMessageID}`;
          if (deliveredVideoKeys.has(dedupKey)) {
            const existing = await loadExistingMessage(roomID, effectiveMessageID);
            if (existing) {
              return callback && callback({
                ok: true,
                duplicate: true,
                messageID: effectiveMessageID,
                seq: existing.seq
              });
            }
          }
          deliveredVideoKeys.add(dedupKey);
          if (deliveredVideoKeys.size > 50000) deliveredVideoKeys.clear();

          const nickname = senderNickname || senderNickName || '';
          const attachment = {
            pathOriginal: storagePath,
            pathThumb: thumbnailPath,
            width,
            height,
            sizeBytes,
            duration,
            approxBitrateMbps,
            preset
          };

          const existingMessage = await loadExistingMessage(roomID, effectiveMessageID);
          if (existingMessage) {
            return callback && callback({
              ok: true,
              duplicate: true,
              messageID: effectiveMessageID,
              seq: existingMessage.seq
            });
          }

          const storagePaths = [storagePath, thumbnailPath];
          const actualPathCount = storagePaths.filter(Boolean).length;
          const contract = validateMediaUploadContract("video", 1, actualPathCount);
          if (!contract.ok) {
            deliveredVideoKeys.delete(dedupKey);
            return callback && callback({ ok: false, error: contract.error });
          }

          const reservation = await assertMediaUploadReservation({
            roomID,
            messageID: effectiveMessageID,
            senderUID: videoSenderUID,
            kind: "video",
            attachmentCount: contract.attachmentCount,
            expectedPathCount: contract.expectedPathCount,
            storagePaths
          });
          if (!reservation.ok) {
            deliveredVideoKeys.delete(dedupKey);
            return callback && callback({ ok: false, error: reservation.error });
          }

          const serverMsg = buildServerVideoMessage({
            roomID,
            messageID: effectiveMessageID,
            msg: typeof msg === 'string' ? msg : '',
            attachments: [attachment],
            senderUID: videoSenderUID,
            senderEmail: videoSenderEmail,
            senderNickname: nickname,
            senderAvatarPath,
            sentAt
          });

          try {
            const seq = await allocateSeqAndPersist(roomID, effectiveMessageID, serverMsg, {
              mediaUploadRef: reservation.ref
            });
            serverMsg.seq = seq;
          } catch (e) {
            deliveredVideoKeys.delete(dedupKey);
            console.error('[chat:mediaFinalize/video] seq allocation/persist error:', e);
            return callback && callback({ ok: false, error: 'seq_persist_error' });
          }

          io.to(roomID).emit(`receiveVideo`, serverMsg);
          void fanoutChatPush({
            roomID,
            messageData: serverMsg
          });
          console.log(`[Video][${roomID}] ${nickname || "Anonymous"} sent video meta`, serverMsg);

          return callback && callback({ ok: true, messageID: effectiveMessageID });
        } catch (error) {
          console.error('[chat:mediaFinalize/video] handler error:', error);
          return callback && callback({ ok: false, error: 'internal_error' });
        }
      }

      return callback && callback({ ok: false, error: 'invalid_media_kind' });
    }

    socket.on('chat:mediaFinalize', async (data, callback) => {
      return handleMediaFinalize(data, callback);
    });

    socket.on('disconnect', () => {
        console.log('User disconnected:', socket.id);
        for (const roomID in rooms) {
            rooms[roomID] = rooms[roomID].filter((user) => user !== socket.username);
            io.to(roomID).emit("user list", rooms[roomID]); // 참여 유저 목록 갱신
        }
      });

    // Removed automatic joining to all rooms on connection
});

function startServer() {
  server.listen(PORT, () => {
    console.log(`server running at http://0.0.0.0:${PORT}`);
  });
}

function exitAfterServerClose(error) {
  if (error && error.code !== 'ERR_SERVER_NOT_RUNNING') {
    console.error('[shutdown] server close failed:', error);
    process.exit(1);
  }
  console.log('[shutdown] server closed');
  process.exit(0);
}

function shutdown(signal) {
  if (isShuttingDown) return;
  isShuttingDown = true;
  console.log(`[shutdown] received ${signal}, closing socket server`);

  io.close(() => {
    if (server.listening) {
      server.close(exitAfterServerClose);
    } else {
      exitAfterServerClose();
    }
  });

  setTimeout(() => {
    console.error('[shutdown] forced exit after timeout');
    process.exit(1);
  }, 10_000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

server.on('error', (error) => {
  console.error('[server] listen error:', error);
  process.exit(1);
});

// Fetch rooms from Firebase first, then start server.
fetchRoomsFromFirebase().then(() => {
  console.log("All rooms initialized and ready:", Object.keys(rooms));
  startServer();
}).catch((err) => {
  console.error("Failed to fetch rooms from Firebase:", err);
  startServer();
});
