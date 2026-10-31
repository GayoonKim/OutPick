import test from 'node:test';
import assert from 'node:assert/strict';
import {imageMetric} from './capture-image-metrics.mjs';

const key = 'a'.repeat(24);
const line = `[ImageBaseline] seq=1 t=10.5 id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA parent=none key=${key} stage=ui.asset.assigned action=end outcome=success ms=0.1 active=0 bytes=100 heldBytes=0`;
test('DIM-P01 기존 이미지 계측에서 승인 게시 경로 hash의 허용 값만 수집한다', () => {
  assert.equal(imageMetric(line, new Set([key])).stage, 'ui.asset.assigned');
  assert.equal(imageMetric(line, new Set([key])).bytes, 100);
});
test('DIM-P02 다른 이미지 임의 콘솔 개인정보 문자열과 손상 숫자를 기록하지 않는다', () => {
  for (const value of [line.replace(key, 'b'.repeat(24)), 'token=private-canary',
    line.replace('outcome=success', 'outcome=private-canary'), line + ' token=private-canary', line.replace('t=10.5', 't=..')]) {
    assert.equal(imageMetric(value, new Set([key])), null);
  }
});
