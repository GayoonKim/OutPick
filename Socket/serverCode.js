import express from "express";
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Server } from "socket.io";
import admin from "firebase-admin";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const serviceAccount = require('./outpick-664ae-firebase-adminsdk-s16bx-6165221731.json');

const app = express();
const server = createServer(app);
const io = new Server(server, {
  maxHttpBufferSize: 2 * 1024 * 1024,           // 최대 2MB까지 허용 (썸네일 버퍼 여유)
  perMessageDeflate: { threshold: 1024 }        // 작은 메시지에는 비활성(이미지엔 효과 제한)
});

// ---- Reconnect policy (server hints) ----
const RECONNECT_POLICY = Object.freeze({
  maxAttempts: 5,
  baseDelayMs: 500,
  maxDelayMs: 8000,
  jitter: 0.3,
  windowMs: 60_000 // count attempts within 60s
});

// Track connection attempts per client key (auth.clientKey | query.clientKey | remote address)
const connectAttempts = new Map();
function getClientKey(handshake) {
  try {
    return (
      handshake.auth?.clientKey ||
      handshake.query?.clientKey ||
      handshake.address || // e.g., "::ffff:127.0.0.1"
      'unknown'
    );
  } catch {
    return 'unknown';
  }
}

let rooms = {}; // 방 목록 및 방 별 사용자 관리

// 이미지 메시지 중복 방지 및 용량 가드
const deliveredImageKeys = new Set(); // key: `${roomID}:${clientMessageID}`
const MAX_IMAGES_PER_MESSAGE = 30;
const MAX_THUMB_PAYLOAD_BYTES = 600 * 1024; // 썸네일 총량 예산(600KB)
const PER_ITEM_THUMB_MAX_BYTES = 25 * 1024;     // 개별 썸네일 최대 25KB

// Video meta de-dup & rate
const deliveredVideoKeys = new Set(); // key: `${roomID}:${messageID}`
const RATE_MAX_VIDEOS = 4;            // 2초에 비디오 메타 4회

// If the client does not send per-image URL, server can derive it via env:
//   export IMAGE_CDN_BASE="https://cdn.example.com/images"
// Then withDerivedUrls() will emit both `url` and `originalUrl` based on storagePath/fileName.

// ---- Safety guards ----
const MAX_CHAT_MESSAGE_BYTES = 4000;           // UTF-8 기준 텍스트 최대 바이트
const RATE_WINDOW_MS = 2000;                   // 2초 윈도우
const RATE_MAX_CHAT = 12;                      // 2초에 채팅 12회
const RATE_MAX_IMAGES = 4;                     // 2초에 이미지 4회

function isValidRoomID(roomID) {
  return (typeof roomID === 'string') && /^[A-Za-z0-9_-]{1,64}$/.test(roomID);
}

// 간단한 토큰버킷/슬라이딩 윈도우 형태의 레이트 리밋
const rateBuckets = new Map(); // key -> [timestamps]
function allowRate(key, limit, windowMs) {
  const now = Date.now();
  const arr = rateBuckets.get(key) || [];
  while (arr.length && (now - arr[0] > windowMs)) arr.shift();
  if (arr.length >= limit) return false;
  arr.push(now);
  rateBuckets.set(key, arr);
  return true;
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
    senderID = '',
    senderNickname = '',
    senderAvatarPath = '',
    sentAt
  } = body || {};

  const normalized = attachments.map((a, i) => normalizeAttachment(a, i));

  return {
    ID: messageID,                 // mirror client messageID
    roomID,
    senderID,
    senderNickname,
    ...(senderAvatarPath ? { senderAvatarPath } : {}),
    msg,
    sentAt: sentAt || new Date().toISOString(),
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
    senderID = '',
    senderNickname = '',
    senderAvatarPath = '',
    sentAt
  } = body || {};

  const normalized = attachments.map((a, i) => normalizeVideoAttachment(a, i));

  return {
    ID: messageID,
    roomID,
    senderID,
    senderNickname,
    ...(senderAvatarPath ? { senderAvatarPath } : {}),
    msg,
    sentAt: sentAt || new Date().toISOString(),
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

app.get('/', (req, res) => {
  res.sendFile(join(__dirname, 'index.html'));
});

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});
const db = admin.firestore();
const USERS_COLLECTION = "users";

function normalizeEmail(email) {
  return typeof email === "string" ? email.trim().toLowerCase() : "";
}

function chunkArray(items, size) {
  const chunks = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}

