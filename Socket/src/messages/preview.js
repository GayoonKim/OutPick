import { trimPushText } from "../utils/strings.js";

export function buildPushPreview(messageData) {
  const raw = trimPushText(messageData?.msg || messageData?.message || "");
  if (raw) return raw;

  const attachments = Array.isArray(messageData?.attachments) ? messageData.attachments : [];
  const images = attachments.filter((item) => item?.type === "image").length;
  const videos = attachments.filter((item) => item?.type === "video").length;

  switch (true) {
    case images > 0 && videos === 0:
      return images === 1 ? "사진을 보냈어요" : `사진 ${images}장을 보냈어요`;
    case videos > 0 && images === 0:
      return videos === 1 ? "동영상을 보냈어요" : `동영상 ${videos}개를 보냈어요`;
    case images > 0 && videos > 0:
      return `사진 ${images}장, 동영상 ${videos}개를 보냈어요`;
    default:
      return "새 메시지가 도착했어요";
  }
}

export function deriveLastMessage(messageData) {
  const raw = (typeof messageData?.msg === "string" ? messageData.msg.trim() : "");
  if (raw) return raw;
  const attachments = Array.isArray(messageData?.attachments) ? messageData.attachments : [];
  const images = attachments.filter((item) => item && item.type === "image").length;
  const videos = attachments.filter((item) => item && item.type === "video").length;
  if (images && videos) return `[사진 ${images}장 · 동영상 ${videos}개]`;
  if (images) return images === 1 ? "[사진]" : `[사진 ${images}장]`;
  if (videos) return videos === 1 ? "[동영상]" : `[동영상 ${videos}개]`;
  return "[첨부]";
}

export function lookbookShareFallbackPreview(contentType) {
  switch (contentType) {
    case "brand":
      return "브랜드를 공유했어요";
    case "season":
      return "시즌을 공유했어요";
    case "post":
      return "포스트를 공유했어요";
    default:
      return "룩북을 공유했어요";
  }
}
