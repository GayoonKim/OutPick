import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';

// 실패 진단 부재만으로 성공을 만들지 않고 사람의 화면 관찰과 구분한다.
export function interestRecheck(capture, observation, checkedAt = Date.now()) {
  assert.equal(capture.schemaVersion, 1); assert.equal(capture.rawConsoleStored, false);
  assert.equal(capture.positiveSDKResponseCaptured, false);
  assert.equal(capture.launchConfirmed, true); assert.equal(capture.launchedNormalApp, true);
  assert.ok(Array.isArray(capture.failures));
  assert.equal(observation.source, 'user-physical-device-observation');
  assert.equal(observation.existingLoginKept, true);
  assert.equal(observation.profilePreferencesChanged, false);
  assert.equal(observation.interestConfigured, true, '관심 스타일 미설정은 조회 성공이 아닙니다.');
  assert.ok(['ready', 'empty'].includes(observation.state), '로딩/오류/미관측은 통과하지 않습니다.');
  assert.ok(Date.parse(observation.observedAt) >= Date.parse(capture.startedAt));
  assert.ok(Date.parse(observation.observedAt) <= checkedAt, '미래의 관찰 기록은 수락하지 않습니다.');
  assert.equal(capture.failures.length, 0, '새 조회 실패가 관측됐습니다.');
  return {verdict: 'passed', scope: 'manual-interest-query-recheck-with-error-console',
    state: observation.state, capturedFailureCount: 0, code9Reproduced: false,
    positiveSDKResponseCaptured: false, rootCauseOfHistoricalCode9Established: false,
    automaticUIOrFirestoreSnapshotVerified: false};
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const result = interestRecheck(JSON.parse(readFileSync(process.env.OUTPICK_INTEREST_QA_OUTPUT + '/capture.json')),
      JSON.parse(readFileSync(process.env.OUTPICK_INTEREST_QA_OBSERVATION)));
    process.stdout.write(JSON.stringify(result) + '\n');
  } catch {
    process.stderr.write('관심 스타일 실제 관찰/오류 진단 근거가 없거나 조회 실패가 남아 있습니다.\n');
    process.exitCode = 2;
  }
}
