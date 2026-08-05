# Lookbook Extraction Issue Operations Progress

## 현재 상태

- 2026-08-05 제품·운영 방향과 상세 API/data/release 설계를 확정했다.
- 공식 Cloud Run 인증 계약 점검에서 사용자 `gcloud` ID token의 audience 부재를 확인했고, Production은 환경별 전용 operator service account impersonation으로 확정했다.
- 2026-08-05 Phase 1 공통 계약, Phase 2 자동 기록, Phase 3 IAM 운영 API·CLI, Phase 4 runtime/smoke/verifier, Phase 5 iOS 단순 상태·레거시 제거를 완료했다. Phase 6 Development 인프라 통합과 상태 전이 QA도 완료했으며 실제 fix loop는 첫 추출 로직 수정 시 배포 게이트로 남겼다.
- 2026-08-05 첫 실제 fix 대상으로 AMOMENTO 시즌 discovery fingerprint `dea8279b10822fa379277cf56048492303616e89`를 선택했다. Cafe24 모달 행의 `button[data-url]`을 공통 후보로 읽는 contract 2를 Development에 배포하고 ground truth 15개 actual smoke, 총 관리자 재시도 성공, cluster `verified`까지 완료했다. Production은 변경하지 않았다.
- 2026-08-05 Phase 7의 `목록 이미지 우선 → 시즌 상세 콘텐츠 영역의 최상단 첫 유효 이미지 fallback`을 구현하고 Development 배포·실제 URL QA까지 완료했다. 첫 contract 3 job은 최신 5개만 채워 구형 `collection-images` 직접 영역 fixture 누락을 발견했고, Cafe24 adapter `1.0.1`로 보강한 뒤 AMOMENTO 후보·대표 이미지 15/15와 앱 렌더링을 확인했다. Production은 변경하지 않았다.

## 완료

