import assert from "node:assert/strict";
import test from "node:test";

import {loadConfig} from "./config.js";

const baseEnv = {
  OUTPICK_FIREBASE_PROJECT_ID: "outpick-test",
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
