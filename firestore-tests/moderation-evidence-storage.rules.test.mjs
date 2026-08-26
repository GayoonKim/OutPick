import {after, before, describe, test} from "node:test";
import {readFileSync} from "node:fs";
import {assertFails, initializeTestEnvironment} from "@firebase/rules-unit-testing";

const projectId = "outpick-rules-test";
const storageRules = readFileSync(new URL("../storage.moderation-evidence.rules", import.meta.url), "utf8");
let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    storage: {host: "127.0.0.1", port: 9199, rules: storageRules},
  });
});

after(async () => testEnvironment.cleanup());

describe("moderation Evidence Storage 클라이언트 경계", () => {
  test("인증 여부와 무관하게 read/write/delete를 모두 거부한다", async () => {
    const authenticated = testEnvironment.authenticatedContext("admin-like-user");
    const reference = authenticated.storage().ref("bundle/g0/attachment/display");
    await assertFails(reference.put(new Uint8Array([1, 2, 3]), {contentType: "image/jpeg"}));
    await assertFails(reference.getDownloadURL());
    await assertFails(reference.delete());
  });
});
