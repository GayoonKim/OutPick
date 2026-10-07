# Q7 platformAdmins 전환 설계·구현 계획

2026-10-06 최신: P1 서버 인가 구현·필수 로컬 검증 완료. 재인증 후 Web 앱0개·Google 활성·localhost 허용 확인. [전체 계획](product-queue-q7-server-validation-plan.md)과 [P2 최소 연결](q7-verifier-p2-plan.md)을 기준으로 로그인 전용 HTML+기존 Node 실행기+기존 callable을 연결한다. Vite·새 권한 preflight API 제안은 대체했다. P2는 계획 작성 상태이며 P1 배포·권한 부여·실제 제품 URL 흐름은 미실행이다. 아래 과거 조사 시점의 인증 만료 문구는 해결된 이력이다.

## 목표와 전제

관리자 웹이 없어도 정상 Firebase 사용자 인증과 서버 인가를 거쳐 UNAFFECTED Q7 검증을 실행할 수 있게 한다. iOS 관리자 화면은 필수 조건이 아니다. 관리자 웹은 localhost/Google 로그인, 권한 원천은 platformAdmins라는 기존 결정을 따른다. 원격 project는 outpick-test만 사용한다.

현재 brandAdmins0건, platformAdmins1건 중 isActive=true0건이라는 읽기 전용 결과를 확인했다. 실제 실행 전 활성화할 본인 계정을 식별하고 별도 승인해야 한다. 이 문서에서 계정·UID를 임의 선정하거나 새 권한을 만들지 않는다.

## 확정 범위

채택 A: Q7 필수 접수·조회·검토·재시도 API를 platformAdmins 전용으로 먼저 전환한다. 기존 공용 brandAuthorization의 의미를 일괄 바꾸지 않으므로 삭제/댓글/브랜드 요청 API에 영향이 번지지 않는다. 나머지 기존 관리자 API/Rules 정리는 admin-web-operations-migration에 남기고 전체 전환 완료라고 보고하지 않는다.

대안 B: 브랜드/룩북 관리자 권한 전체를 함께 전환한다. brandAuthorization 소비자인 brand/requests, lookbook/deletion, comments, seasonMoodFunctions와 brand manager 추가/제거, Firestore 포스트 직접 쓰기까지 설계·검증 범위를 확장한다. 일반 사용자 댓글/신고/차단 및 채팅방 moderator 권한은 유지해야 한다. API 제거/Rules 차단의 정확한 순서는 별도 범위 확정이 필요하다.

## 데이터·인가 계약

- 권한 원천: platformAdmins/{검증된 Firebase UID}. 최소 isActive=true, 기존 moderation 계약상 revokedAt이 Firestore Timestamp가 아님을 요구한다. 기록 없음/false/회수된 권한은 거절한다.
- callable의 request.auth.uid만 사용한다. payload의 UID, 이메일 일치, Google 로그인 성공, localhost 여부만으로 권한을 부여하지 않는다.
- 신형 경로에는 brandAdmins 또는 브랜드별 owner/admin fallback을 두지 않는다. 플랫폼 관리자여도 삭제된 브랜드/유효하지 않은 job/generation/snapshot은 기존 계약대로 거절한다.
- createBrand와 queue 접수는 동일 transaction 안에서 관리자 문서를 읽는다. 권한 회수와 접수가 경합하면 Firestore 재시도 시 새 권한으로 판정한다. 중복 영수증을 반환하기 전에도 인가한다.
- getSeasonImportBatch는 현재 requestedBy==uid 검사와 현재 인가를 모두 유지한다. 다른 관리자의 요청을 볼 수 있는 전역 조회 기능은 추가하지 않는다.
- 정상 접수된 작업의 실행권/epoch/drain·FIFO 의미는 변경하지 않는다. 현재 Worker는 사용자 권한의 상시 재검사로 작업을 취소하지 않는다. 새 접수/조회/승인은 회수된 권한으로 거절하고, 기존 작업의 긴급 중단 정책은 별도 복구 계약이다. 권한 회수가 이미 접수된 작업까지 취소한다고 안내하지 않는다.
- requestID/requestCreatedAt/queueContractVersion, payload와 영수증 형식, 5회 재시도/자원 제한/128MiB/12·14·15분 기준은 유지한다.
- 기존 관리자 문서 자동 복사·삭제, roles 데이터 자동 승격은 하지 않는다. 플랫폼 문서는 기존 운영 도구로 대상 확인 후 명시적으로 활성화한다.

## 코드 조사로 확인한 변경 후보