- 실패 자동 기록, Codex cluster 요약·선택 처리, Production 반영 후 retry 활성화 흐름 확정.
- IAM private HTTP API와 read/write/release 분리 확정.
- service-account JSON 없이 현재 개발자 계정이 환경별 operator service account를 impersonate하고 audience 고정 단기 token을 사용하는 인증 계약 확정.
- 공통 fingerprint와 `open/inProgress/needsGroundTruth/fixed/verified/wontFix` 상태 확정.
- occurrence evidence 7일, 대표 evidence와 terminal cluster 60일 정책 확정.
- runtime registry와 Worker `/runtime-contract`, Production verifier 계약 확정.
- 앱 3단계 상태와 전역 issue UI 제외, 배포 전 앱이므로 레거시 호환 미지원 확정.
- phase 계획과 자동 테스트/수동 QA 경계 작성.
- canonical stage를 `seasonDiscovery | seasonImageImport`로 고정했다.
- runtime version을 `contract:{revision} | extractor:{semver}`로 분리하고 stage 불일치와 다른 종류 비교를 fail closed 처리했다.
- 로직 불충분만 issue로 인정하는 실패 분류, 두 stage 공통 40자 fingerprint, `jobPath + generation + evidenceID` occurrence key를 Functions와 Worker에 고정했다.
- 전체 허용·금지 상태 전이, stateVersion CAS, fixed/verified/wontFix 재발 reopen과 7일/60일 retention 계산을 순수 계약으로 고정했다.
- `contracts/lookbook-extraction-issue-v1.json` golden vector를 양 런타임 테스트가 함께 사용해 fingerprint drift를 차단한다.
- 시즌 discovery와 이미지 import가 공통 recorder로 로직 불충분 occurrence를 자동 기록한다.
- `expected_count_unverified` 단독 결과는 issue가 아닌 기존 검토로 유지한다.
- cluster의 영향 domain/brand 표본을 제거하고 adapter scope와 대표 evidence만 유지한다.
- occurrence ledger와 Storage evidence는 7일, terminal cluster 대표 evidence는 scheduled cleanup으로 정리한다.
- 기존 개선 요청 callable은 더 이상 cluster를 생성하거나 영향 domain을 집계하지 않는다.
- read/write Gen2 HTTP Function을 private invoker로 분리하고 project/environment/audience/verified operator email을 서버에서 재검증한다.
- read API는 bounded list, 단일 상세, 최대 20개 batch와 allowlist DTO만 제공하며 `brandID` filter와 최근 브랜드/job 사례를 제공하지 않는다.
- mutation API는 request ID 멱등 audit, stateVersion CAS, 허용 상태 전이와 정확한 job projection 갱신을 한 transaction 경계로 처리한다. client는 `fixed/verified/retry-ready`를 만들 수 없다.
- ground truth와 wont-fix enum, candidate key, note/body 크기를 strict parser로 제한했다.
- CLI는 고정 environment/project/function/operator만 사용하고 실제 Cloud Run URI를 audience로 하는 impersonated ID token을 발급한다. 임의 URL과 Firestore Admin 접근은 없다.
- Development 전용 operator service account를 만들고 현재 개발자에게 `roles/iam.serviceAccountTokenCreator`, operator에게 두 Cloud Run service의 `roles/run.invoker`를 부여했다.
- Development Firestore projection index와 audit TTL, 두 운영 Function을 배포했다. Production IAM·index·Function은 변경하지 않았다.
- Development 실제 endpoint에서 무인증 403, operator identity read 정상 응답, 존재하지 않는 fingerprint write의 애플리케이션 404를 확인했다. write smoke는 cluster/audit/job을 변경하지 않았다.
- Worker가 실행 revision/source revision, discovery contract, image extractor와 adapter map을 제공하는 IAM 전용 `/runtime-contract`를 제공한다.
- Worker `/smoke/extraction`은 대표 job URL을 두 stage의 실제 최신 추출 경로로 재실행하며 콘텐츠를 materialize하지 않는다.
- Production release Function은 Cloud Run v2의 Ready·reconciling·observed traffic 100%, runtime contract, source revision, 실제 smoke와 cluster CAS를 모두 검증한다.
- parse 실패는 동일 logic issue 제거로 판단하고, completeness 계열은 ground truth count/key 없이는 fail closed한다.
- 검증 성공은 24시간 smoke 영수증, runtime registry, fixed cluster와 cursor 기반 release record를 만들며 최대 200개씩 정확한 fingerprint job만 retry-ready로 갱신한다.
- 실제 retry 성공은 fixed runtime 경계를 다시 확인한 transaction으로 cluster를 verified로 바꾸고 60일 TTL을 설정한다.
- iOS는 job projection의 `open/inProgress/needsGroundTruth/fixed/wontFix`를 `개선 대기/처리 중/다시 가져오기 가능/추가 작업 필요`로 단순화하고, 총 관리자에게도 `fixed + 상위 동일-stage runtime`에서만 재시도를 제공한다.
- 시즌 목록과 이미지의 재시도 callable을 `retrySeasonDiscoveryAfterExtractionFix`, `retryLookbookExtractionAfterFix`로 교체하고 서버에서도 fixed/runtime 경계를 다시 검증한다. 기존 개선 요청·즉시 재분석 callable/export와 `improvementRequested*` 앱 계약은 제거했다.
- `wontFix` 사유를 job에 투영하며 source unavailable/access restricted 시즌 목록 문제는 기존 URL 수정 action만 제공한다. 이미지 import 행은 season/source title을 사용하고 job ID를 표시하지 않는다.

## 남은 작업

1. 목록 이미지를 제공하는 기존 브랜드의 Development 재탐색 시 목록 cover가 유지되는지 실제 QA한다.
2. 이미지 extraction stage의 첫 실제 로직 수정에서 `fixed → retry success → verified` 실제 URL 검증.
3. 별도 승인 기반 Production rollout과 기존 callable/data 정리.

## 현재 위험

