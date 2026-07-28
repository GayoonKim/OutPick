/* eslint-disable require-jsdoc */
import {FieldValue} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../core/firebase.js";
import {
  CreateStyleMoodInput,
  STYLE_MOOD_SCHEMA_VERSION,
  StyleMoodTerm,
  StyleMoodValues,
  UpdateStyleMoodInput,
} from "./contracts.js";
import {
  resolveStyleMoodUpdate,
  styleMoodTermIndexID,
  styleMoodTerms,
} from "./policy.js";

function valuesFromData(
  data: FirebaseFirestore.DocumentData | undefined
): StyleMoodValues {
  if (
    data === undefined ||
    typeof data.displayName !== "string" ||
    typeof data.normalizedName !== "string" ||
    typeof data.displayGroup !== "string" ||
    !Array.isArray(data.aliases) ||
    typeof data.sortOrder !== "number" ||
    typeof data.isFeaturedInOnboarding !== "boolean" ||
    (data.status !== "active" && data.status !== "inactive")
  ) {
    throw new HttpsError(
      "failed-precondition",
      "저장된 스타일 무드 데이터가 올바르지 않습니다."
    );
  }
  return data as StyleMoodValues;
}

function termReference(term: StyleMoodTerm) {
  return db
    .collection("styleMoodTermIndex")
    .doc(styleMoodTermIndexID(term.normalizedTerm));
}

async function assertTermsAvailable(
  transaction: FirebaseFirestore.Transaction,
  terms: StyleMoodTerm[],
  allowedMoodID: string | null
): Promise<Set<string>> {
  const snapshots = await Promise.all(
    terms.map((term) => transaction.get(termReference(term)))
  );
  const hasConflict = snapshots.some((snapshot) =>
    snapshot.exists && snapshot.data()?.moodID !== allowedMoodID
  );
  if (hasConflict) {
    throw new HttpsError(
      "already-exists",
      "이미 다른 스타일 무드에서 사용하는 이름 또는 alias입니다."
    );
  }
  return new Set(
    snapshots
      .filter((snapshot) => snapshot.exists)
      .map((snapshot) => snapshot.id)
  );
}

function setTermIndexes(
  transaction: FirebaseFirestore.Transaction,
  moodID: string,
  terms: StyleMoodTerm[],
  existingTermIDs: ReadonlySet<string>
): void {
  for (const term of terms) {
    const reference = termReference(term);
    const payload: FirebaseFirestore.DocumentData = {
      moodID,
      termType: term.termType,
    };
    if (!existingTermIDs.has(reference.id)) {
      payload.createdAt = FieldValue.serverTimestamp();
    }
    transaction.set(reference, payload, {merge: true});
  }
}

export async function createStyleMoodRecord(
  input: CreateStyleMoodInput
): Promise<string> {
  const moodRef = input.moodID === null ?
    db.collection("styleMoods").doc() :
    db.collection("styleMoods").doc(input.moodID);
  const terms = styleMoodTerms(input);

  await db.runTransaction(async (transaction) => {
    const moodSnapshot = await transaction.get(moodRef);
    if (moodSnapshot.exists) {
      throw new HttpsError("already-exists", "이미 존재하는 moodID입니다.");
    }
    const existingTermIDs = await assertTermsAvailable(
      transaction,
      terms,
      null
    );

    transaction.set(moodRef, {
      schemaVersion: STYLE_MOOD_SCHEMA_VERSION,
      displayName: input.displayName,
      normalizedName: input.normalizedName,
      displayGroup: input.displayGroup,
      aliases: input.aliases,
      sortOrder: input.sortOrder,
      isFeaturedInOnboarding: input.isFeaturedInOnboarding,
      status: input.status,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    setTermIndexes(transaction, moodRef.id, terms, existingTermIDs);
  });

  return moodRef.id;
}

export async function updateStyleMoodRecord(
  input: UpdateStyleMoodInput
): Promise<void> {
  const moodRef = db.collection("styleMoods").doc(input.moodID);

  await db.runTransaction(async (transaction) => {
    const moodSnapshot = await transaction.get(moodRef);
    if (!moodSnapshot.exists) {
      throw new HttpsError("not-found", "스타일 무드를 찾을 수 없습니다.");
    }

    const current = valuesFromData(moodSnapshot.data());
    const next = resolveStyleMoodUpdate(current, input);
    const previousTerms = styleMoodTerms(current);
    const nextTerms = styleMoodTerms(next);

    const existingTermIDs = await assertTermsAvailable(
      transaction,
      nextTerms,
      input.moodID
    );

    const nextTermIDs = new Set(
      nextTerms.map((term) => styleMoodTermIndexID(term.normalizedTerm))
    );
    for (const term of previousTerms) {
      const indexID = styleMoodTermIndexID(term.normalizedTerm);
      if (!nextTermIDs.has(indexID)) {
        transaction.delete(
          db.collection("styleMoodTermIndex").doc(indexID)
        );
      }
    }

    transaction.update(moodRef, {
      ...next,
      updatedAt: FieldValue.serverTimestamp(),
    });
    setTermIndexes(
      transaction,
      input.moodID,
      nextTerms,
      existingTermIDs
    );
  });
}