| 위치 | 책임/추천 A의 변경 |
|---|---|
| functions/src/shared/platformAuthorization.ts (신규 후보) | Firestore/Transaction에서 사용할 활성 플랫폼 관리자 판정. moderation 의미와 차이가 나지 않도록 동일 사례 검증 |
| functions/src/brand/admin/functions.ts | createBrand transaction의 관리자 문서/판정 교체. getBrandAdminCapabilities와 나머지 관리 API는 범위 결정에 따라 분리 |
| functions/src/lookbook/import/queue/authorization.ts | 플랫폼 관리자+브랜드 존재/삭제 상태 검사, 브랜드 owner/admin fallback 제거 |
| functions/src/lookbook/import/queue/discovery-admission.ts | afterFix의 brandAdmins 직접 읽기 제거/신형 인가로 통일 |
| functions/src/lookbook/import/queue/followup-admission.ts | manualRetry의 brandAdmins 직접 읽기 제거/신형 인가로 통일 |
| functions/src/lookbook/import/functions.ts | getLookbookExtractionReview, reviewLookbookExtraction의 비승인 분기, retry 표시, previewLookbookSeasonRepair 등 큐 밖 조회/분기까지 동일 인가 적용. 기존 진단 경로 영향은 명시적으로 분리 |
| functions/src/lookbook/import/seasonDiscoveryJobs.ts | Q7이 사용하는 후보 조회/resolve 및 취소 경로의 인가 경계 점검. shared queue를 통하는 request/retry는 전환 결과 검증 |
| functions/src/lookbook/import/queue/functions.ts | 영수증 조회가 신형 인가를 쓰는지 검증, 타 요청자 거절 유지 |
| functions/src/shared/brandAuthorization.ts | 추천 A에서는 기존 타 기능 의미를 일괄 변경하지 않음. 새 도구는 기존 capability API에 의존하지 않음 |
| functions/src/moderation/admin/service.ts | 기존 isActive/revokedAt 조건이 비교 기준. 새 공용 함수로 이동하면 기존 moderation 테스트/게이트도 필수 추가 |
| functions/scripts/manage-platform-admin.mjs | 기존 audit/grant/revoke 운영 도구 재사용 가능성 확인. provider에 정확히1명이 있어야 apply 가능. 계정 수가 맞지 않으면 임의 선택하지 않음 |

Q7 호출 행렬: createBrand, discoverSeasonCandidates/requestSeasonDiscovery, requestSeasonCandidateImportJobs/requestSeasonImport, getSeasonImportBatch, getLookbookExtractionReview, reviewLookbookExtraction, requestSeasonAssetRetry, retrySeasonDiscovery/retrySeasonDiscoveryAfterExtractionFix, retryLookbookExtractionAfterFix, requestLookbookSeasonRepair/previewLookbookSeasonRepair/applyLookbookSeasonRepair. 동일 queueAuthorization 소비자는 모두 인가 변경 영향을 받으므로 happy path와 거절 검사를 연결한다.

Firestore에는 현재 hasBrandWriteAccess가 brandAdmins/브랜드별 admins를 통해 posts create/update를 허용한다. 추천 A는 이 기존 경로를 새 platformAdmins로 확대하지 않는다. 전체 관리자 권한 정리가 끝난 것은 아니며, 후속 웹 전환에서 직접 쓰기 제거와 서버 API 대체를 검증한다. platformAdmins collection의 client read/write deny는 유지한다.

## 단계별 구현 계획

### P0 — 범위와 인가 행렬 확정

- 목표: 추천 A/B 선택, 신형 인가 적용 API와 남는 기존 경로를 구분한다.
- 변경: 본 문서, Q7 readiness/implementation-plan, ENTRYPOINTS/FIREBASE/TESTS.
- 완료: API마다 인증/권한/transaction/재전송/조회 소유권/요청 후 처리 계약 명시. 추천 A 선택 완료.
- 검증: 실제 호출부 조사 및 기존 관리자 웹 결정과 대조 완료. 다음은 구현 승인 후 P1이다.

### P1 — 플랫폼 인가와 서버 접수 연결

- 목표: 승인된 범위의 기존 callable이 정상 플랫폼 관리자만 허용한다.
- 변경: 위 후보 중 확정된 Functions 파일과 관련 unit/Emulator 테스트. Worker/Swift DI·Container·Coordinator 변경 없음.
- 완료(2026-10-06): 활성 platform 관리자만 Q7 접수·검토·수정 경로를 허용하고 legacy total admin/brand owner fallback은 거절한다. 이미 접수된 배치 준비는 호출 권한 회수와 무관하게 이어지며, 새 상태 조회는 현재 권한을 재검사한다.
- 검증: Functions gate `1791267712654-f7786f8f-3eef-4749-b261-71942e017148` passed(필수 lint/build/320 tests, 0 failures/skips). 제품 큐 gate `1791267891214-8537e254-a48d-4163-a9a8-89121c86c5da` passed(Worker build, Functions build, Firestore Emulator 69 tests, 0 failures/skips). 최종 제품 큐 source digest `9483e185b9054624824de4e3236df3340e24bbea92956a11d4f07c3e8d457ea8`/289 files. 테스트는 비활성/legacy 관리자 거절, 접수 후 권한 회수 시 기존 준비 지속, 삭제 브랜드 차단을 포함한다.
- 잔여: Functions 배포와 Development 활성 관리자 부여는 수행하지 않았다. Functions의 기존 진단용 경로 두 곳은 공용 `brandAuthorization`을 계속 사용하며, 승인된 Q7 접수·검토·재시도 범위 밖이다. P2 검증 도구는 Web SDK/provider/origin/App Check 설정을 읽기 전용으로 확인한 뒤 구현 계획을 구체화한다.

