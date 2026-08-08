import {after, before, beforeEach, describe, test} from "node:test";
import {readFileSync} from "node:fs";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, setDoc} from "firebase/firestore";

const projectId = "outpick-rules-test";
const totalAdminUID = "storage-total-admin";
const brandManagerUID = "storage-brand-manager";
const inactiveAdminUID = "storage-inactive-admin";
const otherUID = "storage-other";
const brandID = "brand-storage-test";
const firestoreRules = readFileSync(
  new URL("../firestore.rules", import.meta.url),
  "utf8",
);
const storageRules = readFileSync(
  new URL("../storage.rules", import.meta.url),
  "utf8",
);

let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules: firestoreRules,
    },
    storage: {
      host: "127.0.0.1",
      port: 9199,
      rules: storageRules,
    },
  });
});

beforeEach(async () => {
  await Promise.all([
    testEnvironment.clearFirestore(),
    testEnvironment.clearStorage(),
  ]);
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await Promise.all([
      setDoc(doc(firestore, "users", totalAdminUID), {
        accountStatus: "active",
      }),
      setDoc(doc(firestore, "users", brandManagerUID), {
        accountStatus: "active",
      }),
      setDoc(doc(firestore, "users", inactiveAdminUID), {
        accountStatus: "deletionPending",
      }),
      setDoc(doc(firestore, "users", otherUID), {
        accountStatus: "active",
      }),
      ...[totalAdminUID, brandManagerUID, inactiveAdminUID, otherUID].map(
        (uid) => setDoc(doc(firestore, "moderationAccounts", uid), {
          moderationStatus: "active", stateVersion: 1,
        }),
      ),
      setDoc(doc(firestore, "brandAdmins", totalAdminUID), {
        isActive: true,
      }),
      setDoc(doc(firestore, "brandAdmins", inactiveAdminUID), {
        isActive: true,
      }),
      setDoc(doc(firestore, "brands", brandID), {
        name: "Storage Test Brand",
      }),
      setDoc(
        doc(firestore, "brands", brandID, "admins", brandManagerUID),
        {
          uid: brandManagerUID,
          role: "admin",
        },
      ),
    ]);
  });
});

after(async () => {
  await testEnvironment.cleanup();
});

function logoReference(context, fileName = "thumb.jpg") {
  return context
    .storage()
    .ref(`brands/${brandID}/logo/${fileName}`);
}

function uploadLogo(reference) {
  return reference.put(
    new Uint8Array([0xff, 0xd8, 0xff, 0xd9]),
    {contentType: "image/jpeg"},
  );
}

describe("brand storage boundary", () => {
  test("active 총 관리자는 브랜드 로고를 업로드할 수 있다", async () => {
    const totalAdmin = testEnvironment.authenticatedContext(totalAdminUID);

    await assertSucceeds(uploadLogo(logoReference(totalAdmin)));
  });

  test("active 브랜드 관리자는 브랜드 로고를 업로드할 수 있다", async () => {
    const brandManager = testEnvironment.authenticatedContext(brandManagerUID);

    await assertSucceeds(uploadLogo(logoReference(brandManager, "detail.jpg")));
  });

  test("비활성 관리자와 권한 없는 사용자의 업로드를 거부한다", async () => {
    const inactiveAdmin = testEnvironment.authenticatedContext(inactiveAdminUID);
    const other = testEnvironment.authenticatedContext(otherUID);

    await assertFails(uploadLogo(logoReference(inactiveAdmin)));
    await assertFails(uploadLogo(logoReference(other)));
  });
});
