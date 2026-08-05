# Lookbook Extraction Issue Operations Plan

## 전체 상태

- 제품·운영·API·data·security·release 상세 설계 완료.
- Phase 1 공통 계약과 Phase 2 자동 occurrence/cluster/대표 evidence 구현 완료.
- Phase 7 시즌 대표 이미지 보강의 상세 설계와 구현 계획을 확정했으며 구현 승인을 기다린다.
- 각 phase의 Production 배포와 데이터 cleanup은 별도 명시 승인을 받는다.

## Phase 1. 공통 계약과 순수 테스트

상태: 완료.

목표:

- 두 stage의 issue 분류, fingerprint, 상태 전이, retention과 runtime version 비교를 Firebase와 분리해 고정한다.

예상 변경 범위:

- `functions/src/lookbook/import/` 공통 issue contract/state/retention 모듈과 테스트.
- `tools/lookbook-import-worker/src/extraction/` 공통 identity/evidence contract와 테스트.
- 필요 시 공유 JSON fixture contract.

완료 기준:

- 로직 불충분과 transient/input/permanent/identity-review가 table test로 분리된다.
- occurrence key와 fingerprint가 stage 간 동일 규칙으로 결정적이다.
- 유효/무효 상태 전이, stateVersion CAS, 재발 reopen과 7일/60일 계산이 고정된다.

검증:

- Functions/Worker unit test, lint, build.

논의 필요 사항:

- 없음. 구현 시작 승인만 필요하다.

## Phase 2. 자동 occurrence·cluster·대표 evidence

상태: 완료.

목표:

- 시즌 discovery와 이미지 import 실패가 버튼 없이 issue를 자동 기록한다.

예상 변경 범위:

- Worker `processor.ts`, `season-discovery-processor.ts`와 evidence retention 모듈.
- Functions cleanup/reconciler와 필요한 Firestore indexes/TTL 설정.
- 기존 개선 요청 기반 cluster 생성을 제거하는 Functions 코드.

완료 기준:

- 중복 task/transaction이 count를 중복 증가시키지 않는다.
- 대표 evidence 한 개가 미해결 동안 보존되고 terminal +60일에 정리된다.
- job projection이 cluster 상태와 일치한다.
- 기존 7일 occurrence cleanup이 대표 evidence를 삭제하지 않는다.

검증:

- Worker transaction fake/integration test, cleanup 경계 test, fixture differential 전체.
- Firestore index/TTL dry-run. 실제 적용은 승인 후.

논의 필요 사항:

- 없음. 읽기 전용 확인 결과 Production의 legacy cluster/evidence/import job 각 3건은 성공·승인된 과거 데이터라 자동 backfill/삭제하지 않는다.

## Phase 3. IAM 운영 API와 Codex CLI

상태: 완료. Development 배포·identity smoke까지 수행했으며 Production은 미변경이다.

목표:

- Firestore 직접 접근 없이 안전한 cluster 요약·상세·상태 mutation을 제공한다.

예상 변경 범위:

- `functions/src/lookbook/issueOperations/` 후보와 `functions/src/index.ts`.
- `tools/lookbook-extraction-issue-ops/` CLI.
- 환경별 canonical endpoint/operator 설정과 IAM 배포 문서.

완료 기준:

- IAM + ID token audience/issuer/email 검증이 모두 통과해야 한다.
- 목록 pagination과 batch 20개 상한, allowlist DTO, request ID 멱등성, CAS가 동작한다.
- CLI는 environment 필수, 임의 URL·Firestore Admin 접근 불가, token 비로그를 지킨다.

검증:

- auth 실패, 환경 교차, malicious payload, pagination, missing/expired evidence, 중복 mutation 자동 테스트.
- Development 실제 운영자 identity smoke. Production IAM 변경은 별도 승인.

논의 필요 사항:

- 없음. Development operator와 실제 Cloud Run audience를 확인해 적용했다. Production principal/IAM/배포는 별도 승인 사항이다.

## Phase 4. Runtime registry와 Production fix verifier

상태: 로컬 구현·fake rehearsal 완료. Production/Development 배포와 실제 URL smoke는 미수행이다.

목표:

- 실제 Production revision 검증 뒤에만 retry를 활성화한다.

예상 변경 범위:

- Worker `/runtime-contract`와 runtime metadata.
- Functions release verifier, runtime registry, smoke run 조회와 bounded readiness reconciler.
- Worker candidate/traffic 스크립트의 검증 결과 접합부.

