import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';

// 장치 ID는 실행 시 주입한다. 계정/로그인 내용·호스트 파일 경로를 앱 인자로 넘기지 않는다.
const device = process.env.OUTPICK_BRAND_LOCAL_DEVICE_UDID;
const index = process.argv.indexOf('-resultBundlePath');
if (!/^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{16}$/.test(device ?? '') || index < 0 || !process.argv[index + 1]) {
  throw Error('승인된 실기기 ID와 게이트 결과 경로가 필요합니다.');
}
const bundle = resolve(process.argv[index + 1]);
if (!bundle.startsWith(resolve('output') + '/')) throw Error('검사 출력 범위가 아닙니다.');
const environment = Object.fromEntries(['PATH', 'HOME', 'USER', 'LOGNAME', 'SHELL', 'TMPDIR', 'DEVELOPER_DIR', 'LANG', 'LC_ALL']
  .filter(key => process.env[key] !== undefined).map(key => [key, process.env[key]]));
const result = spawnSync('xcodebuild', ['test', '-project', 'OutPick.xcodeproj', '-scheme', 'OutPick-Development',
  '-configuration', 'Development-Debug', '-destination', `platform=iOS,id=${device}`, '-parallel-testing-enabled', 'NO',
  '-derivedDataPath', 'output/brand-device-derived-data',
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) OUTPICK_BRAND_LOCAL_DEVICE',
  'OUTPICK_DEBUG_INFOPLIST_FILE=output/brand-operations-b5/device-l163/DeviceQA-Info.plist',
  '-only-testing:OutPickUITests/BrandLocalUISimulatorTests/testDeviceCompletedRequestAndPublishedImagesWithoutWrites',
  '-resultBundlePath', bundle], {env: environment, stdio: 'inherit'});
process.exit(result.status ?? 1);
