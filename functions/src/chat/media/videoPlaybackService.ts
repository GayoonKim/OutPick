/* eslint-disable require-jsdoc, max-len */
import {HttpsError} from "firebase-functions/v2/https";
import {Timestamp, type Firestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {db} from "../../core/firebase.js";
import {assertAccountCapability} from "../../shared/accountStatus.js";
import type {IssueChatVideoPlaybackURLInput} from "./videoPlaybackContracts.js";

const PLAYBACK_URL_TTL_MILLIS = 60 * 60 * 1000;

const VIDEO_CONTENT_TYPES = new Set([
  "video/mp4",
  "video/quicktime",
  "video/x-m4v",
]);
const IMAGE_CONTENT_TYPES = new Set(["image/jpeg", "image/png", "image/gif", "image/webp", "image/heic", "image/heif"]);

export type ChatVideoPlaybackObject = {
  bucket: string;
  path: string;
  generation: string;
};

export interface ChatVideoPlaybackURLSigner {
  metadata(object: ChatVideoPlaybackObject): Promise<{
    generation?: string | number;
    contentType?: string;
  }>;
  sign(object: ChatVideoPlaybackObject, expiresAt: Date): Promise<string>;
}

export type ChatVideoPlaybackURLResult = {
  url: string;
  urlExpiresAt: string;
  mediaExpiresAt: string;
  generation: string;
};

type ServiceInput = {
  actorUID: string;
  request: IssueChatVideoPlaybackURLInput;
  readyBucket: string;
  firestore?: Firestore;
  signer?: ChatVideoPlaybackURLSigner;
  now?: () => Date;
  authorize?: (uid: string, firestore: Firestore, now: Date) => Promise<void>;
  variant?: "original" | "thumbnail";
};

function failedPrecondition(errorCode: string, message: string): HttpsError {
  return new HttpsError("failed-precondition", message, {errorCode});
}

function mediaExpiryMillis(value: unknown): number {
  if (!(value instanceof Timestamp)) {
    throw failedPrecondition("MEDIA_EXPIRATION_UNAVAILABLE", "미디어 보관 기한을 확인할 수 없습니다.");
  }
  return value.toMillis();
}

function roomIsActive(data: FirebaseFirestore.DocumentData): boolean {
  return data.isClosed !== true &&
    (data.lifecycleStatus === undefined || data.lifecycleStatus === "active");
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> : {};
}

function expectedObject(input: {
  roomID: string;
  messageID: string;
  attachmentID: string;
  attachment: Record<string, unknown>;
  readyBucket: string;
  variant: "original" | "thumbnail";
}): ChatVideoPlaybackObject {
  const original = input.variant === "original";
  const bucket = input.attachment[original ? "bucketOriginal" : "bucketThumb"];
  const path = input.attachment[original ? "pathOriginal" : "pathThumb"];
  const generation = input.attachment[original ? "generationOriginal" : "generationThumb"];
  const expectedPath = `rooms/${input.roomID}/messages/${input.messageID}/attachments/${input.attachmentID}/${original ? "display" : "thumbnail"}`;
  if (bucket !== input.readyBucket || path !== expectedPath ||
      typeof generation !== "string" || !/^[1-9][0-9]*$/.test(generation) ||
      (original && (typeof input.attachment.contentTypeOriginal !== "string" ||
      !(input.attachment.type === "video" ? VIDEO_CONTENT_TYPES : IMAGE_CONTENT_TYPES).has(input.attachment.contentTypeOriginal)))) {
    throw failedPrecondition("INVALID_VIDEO_ATTACHMENT", "영상 첨부 정보가 올바르지 않습니다.");
  }
  return {bucket: input.readyBucket, path: expectedPath, generation};
}

function isMissingObject(error: unknown): boolean {
  const value = error && typeof error === "object" ? error as Record<string, unknown> : {};
  return Number(value.code) === 404 || Number(value.statusCode) === 404;
}

function urlExpiryMillis(nowMillis: number, mediaExpiresAtMillis: number): number {
  const unrounded = Math.min(nowMillis + PLAYBACK_URL_TTL_MILLIS, mediaExpiresAtMillis);
  // Cloud Storage V4 signed URL의 expiration은 초 단위이므로 기한을 넘지 않게 내림한다.
  return Math.floor(unrounded / 1000) * 1000;
}

export async function issueChatVideoPlaybackURLService(
  input: ServiceInput,
): Promise<ChatVideoPlaybackURLResult> {
  if (!input.readyBucket.trim()) {
    throw new Error("chat_media_ready_bucket_missing");
  }
  const firestore = input.firestore ?? db;
  const clock = input.now ?? (() => new Date());
  const authorize = input.authorize ?? ((uid, store, now) =>
    assertAccountCapability(uid, "readAppContent", store, now)
  );
  await authorize(input.actorUID, firestore, clock());

  const roomRef = firestore.collection("Rooms").doc(input.request.roomID);
  const messageRef = roomRef.collection("Messages").doc(input.request.messageID);
  const [room, message] = await Promise.all([roomRef.get(), messageRef.get()]);
  const roomData = room.data();
  const messageData = message.data();
  if (!room.exists || !roomData || !message.exists || !messageData) {
    throw new HttpsError("not-found", "채팅 미디어를 찾을 수 없습니다.");
  }
  if (!roomIsActive(roomData)) {
    throw failedPrecondition("CHAT_ROOM_CLOSED", "종료된 채팅방의 미디어는 열 수 없습니다.");
  }
  if (messageData.mediaContractVersion !== 3) {
    throw failedPrecondition("UNSUPPORTED_MEDIA_CONTRACT", "지원하지 않는 채팅 미디어 계약입니다.");
  }
  if (messageData.isDeleted === true ||
      (messageData.moderationVisibilityState !== undefined &&
       messageData.moderationVisibilityState !== "visible")) {
    throw new HttpsError("not-found", "채팅 미디어를 찾을 수 없습니다.");
  }

  const mediaExpiresAtMillis = mediaExpiryMillis(messageData.mediaExpiresAt);
  const mediaExpiresAt = new Date(mediaExpiresAtMillis);
  const nowBeforeLookup = clock().getTime();
  if (mediaExpiresAtMillis <= nowBeforeLookup) {
    throw failedPrecondition("MEDIA_EXPIRED", "미디어 보관 기한이 종료됐습니다.");
  }
  const readyAttachmentIDs = messageData.readyAttachmentIDs;
  if (!Array.isArray(readyAttachmentIDs) ||
      !readyAttachmentIDs.includes(input.request.attachmentID)) {
    throw new HttpsError("not-found", "채팅 미디어 첨부를 찾을 수 없습니다.");
  }
  const attachments = Array.isArray(messageData.attachments) ? messageData.attachments : [];
  const attachment = attachments.map(record).find((value) =>
    value.attachmentID === input.request.attachmentID
  );
  if (!attachment || (input.variant === undefined ? attachment.type !== "video" :
    !["video", "image"].includes(String(attachment.type)))) {
    throw new HttpsError("not-found", "채팅 영상 첨부를 찾을 수 없습니다.");
  }
  const object = expectedObject({
    roomID: input.request.roomID,
    messageID: input.request.messageID,
    attachmentID: input.request.attachmentID,
    attachment,
    readyBucket: input.readyBucket,
    variant: input.variant ?? "original",
  });

  const signer = input.signer ?? firebaseChatVideoPlaybackURLSigner();
  let metadata: Awaited<ReturnType<ChatVideoPlaybackURLSigner["metadata"]>>;
  try {
    metadata = await signer.metadata(object);
  } catch (error) {
    if (isMissingObject(error)) {
      throw new HttpsError("not-found", "채팅 영상 원본을 찾을 수 없습니다.");
    }
    throw error;
  }
  if (String(metadata.generation) !== object.generation ||
      metadata.contentType !== (input.variant === "thumbnail" ? "image/jpeg" : attachment.contentTypeOriginal)) {
    throw failedPrecondition("VIDEO_OBJECT_VERSION_MISMATCH", "채팅 영상 원본 버전이 일치하지 않습니다.");
  }

  const nowBeforeSign = clock().getTime();
  if (mediaExpiresAtMillis <= nowBeforeSign) {
    throw failedPrecondition("MEDIA_EXPIRED", "미디어 보관 기한이 종료됐습니다.");
  }
  const signedExpiryMillis = urlExpiryMillis(nowBeforeSign, mediaExpiresAtMillis);
  if (signedExpiryMillis <= nowBeforeSign) {
    throw failedPrecondition("PLAYBACK_URL_EXPIRY_TOO_CLOSE", "미디어 만료가 임박해 재생 URL을 발급할 수 없습니다.");
  }
  const signedExpiry = new Date(signedExpiryMillis);
  const url = await signer.sign(object, signedExpiry);
  const nowBeforeReturn = clock().getTime();
  if (mediaExpiresAtMillis <= nowBeforeReturn) {
    throw failedPrecondition("MEDIA_EXPIRED", "URL 발급 중 미디어 보관 기한이 종료됐습니다.");
  }
  if (signedExpiryMillis <= nowBeforeReturn) {
    throw failedPrecondition("PLAYBACK_URL_EXPIRED_DURING_ISSUE", "URL 발급 중 재생 URL이 만료됐습니다.");
  }
  return {
    url,
    urlExpiresAt: signedExpiry.toISOString(),
    mediaExpiresAt: mediaExpiresAt.toISOString(),
    generation: object.generation,
  };
}

export function firebaseChatVideoPlaybackURLSigner(): ChatVideoPlaybackURLSigner {
  const storage = getStorage();
  return {
    metadata: async (object) => {
      const [metadata] = await storage.bucket(object.bucket)
        .file(object.path, {generation: object.generation}).getMetadata();
      return {
        generation: metadata.generation,
        contentType: metadata.contentType,
      };
    },
    sign: async (object, expiresAt) => {
      const [url] = await storage.bucket(object.bucket)
        .file(object.path, {generation: object.generation})
        .getSignedUrl({version: "v4", action: "read", expires: expiresAt});
      return url;
    },
  };
}
