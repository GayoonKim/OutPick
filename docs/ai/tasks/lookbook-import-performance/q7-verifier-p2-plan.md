# Q7 P2 최소 연결 세부 구현안

2026-10-06 최신 기준. Vite/IndexedDB 및 새 `getLookbookAdminContext` 제안을 대체한 최소 도구 구현안이다. **P2 구현 완료:** 정식 관리자 웹 없이 기존 제품 callable과 스크립트를 연결했다. 아래 구현 체크리스트는 계획 당시 파일/계약을 설명하며 실제 차이는 마지막 절의 구현 결과를 따른다.

## 환경·기술 선택

초기 read-only 조사에서는 `outpick-test` Web 앱 0개, Google provider 활성, localhost 허용을 확인했다. 이후 아래 Web app을 등록했다. CLI 재인증을 다시 요구하지 않는다. Q7 source에는 App Check 강제가 없지만 실제 배포 설정을 P3에서 대조하며 정책을 완화하지 않는다.

기존 Worker의 Node 환경과 firebase-admin/google-auth-library를 재사용한다. 별도 package/workspace/UI 프레임워크를 만들지 않는다. 로그인 전용 HTML만 Firebase modular Web SDK를 고정 버전 CDN에서 읽는다. 구현 시작 시 버전을 명시하고 실행 manifest에 기록한다. 외부 SDK 로드 실패는 환경 미준비로 중단한다.

Web 앱1개 등록이 원격 준비에 필요하다. public config는 비밀 토큰과 구분하며 프로젝트를 검사한다. 등록은 Hosting 배포나 관리자 권한 부여가 아니다.

## 인증·네트워크 계약

- q7-session.mjs는127.0.0.1에만 바인딩한다. 브라우저 origin은 허용된 localhost와 실행 시 정한 포트로 고정한다.
- q7-login.html은 프로젝트/계정/연결 상태와 Google 로그인·로그아웃만 표시한다. 실험 시작은 별도 runner 명시 동작이다.
- Firebase inMemoryPersistence와 popup 로그인을 사용한다. ID token만 nonce로 보호한 loopback POST로 전달하고 메모리에만 둔다. refresh token·운영자 토큰은 전달하지 않는다.
- Host/Origin/시작 nonce/body 크기/메서드를 검사한다. 임의 CORS·임의 원격 URL을 허용하지 않는다. nonce는 URL fragment에서 읽고 제거하며 로그에 남기지 않는다.
- Firebase Admin verifyIdToken으로 프로젝트·발급자·만료·서명을 검증한다. 단순 JWT decode는 인증이 아니다. 실행 시작 후 UID를 고정하고 계정 변경/만료/로그아웃 시 새 접수를 차단한다. 이미 접수된 서버 작업은 유지한다.
- 브라우저 갱신 토큰 이벤트로 새 ID token을 받아 갱신한다. 세션을 잃으면 같은 UID 로그인 후 journal과 영수증으로 복원한다.
- q7-callable.mjs는 outpick-test/asia-northeast3 고정 URL에 Firebase 사용자 ID token과 callable {data: ...} 계약을 사용한다. HTTP200 안의 error도 실패다. GCP ID token/ADC는 사용자 인증 대체 수단이 아니다.
- 초기 허용 API는 createBrand, requestSeasonCandidateImportJobs, getSeasonImportBatch, getLookbookExtractionReview, reviewLookbookExtraction이다. 실제 입력 계약은 해당 producer와 테스트에서 대조한다.
- platformAdmins 읽기 전용 audit은 사전 정보다. 최종 인가는 매 callable에서 수행한다. 없는 requestID의 not-found 또는 legacy capability를 관리자 인증 성공으로 해석하지 않는다. 권한 확인용 가짜 브랜드도 만들지 않는다.

## 영속 기록·재진입 계약

q7-journal.mjs가 프로젝트/UID/runID별 로컬 JSON을 관리한다. 독점 실행 잠금, 임시 파일+fsync+rename 원자 교체를 사용한다. 권한은 소유자만 읽도록 설정한다.

최소 필드: schemaVersion, projectID, UID, runID, fixture/plan/source digest, stage, requestID/requestCreatedAt, frozen payload 및 digest, 상태(prepared/sent/uncertain/accepted/terminal), 응답 영수증과 관련 ID, 시간, 오류 코드. 토큰·인증 헤더·비밀 값은 제외한다.

전송 전 기록 실패면 네트워크 mutation0건이다. 동일 run 두 실행은 거절한다. 응답 유실은 uncertain으로 남기고 기존 영수증을 조회한다. 새 ID 생성이나 자동 mutation 재전송은 하지 않는다. 명시적 resume에서 동일 ID·동일 payload·현재 인가·만료 계약을 확인하고 기존 API의 멱등 계약으로 조정한다. 조회 오류10→20→40→60초를 적용하고 전체 실행 창을 넘으면 새 접수를 멈춘다. 서버의 즉시 총5회 시즌 재시도와 클라이언트 전송 복원은 별개다.

## 실행·증거 구조

q7-runner.mjs는 기존 makePlan/assertReviewMatches/assertBatchRunEvidence를 재사용한다. sourceInputDigest c4fb65f71fa5f26a6f9a531e58b8629ba2aff0f612c81e75e7cdeb05028f0c56의 fixture가 기준이다. 실제 사이트가 달라지면 승인하지 않고 입력 변경으로 보고한다.

원본 결과 경로: output/lookbook-import-performance/product-queue-q7/<runID>/.
manifest.json, journal.json, requests.jsonl, evidence/, metrics/, report.json 및 gate summary를 연결한다. 계정 식별정보는 로컬 증거에 필요한 최소만 보관하고 공유 요약에는 비식별화한다.

