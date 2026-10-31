import {readFile, stat, writeFile, mkdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {resolve, dirname} from 'node:path';
import {createHash} from 'node:crypto';

// 외부 파일은 실행 시 주입한다. 서버 기동/초기화/종료나 계정 변경을 하지 않는다.
const root = process.cwd();
const preparation = process.argv.includes('--preparation');
const followup = process.argv.includes('--followup');
const published = process.argv.includes('--published');
const detailUI = process.argv.includes('--detail-ui');
const ui = process.argv.includes('--ui') || detailUI;
if ([preparation, followup, published, process.argv.includes('--ui'), detailUI].filter(Boolean).length > 1) throw Error('검사 단계는 하나만 지정하세요.');
// 게시 근거는 Backend 전달 뒤에만 주입한다. 내부 DTO를 해석하거나 복사하지 않는다.
let publication;
if (published) {
  const roundID = process.env.OUTPICK_BRAND_LOCAL_ROUND;
  const groupID = process.env.OUTPICK_BRAND_LOCAL_GROUP;
  const brandID = process.env.OUTPICK_BRAND_LOCAL_BRAND;
  const evidencePath = process.env.OUTPICK_BRAND_LOCAL_PUBLICATION_EVIDENCE;
  if (!/^[a-f0-9-]{36}$/.test(roundID ?? '') || !groupID?.trim() || !brandID?.trim() || !evidencePath) {
    throw Error('게시 완료 전달의 회차/groupID/brandID/근거 경로가 필요합니다.');
  }
  const metadata = await stat(evidencePath);
  if (!metadata.isFile() || metadata.size === 0) throw Error('게시 완료 근거 파일이 필요합니다.');
  publication = {roundID, groupID, brandID, evidencePath: resolve(evidencePath),
    evidenceSHA256: createHash('sha256').update(await readFile(evidencePath)).digest('hex')};
}
const bundleIndex = process.argv.indexOf('-resultBundlePath');
if (bundleIndex < 0 || !process.argv[bundleIndex + 1]) throw Error('게이트 결과 경로가 필요합니다.');
const bundle = resolve(process.argv[bundleIndex + 1]);
if (!bundle.startsWith(resolve(root, 'output') + '/')) throw Error('검사 출력 범위를 확인하세요.');
const uiEvidencePath = resolve(dirname(bundle), 'ui-evidence.json');
const environment = Object.fromEntries(['PATH', 'HOME', 'USER', 'LOGNAME', 'SHELL', 'TMPDIR', 'DEVELOPER_DIR', 'LANG', 'LC_ALL']
  .filter(key => process.env[key] !== undefined).map(key => [key, process.env[key]]));

if (!preparation) {
  const targetPath = process.env.OUTPICK_BRAND_LOCAL_TARGET;
  const loginPath = process.env.OUTPICK_BRAND_LOCAL_LOGIN;
  if (!targetPath || !loginPath) throw Error('이번 회차의 target/login 경로가 필요합니다.');
  const raw = await readFile(targetPath);
  const target = JSON.parse(raw);
  if (target.projectID !== 'outpick-test' || target.region !== 'asia-northeast3' ||
      target.allRequiredServicesLocal !== true || target.inheritedCredentials !== false ||
      dirname(resolve(targetPath)) !== dirname(resolve(loginPath))) throw Error('로컬 회차 설정 불일치');
  if (publication && target.directory.split('/').at(-1) !== publication.roundID) throw Error('게시 전달과 로컬 회차 불일치');
  if (ui) {
    const storagePath = process.env.OUTPICK_BRAND_LOCAL_STORAGE_TARGET;
    const name = process.env.OUTPICK_BRAND_LOCAL_UI_BRAND_NAME;
    if (!storagePath || !name?.trim()) throw Error('Storage target과 기대 브랜드명이 필요합니다.');
    const storageRaw = await readFile(storagePath);
    const storage = JSON.parse(storageRaw);
    if (storage.projectID !== target.projectID || storage.roundID !== target.directory.split('/').at(-1) ||
        storage.firestoreHost !== target.firestoreHost || storage.targetSHA256 !== createHash('sha256').update(raw).digest('hex') ||
        !/^127\.0\.0\.1:[1-9][0-9]{3,4}$/.test(storage.storageHost)) throw Error('Storage 회차/로컬 연결 불일치');
    process.kill(storage.pid, 0);
    const observed = spawnSync('lsof', ['-nP', `-iTCP:${storage.storageHost.split(':')[1]}`, '-sTCP:LISTEN', '-t'], {encoding: 'utf8'});
    if (observed.status !== 0 || !observed.stdout.trim()) throw Error('Storage 리스너가 준비되지 않았습니다.');
    for (let listener of observed.stdout.trim().split('\n').map(Number)) {
      let owned = false;
      for (let depth = 0; depth < 32 && listener > 1; depth++) {
        if (listener === storage.pid) { owned = true; break; }
        const parent = spawnSync('ps', ['-o', 'ppid=', '-p', String(listener)], {encoding:'utf8'});
        if (parent.status !== 0) break;
        listener = Number(parent.stdout.trim());
      }
      if (!owned) throw Error('Storage 리스너 소유권 불일치');
    }
    environment.TEST_RUNNER_OUTPICK_BRAND_LOCAL_STORAGE_TARGET = resolve(storagePath);
    environment.TEST_RUNNER_OUTPICK_BRAND_LOCAL_UI_BRAND_NAME = name;
    await mkdir(dirname(bundle), {recursive:true});
    await writeFile(resolve(dirname(bundle), 'storage-observation.json'), JSON.stringify({
      storageTargetPath: resolve(storagePath), storageTargetSHA256: createHash('sha256').update(storageRaw).digest('hex'),
      storageHost: storage.storageHost, roundID: storage.roundID, ownerPIDAlive: true, listenerOwnershipVerified: true, credentialsIncluded: false,
    }, null, 2) + '\n');
  }
  process.kill(target.pid, 0);
  for (const key of ['authHost', 'functionsHost', 'firestoreHost']) {
    if (!/^127\.0\.0\.1:[1-9][0-9]{3,4}$/.test(target[key])) throw Error('로컬 주소가 필요합니다.');
    const port = Number(target[key].split(':')[1]);
    const observed = spawnSync('lsof', ['-nP', `-iTCP:${port}`, '-sTCP:LISTEN', '-t'], {encoding: 'utf8'});
    const pids = observed.stdout.trim().split('\n').filter(Boolean).map(Number);
    if (observed.status !== 0 || !pids.length || pids.some(pid => !target.listeners[String(port)]?.includes(pid))) {
      throw Error('이번 회차의 소유 리스너가 아닙니다.');
    }
  }
  if (((await stat(loginPath)).mode & 0o777) !== 0o600) throw Error('가상 로그인 파일 권한600이 필요합니다.');
  const login = JSON.parse(await readFile(loginPath));
  if (!login.syntheticLocalOnly || login.projectID !== 'outpick-test' || !login.user?.email || !login.password) {
    throw Error('가상 일반 사용자 설정이 필요합니다.');
  }
  await mkdir(dirname(bundle), {recursive: true});
  const output = resolve(dirname(bundle), 'sdk-evidence.json');
  environment.TEST_RUNNER_OUTPICK_BRAND_LOCAL_TARGET = resolve(targetPath);
  environment.TEST_RUNNER_OUTPICK_BRAND_LOCAL_LOGIN = resolve(loginPath);
  environment.TEST_RUNNER_OUTPICK_BRAND_LOCAL_OUTPUT = ui ? uiEvidencePath : output;
  if (followup || published) {
    const group = process.env.OUTPICK_BRAND_LOCAL_GROUP;
    if (!/^[a-f0-9]{32}$/.test(group ?? '')) throw Error('후속 조회 groupID가 필요합니다.');
    environment.TEST_RUNNER_OUTPICK_BRAND_LOCAL_GROUP = group;
  }
  if (publication) {
    environment.TEST_RUNNER_OUTPICK_BRAND_LOCAL_BRAND = publication.brandID;
    environment.TEST_RUNNER_OUTPICK_BRAND_LOCAL_ROUND = publication.roundID;
    environment.TEST_RUNNER_OUTPICK_BRAND_LOCAL_PUBLICATION_SHA256 = publication.evidenceSHA256;
  }
  await writeFile(resolve(dirname(bundle), 'target-observation.json'), JSON.stringify({
    targetPath: resolve(targetPath), targetSHA256: createHash('sha256').update(raw).digest('hex'),
    roundID: target.directory.split('/').at(-1), projectID: target.projectID, region: target.region,
    authHost: target.authHost, functionsHost: target.functionsHost, firestoreHost: target.firestoreHost,
    generalUserTenant: null, ownerListenersVerified: true, loginMode600: true,
    credentialsCopied: false, observedAt: new Date().toISOString(),
    ...(publication ? {publicationReceipt: publication} : {}),
  }, null, 2) + '\n');
}

const suite = ui ? 'BrandLocalUISimulatorTests/' + (detailUI ? 'testLocalPostsOpenOriginalImagesAndReturnWithoutWrites' : 'testCompletedRequestShowsLocalPublishedImages') :
  preparation ? 'BrandLocalIntegrationPreparationTests' : 'BrandLocalSDKIntegrationTests/' +
  (published ? 'testReadAddedHistoryAndOpenCurrentPublicBrandWithRealLocalSDK()' :
    followup ? 'testReadReviewingHistoryAfterWebProcessingWithRealLocalSDK()' : 'testSubmitDuplicateAndReadInitialHistoryWithRealLocalSDK()');
const args = ['test', '-project', 'OutPick.xcodeproj', '-scheme', 'OutPick-Development',
  '-destination', 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2', '-parallel-testing-enabled', 'NO',
  '-derivedDataPath', 'output/verification-derived-data', 'CODE_SIGNING_ALLOWED=YES',
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) OUTPICK_BRAND_LOCAL_INTEGRATION',
  '-disableAutomaticPackageResolution', `-only-testing:${ui ? 'OutPickUITests' : 'OutPickTests'}/${suite}`, '-resultBundlePath', bundle];
