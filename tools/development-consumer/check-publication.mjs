import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {digest} from './check-submission.mjs';

const utc = value => typeof value === 'string' && Number.isFinite(Date.parse(value))
  && new Date(value).toISOString() === value;

// 게시 이전 통과/실패 기록과 분리하여 신호 이후의 같은 개인 요청만 판정한다.
export function validatePublishedHistory(evidence, provenance, prior, priorProvenance, priorResult, target, signal) {
  assert.equal(signal.status, 'development-publication-consumer-reads-allowed');
  assert.equal(signal.resubmissionAllowed, false);
  assert.equal(signal.additionalBrandWorkflowWritesAllowed, false);
  assert.equal(target.projectID, 'outpick-test');
  assert.equal(target.contractVersion, 1);
  assert.equal(target.generalAuth.tenant, null);
  assert.equal(evidence.projectID, target.projectID);
  assert.equal(evidence.region, target.region);
  assert.equal(evidence.schemaVersion, 1); assert.equal(evidence.writeFailures, 0);
  for (const key of ['mode', 'fixture', 'bundleID', 'projectID', 'collectorArgument', 'collectionMethod', 'executableSHA256', 'installationOriginal']) {
    assert.equal(provenance[key], priorProvenance[key]);
  }
  assert.equal(provenance.mode, 'normal-development'); assert.equal(provenance.fixture, false);
  assert.equal(provenance.bundleID, 'GayoonKim.OutPick.dev');
  assert.equal(provenance.projectID, 'outpick-test');
  assert.equal(provenance.collectionMethod, 'device-app-data-copy');
  assert.match(provenance.executableSHA256, /^[0-9a-f]{64}$/);
  assert.equal(provenance.collectorArgument, '-BrandRequestSDKQA');
  assert.equal(provenance.sessionID, evidence.sessionID);
  assert.ok(utc(provenance.copiedAt) && Date.parse(provenance.copiedAt) >= Date.parse(signal.issuedAt));
  assert.equal(target.groupID, priorResult.actualSDK.groupID);
  assert.equal(target.groupID, signal.groupID); assert.equal(target.brandID, signal.brandID);
  assert.equal(target.expected.resolvedBrandID, target.brandID);
  assert.equal(target.expected.requestStatus, 'added');
  if (evidence.sessionID === prior.sessionID) assert.deepEqual(evidence.events.slice(0, prior.events.length), prior.events);
  const suffix = evidence.events.filter(event => Date.parse(event.at) >= Date.parse(signal.issuedAt));
  assert.ok(suffix.length > 0, '게시 후 실제 SDK 조회0건입니다.');
  const calls = new Map(); const scopes = new Set(); const times = [];
  for (const [index, event] of evidence.events.entries()) {
    assert.equal(event.sequence, index + 1); assert.ok(utc(event.at));
    if (!suffix.includes(event)) continue;
    assert.equal(event.call, 'listMyBrandRequests', '게시 후 재접수는 허용하지 않습니다.');
    assert.ok(typeof event.callID === 'string' && event.callID.length > 0);
    assert.ok(['started', 'returned'].includes(event.event), '게시 후 SDK 실패는 통과하지 않습니다.');
    assert.ok(Date.parse(event.at) <= Date.parse(provenance.copiedAt));
    calls.set(event.callID, [...(calls.get(event.callID) ?? []), event]);
  }
  for (const pair of calls.values()) {
    assert.equal(pair.length, 2); assert.equal(pair[0].event, 'started'); assert.equal(pair[1].event, 'returned');
    assert.ok(Date.parse(pair[0].at) <= Date.parse(pair[1].at));
    const page = pair[1].fields;
    assert.equal(page.strictMapperCheckPassed, true);
    assert.ok(['active', 'history'].includes(page.scope) && Array.isArray(page.requests));
    assert.equal(page.nextCursor, null, '명시 null 커서가 필요합니다.');
    assert.equal(page.requests.length, page.scope === 'active' ? 0 : 1);
    if (page.scope === 'history') {
      const row = page.requests[0];
      assert.equal(digest(row.requestID), priorResult.actualSDK.requestIDSHA256);
      assert.equal(row.groupID, target.groupID); assert.equal(row.status, 'added');
      assert.equal(row.resolvedBrandID, target.brandID); assert.equal(row.rejectionReason, null);
      assert.ok(utc(row.createdAt) && utc(row.updatedAt));
    }
    scopes.add(page.scope); times.push({scope: page.scope, startedAt: pair[0].at, returnedAt: pair[1].at});
  }
  assert.deepEqual([...scopes].sort(), ['active', 'history']);
  return {groupID: target.groupID, brandID: target.brandID, requestIDSHA256: priorResult.actualSDK.requestIDSHA256,
    status: 'added', resolvedBrandID: target.brandID, activeCount: 0, historyCount: 1,
    activeNextCursor: null, historyNextCursor: null, historyCalls: calls.size, newSubmissionCalls: 0,
    strictMapperChecked: true, times, publicDocumentOrImagesVerifiedByThisValidator: false};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const read = path => JSON.parse(readFileSync(path));
    const checked = (path, sha) => { const bytes = readFileSync(path); assert.equal(digest(bytes), sha); return JSON.parse(bytes); };
    const a = read(process.env.OUTPICK_BRAND_PUBLICATION_ACCEPTANCE);
    const signal = checked(a.signalPath, a.signalSHA256); const target = checked(a.targetPath, a.targetSHA256);
    assert.equal(checked(a.backendGatePath, a.backendGateSHA256).verdict, 'passed');
    checked(a.verifiedFilesPath, a.verifiedFilesSHA256);
    const prior = checked(a.priorEvidencePath, a.priorEvidenceSHA256);
    const priorProvenance = checked(a.priorProvenancePath, a.priorProvenanceSHA256);
    const priorResult = checked(a.priorResultPath, a.priorResultSHA256);
    const p = read(process.env.OUTPICK_BRAND_DEVELOPMENT_PROVENANCE);
    const evidence = checked(process.env.OUTPICK_BRAND_DEVELOPMENT_EVIDENCE, p.evidenceSHA256);
    const result = validatePublishedHistory(evidence, p, prior, priorProvenance, priorResult, target, signal);
    process.stdout.write(JSON.stringify({verdict: 'passed', stage: 'actual-sdk-published-history', ...result}) + '\n');
  } catch {
    process.stderr.write('게시 후 동일 요청 내역/원본 지문/실행 근거가 없거나 유효하지 않습니다.\n');
    process.exitCode = 2;
  }
}
