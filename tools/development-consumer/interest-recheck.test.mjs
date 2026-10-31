import test from 'node:test';
import assert from 'node:assert/strict';
import {interestFailure} from './capture-interest-recheck.mjs';
import {interestRecheck} from './interest-recheck.mjs';

test('DIR-P01 기존 관심 스타일 실패의 domain code만 수집하고 임의 콘솔을 버린다', () => {
  const line = '[LookbookHomeViewModel] 관심 스타일 조회 실패: domain=FIRFirestoreErrorDomain, code=9';
  assert.deepEqual(interestFailure(line), {domain: 'FIRFirestoreErrorDomain', code: 9});
  for (const value of ['token=private-canary', line + ' token=private-canary', line.replace('code=9', 'code=private-canary')]) assert.equal(interestFailure(value), null);
});
test('DIR-P02 미설정 로딩 오류 미관측과 code9를 정상 조회로 판정하지 않는다', () => {
  const at = '2026-10-20T12:00:00.000Z';
  const c = {schemaVersion: 1, rawConsoleStored: false, positiveSDKResponseCaptured: false, launchConfirmed: true, launchedNormalApp: true, startedAt: at, failures: []};
  const o = {source: 'user-physical-device-observation', existingLoginKept: true, profilePreferencesChanged: false, interestConfigured: true, state: 'ready', observedAt: at};
  const check = (capture, observation) => interestRecheck(capture, observation, Date.parse(at) + 1000);
  assert.equal(check(c, o).code9Reproduced, false);
  assert.equal(check(c, {...o, state: 'empty'}).positiveSDKResponseCaptured, false);
  for (const state of ['loading', 'failed', 'unconfigured', 'unknown']) assert.throws(() => check(c, {...o, state}));
  assert.throws(() => check(c, {...o, interestConfigured: false}));
  assert.throws(() => check({...c, launchConfirmed: false}, o));
  assert.throws(() => check({...c, failures: [{domain: 'FIRFirestoreErrorDomain', code: 9}]}, o));
  assert.throws(() => check(c, {...o, observedAt: '2026-10-21T12:00:00.000Z'}));
});
