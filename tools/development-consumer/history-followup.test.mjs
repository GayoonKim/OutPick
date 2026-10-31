import test from 'node:test';
import assert from 'node:assert/strict';
import {validateHistoryFollowup} from './check-history-followup.mjs';

function fixture() {
  const at = '2026-10-20T08:20:00.000Z';
  const event = (call, callID, stage, fields = {}) => ({call, callID, event: stage, fields, at});
  const row = {requestID: 'request', groupID: 'group', status: 'submitted', resolvedBrandID: null, createdAt: at, updatedAt: at};
  const events = [event('submitBrandRequest', 'submit', 'started'), event('submitBrandRequest', 'submit', 'returned', row),
    event('listMyBrandRequests', 'old', 'started'), event('listMyBrandRequests', 'old', 'failed', {code: 13})]
    .map((e, i) => ({...e, sequence: i + 1}));
  const before = {schemaVersion: 1, sessionID: 'session', projectID: 'outpick-test', region: 'asia-northeast3', writeFailures: 0, events};
  const evidence = structuredClone(before);
  for (const scope of ['active', 'history']) evidence.events.push(event('listMyBrandRequests', scope, 'started'),
    event('listMyBrandRequests', scope, 'returned', {scope, requests: scope === 'active' ? [structuredClone(row)] : [], nextCursor: null, strictMapperCheckPassed: true}));
  evidence.events = evidence.events.map((e, i) => ({...e, sequence: i + 1}));
  const previousProvenance = {mode: 'normal-development', fixture: false, collectionMethod: 'device-app-data-copy', sessionID: 'session',
    bundleID: 'GayoonKim.OutPick.dev', projectID: 'outpick-test', collectorArgument: '-BrandRequestSDKQA', executableSHA256: 'a'.repeat(64)};
  const provenance = {...previousProvenance, copiedAt: at};
  const signal = {status: 'same-request-history-read-allowed', allowedCallable: 'listMyBrandRequests',
    preserveCurrentLoginAndRequest: true, submitBrandRequestAllowed: false, newRequestIDAllowed: false,
    previousFailedGateMustBePreserved: true, groupID: 'group', issuedAt: at, recoveryCompletedAt: at,
    expected: {active: {count: 1}, history: {count: 0}}};
  return [before, evidence, provenance, previousProvenance, signal];
}
test('DHF-P01 이전 실패 원본을 유지하고 같은 요청의 두 범위 후속 조회만 수락한다', () => {
  const result = validateHistoryFollowup(...fixture());
  assert.equal(result.historyCalls, 2); assert.equal(result.newSubmissionCalls, 0); assert.equal(result.preservedEvents, 4);
  assert.ok(!Object.hasOwn(result, 'requestID'));
});
test('DHF-P02 원본 변조 재접수 조회0건 누락 실패와 다른 세션을 거절한다', () => {
  for (const mutate of [
    f => { f[1].events[3].fields.code = 0; }, f => { f[1].events[4].call = 'submitBrandRequest'; },
    f => { f[1].events.length = 4; }, f => { f[1].events.pop(); },
    f => { f[1].events[5].event = 'failed'; }, f => { f[1].sessionID = 'other'; },
    f => { f[2].fixture = true; }, f => { f[1].events[4].at = '2026-10-19T00:00:00.000Z'; }
  ]) { const f = fixture(); mutate(f); assert.throws(() => validateHistoryFollowup(...f)); }
});
test('DHF-P03 다른 요청 손상 mapper 누락 커서 잘못된 상태와 한 범위 미실행을 거절한다', () => {
  for (const mutate of [
    f => { f[1].events[5].fields.requests[0].requestID = 'other'; },
    f => { f[1].events[5].fields.requests[0].status = 'reviewing'; },
    f => { f[1].events[5].fields.strictMapperCheckPassed = false; },
    f => { delete f[1].events[5].fields.nextCursor; },
    f => { f[1].events[5].fields.nextCursor = {}; },
    f => { f[1].events.length = 6; }
  ]) { const f = fixture(); mutate(f); assert.throws(() => validateHistoryFollowup(...f)); }
});
test('DHF-P04 승인된 같은 설치 앱 재실행은 기존 요청 대조를 유지하고 새 접수를 거절한다', () => {
  const f = fixture();
  f[1].sessionID = 'new-session'; f[2].sessionID = 'new-session';
  f[1].events = f[1].events.slice(4).map((e, i) => ({...e, sequence: i + 1}));
  f[2].launchAt = f[4].issuedAt; f[2].launchOriginal = 'new-launch.json';
  assert.throws(() => validateHistoryFollowup(...f));
  assert.equal(validateHistoryFollowup(...f, true).relaunched, true);
  f[1].events[0].call = 'submitBrandRequest';
  assert.throws(() => validateHistoryFollowup(...f, true));
});
