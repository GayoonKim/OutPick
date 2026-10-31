import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';

export const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const id = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
const utc = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)
  && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;

export function validateSubmissionEvidence(evidence, provenance, evidenceSHA256) {
  assert.ok(object(evidence) && object(provenance), '증거/수집 근거가 필요합니다.');
  assert.ok(evidence.schemaVersion === 1 && evidence.projectID === 'outpick-test'
    && evidence.region === 'asia-northeast3' && evidence.writeFailures === 0 && id(evidence.sessionID), '세션/프로젝트/기록 오류입니다.');
  assert.ok(provenance.mode === 'normal-development' && provenance.fixture === false
    && provenance.bundleID === 'GayoonKim.OutPick.dev' && provenance.projectID === 'outpick-test'
    && provenance.collectorArgument === '-BrandRequestSDKQA'
    && ['device-app-data-copy', 'simulator-app-data-copy'].includes(provenance.collectionMethod)
    && /^[0-9a-f]{64}$/.test(provenance.executableSHA256 ?? '')
    && provenance.evidenceSHA256 === evidenceSHA256 && provenance.sessionID === evidence.sessionID
    && utc(provenance.launchAt) && utc(provenance.copiedAt), '정상 앱 실행/수집 지문이 필요합니다.');
  assert.ok(Array.isArray(evidence.events) && evidence.events.length > 0, 'SDK 실행0건입니다.');
  const calls = new Map();
  for (const [index, event] of evidence.events.entries()) {
    assert.ok(object(event) && event.sequence === index + 1 && utc(event.at) && id(event.callID)
      && ['submitBrandRequest', 'listMyBrandRequests'].includes(event.call)
      && ['started', 'returned'].includes(event.event) && object(event.fields), '누락/실패/손상 이벤트입니다.');
    const stages = calls.get(event.callID) ?? [];
    stages.push(event); calls.set(event.callID, stages);
  }
  const completed = [...calls.values()];
  for (const pair of completed) {
    assert.ok(pair.length === 2 && pair[0].event === 'started' && pair[1].event === 'returned'
      && pair[0].call === pair[1].call && pair[1].fields.strictMapperCheckPassed === true,
    '응답/엄격 mapper 검사가 완료되지 않았습니다.');
  }
  const submissions = completed.filter(pair => pair[0].call === 'submitBrandRequest');
  assert.ok(submissions.length === 1, '수동 접수 정확히1회가 필요합니다.');
  const [started, returned] = submissions[0];
  const receipt = returned.fields;
  assert.ok(id(receipt.requestID) && id(receipt.groupID) && ['submitted', 'reviewing'].includes(receipt.status)
    && receipt.resolvedBrandID === null && typeof receipt.isDuplicate === 'boolean'
    && Number.isInteger(receipt.remainingToday) && receipt.remainingToday >= 0 && receipt.remainingToday <= 5,
  '접수 receipt/초기 상태가 맞지 않습니다.');
  const pages = completed.filter(pair => pair[0].call === 'listMyBrandRequests').map(pair => pair[1].fields);
  assert.ok(pages.length > 0, '실제 내역 조회가 필요합니다.');
  let matched = false;
  for (const page of pages) {
    assert.ok(['active', 'history'].includes(page.scope) && Array.isArray(page.requests)
      && Object.hasOwn(page, 'nextCursor'), '내역 범위/명시 커서가 필요합니다.');
    assert.ok(page.nextCursor === null || (object(page.nextCursor) && id(page.nextCursor.requestID)
      && utc(page.nextCursor.createdAt)), '손상 커서는 끝으로 처리하지 않습니다.');
    for (const row of page.requests) {
      assert.ok(object(row) && id(row.requestID) && id(row.groupID)
        && (page.scope === 'active' ? ['submitted', 'reviewing'] : ['added', 'rejected']).includes(row.status), '내역 행 오류입니다.');
      if (row.requestID === receipt.requestID) {
        assert.ok(row.groupID === receipt.groupID && page.scope === 'active' && row.resolvedBrandID === null,
          '접수와 내역의 대상이 일치하지 않습니다.');
        matched = true;
      }
    }
  }
  assert.ok(matched, '같은 요청을 내역에서 확인하지 못했습니다.');
  return {requestID: receipt.requestID, groupID: receipt.groupID, status: receipt.status,
    resolvedBrandID: receipt.resolvedBrandID, isDuplicate: receipt.isDuplicate,
    remainingToday: receipt.remainingToday, submittedAt: started.at, sessionID: evidence.sessionID,
    evidenceSHA256, submissionCalls: 1, historyCalls: pages.length, strictMapperChecked: true};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const evidencePath = process.env.OUTPICK_BRAND_DEVELOPMENT_EVIDENCE;
    const provenancePath = process.env.OUTPICK_BRAND_DEVELOPMENT_PROVENANCE;
    assert.ok(evidencePath && provenancePath);
    const bytes = readFileSync(evidencePath);
    const result = validateSubmissionEvidence(JSON.parse(bytes), JSON.parse(readFileSync(provenancePath)), digest(bytes));
    process.stdout.write(JSON.stringify({verdict: 'passed', stage: 'actual-sdk-submission', ...result}) + '\n');
  } catch {
    // 입력/오류 객체 자체에는 민감정보가 포함될 수 있어 출력하지 않는다.
    process.stderr.write('실제 SDK 접수/내역 증거 또는 정상 앱 수집 근거가 없거나 유효하지 않습니다.\n');
    process.exitCode = 2;
  }
}
