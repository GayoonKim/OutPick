import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const script = 'tools/brand-operations/run-device-ui.mjs';
test('DUI-P01 장치와 게이트 출력이 없거나 범위 밖이면 빌드 전에 중단한다', () => {
  for (const [device, args] of [[undefined, []], ['other', ['-resultBundlePath', 'output/test.xcresult']],
    ['00000000-0000000000000000', ['-resultBundlePath', '/private/tmp/outside.xcresult']]]) {
    const env = {...process.env};
    delete env.OUTPICK_BRAND_LOCAL_DEVICE_UDID;
    if (device) env.OUTPICK_BRAND_LOCAL_DEVICE_UDID = device;
    const result = spawnSync(process.execPath, [script, ...args], {env, encoding: 'utf8'});
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /필요합니다|출력 범위/);
  }
});

test('DUI-P02 실기기 선택1개와 전용 조건만 전달하고 인증 환경과 원격 갱신을 넘기지 않는다', () => {
  const folder = mkdtempSync(join(tmpdir(), 'outpick-device-runner-test-'));
  try {
    writeFileSync(join(folder, 'xcodebuild'), `#!${process.execPath}\nconsole.log(JSON.stringify({args:process.argv.slice(2), envKeys:Object.keys(process.env)}));\n`, {mode: 0o700});
    const result = spawnSync(process.execPath, [script, '-resultBundlePath', 'output/device-fake/test.xcresult'], {
      encoding: 'utf8', env: {...process.env, PATH: folder + ':' + process.env.PATH,
        OUTPICK_BRAND_LOCAL_DEVICE_UDID: '00000000-0000000000000000', OUTPICK_TEST_UNEXPECTED_SECRET: 'synthetic-only'}
    });
    assert.equal(result.status, 0, result.stderr);
    const value = JSON.parse(result.stdout);
    assert.deepEqual(value.args.filter(arg => arg.startsWith('-only-testing:')), [
      '-only-testing:OutPickUITests/BrandLocalUISimulatorTests/testDeviceCompletedRequestAndPublishedImagesWithoutWrites']);
    assert.ok(value.args.includes('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) OUTPICK_BRAND_LOCAL_DEVICE'));
    assert.ok(value.args.includes('platform=iOS,id=00000000-0000000000000000'));
    assert.ok(!value.args.includes('-allowProvisioningUpdates'));
    assert.ok(!value.envKeys.some(key => key.includes('OUTPICK') || key.includes('TOKEN') || key.includes('GOOGLE_APPLICATION_CREDENTIALS')));
  } finally { rmSync(folder, {recursive: true, force: true}); }
});
