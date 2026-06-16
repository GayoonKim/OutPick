export const RECONNECT_POLICY = Object.freeze({
  maxAttempts: 5,
  baseDelayMs: 500,
  maxDelayMs: 8000,
  jitter: 0.3,
  windowMs: 60_000
});

export const MAX_IMAGES_PER_MESSAGE = 30;
export const MAX_THUMB_PAYLOAD_BYTES = 600 * 1024;
export const PER_ITEM_THUMB_MAX_BYTES = 25 * 1024;
export const MAX_CHAT_MESSAGE_BYTES = 4000;
export const MAX_LOOKBOOK_SHARE_PAYLOAD_BYTES = 16 * 1024;
export const MAX_LOOKBOOK_SHARE_TEXT_BYTES = 4000;
export const MAX_LOOKBOOK_SHARE_ID_LENGTH = 160;
export const MAX_LOOKBOOK_SHARE_TITLE_LENGTH = 200;
export const MAX_LOOKBOOK_SHARE_SUBTITLE_LENGTH = 240;
export const MAX_LOOKBOOK_SHARE_THUMBNAIL_LENGTH = 1000;
export const RATE_WINDOW_MS = 2000;
export const RATE_MAX_CHAT = 12;
export const RATE_MAX_IMAGES = 4;
export const RATE_MAX_VIDEOS = 4;
export const RATE_MAX_LOOKBOOK_SHARE = 6;
export const MAX_MULTICAST_TOKENS = 500;
export const USERS_COLLECTION = "users";
export const DEVICES_SUBCOLLECTION = "devices";

const parsedPort = Number(process.env.PORT);
export const PORT = Number.isInteger(parsedPort) && parsedPort > 0 ? parsedPort : 3000;
