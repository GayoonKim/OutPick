# Worker 기준선 계측 — 2026-10-03

사용자가 추천안을 확정하고 진행하도록 승인한 범위에서 Phase 0의 단계 계측과 필수 회귀 검사를 구현했다. 기존 동시성·재시도·품질 판단·이미지 규격은 유지한다. 계측 구현 완료를 성능 개선이나 Phase 0 전체 완료로 해석하지 않는다.

## 확정한 측정 경계

UNAFFECTED의 실제 추출→검토 대기와 승인 후 저장을 별도로 측정한다. 같은 실행의 다운로드 재사용은 통제된 로컬 연결 실험으로 분리한다. 실제 품질 검토를 자동 통과시키거나 로컬 연결 실험을 실제 자동 등록 성공으로 표시하지 않는다. 이는 2026-10-03 사용자의 ‘추천안으로 확정하고 진행’으로 확정했다.

## 코드 진입점과 사용

- `tools/lookbook-import-worker/src/config.ts`: `OUTPICK_IMPORT_PERFORMANCE_ENABLED=true`일 때만 켠다. 기본 false, 다른 문자열은 설정 오류다.
- `src/index.ts` → `src/server.ts` → `src/performance/session.ts`: 서버가 만든 실행 식별자를 사용한다. 기존 OIDC 인증 후 `/tasks/import-job`, `/wake`를 계측하며 요청 본문으로 계측 정책을 바꾸지 않는다.
- `src/performance/metrics.ts`: AsyncLocalStorage로 병렬 요청을 분리한다. 단조 시계로 단계 호출 수·완료/실패·동시 실행 최대값·시간·bytes를 기록한다.
- `src/processor.ts`, `src/extraction/dedupe.ts`, `src/public-http.ts`: 기존 실제 작업 경계에 연결한다. `jpegBytes`, `uploadJPEG`의 모듈 export는 실제 함수를 검사/로컬 재생에 쓰기 위한 것이며 새 HTTP API가 아니다.
- `src/performance/resources.ts`: 100ms 간격의 프로세스 메모리·sharp queue/process, 구간 CPU·event-loop 지연, cgroup v2/v1의 컨테이너 메모리를 수집한다. 미지원·누락·샘플 오류를 0 사용량으로 바꾸지 않는다.

출력은 `[lookbook-import-performance]` 접두 JSON이다. 실행 UUID, 검증한 source revision, 해시한 instance key, 선택적 input/settings SHA-256, UTC 시작·단조 시간·단계·job 상태·자원 표본을 포함한다. 원본 URL·경로·이미지·인증값·예외 메시지는 새 계측 레코드에 넣지 않는다. 기존 제품 로그 전체를 정제한 변경은 아니다.

서버의 settings digest는 `assetSyncConcurrency`, `UV_THREADPOOL_SIZE`, `NODE_OPTIONS`의 JSON SHA-256이다. 고정 변환 정책은 소스 revision에 속한다. 클라우드 CPU/메모리/큐 설정 전체의 검증된 digest는 아니며 실험 manifest에 별도로 연결해야 한다. HTTP 요청 계측의 input digest는 아직 null이다. 로컬 검사는 별도 입력 digest와 게이트의 작업 트리 digest를 함께 기록한다.

## 수치 해석과 남은 범위

| 수치 | 현재 의미와 한계 |
| --- | --- |
| stage `succeeded` / `failed` | 함수/Promise 반환·예외 수. 제품 성공 여부는 별도 `jobOutcomes`의 awaitingReview/partialFailed/failed 등을 사용한다. |
| `complete` | 반환 시 계측한 단계가 모두 종료되고 계측 값이 유효함. 입력/설정/품질/메모리 안전/실험 횟수까지 검증한 합격 판정은 아니다. |
| 단계 시간·peakActive | 요청 내부 함수의 벽시계 시간과 동시 in-flight. sharp 큐 대기도 변환 시간에 포함한다. 중첩 단계 시간을 더해서 전체 시간으로 쓰지 않는다. 인스턴스 전체 슬롯 상한도 아니다. |
| 수신 bytes / download started | 실제로 읽은 HTML/이미지 body bytes / fetch 함수 호출 수. 크기 제한 중 실패한 읽기 포함. redirect의 각 네트워크 요청·TLS/header·미소비 오류 body·Playwright 하위 리소스는 포함하지 않는다. |
| upload submitted/completed bytes | SDK에 넘긴 바이트/성공 응답을 받은 바이트. SDK 내부 재시도·실패 시 실제 전송량까지 측정한 wire bytes가 아니다. |
| paths.save | 커버 경로 쓰기 또는 post 경로 조회+쓰기 구간. 전체 Firestore 호출 수·ready 전이 검증은 아니다. |
| CPU·메모리 | 같은 프로세스/컨테이너의 공유 자원. 동시 요청의 수치를 합산하거나 이미지별 CPU로 귀속하지 않는다. 표본 최고값은 실제 순간 최고값을 보장하지 않는다. |

