import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFileSync, writeFileSync, appendFileSync, mkdirSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {digest} from './check-submission.mjs';

// 일반 콘솔/오류 원문은 저장하지 않고 기존 계측의 허용된 숫자/열거값만 추출한다.
export function imageMetric(line, keys) {
  const m = /^\[ImageBaseline\] seq=(\d+) t=([\d.]+) id=([0-9A-F-]{36}) parent=(none|[0-9A-F-]{36}) key=([a-f0-9]{24}) stage=([a-zA-Z][a-zA-Z0-9.]{0,63}) action=(begin|end) outcome=([a-zA-Z]*) ms=([\d.]+) active=(\d+) bytes=(\d+) heldBytes=(\d+)$/.exec(line);
  if (!m || !keys.has(m[5]) || !['', 'success', 'completed', 'failure', 'cancelled', 'returnedAfterCancellation', 'memory', 'local', 'hit', 'miss'].includes(m[8])) return null;
  const numbers = [m[1], m[2], m[9], m[10], m[11], m[12]].map(Number);
  if (!numbers.every(Number.isFinite)) return null;
  return {sequence: numbers[0], time: numbers[1], id: m[3], parent: m[4], key: m[5], stage: m[6], action: m[7],
    outcome: m[8], milliseconds: numbers[2], active: numbers[3], bytes: numbers[4], heldBytes: numbers[5]};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const directory = process.env.OUTPICK_IMAGE_QA_OUTPUT;
  const device = process.env.OUTPICK_IMAGE_QA_DEVICE;
  if (!directory || !device) throw new Error('출력 경로와 지정 기기가 필요합니다.');
  const acceptance = JSON.parse(readFileSync(process.env.OUTPICK_BRAND_PUBLICATION_ACCEPTANCE));
  const bytes = readFileSync(acceptance.verifiedFilesPath);
  if (digest(bytes) !== acceptance.verifiedFilesSHA256) throw new Error('게시 파일 근거 지문이 다릅니다.');
  const paths = JSON.parse(bytes).objects.map(item => item.path);
  const keys = new Set(paths.flatMap(path => [path, `imageCache|${path}`]).map(path => digest(path).slice(0, 24)));
  mkdirSync(directory, {recursive: true, mode: 0o700});
  const metadataPath = join(directory, 'capture.json');
  const metricsPath = join(directory, 'image-metrics.jsonl');
  const meta = {schemaVersion: 1, startedAt: new Date().toISOString(), mode: 'normal-development-existing-image-metrics',
    arguments: ['-BrandRequestSDKQA', '-ImageLoadingBaseline'], rawConsoleStored: false,
    allowedPublicationObjects: paths.length, metricCount: 0, sdkSessionID: null};
  writeFileSync(metricsPath, '', {mode: 0o600, flag: 'wx'});
  const save = () => writeFileSync(metadataPath, JSON.stringify(meta, null, 2) + '\n', {mode: 0o600}); save();
  const child = spawn('xcrun', ['devicectl', 'device', 'process', 'launch', '--device', device,
    '--terminate-existing', '--console', '--json-output', join(directory, 'device-launch.json'),
    '--', 'GayoonKim.OutPick.dev', ...meta.arguments], {stdio: ['ignore', 'pipe', 'pipe']});
  const completion = new Promise(resolve => {
    child.on('close', (code, signal) => resolve({code, signal}));
    child.on('error', () => resolve({code: null, signal: 'launch-error'}));
  });
  child.stderr.resume();
  const lines = createInterface({input: child.stdout});
  for await (const line of lines) {
    const session = /^\[BrandRequestSDKQA\] session ([A-F0-9-]{36})$/.exec(line);
    if (session) { meta.sdkSessionID = session[1]; save(); }
    const metric = imageMetric(line, keys);
    if (metric) { appendFileSync(metricsPath, JSON.stringify(metric) + '\n'); meta.metricCount++; save(); }
  }
  const completed = await completion;
  meta.endedAt = new Date().toISOString(); meta.exitCode = completed.code; meta.signal = completed.signal; save();
}
