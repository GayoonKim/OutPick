import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdirSync, writeFileSync, readFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export function interestFailure(line) {
  const match = /^\[LookbookHomeViewModel\] 관심 스타일 조회 실패: domain=([A-Za-z0-9_.-]{1,80}), code=(-?\d{1,8})$/.exec(line);
  return match ? {domain: match[1], code: Number(match[2])} : null;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const directory = process.env.OUTPICK_INTEREST_QA_OUTPUT;
  const device = process.env.OUTPICK_INTEREST_QA_DEVICE;
  if (!directory || !device) throw new Error('지정 기기와 출력 경로가 필요합니다.');
  mkdirSync(directory, {recursive: true, mode: 0o700});
  const path = join(directory, 'capture.json');
  const meta = {schemaVersion: 1, startedAt: new Date().toISOString(),
    mode: 'existing-normal-development-interest-home-error-console', rawConsoleStored: false,
    source: 'existing LookbookHomeViewModel DEBUG error diagnostic',
    positiveSDKResponseCaptured: false, launchConfirmed: false, launchedNormalApp: false, failures: []};
  const save = () => writeFileSync(path, JSON.stringify(meta, null, 2) + '\n', {mode: 0o600}); save();
  const child = spawn('xcrun', ['devicectl', 'device', 'process', 'launch', '--device', device,
    '--terminate-existing', '--console', '--json-output', join(directory, 'device-launch.json'),
    '--', 'GayoonKim.OutPick.dev'], {stdio: ['ignore', 'pipe', 'pipe']});
  const completion = new Promise(resolve => {
    child.on('close', (code, signal) => resolve({code, signal}));
    child.on('error', () => resolve({code: null, signal: 'launch-error'}));
  });
  child.stderr.resume();
  for await (const line of createInterface({input: child.stdout})) {
    const failure = interestFailure(line);
    if (failure) { meta.failures.push({at: new Date().toISOString(), ...failure}); save(); }
  }
  const completed = await completion;
  try {
    const result = JSON.parse(readFileSync(join(directory, 'device-launch.json'))).result;
    meta.launchConfirmed = Number.isInteger(result?.process?.processIdentifier) && result.process.processIdentifier > 0
      && result.process.executable.endsWith('/OutPick.app/OutPick') && result.terminationResult?.wasCoreDumpCreated !== true;
    meta.launchedNormalApp = Array.isArray(result?.launchOptions?.arguments) && result.launchOptions.arguments.length === 0;
  } catch { /* 원문 없이 실행 미확인 상태를 유지한다. */ }
  meta.endedAt = new Date().toISOString(); meta.exitCode = completed.code; meta.signal = completed.signal; save();
}
