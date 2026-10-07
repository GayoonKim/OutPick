import assert from "node:assert/strict";
import test from "node:test";
import {
  assetKey, assetWritePaths, type AssetPathIdentity,
} from "./asset-paths.js";

const post: AssetPathIdentity = {
  brandID: "brand-a", seasonID: "season-a", jobID: "job-a",
  executionID: "execution-a", epoch: 2, writeID: "write-a",
  kind: "postImage", postID: "post-a", mediaIndex: 0,
  sourceURL: "https://example.com/look.jpg?token=private",
  transformPolicyVersion: "jpeg-v1",
};

test("PQ12 post asset 경로는 실행·epoch·write마다 다르고 입력 URL을 노출하지 않는다", () => {
  const first = assetWritePaths(post);
  const second = assetWritePaths({...post, writeID: "write-b"});
  const nextEpoch = assetWritePaths({...post, epoch: 3, writeID: "write-c"});
  assert.equal(first.thumbPath.endsWith("/thumb.jpg"), true);
  assert.equal(first.detailPath.endsWith("/detail.jpg"), true);
  assert.notEqual(first.thumbPath, second.thumbPath);
  assert.notEqual(first.thumbPath, nextEpoch.thumbPath);
  assert.match(first.thumbPath, /execution-a\/2\/[^/]+\/write-a\/thumb\.jpg$/);
  assert.doesNotMatch(first.thumbPath, /token=private|example\.com/);
  assert.equal(first.assetKey, assetKey(post));
});

test("PQ12 cover 경로는 기존 thumb 파일명 계산 규칙을 유지한다", () => {
  const paths = assetWritePaths({...post, kind: "seasonCover",
    writeID: "cover-write"});
  assert.match(paths.thumbPath, /\/cover_thumb\.jpg$/);
  assert.match(paths.detailPath, /\/cover\.jpg$/);
  assert.match(paths.detailPath,
    /brands\/brand-a\/seasons\/season-a\/imports\/execution-a\/2\/cover\//);
  assert.match(paths.detailPath, /cover-write\/cover\.jpg$/);
});

test("PQ12 비정상 Storage 경로 ID와 media index는 거절한다", () => {
  assert.throws(() => assetWritePaths({...post, writeID: "../overwrite"}),
    /INVALID_ASSET_PATH_ID/);
  assert.throws(() => assetWritePaths({...post, mediaIndex: -1}),
    /INVALID_ASSET_PATH_ID/);
  assert.throws(() => assetWritePaths({...post, brandID: "brand/a"}),
    /INVALID_ASSET_PATH_ID/);
});