async function findUserDocRefByEmail(email) {
  const normalizedEmail = normalizeEmail(email);
  if (!normalizedEmail) return null;

  const snapshot = await db.collection(USERS_COLLECTION)
    .where("email", "==", normalizedEmail)
    .limit(1)
    .get();

  return snapshot.empty ? null : snapshot.docs[0].ref;
}

async function findUserDocRefsByEmails(emails) {
  const normalizedEmails = [...new Set(emails.map(normalizeEmail).filter(Boolean))];
  const refsByEmail = new Map();

  if (!normalizedEmails.length) {
    return refsByEmail;
  }

  const chunks = chunkArray(normalizedEmails, 10);
  const snapshots = await Promise.all(
    chunks.map((chunk) =>
      db.collection(USERS_COLLECTION)
        .where("email", "in", chunk)
        .get()
    )
  );

  for (const snapshot of snapshots) {
    snapshot.forEach((doc) => {
      const email = normalizeEmail(doc.get("email"));
      if (email) {
        refsByEmail.set(email, doc.ref);
      }
    });
  }

  return refsByEmail;
}

async function stageRoomMembershipCleanup(batch, roomID, email, userRef = null) {
  const normalizedEmail = normalizeEmail(email);
  if (!normalizedEmail) return false;

  const resolvedUserRef = userRef ?? await findUserDocRefByEmail(normalizedEmail);
  if (!resolvedUserRef) {
    console.warn("[room-membership] user doc not found", { roomID, email: normalizedEmail });
    return false;
  }

  batch.set(resolvedUserRef, {
    joinedRooms: admin.firestore.FieldValue.arrayRemove(roomID),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });
  batch.delete(resolvedUserRef.collection("roomStates").doc(roomID));
  return true;
}

