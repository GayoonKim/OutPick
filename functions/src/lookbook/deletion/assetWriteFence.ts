/* eslint-disable require-jsdoc */
import type {Firestore, Query} from "firebase-admin/firestore";

export type LookbookAssetWriteScope = {
  brandID: string;
  seasonID?: string;
  postID?: string;
};

/** 활성 업로드 원장이 남아 있으면 Storage 삭제를 시작하지 않는다.
 * @param {Firestore} db Firestore Admin client
 * @param {LookbookAssetWriteScope} scope 삭제 대상 범위
 * @return {Promise<void>} 활성 작업이 없으면 완료
 */
export async function assertNoActiveLookbookAssetWrites(
  db: Firestore,
  scope: LookbookAssetWriteScope,
): Promise<void> {
  let query: Query = db.collectionGroup("writes")
    .where("status", "==", "uploading");
  if (scope.postID !== undefined && scope.seasonID !== undefined) {
    const targetPath = `brands/${scope.brandID}/seasons/${scope.seasonID}` +
      `/posts/${scope.postID}`;
    query = query.where("targetPath", "==", targetPath);
  } else if (scope.seasonID !== undefined) {
    query = query.where("targetSeasonPath", "==",
      `brands/${scope.brandID}/seasons/${scope.seasonID}`);
  } else {
    query = query.where("brandID", "==", scope.brandID);
  }
  const active = await query.limit(1).get();
  if (!active.empty) {
    throw new Error("LOOKBOOK_ASSET_WRITE_STILL_ACTIVE");
  }
}