완료 기준:

- partial traffic, revision/version mismatch, Development project, stale smoke와 stale stateVersion을 거부한다.
- registry/cluster/release record가 일관되고 projection 갱신이 cursor로 멱등 재개된다.
- fixed job은 자동 실행되지 않으며 성공 재시도만 verified를 만든다.

검증:

- fake Run API/runtime endpoint/smoke record 기반 unit test.
- no-traffic candidate → 100% traffic → verifier Development rehearsal.
- Production 전환은 PR 승인과 별도 배포 승인 후 수동 QA.

논의 필요 사항:

- 없음. release마다 사용자가 cluster와 Production revision/runtime을 선택하며, 서버가 cluster의 대표 job URL을 내부에서 해석한다. 실제 Production 실행은 별도 승인 사항이다.

## Phase 5. iOS 단순 상태와 레거시 제거

상태: 로컬 구현·자동 검증 완료. Simulator 화면 수동 QA와 배포는 Phase 6에서 수행한다.

목표:

- 앱을 세 운영 상태와 안전한 retry action으로 단순화한다.

예상 변경 범위:

- discovery/import domain entity, repository mapper/use case/ViewModel.
- `SeasonImportManagementView`, `LookbookExtractionReviewView`.
- 기존 개선 요청 protocol/implementation/callable export 제거.

완료 기준:

- open/inProgress·needsGroundTruth/fixed가 확정 문구와 action으로 표시된다.
- fixed 이전 시즌 목록·이미지 재추출을 앱과 서버 모두 거부한다.
- 시즌 image import 행은 시즌명을 유지한다.
- 레거시 `improvementRequested`를 새 앱이 읽거나 쓰지 않는다.

검증:

- fake repository 기반 ViewModel 상태/action 테스트.
- targeted iOS build/test, Simulator 상태 fixture 수동 QA.

논의 필요 사항:

- 없음. 화면의 실제 간격·Dynamic Type 문제만 수동 QA에서 조정한다.

## Phase 6. Development 통합·문서·Production 준비

상태: Development 인프라 통합과 상태 전이 QA 완료. 실제 extraction fix가 없는 상태에서 가짜 `fixed`를 만들지 않기로 확정했으며, 두 stage의 `fixed → retry success → verified`는 첫 실제 로직 수정과 runtime 상승 시 필수 배포 게이트로 수행한다.

목표:

- 전체 운영 loop를 Development에서 검증하고 Production 배포 가능한 상태로 마감한다.

예상 변경 범위:

- Development Functions/Worker/index/TTL/IAM.
- task progress/QA와 ENTRYPOINTS/DATA_SCHEMA/FIREBASE/LOOKBOOK/ADR.

완료 기준:

- Development Worker candidate와 환경별 verifier/IAM/TTL/index/Functions 계약이 실제 환경에서 통과한다.
- `needsGroundTruth`, `wontFix`, 재발 reopen, evidence cleanup과 권한 거부를 확인한다.
- queue/Worker/Functions 오류와 임시 fixture/evidence 잔존이 없다.
- 두 stage의 `open → inProgress → fixed → retry success → verified`는 실제 extraction 로직 수정과 상위 runtime이 존재할 때 통과해야 하며, 운영 시스템 자체 QA를 위해 이를 합성하지 않는다.

검증:

- 자동 회귀 전체와 Development 실제 URL 통합 QA.
- Production diff, IAM, candidate, rollback plan을 읽기 전용 점검.

논의 필요 사항:

- Production 배포, traffic 전환, callable 삭제와 기존 데이터 cleanup은 각각 사용자 명시 승인 필요.

## Phase 7. 시즌 대표 이미지 보강

상태: 로컬 구현·자동 검증 완료. Development 배포·실제 QA 승인 대기.

목표:

- 시즌 identity 결과와 대표 이미지 표시를 분리하고, 모든 브랜드에서 목록 이미지가 없으면 시즌 상세 콘텐츠 영역의 최상단 첫 유효 이미지로 보강한다.

변경 범위:

