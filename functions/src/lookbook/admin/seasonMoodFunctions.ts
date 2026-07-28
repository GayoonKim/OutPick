/* eslint-disable require-jsdoc */
import {FieldValue} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  recordData,
  requiredAuthUID,
  requiredDocumentID,
  requiredString,
} from "../../core/callable.js";
import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {assertBrandCreationAccess} from "../../shared/brandAuthorization.js";
import {
  assertActiveStyleMoodIDs,
  requiredStyleMoodIDs,
} from "../../shared/styleMoodAssignmentPolicy.js";

interface UpdateSeasonMoodDependencies {
  assertTotalAdmin: (uid: string) => Promise<void>;
  updateRecord: (
    brandID: string,
    seasonID: string,
    moodIDs: string[],
    uid: string
  ) => Promise<void>;
}

async function updateSeasonMoodRecord(
  brandID: string,
  seasonID: string,
  moodIDs: string[],
  uid: string
): Promise<void> {
  const seasonRef = db
    .collection("brands")
    .doc(brandID)
    .collection("seasons")
    .doc(seasonID);

  await db.runTransaction(async (transaction) => {
    const seasonSnapshot = await transaction.get(seasonRef);
    if (!seasonSnapshot.exists) {
      throw new HttpsError("not-found", "시즌을 찾을 수 없습니다.");
    }
    await assertActiveStyleMoodIDs(transaction, moodIDs);
    transaction.update(seasonRef, {
      moodIDs,
      updatedBy: uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

const liveDependencies: UpdateSeasonMoodDependencies = {
  assertTotalAdmin: assertBrandCreationAccess,
  updateRecord: updateSeasonMoodRecord,
};

export async function handleUpdateSeasonMoods(
  authUID: string | undefined,
  rawData: unknown,
  dependencies = liveDependencies
): Promise<{brandID: string; seasonID: string; moodIDs: string[]}> {
  const uid = requiredAuthUID(authUID);
  const data = recordData(rawData);
  const brandID = requiredDocumentID(
    requiredString(data, "brandID", 128),
    "brandID"
  );
  const seasonID = requiredDocumentID(
    requiredString(data, "seasonID", 128),
    "seasonID"
  );
  const moodIDs = requiredStyleMoodIDs(data.moodIDs);

  await dependencies.assertTotalAdmin(uid);
  await dependencies.updateRecord(brandID, seasonID, moodIDs, uid);
  return {brandID, seasonID, moodIDs};
}

export const updateSeasonMoods = onCall(
  {region: FUNCTIONS_REGION},
  async (request) =>
    handleUpdateSeasonMoods(request.auth?.uid, request.data)
);
