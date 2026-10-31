import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {validateSubmissionEvidence, digest} from './check-submission.mjs';

function fixture() {
  const at = '2026-10-20T01:00:00.000Z';
  const receipt = {requestID: 'request', groupID: 'group', status: 'submitted', resolvedBrandID: null,
    isDuplicate: false, remainingToday: 4, strictMapperCheckPassed: true};
  const pair = (call, callID, fields) => [{at, call, callID, event: 'started', fields: {}},
    {at, call, callID, event: 'returned', fields}];
  const evidence = {schemaVersion: 1, sessionID: 'session', projectID: 'outpick-test', region: 'asia-northeast3',
    writeFailures: 0, events: [...pair('submitBrandRequest', 'submit', receipt),
      ...pair('listMyBrandRequests', 'list', {scope: 'active', requests: [{...receipt}], nextCursor: null, strictMapperCheckPassed: true})]
      .map((event, index) => ({...event, sequence: index + 1}))};
  const provenance = {mode: 'normal-development', fixture: false, bundleID: 'GayoonKim.OutPick.dev', projectID: 'outpick-test',
    collectorArgument: '-BrandRequestSDKQA', collectionMethod: 'device-app-data-copy', executableSHA256: 'a'.repeat(64),
    evidenceSHA256: digest(JSON.stringify(evidence)), sessionID: 'session', launchAt: at, copiedAt: at};
  return {evidence, provenance};
}
function check({evidence, provenance}) { return validateSubmissionEvidence(evidence, provenance, digest(JSON.stringify(evidence))); }
function mutate(fn) {
  const f = fixture(); fn(f.evidence, f.provenance);
  f.provenance.evidenceSHA256 = digest(JSON.stringify(f.evidence)); return f;
}

test('DVE-P01 모의 원본 검사기는 단일 접수와 같은 내역 및 수집 지문을 대조한다', () => {
  const result = check(fixture());
  assert.equal(result.groupID, 'group'); assert.equal(result.submissionCalls, 1); assert.equal(result.historyCalls, 1);
});
test('DVE-P02 누락 중복 실패 mapper 오류와 잘못된 수집 근거는 통과하지 않는다', () => {
  for (const change of [
    e => { e.events = []; }, e => { e.events.pop(); }, e => { e.events[1].event = 'failed'; },
    e => { e.events[1].fields.strictMapperCheckPassed = false; }, e => { e.writeFailures = 1; },
    e => { e.projectID = 'other'; }, (_, p) => { p.fixture = true; }, (_, p) => { p.mode = 'local'; },
    (_, p) => { p.collectorArgument = ''; }, (_, p) => { p.sessionID = 'other'; },
    e => { e.events.push(...e.events.slice(0, 2).map((v, i) => ({...v, callID: 'duplicate', sequence: 5 + i}))); }
  ]) assert.throws(() => check(mutate(change)));
  const mismatch = fixture(); mismatch.provenance.evidenceSHA256 = '0'.repeat(64); assert.throws(() => check(mismatch));
  const env = {...process.env}; delete env.OUTPICK_BRAND_DEVELOPMENT_EVIDENCE; delete env.OUTPICK_BRAND_DEVELOPMENT_PROVENANCE;
  const missing = spawnSync(process.execPath, ['tools/development-consumer/check-submission.mjs'], {env, encoding: 'utf8'});
  assert.equal(missing.status, 2); assert.equal(missing.stdout, '');
});
test('DVE-P03 명시 null과 유효 커서는 수락하고 손상 커서 및 다른 요청은 거절한다', () => {
  assert.doesNotThrow(() => check(mutate(e => { e.events[3].fields.nextCursor = {createdAt: '2026-10-20T01:00:00.000Z', requestID: 'cursor'}; })));
  for (const change of [
    e => { delete e.events[3].fields.nextCursor; }, e => { e.events[3].fields.nextCursor = {}; },
    e => { e.events[3].fields.requests = []; }, e => { e.events[3].fields.requests[0].groupID = 'other'; },
    e => { e.events[1].fields.resolvedBrandID = 'pending'; }
  ]) assert.throws(() => check(mutate(change)));
});