- Worker 공통 이미지 후보 추출 모듈과 bounded season-cover enrichment 모듈.
- `season-discovery.ts`의 cover 기반 후보 제거 삭제, 목록 우선 병합과 상세 보강 orchestration.
- Generic detail fallback과 Platform/Domain content-section 보강 계약.
- candidate provenance와 season discovery job cover 집계.
- Functions/Worker season discovery runtime `contract:3` 정렬.
- Worker 단위 테스트, AMOMENTO 상세 fixture와 전체 corpus differential.
- 관련 Worker/Firebase/Test/data/architecture 진입점 문서와 task 하네스.

예상 변경 파일:

- `tools/lookbook-import-worker/src/extraction/{image-candidates,season-cover}.ts` 신규 후보
- 필요 시 `tools/lookbook-import-worker/src/extraction/adapters/{types,cafe24}.ts`
- `tools/lookbook-import-worker/src/{processor,season-discovery,season-discovery-processor}.ts`
- 관련 `*.test.ts`, `fixtures/discovery/generic/season-detail-cover/` 신규 후보와 `fixtures/discovery/platform/cafe24-modal-data-url/`
- `functions/src/shared/seasonDiscoveryCreation.ts`
- `functions/src/lookbook/import/seasonDiscoveryContract.test.ts`
- `scripts/ai/deploy-lookbook-import-worker.sh`
- 관련 `docs/ai/` 문서

구현 순서:

1. 이미지 content-section 선택 순수 로직을 side effect 없는 공유 모듈로 분리하고 기존 이미지 import 회귀 테스트를 유지한다.
2. cover 기반 후보 필터를 제거하고 목록 대표 이미지의 우선순위·출처를 고정한다.
3. 모든 플랫폼에 공통인 Generic 콘텐츠 영역 판정과 Platform/Domain 보강, 30개·동시 3개·`min(15초, 전체 deadline 잔여 시간)` 제한을 가진 best-effort 보강기를 구현한다.
4. candidate provenance와 job 집계를 저장하고 snapshot/runtime 계약을 `contract:3`으로 맞춘다.
5. adapter 없는 Generic 상세 fixture, AMOMENTO 상세 fixture와 기존 fixture differential, 실패·동시성·deadline 테스트를 추가한다.
6. Worker/Functions 전체 test·lint·build와 fixture corpus를 실행한다.
7. 별도 배포 승인 후 Development candidate Worker와 Functions를 배포하고 AMOMENTO 새 job 15개·대표 이미지·앱 표시·queue/error를 실제 QA한다.

완료 기준:

- 후보 개수, 제목, URL과 순서가 대표 이미지 유무로 바뀌지 않는다.
- 목록 이미지가 항상 우선하고, 상세 페이지에서는 실제 시즌 콘텐츠 영역의 최상단 첫 유효 이미지만 fallback된다.
- 상세 보강 실패가 discovery 실패나 issue를 만들지 않는다.
- 최대 30개, 동시 3개, 15초와 public HTTP 안전 경계가 자동 테스트로 고정된다.
- candidate/job 관찰 필드와 집계 불변식이 검증된다.
- Functions/Worker contract 3, 전체 test·fixture·lint·build가 통과한다.
- adapter 없는 Generic fixture와 Development AMOMENTO 실제 15개·앱 대표 이미지 QA가 통과하고 Production은 변경하지 않는다.

검증 방법:

- Worker 순수·orchestration unit test와 fixture corpus 전체.
- adapter 없는 Generic 상세와 Cafe24 Platform 상세의 동일 결과 계약, header/banner/footer/related 제외 fixture.
- Functions season discovery contract test와 전체 test·lint·build.
- Development iOS build 및 실제 AMOMENTO 신규 시즌 선택 화면 수동 QA.
- Development Worker/Functions 로그와 Cloud Tasks backlog 확인.

의존성·충돌 가능성:

- `processor.ts`의 이미지 후보 추출을 공유하므로 기존 season image import와 같은 service 경계를 건드린다. 분리와 discovery 통합을 병렬 구현하지 않고 순차 진행한다.
- Functions canonical revision과 Worker 배포 환경 revision은 한 phase에서 동일하게 변경한다.
- Swift DTO/UI는 기존 nullable `coverImageURL`을 이미 지원하므로 앱 코드 변경은 예상하지 않는다.
- MVVM-C/Repository/UseCase/DI/Coordinator 변경은 없다.

논의 필요 사항:

- 없음. 상세 계약은 `phase-7-season-cover-enrichment.md`로 확정했다.
- 코드 구현은 사용자 승인으로 완료했다. Development 배포와 Production rollout은 각각 별도 승인 범위다.
