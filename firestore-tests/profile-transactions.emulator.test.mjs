import assert from "node:assert/strict";
import {before, describe, test} from "node:test";
import {db} from "../functions/lib/core/firebase.js";
import {
  completeOnboardingRecord,
  updatePublicProfileRecord,
} from "../functions/lib/profile/profileTransaction.js";
import {nicknameIndexID} from "../functions/lib/profile/policy.js";

before(async () => {
  await Promise.all([
    db.collection("styleMoods").doc("transaction-minimal").set({
      displayName: "미니멀",
      status: "active",
      sortOrder: 1,
    }),
    db.collection("styleMoods").doc("transaction-inactive").set({
      displayName: "비활성",
      status: "inactive",
      sortOrder: 2,
    }),
  ]);
});

function onboardingInput(nickname) {
  return {
    nickname,
    selectedMoodIDs: ["transaction-minimal"],
    avatarThumbPath: null,
    avatarOriginalPath: null,
  };
}

describe("profile transactions", () => {
  test("동시 온보딩에서 같은 닉네임은 한 사용자만 획득한다", async () => {
    const nickname = "동시닉네임";
    const results = await Promise.allSettled([
      completeOnboardingRecord(
        "transaction-user-a",
        onboardingInput(nickname),
      ),
      completeOnboardingRecord(
        "transaction-user-b",
        onboardingInput(nickname),
      ),
    ]);

    assert.equal(
      results.filter((result) => result.status === "fulfilled").length,
      1,
    );
    assert.equal(
      results.filter((result) =>
        result.status === "rejected" &&
        result.reason?.code === "already-exists"
      ).length,
      1,
    );

    const [users, publicProfiles, nicknameIndex] = await Promise.all([
      db.collection("users")
        .where("__name__", "in", [
          "transaction-user-a",
          "transaction-user-b",
        ])
        .get(),
      db.collection("userPublicProfiles")
        .where("nickname", "==", nickname)
        .get(),
      db.collection("nicknameIndex")
        .doc(nicknameIndexID(nickname))
        .get(),
    ]);
    assert.equal(users.size, 1);
    assert.equal(publicProfiles.size, 1);
    assert.equal(nicknameIndex.exists, true);
  });

  test("inactive 무드가 포함되면 온보딩 문서를 하나도 만들지 않는다", async () => {
    await assert.rejects(
      completeOnboardingRecord("transaction-inactive-user", {
        ...onboardingInput("비활성무드닉네임"),
        selectedMoodIDs: ["transaction-inactive"],
      }),
      (error) => error.code === "failed-precondition",
    );

    const [user, publicProfile] = await Promise.all([
      db.collection("users").doc("transaction-inactive-user").get(),
      db.collection("userPublicProfiles")
        .doc("transaction-inactive-user")
        .get(),
    ]);
    assert.equal(user.exists, false);
    assert.equal(publicProfile.exists, false);
  });

  test("존재하지 않는 무드가 포함되어도 온보딩 문서를 만들지 않는다", async () => {
    await assert.rejects(
      completeOnboardingRecord("transaction-missing-mood-user", {
        ...onboardingInput("없는무드닉네임"),
        selectedMoodIDs: ["transaction-missing"],
      }),
      (error) => error.code === "failed-precondition",
    );

    const user = await db.collection("users")
      .doc("transaction-missing-mood-user")
      .get();
    assert.equal(user.exists, false);
  });

  test("중복 닉네임 프로필 수정은 기존 프로필과 인덱스를 유지한다", async () => {
    await Promise.all([
      completeOnboardingRecord(
        "transaction-update-a",
        onboardingInput("수정사용자에이"),
      ),
      completeOnboardingRecord(
        "transaction-update-b",
        onboardingInput("수정사용자비"),
      ),
    ]);

    await assert.rejects(
      updatePublicProfileRecord("transaction-update-a", {
        nickname: "수정사용자비",
      }),
      (error) => error.code === "already-exists",
    );

    const [profile, oldIndex, conflictingIndex] = await Promise.all([
      db.collection("userPublicProfiles")
        .doc("transaction-update-a")
        .get(),
      db.collection("nicknameIndex")
        .doc(nicknameIndexID("수정사용자에이"))
        .get(),
      db.collection("nicknameIndex")
        .doc(nicknameIndexID("수정사용자비"))
        .get(),
    ]);
    assert.equal(profile.data()?.nickname, "수정사용자에이");
    assert.equal(oldIndex.data()?.uid, "transaction-update-a");
    assert.equal(conflictingIndex.data()?.uid, "transaction-update-b");
  });

  test("닉네임 변경은 새 인덱스를 만들고 기존 인덱스를 해제한다", async () => {
    await completeOnboardingRecord(
      "transaction-rename-user",
      onboardingInput("변경전닉네임"),
    );

    await updatePublicProfileRecord("transaction-rename-user", {
      nickname: "변경후닉네임",
    });

    const [profile, oldIndex, newIndex] = await Promise.all([
      db.collection("userPublicProfiles")
        .doc("transaction-rename-user")
        .get(),
      db.collection("nicknameIndex")
        .doc(nicknameIndexID("변경전닉네임"))
        .get(),
      db.collection("nicknameIndex")
        .doc(nicknameIndexID("변경후닉네임"))
        .get(),
    ]);
    assert.equal(profile.data()?.nickname, "변경후닉네임");
    assert.equal(oldIndex.exists, false);
    assert.equal(newIndex.data()?.uid, "transaction-rename-user");
  });
});
