import assert from "node:assert/strict";
import test from "node:test";
import { createUserLookup } from "../../src/users/userLookup.js";

test("account status listener는 inactive와 조회 실패를 전달한다", () => {
  let snapshotHandler;
  let errorHandler;
  let unsubscribed = false;
  const db = {
    collection: () => ({
      doc: () => ({
        onSnapshot(onSnapshot, onError) {
          snapshotHandler = onSnapshot;
          errorHandler = onError;
          return () => {
            unsubscribed = true;
          };
        }
      })
    })
  };
  const statuses = [];
  const errors = [];
  const { watchUserAccountStatus } = createUserLookup({ db });
  const unsubscribe = watchUserAccountStatus(
    "uid-a",
    (status) => statuses.push(status),
    (error) => errors.push(error.message)
  );

  snapshotHandler({ exists: true, data: () => ({ accountStatus: "active" }) });
  snapshotHandler({
    exists: true,
    data: () => ({ accountStatus: "deletionPending" })
  });
  errorHandler(new Error("watch-failed"));
  unsubscribe();

  assert.deepEqual(statuses, ["deletionPending"]);
  assert.deepEqual(errors, ["watch-failed"]);
  assert.equal(unsubscribed, true);
});

test("moderation account listener는 상태 문서와 누락을 전달한다", () => {
  let snapshotHandler;
  const db = {
    collection: (name) => ({
      doc: () => ({
        onSnapshot(onSnapshot) {
          assert.equal(name, "moderationAccounts");
          snapshotHandler = onSnapshot;
          return () => {};
        }
      })
    })
  };
  const values = [];
  const { watchModerationAccount } = createUserLookup({ db });
  watchModerationAccount("uid-a", (value) => values.push(value));
  snapshotHandler({
    exists: true,
    data: () => ({ moderationStatus: "restricted", stateVersion: 2 })
  });
  snapshotHandler({ exists: false });
  assert.deepEqual(values, [
    { moderationStatus: "restricted", stateVersion: 2 },
    null
  ]);
});
