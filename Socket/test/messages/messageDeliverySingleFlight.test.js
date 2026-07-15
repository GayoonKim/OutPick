import assert from "node:assert/strict";
import test from "node:test";

import {
  buildMessageDeliveryKey,
  createMessageDeliverySingleFlight
} from "../../src/messages/messageDeliverySingleFlight.js";

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

test("같은 message identity의 동시 요청은 owner operation을 한 번만 실행한다", async () => {
  const gate = deferred();
  const singleFlight = createMessageDeliverySingleFlight();
  let operationCount = 0;
  const identity = { kind: "text", roomID: "room", messageID: "message" };
  const operation = async () => {
    operationCount += 1;
    return gate.promise;
  };

  const owner = singleFlight.run(identity, operation);
  const follower = singleFlight.run(identity, operation);
  gate.resolve({ seq: 7, created: true });

  assert.deepEqual(await owner, {
    value: { seq: 7, created: true },
    duplicate: false
  });
  assert.deepEqual(await follower, {
    value: { seq: 7, created: true },
    duplicate: true
  });
  assert.equal(operationCount, 1);
});

test("kind, roomID와 messageID가 다른 요청은 서로 병합하지 않는다", async () => {
  const singleFlight = createMessageDeliverySingleFlight();
  let operationCount = 0;
  const run = (identity) => singleFlight.run(identity, async () => {
    operationCount += 1;
    return operationCount;
  });

  const results = await Promise.all([
    run({ kind: "text", roomID: "room", messageID: "message" }),
    run({ kind: "lookbook", roomID: "room", messageID: "message" }),
    run({ kind: "text", roomID: "other-room", messageID: "message" }),
    run({ kind: "text", roomID: "room", messageID: "other-message" })
  ]);

  assert.equal(operationCount, 4);
  assert.equal(results.every((result) => result.duplicate === false), true);
  assert.notEqual(
    buildMessageDeliveryKey({ kind: "images", roomID: "a:b", messageID: "c" }),
    buildMessageDeliveryKey({ kind: "images", roomID: "a", messageID: "b:c" })
  );
});

test("owner 실패를 follower와 공유하고 entry를 제거해 재시도를 허용한다", async () => {
  const gate = deferred();
  const singleFlight = createMessageDeliverySingleFlight();
  const identity = { kind: "video", roomID: "room", messageID: "message" };
  const error = new Error("persist failed");
  let operationCount = 0;
  const operation = async () => {
    operationCount += 1;
    return gate.promise;
  };

  const owner = singleFlight.run(identity, operation);
  const follower = singleFlight.run(identity, operation);
  gate.reject(error);

  await assert.rejects(owner, (caught) => caught === error);
  await assert.rejects(follower, (caught) => caught === error);

  const retry = await singleFlight.run(identity, async () => {
    operationCount += 1;
    return { seq: 8, created: true };
  });
  assert.deepEqual(retry, {
    value: { seq: 8, created: true },
    duplicate: false
  });
  assert.equal(operationCount, 2);
});

test("지원하지 않는 kind와 빈 identity를 거부한다", () => {
  assert.throws(
    () => buildMessageDeliveryKey({ kind: "audio", roomID: "room", messageID: "message" }),
    /unsupported message kind/
  );
  assert.throws(
    () => buildMessageDeliveryKey({ kind: "text", roomID: "", messageID: "message" }),
    /roomID must be a non-empty string/
  );
});
