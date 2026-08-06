# Lookbook Extraction Issue Operations Production Rollout Progress

## 현재 상태

- 2026-08-06 `lookbook-extraction-issue-operations`를 Development 구현·QA 완료로 종료하고 Production rollout을 별도 핵심 task로 분리했다.
- Phase 1~5 기능 E2E와 승인된 QA·legacy cleanup을 완료했다. exact Production Firestore rules, canonical discovery 20개·대표 이미지 20개, 앱 카드 표시, 최종 queue/ERROR 0을 확인해 task를 종료했다.
- Production Worker `lookbook-import-worker-00026-qes`를 source `1dbe6e1774686fe8186dc79b9551de779e7c4b60`, contract 3, traffic 100%로 전환했다. `00024-fow`를 rollback revision으로 보존했다.
- Production task/functions service account와 operator exact 리소스에 사용자 `gayunkim.1@gmail.com`의 `roles/iam.serviceAccountOpenIdTokenCreator`만 영구 부여했다. project-level Token Creator, access token impersonation, signing과 key는 사용하지 않는다.

## 완료

- task 경계, 승인 게이트, 제외 범위와 완료 기준 문서화.
- 이벤트 기반 이미지 extraction QA를 실제 결함 발생 시 운영 게이트로 분리.
- legacy callable/data cleanup을 별도 파괴 승인 작업으로 분리.
- Worker live `lookbook-import-worker-00024-fow` traffic 100%, rollback `00023-879`, Ready 상태와 runtime identity/env를 확인했다.
- live source zip을 직접 확인해 extractor `1.2.3`, Cafe24 adapter `1.0.0`, durable discovery endpoint/runtime contract/source metadata가 없는 레거시 runtime임을 확정했다.
- Production Functions에는 구 diagnostic 2개만 있고 durable discovery 7개와 issue operations 4개는 없다. 배포된 `createBrand` 소스에도 durable discovery job 생성이 없으므로 신규 11개와 `createBrand`를 합친 12개가 exact 배포 대상이다.
- Production에는 `lookbook-discovery-jobs` queue와 `seasonDiscoveryJobs`가 없고 기존 import job 3건은 모두 성공, active/pending job은 0건이다.
- local contract 대비 Firestore field index 3개와 TTL 6개가 없음을 확인했다.
- Production operator service account는 없고 compute/task/Worker IAM 현황과 Worker invoker를 확인했다.
- 2026-08-05 이후 Production Worker/Functions severity ERROR는 0건이다.
- 따라서 queue pause/drain 없이 Worker contract 3 candidate 검증·traffic 전환을 먼저 하고 durable discovery backend/Functions를 뒤에 활성화하는 순서를 확정했다.
- candidate 배포 전 Worker 115/115, lint, fixture 9/9가 통과했다. revision은 Ready이고 env/source/contract/runtime identity와 image digest를 확인했으며 신규 severity ERROR는 0건이다.
- 사용자 승인으로 Production task/functions service account 두 exact 리소스에 좁은 `roles/iam.serviceAccountOpenIdTokenCreator`를 영구 부여했다. IAM Credentials `generateIdToken` 직접 호출만 사용했으며 access token impersonation·signing·key는 만들지 않았다.
- candidate OIDC matrix는 task identity의 `/readyz` 200, import/discovery task 빈 payload 500, runtime 403과 functions identity의 runtime 200, diagnostic 빈 payload 500, import/discovery task 403으로 caller 분리를 확인했다.
- `/runtime-contract`는 Worker `00026-qes`, source `1dbe6e1`, contract 3, extractor `1.2.3`, Cafe24 `1.0.1`과 일치했다.
- 기존 Production 해칭룸 성공 import job의 실제 URL로 `seasonImageImport` smoke가 HTTP 200, 후보 12개, logic issue false, failure 0이었다.
- 기존 Production 해칭룸 archive URL의 실제 discovery diagnostic은 HTTP 200, 후보 20개·목록 대표 이미지 20개, 상세 fallback 0, `passed`, failure 0이었다.
- candidate QA 당시 caller matrix의 의도한 빈 payload 500 세 요청만 Cloud Run request ERROR로 기록됐다. 해당 시점 이후 actual smoke의 unexpected ERROR는 0건이고 import queue pending도 0건이었으며 당시 live traffic은 `00024-fow` 100%였다.
- traffic 전환 직전 candidate Ready, live `00024-fow` 100%, queue pending 0, actual smoke 이후 unexpected ERROR 0을 재확인하고 `00026-qes=100`만 적용했다.
- 전환 후 canonical service URL의 `/readyz`, `/runtime-contract`, 해칭룸 실제 `seasonImageImport` smoke가 모두 HTTP 200이었다. runtime은 `00026-qes`·source `1dbe6e1`·contract 3·extractor `1.2.3`·Cafe24 `1.0.1`, 후보 12개·logic issue false·failure 0이었다.
- 최종 traffic `00026-qes` 100%, import queue pending 0, 전환 검증 시작 이후 severity ERROR 0을 확인했다. `00024-fow`는 traffic 0% rollback으로 유지한다.
- Functions는 배포 전 test 146/146, lint/build를 통과했다. CLI는 직접 IAM Credentials `generateIdToken` 경로와 fail-closed 회귀 테스트를 포함해 9/9, lint/build를 통과했다.
- Firestore `candidates(resolution ASC, sortIndex ASC)` composite, collection-group field override 3개, TTL 6개를 배포해 모두 `READY`/`ACTIVE`를 확인했다. `--force`를 사용하지 않아 로컬에 없는 기존 remote override 5개는 보존했다.
- `lookbook-discovery-jobs`를 초당 1건·동시 1건·최대 3회·30~300초 backoff·1시간 retry duration·로그 100%로 생성했고 `RUNNING`을 확인했다.
- `outpick-extraction-ops-prod@outpick-664ae.iam.gserviceaccount.com`을 만들고 사용자에게 exact operator 리소스의 좁은 OIDC 역할만, operator에게 read/write/release 세 private Cloud Run service의 invoker만 부여했다. 공개 invoker는 없다.
- durable discovery 7개, issue operations 4개, `createBrand`를 합친 Function 12개가 모두 ACTIVE/Node 24다. 실제 URI와 read/write/release audience가 일치하고 두 10분 scheduler가 ENABLED임을 확인했다.
- 운영 CLI가 `gcloud --impersonate-service-account`로 광범위한 access token 권한을 요구하던 구현을 제거했다. 고정 사용자 access token으로 exact operator의 IAM Credentials `generateIdToken`만 직접 호출하며 token은 출력·저장하지 않는다.
- Production private API smoke는 무인증 read 403, operator read 성공, 존재하지 않는 fingerprint write 404 fail-closed로 데이터 변경 없이 통과했다.
- 배포 후 import/discovery queue task 0, `seasonDiscoveryJobs` 0, Worker와 Function 12개의 신규 severity ERROR 0을 확인했다.
- Production Simulator에서 Kakao 총 관리자 `kakao:3647141989`로 QA 브랜드 `PC1aBgoDY9PbWHCroRXq`와 최초 job `NBNCRkQ6Q8m9gA4kJ0EN`을 생성했다. job은 contract 3·attempt 1·retry 0으로 `succeeded`, 후보 80·목록 대표 이미지 80이었다.
- 앱 후보 조회는 `Missing or insufficient permissions`로 실패했다. 배포 ruleset은 2026-07-29 버전이고 로컬과의 전체 차이는 `seasonDiscoveryJobs`, 하위 `candidates`, `reviews`에 기존 `hasBrandWriteAccess(brandID)` read와 client write deny를 추가하는 15줄뿐임을 확인했다.
- 로컬 rules emulator에서 rules 30/30, transaction 7/7과 seed apply 후 변경 0 dry-run이 통과했다. Firebase CLI는 모든 검증과 emulator 정리 뒤 `unexpected error`로 exit 2를 반환했으므로 wrapper 종료 코드는 미통과로 기록한다.
- 최초 smoke URL을 기존 Production 데이터에서 먼저 조회하지 않고 `https://hatchingroom.com/archive`로 선택한 판단 오류가 있었다. 현재 이 URL은 상품 목록으로 해석돼 80개 상품 후보가 생겼으므로 유효한 시즌 QA 증거에서 제외한다. canonical URL은 `https://hatchingroom.com/product/archive-list.html?cate_no=226`이다.
- 첫 smoke 완료 시점 이후 import/discovery queue task 0, Worker/Functions severity ERROR 0을 재확인했다. 앱의 permission-denied는 Firestore client 오류이며 Cloud Run ERROR를 만들지 않았다.
- 사용자 승인으로 `firebase deploy --only firestore:rules --project outpick-664ae`를 실행했다. release `projects/outpick-664ae/releases/cloud.firestore`는 ruleset `bce94c07-bb86-4f9c-a74e-e14dc954085c`로 갱신됐고 로컬·운영 `firestore.rules` SHA-256은 `d1978d27b63a73ae5bc230c3fed4bf9c3b0484b6fd44f7305fd8372ffb59cc74`로 정확히 일치한다.
- QA 브랜드의 archive URL을 canonical `https://hatchingroom.com/product/archive-list.html?cate_no=226`로 교정하고 새 job `x7JF1V6Y9byFJI6NyStR`을 요청했다. job은 `succeeded`, 후보 20·대표 이미지 20·목록 대표 이미지 20이며 Kakao 총 관리자 앱에서 20개 카드의 실제 대표 이미지와 제목을 확인했다.
- 재검증 뒤 `lookbook-discovery-jobs`는 승인된 rate/retry 설정과 `RUNNING`, task 0건이고 2026-08-06T06:31:00Z 이후 Worker/Functions severity ERROR는 0건이다.
- 최초 권한 오류 원문이 화면에 남은 직접 원인은 `CreateBrandDiscoveryViewModel.start()`가 `error.localizedDescription`을 `errorMessage`에 그대로 저장하고 `CreateBrandFlowView`가 이를 표시했기 때문이다. 이를 내부 `NSError` 진단 로그와 `시즌 목록을 불러오지 못했어요. 브랜드 등록을 마친 뒤 다시 찾아올 수 있어요.` 사용자 문구로 분리했다.
- `SeasonDiscoveryManagementViewModelTests`에 infrastructure 원문 비노출과 기존 job 성공 발행 회귀를 추가했다. 관련 9/9와 `OutPick-Production`/`Production-Debug` Simulator build가 통과했다.
- 이후 화면 조작·시각 QA는 사용자가 제공받은 체크리스트로 수행한다. Codex는 Simulator를 직접 조작하지 않고 코드, 자동 테스트·빌드, backend/log 자동 검증을 담당한다.
- 읽기 전용 감사에서 QA 브랜드는 부모 1개, 두 discovery job과 후보 100개를 포함한 하위 102개, 이름 인덱스 1개였고 외부 상태·Storage는 0개였다. 사용자 승인 뒤 정확한 104개 Firestore 문서를 삭제해 잔존 0을 확인했다.
- legacy import job 3개는 각각 현재 게시된 시즌과 포스트 12·24·26개의 source job이므로 삭제 대상에서 제외하고 보존했다.
- 코드·앱 참조가 없는 `requestLookbookExtractionReanalysis`를 삭제했다. 삭제 후 Production에 replacement가 아직 없음을 확인해 Functions lint/build·전체 146/146 뒤 사용자 exact 승인으로 `retryLookbookExtractionAfterFix` 하나를 배포했고 ACTIVE를 확인했다.
- 7일 retention이 모두 지난 16:34 KST 이후 legacy cluster 3개, evidence 문서 3개와 Storage JSON 3개를 exact precondition으로 삭제했다. Firestore·Storage 잔존 0, 보존 import job·시즌 3쌍 200, 두 queue task 0, 2026-08-06T07:14:00Z 이후 Cloud Run ERROR 0이다.

## 다음 작업

1. 없음. 이 핵심 task는 완료됐으며 다음 제품 작업은 별도 task로 시작한다.

## 현재 위험

- 실패 화면은 사용자가 안전하게 재현할 수 없으므로 수동 QA 완료 게이트로 두지 않는다. 원문 비노출과 안정 문구 상태 계약은 targeted 테스트로 고정했다.
- 영구 OIDC binding은 두 exact runtime service account identity로 Worker endpoint를 호출할 수 있으므로 사용자 Google 계정 MFA/passkey와 계정 보안에 의존한다. 운영 구조가 바뀌면 전용 QA identity로 분리한다.
- 게시된 시즌이 참조하는 기존 import job 3개는 제품 데이터로 명시 보존한다.
