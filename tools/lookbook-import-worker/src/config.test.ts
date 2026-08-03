import assert from "node:assert/strict";
import test from "node:test";

import {loadConfig} from "./config.js";

const baseEnv = {
  OUTPICK_FIREBASE_PROJECT_ID: "outpick-test",
  OUTPICK_FIREBASE_STORAGE_BUCKET: "outpick-test.firebasestorage.app",
  OUTPICK_IMPORT_OIDC_AUDIENCE:
    "https://lookbook-import-worker-development-xyenspjiwa-du.a.run.app",
  OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL:
    "outpick-lookbook-task-dev@outpick-test.iam.gserviceaccount.com",
  OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL:
    "86635107099-compute@developer.gserviceaccount.com",
};

test("asset sync concurrency는 미설정 시 기본값 3을 사용한다", () => {
  const config = loadConfig(baseEnv);

  assert.equal(config.assetSyncConcurrency, 3);
});

test("asset sync concurrency는 1 이상 8 이하 값을 허용한다", () => {
  assert.equal(
    loadConfig({
      ...baseEnv,
      OUTPICK_IMPORT_ASSET_SYNC_CONCURRENCY: "1",
    }).assetSyncConcurrency,
    1,
  );
  assert.equal(
    loadConfig({
      ...baseEnv,
      OUTPICK_IMPORT_ASSET_SYNC_CONCURRENCY: "8",
    }).assetSyncConcurrency,
    8,
  );
});

test("asset sync concurrency가 범위를 벗어나면 config error를 던진다", () => {
  assert.throws(
    () => loadConfig({
      ...baseEnv,
      OUTPICK_IMPORT_ASSET_SYNC_CONCURRENCY: "0",
    }),
    /OUTPICK_IMPORT_ASSET_SYNC_CONCURRENCY/,
  );
  assert.throws(
    () => loadConfig({
      ...baseEnv,
      OUTPICK_IMPORT_ASSET_SYNC_CONCURRENCY: "9",
    }),
    /OUTPICK_IMPORT_ASSET_SYNC_CONCURRENCY/,
  );
  assert.throws(
    () => loadConfig({
      ...baseEnv,
      OUTPICK_IMPORT_ASSET_SYNC_CONCURRENCY: "fast",
    }),
    /OUTPICK_IMPORT_ASSET_SYNC_CONCURRENCY/,
  );
});

test("OIDC audience와 호출 서비스 계정을 fail-fast 검증한다", () => {
  assert.throws(
    () => loadConfig({
      ...baseEnv,
      OUTPICK_IMPORT_OIDC_AUDIENCE: "http://worker.example.com",
    }),
    /OUTPICK_IMPORT_OIDC_AUDIENCE/,
  );
  assert.throws(
    () => loadConfig({
      ...baseEnv,
      OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL: "user@example.com",
    }),
    /OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL/,
  );
  assert.throws(
    () => loadConfig({
      ...baseEnv,
      OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL: "",
    }),
    /OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL/,
  );
});

test("Storage bucket 누락을 시작 전에 거부한다", () => {
  assert.throws(
    () => loadConfig({
      ...baseEnv,
      OUTPICK_FIREBASE_STORAGE_BUCKET: "",
    }),
    /OUTPICK_FIREBASE_STORAGE_BUCKET/,
  );
});

test("Development project에 Production Storage bucket을 주입하면 거부한다", () => {
  assert.throws(
    () => loadConfig({
      ...baseEnv,
      OUTPICK_FIREBASE_STORAGE_BUCKET: "outpick-664ae.appspot.com",
    }),
    /OUTPICK_FIREBASE_STORAGE_BUCKET/,
  );
});

test("Production project에 Development Storage bucket을 주입하면 거부한다", () => {
  assert.throws(
    () => loadConfig({
      OUTPICK_FIREBASE_PROJECT_ID: "outpick-664ae",
      OUTPICK_FIREBASE_STORAGE_BUCKET: "outpick-test.firebasestorage.app",
      OUTPICK_IMPORT_OIDC_AUDIENCE:
        "https://lookbook-import-worker-715386497547.asia-northeast3.run.app",
      OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL:
        "lookbook-import-task-invoker@outpick-664ae.iam.gserviceaccount.com",
      OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL:
        "715386497547-compute@developer.gserviceaccount.com",
    }),
    /OUTPICK_FIREBASE_STORAGE_BUCKET/,
  );
});

test("Production worker 환경 계약도 정확한 조합만 허용한다", () => {
  const config = loadConfig({
    OUTPICK_FIREBASE_PROJECT_ID: "outpick-664ae",
    OUTPICK_FIREBASE_STORAGE_BUCKET: "outpick-664ae.appspot.com",
    OUTPICK_IMPORT_OIDC_AUDIENCE:
      "https://lookbook-import-worker-715386497547.asia-northeast3.run.app",
    OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL:
      "lookbook-import-task-invoker@outpick-664ae.iam.gserviceaccount.com",
    OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL:
      "715386497547-compute@developer.gserviceaccount.com",
  });

  assert.equal(config.projectID, "outpick-664ae");
  assert.equal(config.storageBucket, "outpick-664ae.appspot.com");
});

test("Development project에 Production 호출 계정을 주입하면 거부한다", () => {
  assert.throws(
    () => loadConfig({
      ...baseEnv,
      OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL:
        "lookbook-import-task-invoker@outpick-664ae.iam.gserviceaccount.com",
    }),
    /OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL/,
  );
  assert.throws(
    () => loadConfig({
      ...baseEnv,
      OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL:
        "715386497547-compute@developer.gserviceaccount.com",
    }),
    /OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL/,
  );
});

test("임의의 유효한 OIDC 설정과 미지원 project를 거부한다", () => {
  assert.throws(
    () => loadConfig({
      ...baseEnv,
      OUTPICK_IMPORT_OIDC_AUDIENCE: "https://other-worker.example.run.app",
    }),
    /OUTPICK_IMPORT_OIDC_AUDIENCE/,
  );
  assert.throws(
    () => loadConfig({
      ...baseEnv,
      OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL:
        "other-task@outpick-test.iam.gserviceaccount.com",
    }),
    /OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL/,
  );
  assert.throws(
    () => loadConfig({
      ...baseEnv,
      OUTPICK_FIREBASE_PROJECT_ID: "other-project",
    }),
    /OUTPICK_FIREBASE_PROJECT_ID/,
  );
});
