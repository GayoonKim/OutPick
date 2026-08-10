import assert from "node:assert/strict";
import {after, beforeEach, describe, test} from "node:test";
import {db} from "../functions/lib/core/firebase.js";
import {
  cancelDeletion,
  createDeletionIntent,
  requestDeletion,
} from "../functions/lib/accountDeletion/repository.js";
import {DELETION_PROCESSING_MS} from "../functions/lib/accountDeletion/policy.js";

const uid = "account-deletion-user";
const context = {
  uid,
  authTimeSeconds: 1_000,
  provider: "google.com",
  providerUserID: null,
};

beforeEach(async () => {
  await Promise.all([
    db.recursiveDelete(db.collection("users").doc(uid)),
    db.recursiveDelete(db.collection("moderationAccounts").doc(uid)),
    db.recursiveDelete(db.collection("accountDeletionIntents")),
    db.recursiveDelete(db.collection("accountDeletionRequests")),
    db.recursiveDelete(db.collection("accountDeletionNotificationOutbox")),
  ]);
  await db.collection("users").doc(uid).set({
    accountStatus: "active",
    accountGenerationID: "generation-a",
  });
  await db.collection("moderationAccounts").doc(uid).set({
    schemaVersion: 2,
    accountStatus: "active",
    moderationStatus: "active",
    stateVersion: 1,
  });
});

after(async () => {
  await Promise.all([
    db.recursiveDelete(db.collection("users").doc(uid)),
    db.recursiveDelete(db.collection("moderationAccounts").doc(uid)),
    db.recursiveDelete(db.collection("accountDeletionIntents")),
    db.recursiveDelete(db.collection("accountDeletionRequests")),
    db.recursiveDelete(db.collection("accountDeletionNotificationOutbox")),
  ]);
});

describe("account deletion transactions", () => {
  test("intent를 한 번 소비해 즉시 pending으로 잠그고 취소 시 복원한다", async () => {
    const now = 1_000_000;
    const intent = await createDeletionIntent(context, now);
    const result = await requestDeletion(context, {
      intentID: intent.intentID,
      nonce: intent.nonce,
    }, now + 1);

    const userAfterRequest = await db.collection("users").doc(uid).get();
    assert.equal(userAfterRequest.data()?.accountStatus, "deletionPending");
    const capabilityAfterRequest = await db.collection("moderationAccounts").doc(uid).get();
    assert.equal(capabilityAfterRequest.data()?.accountStatus, "deletionPending");
    assert.equal(
      Date.parse(result.cancelableUntil) - Date.parse(result.requestedAt),
      DELETION_PROCESSING_MS,
    );
    await assert.rejects(requestDeletion(context, {
      intentID: intent.intentID,
      nonce: intent.nonce,
    }, now + 2));

    const cancellation = await cancelDeletion(context, now + 3);
    assert.equal(cancellation.accountStatus, "active");
    const userAfterCancel = await db.collection("users").doc(uid).get();
    assert.equal(userAfterCancel.data()?.accountStatus, "active");
    const capabilityAfterCancel = await db.collection("moderationAccounts").doc(uid).get();
    assert.equal(capabilityAfterCancel.data()?.accountStatus, "active");
  });

  test("정확한 cancelableUntil 시각부터 취소를 거부한다", async () => {
    const now = 2_000_000;
    const intent = await createDeletionIntent(context, now);
    const result = await requestDeletion(context, {
      intentID: intent.intentID,
      nonce: intent.nonce,
    }, now);
    await assert.rejects(
      cancelDeletion(context, Date.parse(result.cancelableUntil)),
      (error) => error?.code === "failed-precondition",
    );
  });
});