기존 Promise.all이 먼저 실패해 형제 작업이 남아 있으면 `complete=false`로 기록한다. 계측 단계에서 제품의 drain/취소 정책을 바꾸지 않았다. 새 실행 정책은 별도 Phase 1에서 검증한다. 로그 출력 실패는 원본 작업의 성공·실패를 바꾸지 않는다.

후속 구현에서 슬롯 대기/큐 통계, 결과 회차·입력/설정/코드 digest 일치 검사와 오버헤드 준비 측정을 추가했다. [최신 진행·검증](phase-0-1-progress.md)을 따른다. 개별 job/asset 연결 키·attempt/cold/warm 전체 연결·전체 DB 호출·재사용 바이트·최종 성능 채택 판정기·메모리 85%/1초 중단 감독기는 남아 있다. macOS의 cgroup 미지원은 Cloud Run 안전 조건 통과 근거가 아니다.

## 필수 게이트

명령: `node tools/verification-gate/gate.mjs --project . --config verification/lookbook-import.json`. Node 24.19.0으로 실행했다.

- 최종 `passed`: `output/verification/1790999074949-36695c38-e9d7-43cf-accb-ecef369d5009/summary.json`.
- lint·TypeScript build·Node 테스트 134개·fixture corpus 통과, 필수 ID 26개. 신규 16개는 병렬 요청 격리·미완료 형제 작업·실패 바이트·출력 실패·인증 경계·cgroup 미지원·실제 변환/업로드 옵션을 검사한다.
- 당시 검사 소스: HEAD `1d67d61faa04984783083971688a7c628df74748` + 작업 트리, digest `9909986037a4b92e8aef2b53d7c35435262b23b24cf0ffd8cb5ab891d17a4b56`, 108파일. 이후 코드 변경의 최신 152개 게이트와 digest는 [후속 기록](phase-0-1-progress.md)에 있다.
- 선행 실패 `1790998969242-a434587e-cf58-4f55-90e6-e3ba35e1e0c5`도 보존한다. 신규 파일의 줄 길이 lint 오류를 수정한 뒤 전체 필수 게이트를 다시 실행했다. 테스트 134개가 통과했어도 lint 실패 실행은 통과로 기록하지 않았다.

## 고정 자료의 실제 함수 연결 검사

`output/lookbook-import-performance/unaffected-2026-10-03/verify-instrumentation.mjs`를 같은 소스의 빌드 산출물로 실행했다. 원본은 `instrumentation-validation.json`이며 `passed`다. 기존 자료 검사 결과를 덮어쓰지 않았다.

- 6개 시즌의 실제 `resolveContentHashDedupe`가 132개를 131개로 줄이는 순서를 유지했다.
- 실제 `jpegBytes` 출력 274개가 앞서 고정한 출력과 SHA-256·바이트 수가 모두 일치했다. 실제 `uploadJPEG` 함수는 메모리 Storage spy에 274개/42259800 bytes를 전달했다. 클라우드 업로드는 없다.
- `local-extraction` 6개와 `local-assets` 6개를 별도 세션으로 기록했다. 12개 모두 계측 단계 정상 종료, samplingErrors 0, cgroup 사용 가능 0개(macOS)다. 로컬 파일 읽기를 네트워크 다운로드로 기록하지 않았고, paths.save도 0회임을 검사했다.
- 입력 연결 digest `102c45947eace32064e705f04897ebd0462691d1cb81d31ea9e2987c324401d3`은 본문 manifest digest와 커버 해시 목록의 SHA-256이다. 각 실제 파일은 별도 hash/길이 검사했다. 게이트의 작업 트리 digest도 결과에 저장했다.

이 검사는 제품 함수 연결·출력 동일성을 확인한다. 이미지 순차/이미지 내 두 출력 병렬의 검사 실행이며 실제 Worker 전체 스케줄러·Firestore 경로·품질 승인·계측 on/off 성능을 검증한 결과는 아니다.

후속으로 결과 검증·오버헤드 확인과 Phase 1의 선택적 실행 정책 연결까지 진행했다. [후속 기록](phase-0-1-progress.md)을 확인한다. 54회 구조 비교·실제 Storage/Firestore·Development·운영 배포는 아직 수행하지 않았다.
