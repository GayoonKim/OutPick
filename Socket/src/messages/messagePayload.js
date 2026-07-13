import { normalizeSentAt } from "../utils/strings.js";

export function normalizeReplyPreview(replyPreview) {
  if (!replyPreview || typeof replyPreview !== "object") return undefined;
  const messageID = String(replyPreview.messageID || "");
  if (!messageID) return undefined;

  const sentAt = normalizeSentAt(replyPreview.sentAt);
  return {
    messageID,
    sender: String(replyPreview.sender || ""),
    text: String(replyPreview.text || ""),
    imagesCount: Number(replyPreview.imagesCount ?? replyPreview.images ?? 0),
    videosCount: Number(replyPreview.videosCount ?? replyPreview.videos ?? 0),
    ...(replyPreview.firstThumbPath
      ? { firstThumbPath: String(replyPreview.firstThumbPath) }
      : {}),
    ...(replyPreview.senderAvatarPath
      ? { senderAvatarPath: String(replyPreview.senderAvatarPath) }
      : {}),
    ...(sentAt ? { sentAt } : {}),
    isDeleted: Boolean(replyPreview.isDeleted)
  };
}

export function buildTextMessageDocument({
  data,
  roomID,
  messageID,
  msg,
  senderUID,
  senderEmail,
  nickname,
  nowDate
}) {
  const sentAt = normalizeSentAt(data?.sentAt);
  const replyPreview = normalizeReplyPreview(data?.replyPreview);

  return {
    ID: messageID,
    roomID,
    roomName: roomID,
    senderUID,
    ...(senderEmail ? { senderEmail } : {}),
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
