/* eslint-disable require-jsdoc */
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../core/firebase.js";

export const MAX_ASSIGNED_STYLE_MOOD_COUNT = 5;

export function requiredStyleMoodIDs(rawValue: unknown): string[] {
  if (!Array.isArray(rawValue)) {
    throw new HttpsError("invalid-argument", "moodIDs 값이 필요합니다.");
  }
  if (rawValue.length > MAX_ASSIGNED_STYLE_MOOD_COUNT) {
    throw new HttpsError(
      "invalid-argument",
      `moodIDs는 최대 ${MAX_ASSIGNED_STYLE_MOOD_COUNT}개까지 선택할 수 있습니다.`
    );
  }

  const moodIDs = rawValue.map((value) => {
    if (
      typeof value !== "string" ||
      value.trim().length === 0 ||
      value.includes("/")
    ) {
      throw new HttpsError(
        "invalid-argument",
        "moodIDs 값이 올바르지 않습니다."
      );
    }
    return value.trim();
  });

  if (new Set(moodIDs).size !== moodIDs.length) {
    throw new HttpsError("invalid-argument", "moodIDs에 중복 값이 있습니다.");
  }
  return moodIDs;
}

export async function assertActiveStyleMoodIDs(
  transaction: FirebaseFirestore.Transaction,
  moodIDs: string[]
): Promise<void> {
  if (moodIDs.length === 0) {
    return;
  }

  const references = moodIDs.map((moodID) =>
    db.collection("styleMoods").doc(moodID)
  );
  const snapshots = await transaction.getAll(...references);
  const invalidMoodID = snapshots.find((snapshot) =>
    !snapshot.exists || snapshot.data()?.status !== "active"
  )?.id;

  if (invalidMoodID !== undefined) {
    throw new HttpsError(
      "failed-precondition",
      `활성 상태가 아닌 스타일 무드입니다: ${invalidMoodID}`
    );
  }
}