const child = spawnSync('xcodebuild', args, {cwd: root, env: environment, stdio: 'inherit'});
if (child.error) throw Error('로컬 Xcode 검사 시작 실패');
process.exitCode = child.status ?? 1;
if (ui) {
  try {
      const evidence = JSON.parse(await readFile(uiEvidencePath, 'utf8'));
      const downloads = evidence.events.filter(e => ['storage.download', 'storage.downloadFile'].includes(e.kind));
      const decoded = evidence.events.filter(e => ['image.decoded', 'image.fileDecoded'].includes(e.kind) && e.success);
      if (new Set(downloads.map(e => e.path)).size < 3 || decoded.length < 3 ||
          evidence.events.some(e => e.kind === 'image.externalHTTPBlocked')) throw Error('실제 로컬 이미지 근거 미충족');
      if (detailUI && (new Set(downloads.filter(e => e.path.endsWith('/detail.jpg')).map(e => e.path)).size !== 2 || decoded.length < 5 ||
          !evidence.events.some(e => e.kind === 'ui.didShow' && e.controller.includes('PostDetailView')))) {
        throw Error('실제 포스트 상세/원본 이미지 근거 미충족');
      }
  } catch {
      process.stderr.write('로컬 UI 이미지 진단 원본을 확인하지 못했습니다.\n');
      process.exitCode = 1;
  }
}
