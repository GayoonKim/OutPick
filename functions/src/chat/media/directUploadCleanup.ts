import {
  Timestamp, type Firestore, type DocumentReference,
} from "firebase-admin/firestore";

type Target = {path: string};

/**
 * 확정과 같은 원장을 먼저 잠근 뒤 미완료 파일만 정리한다.
 * @param {object} input 정리 원장과 generation 조건 삭제 의존성
 */
export async function cleanupDirectUpload(input: {
  firestore: Firestore;
  ref: DocumentReference;
  nowMillis: number;
  remove: (bucket: string, path: string) => Promise<void>;
}): Promise<void> {
  const claim = await input.firestore.runTransaction(async (tx) => {
    const snapshot = await tx.get(input.ref);
    const data = snapshot.data();
    if (!data || data.contractVersion !== 3 ||
        data.processingStatus === "ready" ||
        !(data.cleanupAfter instanceof Timestamp) ||
        data.cleanupAfter.toMillis() > input.nowMillis) return null;
    const roomRef = input.ref.parent.parent;
    if (!roomRef) return null;
    const message = await tx.get(roomRef.collection("Messages")
      .doc(input.ref.id));
    if (message.exists) return null;
    const prefix = "rooms/" + data.roomID +
      "/messages/" + data.uploadID + "/attachments/";
    const targets: Target[] = Array.isArray(data.targets) ? data.targets : [];
    tx.update(input.ref, {
      processingStatus: data.processingStatus === "uploading" ?
        "expired" : data.processingStatus,
      // 만료 전에 시작된 늦은 PUT도 재정리할 수 있도록 원장 보존 중 반복 확인한다.
      cleanupAfter: Timestamp.fromMillis(input.nowMillis + 15 * 60_000),
      cleanupStatus: "pending",
    });
    return {bucket: String(data.bucket), paths: targets.map((t) => t.path)
      .filter((p): p is string =>
        typeof p === "string" && p.startsWith(prefix))};
  });
  if (!claim) return;
  for (const path of claim.paths) await input.remove(claim.bucket, path);
}
