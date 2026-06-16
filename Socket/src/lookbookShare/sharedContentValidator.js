import {
  MAX_LOOKBOOK_SHARE_ID_LENGTH,
  MAX_LOOKBOOK_SHARE_SUBTITLE_LENGTH,
  MAX_LOOKBOOK_SHARE_THUMBNAIL_LENGTH,
  MAX_LOOKBOOK_SHARE_TITLE_LENGTH
} from "../config.js";
import { trimString } from "../utils/strings.js";

export function sanitizeLookbookSharedContent(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { error: "invalid_shared_content" };
  }

  const schemaVersion = Number(value.schemaVersion ?? 1);
  if (!Number.isInteger(schemaVersion) || schemaVersion !== 1) {
    return { error: "unsupported_shared_content_schema" };
  }

  const contentType = trimString(value.contentType, 24);
  if (!["brand", "season", "post"].includes(contentType)) {
    return { error: "invalid_shared_content_type" };
  }

  const brandID = trimString(value.brandID, MAX_LOOKBOOK_SHARE_ID_LENGTH);
  const seasonID = trimString(value.seasonID, MAX_LOOKBOOK_SHARE_ID_LENGTH);
  const postID = trimString(value.postID, MAX_LOOKBOOK_SHARE_ID_LENGTH);
  const titleSnapshot = trimString(value.titleSnapshot, MAX_LOOKBOOK_SHARE_TITLE_LENGTH);
  const subtitleSnapshot = trimString(value.subtitleSnapshot, MAX_LOOKBOOK_SHARE_SUBTITLE_LENGTH);
  const thumbnailPathSnapshot = trimString(value.thumbnailPathSnapshot, MAX_LOOKBOOK_SHARE_THUMBNAIL_LENGTH);

  if (!brandID || !titleSnapshot) {
    return { error: "invalid_shared_content" };
  }
  if ((contentType === "season" || contentType === "post") && !seasonID) {
    return { error: "invalid_shared_content" };
  }
  if (contentType === "post" && !postID) {
    return { error: "invalid_shared_content" };
  }

  return {
    value: {
      schemaVersion,
      contentType,
      brandID,
      ...(contentType === "season" || contentType === "post" ? { seasonID } : {}),
      ...(contentType === "post" ? { postID } : {}),
      titleSnapshot,
      ...(subtitleSnapshot ? { subtitleSnapshot } : {}),
      ...(thumbnailPathSnapshot ? { thumbnailPathSnapshot } : {})
    }
  };
}
