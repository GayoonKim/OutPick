import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {digest} from './check-submission.mjs';

const utc = value => typeof value === 'string' && Number.isFinite(Date.parse(value))
  && new Date(value).toISOString() === value;

// 이전 실패를 지우거나 최초 접수 게이트의 판정을 바꾸지 않고 추가 조회만 판정한다.
export function validateHistoryFollowup(before, evidence, provenance, previousProvenance, signal, allowSameAppRelaunch = false) {
  assert.equal(signal.status, 'same-request-history-read-allowed');
  assert.equal(signal.allowedCallable, 'listMyBrandRequests');
  assert.equal(signal.preserveCurrentLoginAndRequest, true);
  assert.equal(signal.submitBrandRequestAllowed, false);
  assert.equal(signal.newRequestIDAllowed, false);
  assert.equal(signal.previousFailedGateMustBePreserved, true);
  const relaunched = evidence.sessionID !== before.sessionID;
  assert.ok(!relaunched || allowSameAppRelaunch === true, '새 수집 세션은 별도 재실행 승인이 필요합니다.');
  for (const key of ['schemaVersion', 'projectID', 'region']) assert.equal(evidence[key], before[key]);
  assert.equal(evidence.schemaVersion, 1);
  assert.equal(evidence.projectID, 'outpick-test');
  assert.equal(evidence.region, 'asia-northeast3');
  assert.equal(evidence.writeFailures, 0);
  assert.ok(Array.isArray(before.events) && before.events.length > 0);
  if (!relaunched) assert.deepEqual(evidence.events.slice(0, before.events.length), before.events);
  for (const key of ['mode', 'fixture', 'bundleID', 'projectID', 'collectorArgument',
    'collectionMethod', 'executableSHA256', 'installationOriginal']) {
    assert.equal(provenance[key], previousProvenance[key]);
  }
  assert.equal(provenance.mode, 'normal-development');
  assert.equal(provenance.fixture, false);
  assert.equal(provenance.bundleID, 'GayoonKim.OutPick.dev');
  assert.equal(provenance.projectID, 'outpick-test');
  assert.equal(provenance.collectorArgument, '-BrandRequestSDKQA');
  assert.match(provenance.executableSHA256, /^[0-9a-f]{64}$/);
  assert.equal(provenance.collectionMethod, 'device-app-data-copy');
  assert.equal(provenance.sessionID, evidence.sessionID);
  assert.ok(utc(provenance.copiedAt) && utc(signal.recoveryCompletedAt));
  assert.ok(Date.parse(provenance.copiedAt) >= Date.parse(signal.issuedAt));
  if (relaunched) {
    assert.ok(utc(provenance.launchAt) && Date.parse(provenance.launchAt) >= Date.parse(signal.issuedAt));
    assert.notEqual(provenance.launchOriginal, previousProvenance.launchOriginal);
  } else {
    assert.equal(provenance.launchAt, previousProvenance.launchAt);
    assert.equal(provenance.launchOriginal, previousProvenance.launchOriginal);
  }
  const receipt = before.events.filter(e => e.call === 'submitBrandRequest' && e.event === 'returned');
  assert.equal(receipt.length, 1);
  assert.equal(receipt[0].fields.groupID, signal.groupID);
  const prefixCount = relaunched ? 0 : before.events.length;
  const suffix = evidence.events.slice(prefixCount);
  assert.ok(suffix.length > 0, '후속 SDK 조회0건입니다.');
  const calls = new Map();
  for (const [index, event] of suffix.entries()) {
    assert.equal(event.sequence, prefixCount + index + 1);
    assert.equal(event.call, 'listMyBrandRequests', '재접수는 허용하지 않습니다.');
    assert.ok(utc(event.at) && Date.parse(event.at) >= Date.parse(signal.issuedAt)
      && Date.parse(event.at) <= Date.parse(provenance.copiedAt));
    assert.ok(typeof event.callID === 'string' && event.callID.length > 0
      && !before.events.some(old => old.callID === event.callID));
    assert.ok(['started', 'returned'].includes(event.event), '후속 실패는 통과하지 않습니다.');
    calls.set(event.callID, [...(calls.get(event.callID) ?? []), event]);
  }
  const scopes = new Set(); const times = [];
  for (const pair of calls.values()) {
    assert.equal(pair.length, 2);
    assert.equal(pair[0].event, 'started'); assert.equal(pair[1].event, 'returned');
    assert.ok(Date.parse(pair[1].at) >= Date.parse(pair[0].at));
    const page = pair[1].fields;
    assert.equal(page.strictMapperCheckPassed, true);
    assert.ok(['active', 'history'].includes(page.scope));
    assert.ok(Array.isArray(page.requests));
    assert.equal(page.nextCursor, null, '명시 null 커서가 필요합니다.');
    const expected = signal.expected[page.scope];
    assert.equal(page.requests.length, expected.count);
    if (page.scope === 'active') {
      assert.equal(page.requests.length, 1);
      const row = page.requests[0];
      assert.equal(row.requestID, receipt[0].fields.requestID);
      assert.equal(row.groupID, signal.groupID);
      assert.equal(row.status, 'submitted');
      assert.equal(row.resolvedBrandID, null);
      assert.ok(utc(row.createdAt) && utc(row.updatedAt));
    } else assert.equal(page.requests.length, 0);
    scopes.add(page.scope); times.push({scope: page.scope, startedAt: pair[0].at, returnedAt: pair[1].at});
  }
  assert.deepEqual([...scopes].sort(), ['active', 'history']);
  return {groupID: signal.groupID, requestIDSHA256: digest(receipt[0].fields.requestID),
    status: 'submitted', resolvedBrandID: null, activeCount: 1, historyCount: 0,
    activeNextCursor: null, historyNextCursor: null, strictMapperChecked: true,
    newSubmissionCalls: 0, historyCalls: calls.size, preservedEvents: before.events.length, relaunched, times};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const read = path => JSON.parse(readFileSync(path));
    const acceptance = read(process.env.OUTPICK_BRAND_HISTORY_ACCEPTANCE);
    const checked = (path, sha) => { const bytes = readFileSync(path); assert.equal(digest(bytes), sha); return JSON.parse(bytes); };
    const signal = checked(acceptance.signalPath, acceptance.signalSHA256);
    assert.equal(checked(signal.gateSummaryPath, signal.gateSummarySHA256).verdict, 'passed');
    assert.equal(checked(acceptance.previousFailedGatePath, acceptance.previousFailedGateSHA256).verdict, 'failed');
    const before = checked(acceptance.previousEvidencePath, acceptance.previousEvidenceSHA256);
    const initial = checked(acceptance.initialEvidencePath, acceptance.initialEvidenceSHA256);
    assert.deepEqual(before.events.slice(0, initial.events.length), initial.events);
    assert.ok(before.events.every(event => Date.parse(event.at) < Date.parse(signal.issuedAt)),
      '재조회 신호 이후 기록을 기준선으로 숨길 수 없습니다.');
    const previousProvenance = checked(acceptance.previousProvenancePath, acceptance.previousProvenanceSHA256);
    const provenance = read(process.env.OUTPICK_BRAND_DEVELOPMENT_PROVENANCE);
    const evidence = checked(process.env.OUTPICK_BRAND_DEVELOPMENT_EVIDENCE, provenance.evidenceSHA256);
    assert.equal(previousProvenance.evidenceSHA256, acceptance.initialEvidenceSHA256);
    const allowRelaunch = acceptance.relaunchDecision === 'same-installed-app-evidence-option-approved';
    if (allowRelaunch) {
      checked(acceptance.relaunchOriginalPath, acceptance.relaunchOriginalSHA256);
      assert.equal(provenance.launchOriginal, acceptance.relaunchOriginalPath);
    }
    const result = validateHistoryFollowup(before, evidence, provenance, previousProvenance, signal, allowRelaunch);
    process.stdout.write(JSON.stringify({verdict: 'passed', stage: 'actual-sdk-history-followup', ...result}) + '\n');
  } catch {
    process.stderr.write('동일 요청 후속 조회/원본 보존/실행 근거가 없거나 유효하지 않습니다.\n');
    process.exitCode = 2;
  }
}
