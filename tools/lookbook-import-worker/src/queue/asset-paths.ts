/* eslint-disable require-jsdoc, max-len */
import {createHash} from "node:crypto";

export type AssetPathIdentity = {
  brandID: string;
  seasonID: string;
  jobID: string;
  executionID: string;
  epoch: number;
  writeID: string;
  kind: "seasonCover" | "postImage";
  postID?: string;
  mediaIndex?: number;
  sourceURL: string;
  transformPolicyVersion: string;
};

export type AssetWritePaths = {
  assetKey: string;
  writeID: string;
  thumbPath: string;
  detailPath: string;
};

function segment(value: string): void {
  const hasControlCharacters = [...value].some((character) =>
    character.charCodeAt(0) < 32);
  if (!value || value.length > 128 || value === "." || value === ".." ||
      value.includes("/") || hasControlCharacters) {
    throw new Error("INVALID_ASSET_PATH_ID");
  }
}

export function assetKey(identity: AssetPathIdentity): string {
  segment(identity.brandID);
  segment(identity.seasonID);
  segment(identity.jobID);
  segment(identity.executionID);
  segment(identity.transformPolicyVersion);
  if (!identity.sourceURL || !Number.isSafeInteger(identity.epoch) ||
      identity.epoch < 1) throw new Error("INVALID_ASSET_PATH_ID");
  if (identity.kind === "postImage") {
    if (!identity.postID || !Number.isSafeInteger(identity.mediaIndex) ||
        Number(identity.mediaIndex) < 0) throw new Error("INVALID_ASSET_PATH_ID");
    segment(identity.postID);
  } else if (identity.kind !== "seasonCover") {
    throw new Error("INVALID_ASSET_PATH_ID");
  }
  const stableInput = [identity.jobID, identity.executionID, identity.kind,
    identity.seasonID, identity.postID ?? null, identity.mediaIndex ?? null,
    identity.sourceURL, identity.transformPolicyVersion];
  return createHash("sha256").update(JSON.stringify(stableInput)).digest("hex");
}

// 공개 경로와 분리한 실행별 경로다. writeID는 재시도 간에도 재사용하지 않는다.
export function assetWritePaths(identity: AssetPathIdentity): AssetWritePaths {
  segment(identity.writeID);
  const key = assetKey(identity);
  const base = identity.kind === "seasonCover" ?
    `brands/${identity.brandID}/seasons/${identity.seasonID}/imports/` +
      `${identity.executionID}/${identity.epoch}/cover/${identity.writeID}` :
    `brands/${identity.brandID}/seasons/${identity.seasonID}/posts/` +
      `${identity.postID}/imports/${identity.executionID}/${identity.epoch}/` +
      `${key}/${identity.writeID}`;
  return {
    assetKey: key,
    writeID: identity.writeID,
    thumbPath: `${base}/${identity.kind === "seasonCover" ?
      "cover_thumb.jpg" : "thumb.jpg"}`,
    detailPath: `${base}/${identity.kind === "seasonCover" ?
      "cover.jpg" : "detail.jpg"}`,
  };
}
