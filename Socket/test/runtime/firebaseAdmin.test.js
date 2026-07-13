import assert from "node:assert/strict";
import test from "node:test";

import { initializeFirebaseAdmin } from "../../src/firebaseAdmin.js";

function makeFirebaseAdmin({ initialized = false } = {}) {
  const calls = [];
  const db = { kind: "db" };
  return {
    calls,
    admin: {
      apps: initialized ? [{}] : [],
      credential: {
        applicationDefault: () => ({ kind: "adc" }),
        cert: (value) => ({ kind: "cert", value })
      },
      initializeApp: (options) => calls.push(options),
      firestore: () => db
    },
    db
  };
}

test("ADC로 명시적으로 Firebase Admin을 초기화하고 db를 반환한다", () => {
  const fake = makeFirebaseAdmin();
  const result = initializeFirebaseAdmin({
    env: {},
    firebaseAdmin: fake.admin
  });

  assert.equal(fake.calls.length, 1);
  assert.equal(fake.calls[0].credential.kind, "adc");
  assert.equal(fake.calls[0].storageBucket, "outpick-664ae.appspot.com");
  assert.equal(result.admin, fake.admin);
  assert.equal(result.db, fake.db);
});

test("service account JSON과 storage bucket 환경값을 보존한다", () => {
  const fake = makeFirebaseAdmin();
  initializeFirebaseAdmin({
    env: {
      FIREBASE_SERVICE_ACCOUNT_JSON: '{"project_id":"outpick-test"}',
      OUTPICK_FIREBASE_STORAGE_BUCKET: "test-bucket"
    },
    firebaseAdmin: fake.admin
  });

  assert.equal(fake.calls.length, 1);
  assert.equal(fake.calls[0].credential.kind, "cert");
  assert.deepEqual(fake.calls[0].credential.value, { project_id: "outpick-test" });
  assert.equal(fake.calls[0].storageBucket, "test-bucket");
});

test("이미 초기화된 Admin app은 다시 초기화하지 않는다", () => {
  const fake = makeFirebaseAdmin({ initialized: true });
  initializeFirebaseAdmin({ env: {}, firebaseAdmin: fake.admin });
  assert.equal(fake.calls.length, 0);
});