// --- Sequence allocator & persistence (Firestore transaction) ---
async function allocateSeqAndPersist(roomID, messageID, messageData) {
  const roomRef = db.collection("Rooms").doc(roomID);
  const msgRef  = roomRef.collection("Messages").doc(messageID);

  // 마지막 메시지 텍스트 유도: 우선 msg, 없으면 첨부 타입 요약
  const deriveLastMessage = (md) => {
    const raw = (typeof md?.msg === 'string' ? md.msg.trim() : '');
    if (raw) return raw;
    const atts = Array.isArray(md?.attachments) ? md.attachments : [];
    const img = atts.filter(a => a && a.type === 'image').length;
    const vid = atts.filter(a => a && a.type === 'video').length;
    if (img && vid) return `[사진 ${img}장 · 동영상 ${vid}개]`;
    if (img) return img === 1 ? `[사진]` : `[사진 ${img}장]`;
    if (vid) return vid === 1 ? `[동영상]` : `[동영상 ${vid}개]`;
    return `[첨부]`;
  };

  const lastMessageText = deriveLastMessage(messageData);

  const seq = await db.runTransaction(async (tx) => {
    // Idempotency: if message already exists with a seq, reuse it (do not override room aggregate here)
    const existing = await tx.get(msgRef);
    if (existing.exists) {
      const ed = existing.data() || {};
      if (typeof ed.seq === 'number') {
        tx.set(msgRef, { ...messageData, seq: ed.seq }, { merge: true });
        return ed.seq;
      }
    }

    // Allocate next sequence atomically
    const roomSnap = await tx.get(roomRef);
    const cur = Number((roomSnap.exists && typeof roomSnap.data().seq === 'number') ? roomSnap.data().seq : 0);
    const next = cur + 1;

    // Persist message (with seq)
    tx.set(msgRef, { ...messageData, seq: next }, { merge: true });

    // Update room aggregate: seq / lastMessage / lastMessageAt
    tx.set(roomRef, {
      seq: next,
      lastMessage: lastMessageText,
      lastMessageAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    return next;
  });

  return seq;
}

async function fetchRoomsFromFirebase() {
  const roomsCollection = db.collection("Rooms");
  const snapshot = await roomsCollection.get();

  snapshot.forEach(doc => {
    const roomID = doc.id;
    if (!rooms[roomID]) {
      rooms[roomID] = [];
    }
  });

  console.log("Rooms initialized from Firebase:", Object.keys(rooms));
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

io.on('connection', (socket) => {
    const email = normalizeEmail(socket.handshake.query.email);
    socket.userEmail = email;
    
    console.log('User connected:', socket.userEmail);

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
    socket.on('create room', (roomID) => {
        if (!rooms[roomID]) {
            rooms[roomID] = [];
            console.log(`Room created: ${roomID}`);
        }

        socket.join(roomID);
        if (!rooms[roomID].includes(socket.username || "Anonymous")) {
          rooms[roomID].push(socket.username || "Anonymous");
        }
    });

    // 방 참여
    socket.on('join room', (roomID) => {
        const username = socket.username || "Anonymous";
        console.log(`Join request: ${username} → ${roomID}`);

        if (rooms[roomID]) {
            socket.join(roomID);
            if (!rooms[roomID].includes(username)) {
              rooms[roomID].push(username);
            }
            console.log(`${username} joined room: ${roomID}`);
//            io.to(roomID).emit("user list", rooms[roomID]); // 해당 방 사용자 목록 전송
            socket.emit("joined room", roomID); // 클라이언트에 성공 알림
        } else {
            console.warn(`Join failed: ${username} → ${roomID} (room does not exist)`);
            socket.emit("error", `Room ${roomID} does not exist`);
        }
    });

    socket.on('leave room', (roomID) => {
      if (!roomID || !isValidRoomID(roomID)) return;

      socket.leave(roomID);

      if (rooms[roomID]) {
        rooms[roomID] = rooms[roomID].filter((name) => name !== socket.username);
        io.to(roomID).emit('user list', rooms[roomID]);
      }

      console.log(`Leave room request: ${socket.username || "Anonymous"} → ${roomID}`);
    });

    // 방 나가기 / 방 종료 (서버가 Firestore 상태로 판단)
    // 클라는 roomID + intent만 보냄: { roomID, intent: "leave-or-close" }
    socket.on('room:leave-or-close', async (payload = {}, callback) => {
      const { roomID } = payload || {};
      const userEmail = socket.userEmail;

      console.log('[room:leave-or-close] requested', { roomID, userEmail });

      // --- 기본 검증 ---
      if (!roomID || !isValidRoomID(roomID)) {
        console.warn('[room:leave-or-close] invalid roomID', roomID);
        callback && callback({ ok: false, error: 'invalid_room_id' });
        return;
      }

      if (!userEmail || typeof userEmail !== 'string') {
        console.warn('[room:leave-or-close] missing userEmail on socket');
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
        const participantIDs = Array.isArray(roomData.participantIDs)
          ? [...new Set(roomData.participantIDs.map(normalizeEmail).filter(Boolean))]
          : [];
        if (userEmail && !participantIDs.includes(userEmail)) {
          participantIDs.push(userEmail);
        }

        // 🔑 방장 판단: creatorID 필드만 사용
        const creatorID = typeof roomData.creatorID === 'string'
          ? normalizeEmail(roomData.creatorID)
          : null;
        const isOwner = !!creatorID && creatorID === userEmail;

        // =========================
        // 1) 방장인 경우 → 방 종료
        // =========================
        if (isOwner) {
          console.log('[room:leave-or-close] owner closing room', { roomID, creatorID });

          const cleanupBatch = db.batch();
          const userRefsByEmail = await findUserDocRefsByEmails(participantIDs);
          cleanupBatch.set(roomRef, {
            isClosed: true,
            closedAt: admin.firestore.FieldValue.serverTimestamp(),
            closedBy: userEmail,
            participantIDs: []
          }, { merge: true });

          for (const participantEmail of participantIDs) {
            await stageRoomMembershipCleanup(
              cleanupBatch,
              roomID,
              participantEmail,
              userRefsByEmail.get(participantEmail) ?? null
            );
          }

          await cleanupBatch.commit();

          // 클라이언트들에게 "room closed" 알림
          io.to(roomID).emit('room:closed', {
            roomID,
            closedBy: userEmail
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
        console.log('[room:leave-or-close] participant leaving room', { roomID, userEmail });

        const cleanupBatch = db.batch();
        cleanupBatch.set(roomRef, {
          participantIDs: admin.firestore.FieldValue.arrayRemove(userEmail)
        }, { merge: true });
        await stageRoomMembershipCleanup(cleanupBatch, roomID, userEmail);
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
          roomID,
          msg,
          senderID,
          senderNickname,
          senderAvatarPath,   // 새 필드 지원
          replyPreview,
          sentAt
        } = data || {};

        // ===== 기본 검증 =====
        if (!roomID || typeof msg !== 'string' || msg.trim().length === 0) {
          console.error("[Chat] Invalid data received:", data);
          callback && callback({ success: false, error: "Invalid data" });
          return;
        }
        if (!isValidRoomID(roomID)) {
          console.warn(`[Chat] invalid roomID: ${roomID}`);
          callback && callback({ success: false, error: "invalid_room_id" });
          return;
        }
        if (!rooms[roomID]) {
          console.warn(`[Chat] room not found: ${roomID}`);
          callback && callback({ success: false, error: "room_not_found" });
          return;
        }
        if (!socket.rooms.has(roomID)) {
          console.warn(`[Chat] socket not joined to room: ${roomID}`);
          callback && callback({ success: false, error: "not_joined" });
          return;
        }
        const msgBytes = Buffer.byteLength(msg, "utf8");
        if (msgBytes > MAX_CHAT_MESSAGE_BYTES) {
          console.warn(`[Chat] message too long: ${msgBytes} bytes`);
          callback && callback({ success: false, error: "message_too_long" });
          return;
        }
        const chatRateKey = `${socket.id}:${roomID}:chat`;
        if (!allowRate(chatRateKey, RATE_MAX_CHAT, RATE_WINDOW_MS)) {
          console.warn(`[Chat] rate limited: ${socket.id} @ ${roomID}`);
          callback && callback({ success: false, error: "rate_limited" });
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
          senderID,
          senderNickname,
          ...(senderAvatarPath ? { senderAvatarPath } : {}),
          msg,
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
          callback && callback({ success: false, error: 'seq_persist_error' });
          return;
        }

        const serverMsg = { ...messageDoc, seq };

        // ===== 방으로 브로드캐스트 =====
        io.to(roomID).emit("chat message", serverMsg);
//        io.to(roomID).emit(`chat message:${roomID}`, serverMsg);

        console.log(`[Chat][${roomID}] ${senderNickname || "Anonymous"}: ${msg}`, serverMsg);
        callback && callback({ success: true, seq, messageID });
      } catch (error) {
        console.error("[Chat] Error processing message:", error);
        callback && callback({ success: false, error: error.message });
      }
    });

    // 🔁 Legacy support: "send images" → accept new/old payload, normalize, unified emit
    socket.on('send images', async (data, callback) => {
      try {
        const {
          roomID,
          messageID,
          clientMessageID,
          attachments,        // new client shape (meta-only)
          images,             // legacy client shape
          senderID,
          senderNickname,     // new key (camelcase),     // legacy key
          senderAvatarPath,   // propagate avatar path
          sentAt,             // ISO8601 or epoch
          type,               // optional (should be 'image')
          msg                 // optional (usually '')
        } = data || {};

        // ===== Validations =====
        if (!roomID) return callback && callback({ ok: false, error: 'invalid_room_id' });
        if (!rooms[roomID]) return callback && callback({ ok: false, error: 'room_not_found' });
        if (!socket.rooms.has(roomID)) return callback && callback({ ok: false, error: 'not_joined' });

        // Input list (prefer new attachments, fallback to images)
        const incoming = Array.isArray(attachments)
          ? attachments
          : (Array.isArray(images) ? images : []);

        if (incoming.length === 0) {
          return callback && callback({ ok: false, error: 'no_images' });
        }

        // Rate-limit (per socket per room)
        const imgRateKey = `${socket.id}:${roomID}:images`;
        if (!allowRate(imgRateKey, RATE_MAX_IMAGES, RATE_WINDOW_MS)) {
          return callback && callback({ ok: false, error: 'rate_limited' });
        }

        // De-dup by stable messageID (prefer new `messageID`, fallback to legacy `clientMessageID`)
        let effectiveMessageID = (messageID && String(messageID))
          || (clientMessageID && String(clientMessageID))
          || `${Date.now()}-${Math.random().toString(16).slice(2)}`;

        const dedupKey = `${roomID}:${effectiveMessageID}`;
        if (deliveredImageKeys.has(dedupKey)) {
          return callback && callback({ ok: true, duplicate: true, messageID: effectiveMessageID });
        }
        deliveredImageKeys.add(dedupKey);
        if (deliveredImageKeys.size > 50000) deliveredImageKeys.clear();

        // Cap images per message
        const trimmed = incoming.length > MAX_IMAGES_PER_MESSAGE;
        const capped = incoming.slice(0, MAX_IMAGES_PER_MESSAGE);

        // If legacy `images` were sent, sanitize/derive; if new `attachments`, they may be meta already
        const prepared = (Array.isArray(attachments) ? capped : capped.map(sanitizeImageItem).map(withDerivedUrls));

        // Enforce total thumbnail payload budget (600KB). (Best-effort: only applies if thumbData exists)
        const { images: budgeted, thumbTrimmed } = enforceThumbBudget(prepared, MAX_THUMB_PAYLOAD_BYTES);

        // Normalize to server attachment schema
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
          return callback && callback({ ok: false, error: 'no_valid_attachments' });
        }

        // Build server message payload (unified with text handler)
        const nickname = senderNickname || senderNickName || '';
        const finalType = type || 'image';
        const finalMsg = typeof msg === 'string' ? msg : '';

        // sentAt normalization → ISO8601 string
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
          senderID,
          senderNickname: nickname,
          senderAvatarPath,
          sentAt: when.toISOString()
        });

        // --- Persist with seq and broadcast ---
        try {
          const seq = await allocateSeqAndPersist(roomID, effectiveMessageID, serverMsg);
          serverMsg.seq = seq;
        } catch (e) {
          console.error('[send images] seq allocation/persist error:', e);
          return callback && callback({ ok: false, error: 'seq_persist_error' });
        }

        // (Optional legacy channel for older clients)
        console.log(`[Chat][${roomID}] ${senderNickname || "Anonymous"}: ${msg}`, serverMsg);
//        io.to(roomID).emit(`receiveImages:${roomID}`, serverMsg);
        io.to(roomID).emit(`receiveImages`, serverMsg);
        return callback && callback({ ok: true, messageID: effectiveMessageID, trimmed, thumbTrimmed });
      } catch (error) {
        console.error('[send images] handler error:', error);
        return callback && callback({ ok: false, error: 'internal_error' });
      }
    });

    // Receive meta-only video payload from client and broadcast to the room
    socket.on('chat:video', async (data, callback) => {
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
          senderID,
          senderNickname,
          senderNickName, // legacy
          senderAvatarPath,
          sentAt,
          msg // optional
        } = data || {};

        // ===== Validations =====
        if (!roomID) return callback && callback({ ok: false, error: 'invalid_room_id' });
        if (!rooms[roomID]) return callback && callback({ ok: false, error: 'room_not_found' });
        if (!socket.rooms.has(roomID)) return callback && callback({ ok: false, error: 'not_joined' });

        // Rate-limit (per socket per room)
        const vidRateKey = `${socket.id}:${roomID}:video`;
        if (!allowRate(vidRateKey, RATE_MAX_VIDEOS, RATE_WINDOW_MS)) {
          return callback && callback({ ok: false, error: 'rate_limited' });
        }

        // De-dup by stable messageID
        const effectiveMessageID = (messageID && String(messageID)) || `${Date.now()}-${Math.random().toString(16).slice(2)}`;
        const dedupKey = `${roomID}:${effectiveMessageID}`;
        if (deliveredVideoKeys.has(dedupKey)) {
          return callback && callback({ ok: true, duplicate: true, messageID: effectiveMessageID });
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

        const serverMsg = buildServerVideoMessage({
          roomID,
          messageID: effectiveMessageID,
          msg: typeof msg === 'string' ? msg : '',
          attachments: [attachment],
          senderID,
          senderNickname: nickname,
          senderAvatarPath,
          sentAt
        });

        // --- Persist with seq and broadcast ---
        try {
          const seq = await allocateSeqAndPersist(roomID, effectiveMessageID, serverMsg);
          serverMsg.seq = seq;
        } catch (e) {
          console.error('[chat:video] seq allocation/persist error:', e);
          return callback && callback({ ok: false, error: 'seq_persist_error' });
        }

        // Broadcast to the room
//        io.to(roomID).emit(`receiveVideo:${roomID}`, serverMsg);
        io.to(roomID).emit(`receiveVideo`, serverMsg);
        console.log(`[Video][${roomID}] ${nickname || "Anonymous"} sent video meta`, serverMsg);

        return callback && callback({ ok: true, messageID: effectiveMessageID });
      } catch (error) {
        console.error('[chat:video] handler error:', error);
        return callback && callback({ ok: false, error: 'internal_error' });
      }
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

// Fetch rooms from Firebase first, then start server
fetchRoomsFromFirebase().then(() => {
    // Log all initialized rooms
    console.log("All rooms initialized and ready:", Object.keys(rooms));

    server.listen(3000, ()=> {
        console.log('server running at http://localhost:3000');
    });
}).catch((err) => {
  console.error("Failed to fetch rooms from Firebase:", err);
  // Start server anyway
  server.listen(3000, ()=> {
    console.log('server running at http://localhost:3000');
  });
});