- Production IAM principal, Cloud Run revision과 실제 smoke 대상은 배포 시점의 외부 상태이므로 구현 설계값으로 고정하지 않는다.
- Production 읽기 전용 점검에서 legacy cluster/evidence/import job 각 3건을 확인했다. 모두 성공·승인된 과거 데이터이므로 자동 변경하지 않았다.
- 배포된 기존 callable 삭제는 되돌리기 어려우므로 replacement 검증과 별도 승인이 필요하다.
- 상세 대표 이미지 보강은 외부 사이트 응답 시간에 영향을 받으므로 30개·동시 3개·15초의 best-effort 경계를 넘기지 않는다. 실패는 이미지 없음으로만 남기고 시즌 후보 성공을 바꾸지 않는다.

## 검증

- Functions `npm test`: 134/134 통과. Phase 3 auth/strict contract/pagination/batch/CAS/idempotency/job projection/index/export 계약을 포함한다.
- Worker `npm test`: 99/99 통과. sandbox 실행에서는 기존 HTTP server test 3개가 local listen `EPERM`으로 실패했으나 권한 있는 동일 재실행에서 모두 통과했다.
- Worker fixture corpus: 5/5 통과.
- Phase 3 CLI `npm test`: 7/7 통과, lint/build 통과.
- Functions/Worker `npm run lint`, `npm run build`: 모두 통과.
- Development Firestore index/TTL과 read/write Functions 배포를 완료했다. Worker와 Production은 배포하지 않았고 기존 데이터도 변경하지 않았다.
- 실제 Development IAM smoke는 read 성공, write 인증 후 예상 404, 무인증 403으로 통과했다.
- Phase 4 Functions 검증: 140/140, lint/build 통과. release projection page는 transaction으로 cursor·집계를 함께 전진시켜 verifier/reconciler 동시 실행의 중복 집계를 차단한다.
- Phase 4 Worker 검증: 102/102, lint/build와 fixture 5/5 통과.
- Phase 4 CLI 검증: 8/8, lint/build 통과.
- Phase 4 배포, Cloud Run traffic 조회 권한 변경, 실제 Production smoke/data mutation은 수행하지 않았다.
- Phase 5 Functions 검증: 141/141, lint/build 통과.
- Phase 5 Worker 검증: 102/102, lint/build 통과. sandbox의 localhost listen 제한으로 HTTP 테스트 3개가 실패한 첫 실행은 권한 있는 동일 재실행에서 모두 통과했다.
- Phase 5 iOS 검증: `OutPick-Development` generic Simulator build 통과, 관련 4개 suite 22개 targeted test 통과. 기존 Swift 6 actor isolation/deprecated API/library search path 경고는 남아 있으나 이번 변경 관련 실패는 없다.
- Phase 5 Functions/Worker 배포, index 삭제, 기존 callable 운영 삭제와 Production 변경은 수행하지 않았다.
- Phase 6 Functions 최종 검증은 142/142, CLI는 8/8, Worker는 102/102와 fixture corpus 5/5가 통과했고 각 lint/build가 통과했다.
- Development Firestore projection index와 audit/fix verification/fix release TTL을 적용했다. 구 `seasonDiscoveryJobs(status, improvementRequested)` index는 Development에서만 제거했다.
- Development release/read/write/retry/reconcile 관련 Functions를 배포하고 환경별 Worker service 매핑, runtime project fail-closed, release audience와 최소 IAM을 적용했다. Functions 재배포로 사라진 read/write invoker는 실제 403 확인 후 정확한 operator binding만 복구했다.
- Worker candidate `lookbook-import-worker-development-00006-pob`는 no-traffic 상태에서 Ready, `/readyz` 200, `/runtime-contract` 200, Functions diagnostic 빈 payload 500, Task import 빈 payload 500, Functions→Task 경계 403을 통과했다. runtime은 `outpick-test`, source `bd9bfb7e8fc96daad36d8a205bc044ac6fa689fa`, discovery contract 1, image extractor 1.2.3이다.
- 후보 검증에만 현재 개발자에게 두 Development service account의 Token Creator를 일시 부여했고 검증 직후 모두 회수했다. `00006-pob`를 Development traffic 100%로 전환했으며 rollback은 `00004-xal`이다. 전환 후 신규 ERROR와 두 queue pending은 0건이다.
- Development 전용 fixture로 `open → inProgress → needsGroundTruth → inProgress → wontFix → open`, stale CAS 거부, 무인증 403, job projection과 audit 5건을 실제 API에서 확인했다. fixture cluster/job/audit는 모두 삭제해 잔존 0건이다.
- 실제 cleanup Scheduler 수동 실행은 fixture 외 기존 만료 evidence까지 함께 삭제할 수 있어 수행하지 않았다. 생성했던 만료/비만료 cleanup fixture와 Storage 객체는 즉시 정확히 삭제했고 잔존 0건을 확인했다. 격리 cleanup 단위 테스트와 TTL `ACTIVE` 상태를 검증 근거로 유지한다.
- 실제 extraction fix가 없고 Development cluster도 0건이므로 가짜 `fixed` 성공을 합성하지 않는다. 실제 `fixed → retry → verified`는 첫 runtime 상승이 있는 로직 수정에서 필수로 검증한다.
- Production 읽기 전용 diff에서 기존 Worker `lookbook-import-worker-00024-fow` traffic 100%와 rollback 후보 이력을 확인했다. Production Worker에는 새 runtime metadata가 없고 issue operations Functions, extraction projection index, audit/fix TTL도 아직 없다. Production은 변경하지 않았으며 이 차이 전체가 별도 승인 rollout 대상이다.
- AMOMENTO contract 2 최종 검증은 Functions 145/145·lint/build, Worker 103/103·fixture 6/6·lint/build, iOS targeted test 12개와 Development build가 통과했다. Worker `00008-foq` traffic 100%에서 실제 공개 URL 후보 15개, `fixed` version 5, Simulator 총 관리자 재시도 job 후보 문서 15개·contract 2·`succeeded`, cluster `verified` version 6을 확인했다. 두 queue와 관련 신규 ERROR는 0건이다.
- 통합 중 Cloud Run tag-only 0% traffic을 활성 traffic으로 오인하는 verifier, 삭제된 대표 job을 fallback하지 못하는 verifier, 새 시즌 재시도 job에 fix projection이 승계되지 않는 세 결함을 발견해 테스트와 함께 보강했다. 이미 성공한 Development job은 엄격한 성공·contract·fingerprint 전제 확인 후 동일 공통 verified 로직으로 한 번 보정했다.
- Phase 7 로컬 검증은 최종 Worker 115/115·fixture 9/9·lint/build, Functions 146/146·lint/build, `OutPick-Development` Development-Debug Simulator build가 통과했다. Development Functions 9개를 contract 3으로 배포했고 Worker `lookbook-import-worker-development-00012-fih` source `3597b2b`, contract 3, extractor `1.2.3`, Cafe24 adapter `1.0.1`로 traffic 100% 전환했다. rollback은 `00010-hiq`다.
- 첫 앱 재탐색 job `eyE4A6dz5N7xFE1Ax1zF`은 후보 15개를 유지했지만 대표 이미지 5/15여서 구형 AMOMENTO `collection-images` 직접 영역 누락을 발견했다. 공통 Cafe24 규칙과 incident fixture를 보강한 뒤 앱에서 생성한 job `GwToZCXiZ9iUfKp4tDMg`은 후보 15개·상세 성공 15·실패 0으로 성공했고 저장 URL 15개가 각 실제 상세의 첫 유효 이미지와 모두 일치했다.
- iPhone 17 Pro Max iOS 26.2 Simulator의 신규 시즌 선택 화면을 상단·중간·하단까지 확인해 15개 카드의 대표 이미지 렌더링을 확인했다. 실제 QA 시작 이후 두 queue pending과 Worker/Functions 신규 ERROR는 0이고 배포 Functions 9개는 모두 ACTIVE다.
- Development candidate QA는 사용자 `gayunkim.1@gmail.com`에 두 정확한 Development 서비스 계정 리소스의 `roles/iam.serviceAccountOpenIdTokenCreator`만 영구 부여하고 IAM Credentials `generateIdToken`을 사용한다. 사용자 Token Creator, 서비스 계정 key와 Production 영구 binding은 사용하지 않는다.