### P2 — Development 검증 도구 연결

- 목표: Google 로그인 → 정상 서버 인가 → 고정된 Q7 요청만 실행한다.
- 구성 제안: localhost 소형 검증 화면(로그인·프로젝트/계정 확인·단계 실행·결과) + 고정 입력/영수증 파일 + 읽기 전용 cloud evidence 수집. 관리자 웹 전체 UI/삭제 기능은 만들지 않음.
- 저장소에는 기존 Firebase Web SDK 클라이언트나 web app 설정이 없음을 확인했다. Q7 callable 선언에는 `enforceAppCheck`가 없고 global Functions 옵션은 `maxInstances: 10`만 설정한다. 실제 Development 배포 설정은 별도 read-only 확인 전까지 미검증이다.
- 2026-10-06 read-only `firebase apps:list WEB --project outpick-test`는 Firebase CLI 자격 증명 만료(`credentials are no longer valid`)로 실패했다. 원격 조회 결과는 얻지 않았고 인증 갱신·배포·권한 변경도 하지 않았다. CLI 재인증 후 Web app 등록 유무, Google provider, authorized domains, deployed App Check 조건을 확인한 뒤 구체 구현 계획을 확정한다.
- 사용자 ID token/refresh token을 채팅에 받거나 파일·로그에 기록하지 않는다. 서비스 계정 JSON/운영 Secret을 브라우저에 포함하지 않는다.
- 완료: outpick-test 외 거절, 허용 API/QA 이름/단계/요청량 고정, 전송 전 requestID 영속화, 응답 유실 시 동일 ID 재조회, 재접수 방지, 비밀정보 로그 제거, 후보 불일치 시 import 중단.
- 검증: 도구 자체 로컬 gate 및 기존 development preparation gate. GCP ID token과 Firebase ID token 혼용 거절. 로그인만으로 유료 실험 자동 시작하지 않음.
- 의존/현재 상태: 재인증과 read-only 원격 설정 조사는 완료됐다. Web 앱 0개, Google provider enabled=true/client ID 설정 있음, localhost 허용을 확인했다. 위 인증 만료 기록은 이전 이력이다. [P2 구체 구현안](q7-verifier-p2-plan.md)의 추가 범위를 사용자와 확정한다.

### P3 — Development 전환·기존 승인 smoke

- 목표: 로컬 통과 소스를 정확한 Functions 목록으로 배포하고 기존 Q7을 실행한다.
- 선행: 변경 export/deployment diff, queue 비활성 확인, 현재 권한 audit, 사용자 지정 본인 계정·grant 승인, 정상 로그인 권한 preflight.
- 실행: 후보 탐색 → A2/B1 smoke → 증거 판정 통과 후 A~J16시즌/100ms wave. 기존 비용·입력·자원 한도 유지.
- 완료: 실제 영수증·sequence·batch/items/runs/epoch·drain·review snapshot·Storage generation/hash/크기/공개 경로 증거. 실패/미검증 항목은 명시.
- 되돌림: 새 접수를 멈추고 실행 중 작업 drain/종료를 확인한다. 긴급 권한 회수는 platformAdmins 기존 revoke 경로로 수행하며 fallback을 자동 활성화하지 않는다. 삭제/운영 배포는 별도 승인.

## 필수 검증 시나리오

1. 무인증/권한 없음/false/revokedAt Timestamp/legacy admin-only/brand owner-only는 신형 API 거절.
2. 활성 플랫폼 관리자만 create/discovery/import/review/retry/repair/조회 허용. payload 위장 UID는 무효.
3. 권한 회수 후 동일 requestID 재전송 및 상태 조회 거절. 접수 transaction과 회수 경합에서 권한 재판정.
4. 타 요청자 batch 조회 거절, 삭제된 브랜드/서로 다른 brand-job/오래된 generation/hash 거절 유지.
5. 중복 ID·불확실 응답·동일 payload 재전송은 단일 접수. fixture 불일치에서 실제 import0건.
6. queue FIFO/drain/재시도/공개 원장 회귀. 기존 승인 작업은 인가 변경만으로 취소/새 owner 이동하지 않음.
7. 추천 A의 비대상 API/Rules는 기존 동작을 보존하고 잔존 경로 목록을 남김. 이를 전체 전환 성공으로 판정하지 않음.

현재 완료 범위는 P1 코드·로컬 검증 및 P2 읽기 전용 설정 조사다. 원격 Web 앱 등록·새 권한 부여·P1 코드 배포·실제 URL 처리는 이번 전환 작업에서 미실행이다.