q7-evidence.mjs는 운영자 ADC로 허용된 run의 Firestore/Cloud Logging/Run/Storage를 읽기만 한다. 사용자 callable 토큰과 분리하며 직접 큐 생성·상태 변경·승인은 하지 않는다. 후보 직접 읽기에 기존 Rules의 관리자 권한을 확장하지 않는다.

영수증에는 sequence/원본 후보/전체 자원 계측이 없으므로 읽기 전용 collector가 batch/items/runs/continuations/epoch/검토 snapshot/공개 asset reference/Storage generation을 모은다. mutable 최신 문서만으로 과거 비중첩을 판정하지 않는다.

기존 /tasks/import-batch의 withMeasurement와 stage counters/resource sampling을 우선 재사용한다. 현재 계측 runID만으로 batch/epoch가 자동 연결된다고 가정하지 않는다. 연결이 없으면 server.ts와 performance/session.ts 및 report 타입에 batchID/실행ID/epoch 상관 필드를 추가하고 테스트한다. 토큰·전체 입력 URL을 계측 context에 넣지 않는다. 계측 실패가 제품 작업 재시도를 유발하지 않게 하되 검증 보고서는 불완전으로 실패한다.

## 구현 파일과 필수 검사

| 순서 | 위치 | 필수 검사 |
|---|---|---|
| P2a | scripts/q7-session.mjs·q7-login.html·q7-journal.mjs, 대응 .test.mjs | 잘못된 origin/nonce/project/token/UID 거절, 비밀 제거, 원자 기록 실패·중복 실행·복원 |
| P2b | scripts/q7-callable.mjs·q7-runner.mjs 및 테스트 | 프로토콜 오류/200error/응답 유실/만료/후보 불일치/동일ID 재개/요청 상한 |
| P2c | scripts/q7-evidence.mjs·q7-report.mjs 및 테스트, 필요한 계측 파일 | 범위 밖 읽기 차단, 원본 누락·다른revision·epoch·중첩·generation 오류 실패 |
| P2d | verification/lookbook-q7-verifier.json·lookbook-q7-live.json, 기존 preparation 계약 | 성공/실패 fixture 모두 판정, 필수 검사 누락·skip·0개·환경 미준비 실패 |

기존 Worker package의 검증 진입점에 연결한다. worker 코드 변경 시 Worker gate, queue 계약 변경 시 제품 큐 Emulator, cgroup/supervisor 영향 시 Linux gate, Functions 변경 시 Functions gate가 필수다. 로그인 popup은 실제 수동 QA이며 fake 테스트로 통과했다고 쓰지 않는다. 구체 판정은 검증 행렬을 따른다.

## 구현 전·원격 실행 전 구분

이 문서는 최소 연결의 구현안과 결과를 함께 기록한다. P2a~d 구현과 로컬 gate는 완료됐으며 권한 우회 API나 제품 동시성 재설계는 추가하지 않았다. 실제 smoke는 활성 platform admin 계정으로 A 생성·탐색까지 진행했다. 동적 후보 확장 판정과 Worker domain-status mapping 오류를 발견했으며, 현재 queue head가 `recoveryRequired`라 추가 제품 요청을 멈췄다. 권한 상태를 임의로 바꾸지 않으며 상세 최신 결과는 [Q7 readiness](product-queue-q7-readiness.md)를 따른다.

공식 근거: [SDK 별도 설정](https://firebase.google.com/docs/web/alt-setup), [메모리 인증](https://firebase.google.com/docs/auth/web/auth-state-persistence), [callable 프로토콜](https://firebase.google.com/docs/functions/callable-reference), [ID token 검증](https://firebase.google.com/docs/auth/admin/verify-id-tokens).

## 실제 구현·검증 상태 (2026-10-06)

- 구현 파일은 계획 표의 `q7-callable.mjs`가 아니라 `q7-session.mjs`, `q7-login.html`/`.js`, `q7-journal.mjs`, `q7-runner.mjs`, `q7-storage-evidence.mjs`, `q7-development-preflight.mjs`다. `run-q7-local-tests.mjs`와 `q7-verification.test.mjs`가 실행·검증 진입점이다.
- 미확정 mutation은 자동 resume/replay 하지 않는다. journal에 `sent/uncertain`으로 남은 run이나 완료되지 않은 같은 stage는 새 run을 차단한다. read-only로 조정한 뒤 수동으로 해소해야 한다.
- P2 필수 gate는 16 tests 통과, Worker 전체 gate는 350 tests 및 fixture 검사 통과다. 자세한 source digest와 원본 summary는 Q7 readiness 및 verification outputs를 따른다.
- Development Firebase Web app은 `OutPick Q7 local verifier 20261006` (`1:86635107099:web:831347d278dea0bba239be`)으로 등록했다. public config는 `output/lookbook-import-performance/product-queue-q7/firebase-web-config.json`에 mode 600/ignore 상태로 저장했다. Hosting은 배포하지 않았다.
- 후보 Cloud Run revision `lookbook-import-worker-development-00018-zon`, tag `q7-20261006`은 Q7 source digest로 배포됐다. 기본 revision traffic은 100%, 후보는 0%다. Function `requestSeasonImport`은 해당 tag URL을 사용한다. 실제 smoke/A~J product mutation은 아직 없다.
- 이전 2026-10-06 smoke attempt는 로그인한 UID의 `platformAdmins`가 inactive여서 0 mutation으로 끝났다. 이후 계정 권한이 준비돼 run `e9049126-5161-48ee-ad67-fc6966a7b8ca`에서 A 생성·최초 탐색이 실제 실행됐다. 현재 queue head는 `recoveryRequired`; 최신 상태와 원본 evidence는 [Q7 readiness](product-queue-q7-readiness.md)를 따른다.
