import { normalizeSentAt } from "../utils/strings.js";

export function normalizeReplyPreview(replyPreview, {replySourceMessage = null} = {}) {
  if (!replyPreview || typeof replyPreview !== "object") return undefined;
  const messageID = String(replyPreview.messageID || "");
  if (!messageID) return undefined;

  const sentAt = normalizeSentAt(replyPreview.sentAt);
  const sourceAttachments = Array.isArray(replySourceMessage?.attachments)
    ? replySourceMessage.attachments
    : [];
  const sourceHasMedia = sourceAttachments.some((attachment) =>
    ["image", "video"].includes(String(attachment?.type || "").toLowerCase())
  );
  const sourceExpiry = replySourceMessage?.mediaExpiresAt;
  const mediaExpiresAt = normalizeSentAt(
    sourceExpiry?.toDate?.().toISOString?.() ?? sourceExpiry
  );
  const canShowSourceThumbnail = sourceHasMedia && Boolean(mediaExpiresAt);
  return {
    messageID,
    sender: String(replyPreview.sender || ""),
    text: String(replyPreview.text || ""),
    imagesCount: Number(replyPreview.imagesCount ?? replyPreview.images ?? 0),
    videosCount: Number(replyPreview.videosCount ?? replyPreview.videos ?? 0),
    ...(canShowSourceThumbnail && replyPreview.firstThumbPath
      ? { firstThumbPath: String(replyPreview.firstThumbPath) }
      : {}),
    ...(replyPreview.senderAvatarPath
      ? { senderAvatarPath: String(replyPreview.senderAvatarPath) }
      : {}),
    ...(sentAt ? { sentAt } : {}),
    ...(sourceHasMedia && mediaExpiresAt ? { mediaExpiresAt } : {}),
    isDeleted: Boolean(replyPreview.isDeleted)
  };
}

export function buildTextMessageDocument({
  data,
  roomID,
  messageID,
  msg,
  senderUID,
  nickname,
  nowDate,
  replySourceMessage = null
}) {
  const sentAt = normalizeSentAt(data?.sentAt);
  const replyPreview = normalizeReplyPreview(data?.replyPreview, {replySourceMessage});

  return {
    ID: messageID,
    roomID,
    roomName: roomID,
    senderUID,
    senderNickname: nickname,
    ...(data?.senderAvatarPath ? { senderAvatarPath: data.senderAvatarPath } : {}),
    msg,
    message: msg,
    messageType: "Text",
    ...(replyPreview ? { replyPreview } : {}),
    isFailed: false,
    isDeleted: false,
    sentAt: sentAt || nowDate.toISOString(),
    attachments: []
  };
}
