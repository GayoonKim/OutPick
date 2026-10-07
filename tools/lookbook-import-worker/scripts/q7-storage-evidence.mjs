import {createHash} from "node:crypto";
import sharp from "sharp";

export async function readQ7StorageOutput(bucket, path, expected) {
  const [metadata] = await bucket.file(path).getMetadata();
  const generation = String(metadata.generation);
  if (metadata.contentType !== "image/jpeg" || Number(metadata.size) !== expected.bytes ||
      expected.generation != null && generation !== String(expected.generation)) {
    throw new Error("Q7_STORAGE_OBJECT_VERSION_MISMATCH");
  }
  const file = bucket.file(path, {generation});
  const [bytes] = await file.download({validation: "crc32c"});
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  const image = await sharp(bytes).metadata();
  if (bytes.byteLength !== expected.bytes || sha256 !== expected.sha256 ||
      image.format !== "jpeg" || image.width !== expected.width ||
      image.height !== expected.height || image.orientation && image.orientation !== 1) {
    throw new Error("Q7_STORAGE_GOLDEN_MISMATCH");
  }
  return {bytes: bytes.byteLength, sha256, width: image.width, height: image.height,
    format: image.format, generation: String(metadata.generation),
    contentType: metadata.contentType,
    crc32c: metadata.crc32c ?? null, md5Hash: metadata.md5Hash ?? null};
}

export function q7PublishedCoverReference(season, ledger) {
  if (ledger?.status !== "published" || ledger.kind !== "seasonCover" ||
      ledger.epoch !== season.coverAssetEpoch || ledger.executionID !== season.coverAssetExecutionID ||
      ledger.assetKey !== season.coverAssetKey || ledger.writeID !== season.coverAssetWriteID ||
      ledger.detailPath !== season.coverPath || typeof ledger.thumbPath !== "string" ||
      season.coverThumbPath != null && season.coverThumbPath !== ledger.thumbPath ||
      !/^[1-9][0-9]*$/.test(String(ledger.objects?.thumb?.generation ?? "")) ||
      !/^[1-9][0-9]*$/.test(String(ledger.objects?.detail?.generation ?? ""))) {
    throw new Error("Q7_PUBLISHED_COVER_LEDGER_MISMATCH");
  }
  return {kind: "cover", sourceURL: season.coverRemoteURL,
    thumbPath: ledger.thumbPath, detailPath: ledger.detailPath,
    thumbGeneration: ledger.objects.thumb.generation,
    detailGeneration: ledger.objects.detail.generation};
}
