import { PER_ITEM_THUMB_MAX_BYTES } from "../config.js";

export function sanitizeImageItem(item) {
  if (typeof item === "string") return { url: item };
  if (!item || typeof item !== "object") return undefined;

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

  let safeThumb;
  if (thumbData) {
    if (Buffer.isBuffer(thumbData)) {
      if (thumbData.length <= PER_ITEM_THUMB_MAX_BYTES) safeThumb = thumbData;
    } else if (typeof thumbData === "string") {
      try {
        const buffer = Buffer.from(thumbData, "base64");
        if (buffer.length <= PER_ITEM_THUMB_MAX_BYTES) safeThumb = buffer;
      } catch {}
    }
  }

  return {
    ...(url ? { url } : {}),
    ...(fileName ? { fileName } : {}),
    ...(typeof width === "number" ? { width } : {}),
    ...(typeof height === "number" ? { height } : {}),
    ...(typeof size === "number" ? { size } : {}),
    ...(mimeType ? { mimeType } : {}),
    ...(storagePath ? { storagePath } : {}),
    ...(thumbUrl ? { thumbUrl } : {}),
    ...(safeThumb ? { thumbData: safeThumb } : {})
  };
}

export function withDerivedImageURLs(item, imageCdnBase) {
  let url = item?.url;
  if (!url && imageCdnBase) {
    if (typeof item?.storagePath === "string" && item.storagePath) {
      url = `${imageCdnBase}/${encodeURIComponent(item.storagePath)}`;
    } else if (typeof item?.fileName === "string" && item.fileName) {
      url = `${imageCdnBase}/${encodeURIComponent(item.fileName)}`;
    }
  }
  return { ...item, ...(url ? { url, originalUrl: url } : {}) };
}

export function normalizeImageAttachment(attachment, index) {
  return {
    type: "image",
    index: Number(attachment?.index ?? index),
    pathThumb: String(attachment?.pathThumb ?? attachment?.thumbPath ?? ""),
    pathOriginal: String(
      attachment?.pathOriginal ??
      attachment?.originalPath ??
      attachment?.url ??
      attachment?.originalUrl ??
      ""
    ),
    w: Number(attachment?.w ?? attachment?.width ?? 0),
    h: Number(attachment?.h ?? attachment?.height ?? 0),
    bytesOriginal: Number(attachment?.bytesOriginal ?? attachment?.size ?? 0),
    hash: String(attachment?.hash ?? ""),
    blurhash: attachment?.blurhash ?? null
  };
}

export function normalizeVideoAttachment(attachment, index) {
  return {
    type: "video",
    index: Number(attachment?.index ?? index),
    pathThumb: String(attachment?.pathThumb ?? attachment?.thumbnailPath ?? ""),
    pathOriginal: String(attachment?.pathOriginal ?? attachment?.storagePath ?? ""),
    w: Number(attachment?.w ?? attachment?.width ?? 0),
    h: Number(attachment?.h ?? attachment?.height ?? 0),
    bytesOriginal: Number(attachment?.bytesOriginal ?? attachment?.sizeBytes ?? 0),
    hash: String(attachment?.hash ?? ""),
    blurhash: attachment?.blurhash ?? null,
    ...(typeof attachment?.duration === "number" ? { duration: attachment.duration } : {}),
    ...(typeof attachment?.approxBitrateMbps === "number"
      ? { approxBitrateMbps: attachment.approxBitrateMbps }
      : {}),
    ...(typeof attachment?.preset === "string" ? { preset: attachment.preset } : {})
  };
}

export function buildServerImageMessage(body, nowDate) {
  const attachments = (body?.attachments || []).map(normalizeImageAttachment);
  return {
    ID: body?.messageID,
    roomID: body?.roomID,
    roomName: body?.roomID,
    senderUID: body?.senderUID || "",
    ...(body?.senderEmail ? { senderEmail: body.senderEmail } : {}),
    senderNickname: body?.senderNickname || "",
    ...(body?.senderAvatarPath ? { senderAvatarPath: body.senderAvatarPath } : {}),
    msg: body?.msg || "",
    message: body?.msg || "",
    sentAt: body?.sentAt || nowDate.toISOString(),
    messageType: "Image",
    attachments,
    replyPreview: null,
    isFailed: false
  };
}

export function buildServerVideoMessage(body, nowDate) {
  const attachments = (body?.attachments || []).map(normalizeVideoAttachment);
  return {
    ID: body?.messageID,
    roomID: body?.roomID,
    roomName: body?.roomID,
    senderUID: body?.senderUID || "",
    ...(body?.senderEmail ? { senderEmail: body.senderEmail } : {}),
    senderNickname: body?.senderNickname || "",
    ...(body?.senderAvatarPath ? { senderAvatarPath: body.senderAvatarPath } : {}),
    msg: body?.msg || "",
    message: body?.msg || "",
    sentAt: body?.sentAt || nowDate.toISOString(),
    messageType: "Video",
    attachments,
    replyPreview: null,
    isFailed: false
  };
}

export function enforceThumbBudget(images, budgetBytes) {
  let thumbTrimmed = false;
  let thumbBytes = 0;
  for (const item of images) {
    if (Buffer.isBuffer(item?.thumbData)) thumbBytes += item.thumbData.length;
  }
  if (thumbBytes > budgetBytes) {
    let over = thumbBytes - budgetBytes;
    for (let index = images.length - 1; index >= 0 && over > 0; index -= 1) {
      const item = images[index];
      if (Buffer.isBuffer(item?.thumbData)) {
        over -= item.thumbData.length;
        delete item.thumbData;
        thumbTrimmed = true;
      }
    }
  }
  return { images, thumbTrimmed };
}
