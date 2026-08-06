# Lookbook Extraction Issue Operations Production Rollout QA Checklist

## Phase 1 읽기 전용 감사

- [x] Production Worker live traffic과 rollback revision을 확인한다.
- [x] Worker runtime/source/contract/extractor/adapter를 확인한다.
- [x] Production Functions exact 배포 목록과 runtime identity/environment를 확인한다.
- [x] 필요한 Firestore composite 1개·field index 3개·TTL 6개 diff를 확인한다.
- [x] Production operator/release/task/functions IAM diff를 확인한다.
- [x] active discovery/import job과 queue 상태를 확인한다.
- [x] contract cutover의 pause/drain 불필요와 Worker-first 순서를 결정한다.

## 로컬·candidate 게이트

- [x] Worker test 115/115·lint·build와 fixture corpus 9/9가 통과한다.
- [x] fixture의 민감 query 차단과 실제 candidate 응답의 마스킹 evidence를 확인했고 OIDC token을 출력·기록하지 않았다.
- [x] cursor projection reconciler와 iOS wontFix/title 검증은 Worker candidate 차단 조건이 아니며 backend/app end-to-end 단계로 재분류했다.
- [x] Worker no-traffic candidate `00026-qes`와 live `00024-fow`·rollback `00023-879`를 확보한다.
- [x] candidate `/readyz`와 `/runtime-contract`가 source·contract·extractor·adapter까지 일치한다.
- [x] Functions/Task caller OIDC 경계가 기대 상태 코드 200/403/500을 반환한다.
- [x] 해칭룸 실제 discovery 20개·대표 이미지 20개와 이미지 extraction 12개 read-only smoke가 통과한다.
- [x] 의도한 빈 payload ERROR 3건 이후 unexpected ERROR 0건, import queue pending 0건이고 live traffic은 기존 revision 100%다.

## Production cutover

- [x] 사용자에게 backend exact mutation 범위를 승인받는다.
- [x] Worker traffic/canonical contract 전환을 별도 승인받았다.
- [x] 승인된 순서로 Functions/Worker contract를 일치시킨다.
- [x] Worker live traffic `00026-qes` 100%와 runtime contract를 재확인했다.
- [x] Firestore composite 1개·field override 3개·TTL 6개가 `READY`/`ACTIVE`다.
- [x] discovery queue가 승인된 rate/retry 설정으로 `RUNNING`이다.
- [x] Production operator와 private read/write/release invoker가 exact resource 최소 권한이며 public invoker가 없다.
- [x] Function 12개가 ACTIVE이고 실제 URI·audience와 scheduler 상태가 일치한다.
- [x] 운영 CLI는 direct IAM Credentials `generateIdToken`만 사용하고 광범위한 impersonation 권한 없이 9/9 테스트를 통과한다.
- [x] 실제 Production discovery smoke가 성공한다.
- [x] 실제 Production createBrand → queue → Worker → published pointer는 contract 3, attempt 1, retry 0으로 완료된다.
- [x] Production Firestore rules에 exact durable discovery read 경계를 배포하고 총 관리자 앱 read를 통과한다.
- [x] canonical 해칭룸 archive URL로 후보·대표 이미지와 앱 카드 표시를 다시 검증한다.
- [x] backend 배포 후 두 queue task와 신규 Worker/Functions ERROR가 0건이다.
- [x] 사용자 영구 OIDC binding은 승인된 두 exact service account의 `roles/iam.serviceAccountOpenIdTokenCreator`만 사용한다.

## 제외·후속

- [x] 기존 callable 삭제는 이번 rollout 승인에 포함하지 않는다.
- [x] legacy data cleanup은 이번 rollout 승인에 포함하지 않는다.
- [x] 과거 실패 job을 자동 재실행하지 않는다.
- [x] 실제 이미지 extraction fix loop는 결함 발생 시 이벤트 기반 QA로 실행한다.
- [x] QA 브랜드 부모·하위 102개·이름 인덱스 1개를 별도 승인받아 삭제하고 Firestore·Storage 잔존 0을 확인한다.
- [x] legacy callable 1개를 제거하고 replacement `retryLookbookExtractionAfterFix` ACTIVE를 확인한다.
- [x] retention 만료 뒤 legacy cluster 3개·evidence 3개·Storage JSON 3개를 삭제하고 잔존 0을 확인한다.
- [x] 게시된 시즌이 참조하는 legacy import job 3개와 연결 콘텐츠는 보존한다.
- [x] Firebase 원문 오류는 내부 로그로만 남기고 안정된 사용자 문구를 발행하도록 교정했으며 targeted 9/9와 Production Simulator build를 통과했다.
- [x] 안전하게 재현할 수 없는 실패 화면 수동 QA는 완료 게이트에서 제외하고 원문 비노출·안정 문구를 targeted 테스트로 고정한다.
