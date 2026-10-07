import assert from "node:assert/strict";
import test from "node:test";
import {parseRecoveryCLICommand} from "./recovery-cli.js";

const env = {
  OUTPICK_IMPORT_RECOVERY_URL:
    "https://lookbook-import-worker-development-xyenspjiwa-du.a.run.app",
  OUTPICK_IMPORT_RECOVERY_AUDIENCE:
    "https://lookbook-import-worker-development-xyenspjiwa-du.a.run.app",
  OUTPICK_IMPORT_RECOVERY_SERVICE_ACCOUNT_EMAIL:
    "lookbook-import-recovery@outpick-test.iam.gserviceaccount.com",
};
const target = ["--project=outpick-test",
  "--service=lookbook-import-worker-development",
  "--revision=lookbook-import-worker-development-00002-test",
  `--batch=${"a".repeat(64)}`, "--epoch=4"];

test("PQ14 복구 CLI는 inspect와 동일한 환경·batch·epoch 입력만 구성한다", () => {
  const command = parseRecoveryCLICommand(["inspect", ...target], env);
  assert.equal(command.mode, "inspect");
  assert.equal(command.target.expectedEpoch, 4);
  assert.equal(command.target.batchID, "a".repeat(64));
  assert.equal(command.serviceAccountEmail,
    "lookbook-import-recovery@outpick-test.iam.gserviceaccount.com");
});

test("PQ14 resume와 correction 정산은 보고서 digest·상태 revision·결정 ID를 요구한다", () => {
  assert.throws(() => parseRecoveryCLICommand(["resume", ...target], env),
    /RECOVERY_CLI_DECISION_CONFIRMATION_REQUIRED/);
  const command = parseRecoveryCLICommand(["resume", ...target,
    `--report-digest=${"b".repeat(64)}`, "--state-revision=7",
    "--decision-id=11111111-1111-4111-8111-111111111111"], env);
  assert.equal(command.mode, "resume");
  assert.equal(command.expectedStateRevision, 7);
  assert.equal(command.decisionID, "11111111-1111-4111-8111-111111111111");
  const settlement = parseRecoveryCLICommand(["settle-correction", ...target,
    `--report-digest=${"c".repeat(64)}`, "--state-revision=7",
    "--decision-id=22222222-2222-4222-8222-222222222222"], env);
  assert.equal(settlement.mode, "settle-correction");
  assert.equal(settlement.reportDigest, "c".repeat(64));
  assert.throws(() => parseRecoveryCLICommand(["inspect", ...target,
    "--force=true"], env), /RECOVERY_CLI_ARGUMENT_UNKNOWN/);
  assert.throws(() => parseRecoveryCLICommand(["inspect", ...target], {
    ...env, OUTPICK_IMPORT_RECOVERY_SERVICE_ACCOUNT_EMAIL:
      "other@outpick-664ae.iam.gserviceaccount.com",
  }), /RECOVERY_CLI_ACCOUNT_PROJECT_MISMATCH/);
});
