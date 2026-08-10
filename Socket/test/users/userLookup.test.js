import assert from "node:assert/strict";
import test from "node:test";
import { createUserLookup } from "../../src/users/userLookup.js";

test("통합 account listener는 계정·제재 상태 문서와 누락을 전달한다", () => {
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
    data: () => ({
      accountStatus: "active", moderationStatus: "restricted", stateVersion: 2
    })
  });
  snapshotHandler({ exists: false });
  assert.deepEqual(values, [
    { accountStatus: "active", moderationStatus: "restricted", stateVersion: 2 },
    null
  ]);
});
