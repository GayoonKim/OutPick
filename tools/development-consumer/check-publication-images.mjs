import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {digest} from './check-submission.mjs';

export function publicationImages(events, target, files) {
  assert.equal(target.posts.length, 24); assert.equal(files.objects.length, 50);
  assert.ok(events.length > 0, '이미지 실제 계측0건입니다.');
  const successful = new Set(events.filter(e => e.action === 'end' && e.outcome === 'success'
    && /^pipelineRequest\./.test(e.stage)).map(e => e.key));
  const assigned = new Set(events.filter(e => e.action === 'end' && e.outcome === 'success'
    && e.stage === 'ui.asset.assigned').map(e => e.key));
  const key = path => digest(path).slice(0, 24);
  const required = target.posts.flatMap(post => [post.thumbPath, post.detailPath]);
  assert.equal(new Set(required).size, 48);
  const publicationPaths = new Set(files.objects.map(o => o.path));
  assert.ok(required.every(path => publicationPaths.has(path)));
  const covers = files.objects.filter(o => !required.includes(o.path)).map(o => o.path);
  assert.equal(covers.length, 2);
  const missing = required.filter(path => !successful.has(key(path)));
  assert.equal(missing.length, 0, '게시 포스트 썸네일/원본의 성공 계측이 누락됐습니다.');
  const visibleThumbs = target.posts.filter(p => assigned.has(key(p.thumbPath))).length;
  assert.equal(visibleThumbs, 24, '룩북24개 UI 이미지 할당 계측이 필요합니다.');
  assert.ok(covers.some(path => successful.has(key(path)) && assigned.has(key(path))), '시즌 커버 UI 할당/로딩 성공이 필요합니다.');
  return {postCount: 24, thumbnailSuccesses: 24, detailPathSuccesses: 24, uiThumbnailAssignments: visibleThumbs,
    coverPathsLoaded: covers.filter(path => successful.has(key(path))).length,
    objectPathsLoaded: files.objects.filter(o => successful.has(key(o.path))).length,
    cacheOutcomes: [...new Set(events.filter(e => e.stage === 'cache' && e.action === 'end').map(e => e.outcome))],
    failedPipelineEvents: events.filter(e => /^pipelineRequest\./.test(e.stage) && e.action === 'end' && e.outcome === 'failure').length,
    cancelledPipelineEvents: events.filter(e => /^pipelineRequest\./.test(e.stage) && e.action === 'end' && e.outcome === 'cancelled').length,
    networkBodyMarkerEvents: events.filter(e => e.stage === 'network.body.received' && e.action === 'begin').length,
    metricCount: events.length, storageBytesOrJPEGHashProvenByThisValidator: false,
    manualFullSizeUIConfirmedByThisValidator: false, publicFirestoreDocumentProvenByThisValidator: false};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const a = JSON.parse(readFileSync(process.env.OUTPICK_BRAND_PUBLICATION_ACCEPTANCE));
    const checked = (p, sha) => { const bytes = readFileSync(p); assert.equal(digest(bytes), sha); return JSON.parse(bytes); };
    const target = checked(a.targetPath, a.targetSHA256); const files = checked(a.verifiedFilesPath, a.verifiedFilesSHA256);
    const meta = JSON.parse(readFileSync(process.env.OUTPICK_IMAGE_QA_OUTPUT + '/capture.json'));
    assert.equal(meta.rawConsoleStored, false); assert.equal(meta.allowedPublicationObjects, 50);
    assert.ok(Date.parse(meta.startedAt) >= Date.parse(checked(a.signalPath, a.signalSHA256).issuedAt));
    const events = readFileSync(process.env.OUTPICK_IMAGE_QA_OUTPUT + '/image-metrics.jsonl', 'utf8').trim().split('\n').map(JSON.parse);
    assert.equal(events.length, meta.metricCount);
    process.stdout.write(JSON.stringify({verdict: 'passed', stage: 'actual-image-pipeline', ...publicationImages(events, target, files)}) + '\n');
  } catch {
    process.stderr.write('게시 후 이미지 계측/필수경로/실행 근거가 없거나 유효하지 않습니다.\n');
    process.exitCode = 2;
  }
}
