# Lookbook Extraction Issue Operations Plan

## 전체 상태

- 제품·운영·API·data·security·release 상세 설계 완료.
- Phase 1 공통 계약과 Phase 2 자동 occurrence/cluster/대표 evidence 구현 완료.
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

목표:

- 전체 운영 loop를 Development에서 검증하고 Production 배포 가능한 상태로 마감한다.

예상 변경 범위:

- Development Functions/Worker/index/TTL/IAM.
- task progress/QA와 ENTRYPOINTS/DATA_SCHEMA/FIREBASE/LOOKBOOK/ADR.

완료 기준:

- 두 stage에서 `open → inProgress → fixed → retry success → verified`가 실제로 통과한다.
- `needsGroundTruth`, `wontFix`, 재발 reopen, evidence cleanup과 권한 거부를 확인한다.
- queue/Worker/Functions 오류와 임시 fixture/evidence 잔존이 없다.

검증:

- 자동 회귀 전체와 Development 실제 URL 통합 QA.
- Production diff, IAM, candidate, rollback plan을 읽기 전용 점검.

논의 필요 사항:

- Production 배포, traffic 전환, callable 삭제와 기존 데이터 cleanup은 각각 사용자 명시 승인 필요.
