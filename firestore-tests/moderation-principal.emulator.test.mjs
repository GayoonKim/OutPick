import assert from "node:assert/strict";
import {after, beforeEach, describe, test} from "node:test";
import {db} from "../functions/lib/core/firebase.js";
import {moderationAliasID} from "../functions/lib/moderation/identity.js";
import {bindModerationPrincipal} from "../functions/lib/moderation/state.js";
import {removePrivateState} from "../functions/lib/accountDeletion/cleanup.js";

const identity = {provider: "google", subject: "stable-provider-subject"};
const secret = "emulator-only-moderation-secret";

async function clearFixtures() {
  await Promise.all([
    db.recursiveDelete(db.collection("moderationAccounts")),
    db.recursiveDelete(db.collection("moderationPrincipalAliases")),
    db.recursiveDelete(db.collection("moderationPrincipals")),
  ]);
}

beforeEach(clearFixtures);
after(clearFixtures);

describe("moderation principal binding transaction", () => {
  test("동시 재가입 UID는 같은 provider alias와 principal에 수렴한다", async () => {
    await Promise.all([
      bindModerationPrincipal("moderation-uid-a", identity, secret),
      bindModerationPrincipal("moderation-uid-b", identity, secret),
    ]);

    const [accountA, accountB, alias] = await Promise.all([
      db.collection("moderationAccounts").doc("moderation-uid-a").get(),
      db.collection("moderationAccounts").doc("moderation-uid-b").get(),
      db.collection("moderationPrincipalAliases")
        .doc(moderationAliasID(identity, secret))
        .get(),
    ]);
    assert.equal(accountA.data()?.moderationPrincipalID,
      accountB.data()?.moderationPrincipalID);
    assert.equal(alias.data()?.moderationPrincipalID,
      accountA.data()?.moderationPrincipalID);
    assert.equal(JSON.stringify(alias.data()).includes(identity.subject), false);
  });

  test("기존 principal의 suspended 제재를 새 UID projection에 복원한다", async () => {
    await bindModerationPrincipal("moderation-old-uid", identity, secret);
    const oldAccount = await db.collection("moderationAccounts")
      .doc("moderation-old-uid")
      .get();
    const principalID = oldAccount.data()?.moderationPrincipalID;
    await db.collection("moderationPrincipals").doc(principalID).update({
      moderationStatus: "suspended",
      stateVersion: 2,
    });

    const state = await bindModerationPrincipal(
      "moderation-new-uid", identity, secret,
    );
    const newAccount = await db.collection("moderationAccounts")
      .doc("moderation-new-uid")
      .get();
    assert.equal(state.moderationStatus, "suspended");
    assert.equal(newAccount.data()?.moderationPrincipalID, principalID);
    assert.equal(newAccount.data()?.moderationStatus, "suspended");
  });

  test("key 회전은 old alias로 조회하고 new alias를 같은 principal에 추가한다", async () => {
    await bindModerationPrincipal("moderation-key-v1", identity, secret);
    const oldAliasID = moderationAliasID(identity, secret, 1);
    const oldAlias = await db.collection("moderationPrincipalAliases")
      .doc(oldAliasID)
      .get();

    await bindModerationPrincipal(
      "moderation-key-v2",
      identity,
      {version: 2, secret: "emulator-new-secret"},
      new Date(),
      [{version: 1, secret}],
    );
    const newAlias = await db.collection("moderationPrincipalAliases")
      .doc(moderationAliasID(identity, "emulator-new-secret", 2))
      .get();
    assert.equal(newAlias.exists, true);
    assert.equal(newAlias.data()?.moderationPrincipalID,
      oldAlias.data()?.moderationPrincipalID);
  });

  test("계정 삭제는 UID projection만 제거하고 principal과 alias를 보존한다", async () => {
    const uid = "moderation-deleted-uid";
    await db.collection("users").doc(uid).set({accountStatus: "active"});
    await bindModerationPrincipal(uid, identity, secret);
    const account = await db.collection("moderationAccounts").doc(uid).get();
    const principalID = account.data()?.moderationPrincipalID;

    await removePrivateState(uid);
    const [deletedAccount, principal, alias] = await Promise.all([
      db.collection("moderationAccounts").doc(uid).get(),
      db.collection("moderationPrincipals").doc(principalID).get(),
      db.collection("moderationPrincipalAliases")
        .doc(moderationAliasID(identity, secret))
        .get(),
    ]);
    assert.equal(deletedAccount.exists, false);
    assert.equal(principal.exists, true);
    assert.equal(alias.exists, true);
  });
});
