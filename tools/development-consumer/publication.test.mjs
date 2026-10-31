import test from 'node:test';
import assert from 'node:assert/strict';
import {digest} from './check-submission.mjs';
import {validatePublishedHistory} from './check-publication.mjs';

function fixture() {
  const at = '2026-10-20T11:00:00.000Z';
  const prior = {sessionID: 'session', events: []};
  const events = ['active', 'history'].flatMap(scope => [
    {call: 'listMyBrandRequests', callID: scope, event: 'started', at, fields: {}},
    {call: 'listMyBrandRequests', callID: scope, event: 'returned', at, fields: {
      scope, nextCursor: null, strictMapperCheckPassed: true, requests: scope === 'active' ? [] : [
        {requestID: 'request', groupID: 'group', status: 'added', resolvedBrandID: 'brand', rejectionReason: null, createdAt: at, updatedAt: at}]
    }}]).map((e, i) => ({...e, sequence: i + 1}));
  const e = {schemaVersion: 1, sessionID: 'session', projectID: 'outpick-test', region: 'asia-northeast3', writeFailures: 0, events};
  const p = {mode: 'normal-development', fixture: false, collectorArgument: '-BrandRequestSDKQA', sessionID: 'session', copiedAt: at,
    bundleID: 'GayoonKim.OutPick.dev', projectID: 'outpick-test', collectionMethod: 'device-app-data-copy', executableSHA256: 'a'.repeat(64)};
  const target = {projectID: e.projectID, region: e.region, contractVersion: 1, groupID: 'group', brandID: 'brand',
    generalAuth: {tenant: null}, expected: {resolvedBrandID: 'brand', requestStatus: 'added'}};
  const signal = {status: 'development-publication-consumer-reads-allowed', resubmissionAllowed: false,
    additionalBrandWorkflowWritesAllowed: false, groupID: 'group', brandID: 'brand', issuedAt: at};
  return [e, p, prior, structuredClone(p), {actualSDK: {groupID: 'group', requestIDSHA256: digest('request')}}, target, signal];
}
test('DPH-P01 같은 요청의 게시 후 added 대상과 양쪽 명시 null 커서를 대조한다', () => {
  const r = validatePublishedHistory(...fixture());
  assert.equal(r.status, 'added'); assert.equal(r.historyCalls, 2); assert.equal(r.newSubmissionCalls, 0);
  assert.equal(r.publicDocumentOrImagesVerifiedByThisValidator, false); assert.ok(!Object.hasOwn(r, 'requestID'));
});
test('DPH-P02 다른 요청 브랜드 상태 손상 커서 mapper와 한 범위 누락을 거절한다', () => {
  for (const mutate of [
    f => { f[0].events[3].fields.requests[0].requestID = 'other'; },
    f => { f[0].events[3].fields.requests[0].resolvedBrandID = null; },
    f => { f[0].events[3].fields.requests[0].status = 'reviewing'; },
    f => { delete f[0].events[3].fields.nextCursor; }, f => { f[0].events[3].fields.nextCursor = {}; },
    f => { f[0].events[3].fields.strictMapperCheckPassed = false; }, f => { f[0].events.length = 2; }
  ]) { const f = fixture(); mutate(f); assert.throws(() => validatePublishedHistory(...f)); }
});
test('DPH-P03 이전 응답 재사용 실제0건 새접수 실패와 과거 기록 변조를 거절한다', () => {
  for (const mutate of [
    f => { f[0].events = []; }, f => { f[6].issuedAt = '2026-10-21T00:00:00.000Z'; },
    f => { f[0].events[0].call = 'submitBrandRequest'; }, f => { f[0].events[1].event = 'failed'; },
    f => { f[2].events = [{event: 'preserved'}]; }, f => { f[1].fixture = true; }
  ]) { const f = fixture(); mutate(f); assert.throws(() => validatePublishedHistory(...f)); }
});
