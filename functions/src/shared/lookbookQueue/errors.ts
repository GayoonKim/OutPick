/* eslint-disable require-jsdoc, max-len */
import {HttpsError} from "firebase-functions/v2/https";
export function queueAdmissionError(error: unknown): never {
  if (error instanceof HttpsError) throw error;
  const code = error instanceof Error ? error.message : "";
  if (code === "INVALID_CONTRACT") throw new HttpsError("invalid-argument", code);
  if (code === "PERMISSION_DENIED") throw new HttpsError("permission-denied", code);
  if (["REQUEST_NOT_FOUND", "TARGET_DELETED"].includes(code)) throw new HttpsError("not-found", code);
  if (["REQUEST_EXPIRED", "CLOCK_INVALID", "REQUEST_ID_CONFLICT", "SNAPSHOT_STALE",
    "ASSET_RETRY_NOT_ALLOWED"].includes(code)) throw new HttpsError("failed-precondition", code);
  throw new HttpsError("internal", "시즌 접수를 완료하지 못했습니다.");
}
