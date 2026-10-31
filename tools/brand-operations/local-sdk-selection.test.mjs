import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, writeFileSync, rmSync, existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';

// 실제 서버/계정 없이 사전 거절만 검사한다. 유효한 게시 후 SDK 실행은 별도 필수다.
function run(args, extra = {}) {
  return spawnSync(process.execPath, ['tools/brand-operations/run-local-sdk.mjs', ...args], {
    cwd: process.cwd(), encoding: 'utf8', timeout: 10000,
    env: {PATH: process.env.PATH, ...extra},
  });
}
test('L154-S01 겹치는 단계는 접속과 Xcode 실행 전에 거절한다', () => {
  for (const args of [['--published', '--followup'], ['--published', '--preparation'], ['--followup', '--preparation'],
                    ['--ui', '--published'], ['--ui', '--followup'], ['--ui', '--preparation'],
                    ['--detail-ui', '--ui'], ['--detail-ui', '--published'], ['--detail-ui', '--followup'], ['--detail-ui', '--preparation']]) {
    const result = run(args);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /검사 단계는 하나만/);
  }
});
test('L154-S02 게시 전달 입력이 빠지면 접속 전에 거절한다', () => {
  const values = {OUTPICK_BRAND_LOCAL_ROUND: '2df66a14-e58b-4987-9334-314e96db37e9',
    OUTPICK_BRAND_LOCAL_GROUP: '760ce2acc2eaf8dc84f6272b44871528',
    OUTPICK_BRAND_LOCAL_BRAND: 'local-brand', OUTPICK_BRAND_LOCAL_PUBLICATION_EVIDENCE: '/unread-proof'};
  for (const key of Object.keys(values)) {
    const input = {...values};
    delete input[key];
    const result = run(['--published'], input);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /게시 완료 전달의/);
  }
});
test('L154-S03 빈 근거와 디렉터리는 게시 완료 근거로 쓰지 않는다', () => {
  const directory = mkdtempSync(join(tmpdir(), 'outpick-publication-selection-'));
  try {
    const file = join(directory, 'empty.json');
    writeFileSync(file, '');
    for (const evidence of [directory, file]) {
      const result = run(['--published'], {OUTPICK_BRAND_LOCAL_ROUND: '2df66a14-e58b-4987-9334-314e96db37e9',
        OUTPICK_BRAND_LOCAL_GROUP: 'local-group', OUTPICK_BRAND_LOCAL_BRAND: 'local-brand',
        OUTPICK_BRAND_LOCAL_PUBLICATION_EVIDENCE: evidence});
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /게시 완료 근거 파일/);
    }
  } finally { rmSync(directory, {recursive: true, force: true}); }
});
test('L154-S04 근거 메타데이터가 있어도 대상 없이는 Xcode를 시작하지 않는다', () => {
  const directory = mkdtempSync(join(tmpdir(), 'outpick-publication-selection-'));
  const bundle = resolve('output', 'unused-publication-selection-' + directory.split('/').at(-1), 'tests.xcresult');
  try {
    const file = join(directory, 'synthetic-proof.json');
    writeFileSync(file, JSON.stringify({syntheticDriverInputOnly: true}));
    const result = run(['--published', '-resultBundlePath', bundle], {
      OUTPICK_BRAND_LOCAL_ROUND: '2df66a14-e58b-4987-9334-314e96db37e9',
      OUTPICK_BRAND_LOCAL_GROUP: 'local-group', OUTPICK_BRAND_LOCAL_BRAND: 'local-brand',
      OUTPICK_BRAND_LOCAL_PUBLICATION_EVIDENCE: file,
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /이번 회차의 target\/login 경로/);
    assert.equal(existsSync(bundle), false);
  } finally { rmSync(directory, {recursive: true, force: true}); }
});
