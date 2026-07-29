/* eslint-disable require-jsdoc, max-len */
import {randomUUID} from "node:crypto";
import {FieldValue} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../core/firebase.js";
import {requireActiveAccountData} from "../shared/accountStatus.js";
import {
  CompleteOnboardingInput,
  CompleteOnboardingResult,
  CheckNicknameAvailabilityResult,
  CURRENT_ONBOARDING_VERSION,
  PublicProfilePatch,
  UpdatePublicProfileResult,
  UpdateStylePreferencesResult,
} from "./contracts.js";
import {nicknameIndexID, normalizeNicknameDisplay} from "./policy.js";

function assertMoodSnapshotsActive(
  snapshots: FirebaseFirestore.DocumentSnapshot[],
): void {
  if (snapshots.some((snapshot) => !snapshot.exists || snapshot.data()?.status !== "active")) {
    throw new HttpsError(
      "failed-precondition",
      "현재 선택할 수 없는 관심 무드가 포함되어 있습니다.",
    );
  }
}

function assertNicknameAvailable(
  snapshot: FirebaseFirestore.DocumentSnapshot,
  uid: string,
): void {
  if (snapshot.exists && snapshot.data()?.uid !== uid) {
    throw new HttpsError("already-exists", "이미 사용 중인 닉네임입니다.");
  }
}

export async function checkNicknameAvailabilityRecord(
  uid: string,
  nickname: string,
): Promise<CheckNicknameAvailabilityResult> {
  const snapshot = await db
    .collection("nicknameIndex")
    .doc(nicknameIndexID(nickname))
    .get();
  return {
    isAvailable: !snapshot.exists || snapshot.data()?.uid === uid,
  };
}

export async function completeOnboardingRecord(
  uid: string,
  input: CompleteOnboardingInput,
): Promise<CompleteOnboardingResult> {
  const userRef = db.collection("users").doc(uid);
  const publicProfileRef = db.collection("userPublicProfiles").doc(uid);
  const nicknameRef = db.collection("nicknameIndex").doc(nicknameIndexID(input.nickname));
  const moodRefs = input.selectedMoodIDs.map((moodID) =>
    db.collection("styleMoods").doc(moodID),
  );

  await db.runTransaction(async (transaction) => {
    const [userSnapshot, publicProfileSnapshot, nicknameSnapshot, ...moodSnapshots] =
      await Promise.all([
        transaction.get(userRef),
        transaction.get(publicProfileRef),
        transaction.get(nicknameRef),
        ...moodRefs.map((reference) => transaction.get(reference)),
      ]);

    if (userSnapshot.exists || publicProfileSnapshot.exists) {
      throw new HttpsError("already-exists", "이미 온보딩을 완료한 계정입니다.");
    }
    assertNicknameAvailable(nicknameSnapshot, uid);
    assertMoodSnapshotsActive(moodSnapshots);

    const timestamp = FieldValue.serverTimestamp();
    transaction.create(userRef, {
      onboardingVersion: CURRENT_ONBOARDING_VERSION,
      selectedMoodIDs: input.selectedMoodIDs,
      accountStatus: "active",
      accountGenerationID: randomUUID(),
      onboardingCompletedAt: timestamp,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    transaction.create(publicProfileRef, {
      nickname: input.nickname,
      avatarThumbPath: input.avatarThumbPath,
      avatarOriginalPath: input.avatarOriginalPath,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    transaction.set(nicknameRef, {
      uid,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
  });

  return {
    userID: uid,
    onboardingVersion: CURRENT_ONBOARDING_VERSION,
  };
}

export async function updatePublicProfileRecord(
  uid: string,
  patch: PublicProfilePatch,
): Promise<UpdatePublicProfileResult> {
  const userRef = db.collection("users").doc(uid);
  const publicProfileRef = db.collection("userPublicProfiles").doc(uid);

  return db.runTransaction(async (transaction) => {
    const [userSnapshot, publicProfileSnapshot] = await Promise.all([
      transaction.get(userRef),
      transaction.get(publicProfileRef),
    ]);
    requireActiveAccountData(userSnapshot.exists ? userSnapshot.data() : undefined);
    if (!publicProfileSnapshot.exists) {
      throw new HttpsError("failed-precondition", "공개 프로필을 찾을 수 없습니다.");
    }

    const current = publicProfileSnapshot.data() ?? {};
    const currentNickname = normalizeNicknameDisplay(current.nickname);
    const nextNickname = patch.nickname ?? currentNickname;
    const oldNicknameRef = db.collection("nicknameIndex").doc(nicknameIndexID(currentNickname));
    const newNicknameRef = db.collection("nicknameIndex").doc(nicknameIndexID(nextNickname));
    const [oldNicknameSnapshot, newNicknameSnapshot] = await Promise.all([
      transaction.get(oldNicknameRef),
      transaction.get(newNicknameRef),
    ]);

    if (!oldNicknameSnapshot.exists || oldNicknameSnapshot.data()?.uid !== uid) {
      throw new HttpsError(
        "failed-precondition",
        "현재 닉네임 인덱스가 일치하지 않습니다.",
      );
    }
    assertNicknameAvailable(newNicknameSnapshot, uid);

    const timestamp = FieldValue.serverTimestamp();
    const update: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
      updatedAt: timestamp,
    };
    if (patch.nickname !== undefined) {
      update.nickname = nextNickname;
    }
    if (patch.avatarThumbPath !== undefined) {
      update.avatarThumbPath = patch.avatarThumbPath;
    }
    if (patch.avatarOriginalPath !== undefined) {
      update.avatarOriginalPath = patch.avatarOriginalPath;
    }
    transaction.update(publicProfileRef, update);

    if (oldNicknameRef.path !== newNicknameRef.path) {
      transaction.delete(oldNicknameRef);
      transaction.set(newNicknameRef, {
        uid,
        createdAt: timestamp,
        updatedAt: timestamp,
      });
    } else if (patch.nickname !== undefined) {
      transaction.update(newNicknameRef, {updatedAt: timestamp});
    }

    return {
      userID: uid,
      nickname: nextNickname,
      avatarThumbPath: patch.avatarThumbPath !== undefined ?
        patch.avatarThumbPath :
        (current.avatarThumbPath ?? null),
      avatarOriginalPath: patch.avatarOriginalPath !== undefined ?
        patch.avatarOriginalPath :
        (current.avatarOriginalPath ?? null),
    };
  });
}

export async function updateStylePreferencesRecord(
  uid: string,
  selectedMoodIDs: string[],
): Promise<UpdateStylePreferencesResult> {
  const userRef = db.collection("users").doc(uid);
  const moodRefs = selectedMoodIDs.map((moodID) =>
    db.collection("styleMoods").doc(moodID),
  );

  await db.runTransaction(async (transaction) => {
    const [userSnapshot, ...moodSnapshots] = await Promise.all([
      transaction.get(userRef),
      ...moodRefs.map((reference) => transaction.get(reference)),
    ]);
    requireActiveAccountData(userSnapshot.exists ? userSnapshot.data() : undefined);
    assertMoodSnapshotsActive(moodSnapshots);
    transaction.update(userRef, {
      selectedMoodIDs,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return {userID: uid, selectedMoodIDs};
}
