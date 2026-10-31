import test from 'node:test';
import assert from 'node:assert/strict';
import {digest} from './check-submission.mjs';
import {publicationImages} from './check-publication-images.mjs';

function fixture() {
  const target = {posts: Array.from({length: 24}, (_, i) => ({thumbPath: `p${i}/thumb.jpg`, detailPath: `p${i}/detail.jpg`}))};
  const paths = [...target.posts.flatMap(p => [p.thumbPath, p.detailPath]), 'cover/thumb.jpg', 'cover/detail.jpg'];
  const event = (path, stage) => ({key: digest(path).slice(0, 24), stage, action: 'end', outcome: 'success'});
  const events = [...paths.map(p => event(p, 'pipelineRequest.visible')),
    ...target.posts.map(p => event(p.thumbPath, 'ui.asset.assigned')), event('cover/thumb.jpg', 'ui.asset.assigned')];
  return [events, target, {objects: paths.map(path => ({path}))}];
}
test('DPI-P01 게시24개 썸네일 원본과 커버 성공을 확인하되 화면 Storage 원문 증명과 구분한다', () => {
  const r = publicationImages(...fixture()); assert.equal(r.objectPathsLoaded, 50);
  assert.equal(r.storageBytesOrJPEGHashProvenByThisValidator, false); assert.equal(r.manualFullSizeUIConfirmedByThisValidator, false);
});
test('DPI-P02 이미지0건 원본 누락 실패 및 UI 할당 없는 선행 로딩을 거절한다', () => {
  for (const mutate of [
    f => { f[0] = []; }, f => { f[0].splice(1, 1); }, f => { f[0][1].outcome = 'failure'; },
    f => { f[0] = f[0].filter(e => e.stage !== 'ui.asset.assigned'); }
  ]) { const f = fixture(); mutate(f); assert.throws(() => publicationImages(...f)); }
});
