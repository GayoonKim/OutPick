import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

test('DVP-S01 일반 조립의 공유 transport는 공개 요청 두 호출만 원본 오류를 보존한다', () => {
  const source = readFileSync('OutPick/App/AppCompositionRoot.swift', 'utf8');
  const initialization = source.match(/let cloudFunctionsTransport = FirebaseCloudFunctionsTransport\(([\s\S]*?)\n        \)/);
  assert.ok(initialization, '일반 앱 transport 조립을 찾지 못했습니다.');
  const preserved = initialization[1].match(/preservingErrorDetailsForCalls:\s*\[([^\]]+)\]/);
  assert.ok(preserved, '일반 앱에서 공개 요청의 원본 오류 보존 옵션이 빠졌습니다.');
  const names = [...preserved[1].matchAll(/"([^"]+)"/g)].map(match => match[1]);
  assert.deepEqual(names.sort(), ['listMyBrandRequests', 'submitBrandRequest']);
  const lookbook = source.match(/let lookbookProvider = LookbookRepositoryProvider\.live\(([\s\S]*?)\n        \)/);
  assert.ok(lookbook);
  assert.match(lookbook[1], /transport: cloudFunctionsTransport/);
});

test('DVP-S02 정상 DEBUG 관측은 브랜드 요청 Repository에만 주입하고 기본 transport를 보존한다', () => {
  const root = readFileSync('OutPick/App/AppCompositionRoot.swift', 'utf8');
  const provider = readFileSync('OutPick/Features/Lookbook/Repositories/LookbookRepositoryProvider.swift', 'utf8');
  const observer = readFileSync('OutPick/App/Bootstrap/DevelopmentBrandRequestEvidenceTransport.swift', 'utf8');
  assert.match(root, /#if DEBUG\s+let brandRequestEvidenceTransport = DevelopmentBrandRequestEvidenceTransport\.makeIfEnabled\(/);
  assert.match(root, /brandRequestTransport: brandRequestEvidenceTransport/);
  assert.match(provider, /brandRequestTransport: \(any CloudFunctionsTransporting\)\? = nil/);
  assert.match(provider, /brandRequestRepository: CloudFunctionsBrandRequestRepository\(transport: brandRequestTransport \?\? transport\)/);
  assert.ok(observer.startsWith('#if DEBUG'));
  assert.doesNotMatch(observer, /useEmulator|FirebaseApp\.configure|signIn\(|tenantID\s*=/);
});
