# A~F 연결·바이트 관측·컨테이너 감독

2026-10-03. **측정기 보완 후 준비 18회와 본 54회 비교 완료. 본 비교는 성공 48회·메모리 중단 6회이며 누락/중복/설정 불일치 검사 통과. C/E는 각 9회 성공으로 후속 후보, C를 우선 추천한다. 최적 수치·제품 기본값·클라우드 성능은 아직 확정하지 않았다.** 최신 Mac/Linux 게이트는 각각 207개/필수 99개 통과다. 아래 중간 기록은 당시 상태이며 최종 결과는 문서 마지막을 따른다.

## 확정된 초기 조합

사용자가 비동기 질문에 추천안 두 항목을 모두 승인했다. 아래 숫자는 첫 구조 탐색 값이며 최적값이 아니다.

| 구조 | 시즌 순서 | 이미지 시작 방식 | 인스턴스 공용 제한 |
| --- | --- | --- | --- |
| A | 병렬, 로컬 실행 폭 6 | 기존 해시 4·저장 작업 3, 이미지별 출력 2 | 기존 경로 유지 |
| B | 병렬, 폭 6 | 해시/저장 각각 8개 묶음, 묶음 내부 전체 시작 | 추가 단계 제한 없음 |
| C | 병렬, 폭 6 | 빈자리 보충, 유한 입력 제출 | 다운로드 4·변환 2·업로드 4·경로 저장 전체 |
| D | 같은 브랜드 순차, 다른 브랜드 병렬 | B와 같음 | B와 같음 |
| E | 같은 브랜드 순차, 다른 브랜드 병렬 | C와 같음 | C와 같음 |
| F | 유한 시즌 전체 시작 | 유한 이미지 전체 시작 | 앱의 추가 단계 제한 없음 |

모두 재사용 off, 메모리 감독/라이브러리·SDK pool은 남는다. 부하는 2026 SS 1시즌 / 한 브랜드 2026FW→2026SS→2025FW→2025SS→2024FW→2024SS / 연도별 합성 브랜드 3개에 FW·SS씩 배정한다. 실제 세 호스트의 결과로 해석하지 않는다. 표본 100ms, 표본 간격 500ms 초과 시 환경 미검증 중단도 승인됐다.

## 코드와 관측 범위

- `src/performance/comparison.ts`: 54회 계획/설정 digest·교차 순서, A~F 정책, 시즌 실행, 단계 계측, 메모리 감독을 연결한다. 추출→검토 대기와 승인 후 저장은 각각 새 runtime/관측 scope에서 실행한다. 기준선 A에는 실험 PipelineRuntime을 넣지 않는다.
- `frozen-input.ts`: 고정 HTML을 제품 추출/기대 수/품질 함수로 검사하고 실제 content hash dedupe를 호출한다. 저장 구간은 고정된 승인 후 입력을 별도로 구성해 제품 JPEG/upload 함수·storeImageVariants를 사용한다. Storage와 경로 저장은 spy이며 실제 Firestore 전체 lifecycle 측정이 아니다.
- `buffer-inventory.ts`: 원본과 JPEG의 논리 보유 payload를 관측한다. 같은 객체를 여러 소비자가 쓸 때 중복 합산하지 않으며, 기본 Promise.all이 조기 실패해도 실행 중 형제의 보유량은 종료까지 남긴다. 다른 view는 별개 객체로 세며 native decoder/stream 수신 중 chunk/GC 후 RSS/원본 보관 캐시는 이 수치와 같지 않다. RSS·공용 원본 예산과 단순 합산하지 않는다.
- `container-runner.ts`: 실행 전 started/plan을 쓰고 고정 image ID/ARM64 Linux를 확인한다. 1CPU·2GiB·swap 없음·네트워크 없음으로 생성하고 wait 종료 코드와 inspect의 OOMKilled를 대조한다. 결과가 없거나 무효이면 실패, OOM/감독 중단은 중단, 환경 미준비는 미준비로 남긴다. 종료가 확인된 자체 컨테이너만 정리하며 실패 시 container ID를 남긴다. 호스트 감독기까지 죽으면 started만 남으므로 집계가 누락으로 차단한다.
- `local-entry.ts`: Linux ARM64/Node 24와 실제 cgroup v2 cpu.max, memory.max, memory.swap.max를 확인한 뒤 고정 자료를 검증하고 측정한다. 결과 파일은 덮어쓰지 않는다. 실측 전 자료 무결성 읽기가 발생하므로 cold-cache 실행이라고 부르지 않는다.
- `comparison-report.ts`: 54개 회차의 누락/중복/이미지 변경/거짓 성공을 차단하고 실패·중단을 분모에 남긴다. 세 번 모두 성공한 구조·부하 조합만 중앙값을 만든다. 별도 `repeatedRegression`은 다섯 쌍에서 ‘3회 이상 10% 느림 + 중앙값 10% 느림’을 판정하며 3회 탐색에는 적용하지 않는다.
- `Dockerfile`의 `local-performance` target: Linux 의존성·src·빌드 산출물·검사 runner·lint 설정을 포함한다. 기존 서버 runtime target은 유지한다.

위 파일은 모두 `tools/lookbook-import-worker/` 기준이다. 앱 DI/화면, Functions/Firestore 계약, 운영 기본 동시성은 바꾸지 않았다. 자동 재시도·분산 순서의 제품 계약은 Phase 4에 남아 있다.

## 프로그램적 검증

**최종 게이트(공용 계약 fixture를 digest에 포함한 상태):** Mac `output/verification/1791006717306-fd590669-df65-4a72-88a9-c5c4463609b4/summary.json`, Linux `output/verification/1791006722118-77789e71-f943-4ae4-8563-7ea35a98fd4c/summary.json` 모두 **passed**. 두 환경 각각 lint/build/201개 테스트/필수 ID 93개/fixture 통과. HEAD는 `1d67d61faa04984783083971688a7c628df74748` + 작업 트리. Mac digest `1bb23bbd50f2d6a3ccced9b6a3d62da48cab79bfa0de6a57e386026a1314da4c`(132파일), Linux 연결 설정 포함 digest `cd14e28d3d872bd59372826c68c58747a029bc96b37f0819c0829cffea363439`(135파일). 이 이후 Worker 코드·게이트 설정은 변경하지 않았다.

첫 Linux 실행에서는 fixture 디렉터리와 공용 contracts 파일이 이미지에 없어 기존 검사 4건/fixture 명령이 실패했다. 테스트를 생략하지 않고 기존 자료를 읽기 전용 mount해 연결했으며, 누락돼 있던 공용 계약 파일을 Mac/Linux 게이트 입력에 모두 추가했다. 이미지의 기본 npm test만 단독 실행하면 저장소 외부 계약 fixture는 준비되지 않으므로 위 linux-check 연결을 사용한다.

Mac Node 24.19.0의 최종 필수 게이트: `output/verification/1791006388283-e8b2a964-4318-438b-b230-f63562d3ac86/summary.json`, **passed**. lint·build·테스트 **201개**, 필수 ID **93개**, 추출 fixture 통과. 이번 추가 필수 17개는 바이트 4, 비교 연결 4, 외부 감독 5, 집계/악화 4다. 중간 lint의 줄 길이 오류를 수정하고 전체 게이트를 다시 실행했다. 기본 A의 늦은 변환/업로드 정리, 모의 Docker의 OOM/비정상 종료/누락/정상 exit 중단, 누락 회차/정상 중앙값/5쌍 악화 기준을 포함한다.

실제 고정 자료 연결 검사는 `output/lookbook-import-performance/unaffected-2026-10-03/comparison-fixture-1a34bb60-f702-402d-8c0f-875a28433554/{plan.json,result.json}`에 있다. A~F에서 2026 SS를 각각 한 번씩, 두 구간 총 12개 측정으로 검사했다. 각 경로의 본문 30개+커버 1개→JPEG 62개가 고정 SHA/용량과 일치하고 needsReview 유지, 종료 보유 objects/bytes 0을 확인했다. **memory probe는 fake**이며 컨테이너 안전이나 처리 속도 개선의 증거가 아니다. 마지막 Dockerfile의 lint 설정 복사 외에는 이 검사 후 실행 로직 변경이 없다.

입력 digest는 기존 본문·커버 hash에 `input-validation.json`의 golden hash까지 추가한 `a3885d467d8430ca9d40e28b36e163bbb2f1303fb1cad4c37187a79e0b48c05b`다. 원본이 바뀐 것이 아니라 정합성 기준 파일까지 식별 범위를 넓혔다.

## 환경 준비

공식 Apple Silicon Docker.dmg(586074635 bytes)를 임시 경로에 내려받아 읽기 전용 mount, codesign 검증, spctl의 Notarized Developer ID accepted를 확인하고 `/Applications/Docker.app`에 설치했다. 최초 화면 검사 도구는 timeout이었으나 CLI에서 Docker Desktop 4.93.0, Engine 29.8.1, Linux ARM64 엔진 응답을 확인했다. 약관 자동 수락 옵션은 사용하지 않았다. 호스트는 macOS 26.6.2, 메모리 18GiB, CPU 11개, 설치 전 디스크 여유 약 32GiB였다.

비교 이미지: `sha256:9929c7ca81f32a5b65c24817c1d02b49101c1ab2aec255a8667c969361081699`, Linux ARM64. base는 빌드 당시 `node:24-slim@sha256:0e0ff40c39bc087845bfb27465a0df4ea419520094bc35842ff83dd8cbe6f9b6`. npm ci의 기존 의존성 audit 경고 29건은 기록됐으며 lockfile 변경이나 자동 audit fix는 하지 않았다. 첫 빌드의 credential helper PATH 오류는 Docker Resources/bin을 명시해 해결했다.

로컬 `output/lookbook-import-performance/{image-id.txt,linux-gate.json,linux-check.mjs}`는 호스트 프로그램적 게이트가 이미지 내부 검사를 실행하는 연결이다. reporter의 원본 파일 경로를 맞추기 위해 이미지의 Linux 코드를 같은 절대 경로의 컨테이너 내부 디렉터리로 복사한다. 호스트 node_modules는 사용하지 않는다. 이는 로컬 준비물이며 배포 스크립트 추가가 아니다.

## 남은 실험 조건

54회 본 실행에 앞서 Linux 게이트와 실제 cgroup/고정 입력 준비 검사를 확인한다. 본 실행의 입력을 Linux volume에 복사해 Mac bind mount I/O가 측정에 섞이지 않도록 준비하고, 준비 실행·on/off 오버헤드 회차 및 fresh process/파일 캐시 상태를 실행 manifest에 구분해 제시한다. 초기 숫자·부하·500ms 간격은 이미 승인됐으므로 재확인하지 않는다. 54회 성능 결과·실제 대역폭/실패율·Development/운영 배포·최종 채택은 아직 보고할 근거가 없다.

준비 회차 확정: 구조별 6시즌 부하 1회씩 6회 + 계측 on/off 준비 각 1회 및 교차 5쌍 10회 = 추가 18회. 사용자가 ‘추가 18회·실행 조건 적용’을 승인했다. 아래 완료한 환경 검사 1회와 본 54회는 별도다. 본 회차마다 새 컨테이너를 사용하고 무결성 검사 뒤 계측하므로 fresh process after input validation으로 기록하며 cold-cache라고 부르지 않는다.

## 실제 컨테이너 준비 검사 완료

`output/lookbook-import-performance/container-preflight-81d55690-ce5d-40a4-8172-5f9dc82f931e/`의 scope와 `A-single-1/{started,plan,container,result,finished}.json`이 원본이다. 한 번의 **환경/정합성 검사**이며 본 54회 성능 표본이 아니다. Mac bind mount를 read-only로 사용했다.

Linux ARM64 Node **24.21.0**, 실제 cgroup v2에서 CPU quota 1, 메모리 한도 **2147483648 bytes**, swap 0 확인. 메모리 유효 표본 20개, 최대 비율 약 **14.36%**, 감독 중단 없음. 추출 구간 원본 읽기 30회·저장 구간 31회·메모리 Storage spy 업로드 62회, 두 구간 정합성 통과. 실제 품질 판단은 needsReview 유지, 종료 보유 바이트/객체 0. 외부 inspect는 exit 0/OOMKilled false, 결과 검증 성공 뒤 자체 컨테이너를 제거했다.

최종 환경 상태: `/Applications/Docker.app`와 고정 비교 이미지는 다음 실험을 위해 유지한다. 설치용 읽기 전용 디스크는 분리한다. 클라우드 배포/실제 Storage 업로드/Firestore 쓰기는 없었다. Mac의 Node 24.19.0 시간과 Linux Node 24.21.0 시간을 섞어 성능 비교하지 않는다.

## 추가 18회 승인 후 구현과 최신 게이트

`performance/overhead.ts`는 A 단일 시즌의 off/on 준비 2회 뒤 순서를 교차한 5쌍을 같은 처리 경로로 실행한다. `overhead-entry.ts`는 회차별 원본을 즉시 파일로 남기고, 준비 실패 뒤 미실행 회차도 null로 기록한다. 준비 2회는 중앙값에서 제외한다. off에서도 메모리 안전 감독과 출력 정합성 검사는 유지하며, 단계·자원·논리 Buffer 계측만 끈다. off 설정 digest는 별도로 만들고 54회 계측 결과로 인정하지 않는다. `container-runner.ts`는 기존 입력 volume 확인/읽기 전용 mount와 별도 overhead 결과 검증을 추가했다. 앱 DI/데이터/API 변경은 없다.

Mac 게이트 `output/verification/1791007729194-7586fa0a-0982-44f8-9530-06ed5710a000/summary.json`, Linux 게이트 `output/verification/1791007765936-f2359d8c-a71b-4291-871f-7de9a849c2df/summary.json` 모두 **passed**. 각각 lint/build/전체 206개 테스트/필수 ID 98개/추출 fixture 통과. 추가 5개는 off 동일 경로, 5쌍 계산, 누락·중복·계측 재사용·환경 오류 거절, 실패 후 미실행 보존, volume/overhead 외부 감독이다. 중간 형식 오류 게이트는 실패로 보존했고 수정 후 전체 재실행했다.

검사한 HEAD는 `1d67d61faa04984783083971688a7c628df74748` + 작업 트리, Mac source digest는 `27a71dc16998b65daa8b1aba467676a3087e44159d644cfd3803e0dfa352e9b7`(135파일). 최신 고정 이미지는 `sha256:2e753ac3e42047906cf88fc15c6e702a415af23cebcfe9030bcaea1432a8b525`(Linux ARM64, Node 24.21.0)이다. 이 게이트 이후 Worker 코드는 변경하지 않았다.

## 첫 준비 측정 중단 — 다음 결정 필요

입력은 전용 Linux volume `outpick-lookbook-input-20261003-18prep`에 manifest/covers/golden/HTML/images만 복사하고 실험에는 읽기 전용으로 연결했다. 실행 manifest와 원본은 `output/lookbook-import-performance/approved-local-23e6cfee-9d91-4fae-befa-98ef70016555/`에 있다. `manifest.json`에 준비 18회/본 54회 계획·이미지·source·입력 digest·캐시 조건을 기록했다. 로컬 실행 연결은 `output/lookbook-import-performance/run-approved-local.mjs`다.

첫 준비 **A-six-1**은 추출 6시즌 모두 needs-review 정합성을 유지했으나 저장 중 메모리 표본 간격이 500ms를 넘어 `aborted/environment/sample-gap`으로 종료했다. 마지막 유효 표본 약 212.48ms, 중단 시각 약 714.23ms로 약 501.75ms 차이다. 안전 감독 표본은 3개, 관측 최대 메모리는 5.54%였지만 중간 표본이 누락됐으므로 전체 최대 사용량으로 해석할 수 없다. 별도 자원 계측에서는 최대 표본 간격 약 1962ms, 이벤트 루프 최대 지연 약 86ms, sharp process 4/queue 12를 기록했다. 외부 종료 exit 0/OOM false여도 실험 성공으로 처리하지 않았다. 종료 시 논리 보유 바이트/객체는 0이다.

추가 18회 중 1회 중단, 나머지 17회 미실행. `preparation-summary.json`은 eligible false, overhead not-started이다. 54회는 **0회**이며 성능 비교나 후보 채택 근거가 없다. 기존 정상 A·단일 시즌 검사 1회와 이번 실패를 서로 대체하지 않는다.

원인 후보는 `resources.ts`의 비동기 `fs.readFile`이 sharp 변환과 libuv 작업 풀을 공유해 cgroup 읽기가 대기하는 것이다. **실제 실패의 단독 원인으로 확정하지는 않았다.** 별도 격리 진단 `output/lookbook-import-performance/{diagnose-sampler-pool.mjs,sampler-pool-diagnostic.json}`에서 4개 CPU 작업 중 비동기 cgroup 읽기는 약 578.79ms, 동일 파일의 동기 표본은 5개/최대 간격 약 101.66ms였다. 이미지 성능 실험 표본이 아닌 측정기 경합 진단이다.

사용자가 **작은 cgroup 파일만 동기 읽기로 변경**하는 안을 승인했다. `resources.ts`의 기본 reader만 `readFileSync`로 바꿔 pool 대기를 없애며, 메인 이벤트 루프 지연 가능성과 100ms/500ms/85% 1초 감독 기준은 유지한다. `resources.test.ts`는 별도 Node 프로세스의 libuv 풀을 1개 CPU 작업으로 채운 뒤 실제 기본 메모리 reader가 그 작업 완료 전에 반환함을 검증한다. 미지원 환경의 null 반환과 v1/v2 계약도 유지한다. 이전 실패 결과는 보존했다.

## 측정기 보완 후 최신 게이트와 재개

Mac `output/verification/1791008002386-bde1aa5b-7aae-459c-bff3-ea1db54c330c/summary.json`, Linux `output/verification/1791008043404-2de19dce-a8dd-4685-ae98-1e42e6b87e7d/summary.json` 모두 **passed**. 각각 lint/build/전체 **207개** 테스트/필수 **99개**/fixture 통과. HEAD는 이전과 같고 Mac digest `ef7ca7fd1293c6f3cec83b7678736283b9eaa7bbe6ee46149ba4096e8efcab34`(135파일), Linux 연결 포함 digest `ffbfdb66f331da6fcdb8e93fb74d22fadcd37d90020aadbc4804b8258f212320`(138파일)이다. 검사 후 Worker 코드 변경 없음.

새 고정 이미지 `sha256:34147ae956274fb5db731ef30b33bd39ccb0d06a11ca0bd8c3f1ef487e03fc72`, 같은 읽기 전용 Linux 입력 volume을 사용한다. 새 회차 원본 디렉터리는 `output/lookbook-import-performance/approved-local-272a52df-4371-4b56-a7b5-fef0da5c33fd/`다. 구 이미지의 중단 1회는 별도 기록이며 신규 18회/54회 성공 분모에 넣지 않는다.

### 구조별 준비 6회 결과

| 구조 | 결과 | 두 구간 합계 | 관측 최대 컨테이너 메모리 |
| --- | --- | ---: | ---: |
| A | 성공 | 72.38초 | 75.11% |
| B | 성공 | 70.98초 | 79.23% |
| C | 성공 | 38.11초 | 76.89% |
| D | 성공 | 58.69초 | 80.48% |
| E | 성공 | 38.02초 | 68.27% |
| F | 메모리 중단 | 비교 부적격 | 88.19% |

A~E는 6시즌 추출/검토와 274개 JPEG 출력 정합성이 통과했다. F는 메모리 85% 이상 구간이 약 1007.51ms 지속돼 감독이 중단했다. 표본 지연/환경 실패나 OOM이 아니며 exit 0/OOM false여도 성공으로 세지 않는다. 중단된 F의 약 71초를 완료 시간으로 비교하지 않는다. 표는 각 구조 1회 준비 결과로 최종 순위·채택 판단에 사용하지 않는다.

최초 로컬 연결 스크립트는 모든 비성공 준비 결과에서 보수적으로 정지했다. 이미 합의한 ‘해당 회차 메모리 중단을 실패 분모에 보존’ 계약에 맞춰 `resume-approved-local.mjs`에서 외부 종료/유효 cgroup/85% 1초/결과 ID·digest·중단 상태를 검증한 후 남은 준비 측정을 이어 간다. `continuation.json`에 근거를 기록하고 기존 `preparation-summary.json`은 덮어쓰지 않는다. 환경 실패·정합성 실패는 후속 실행을 막으며, 정상적으로 감지한 메모리 중단은 성공으로 바꾸지 않고 기존 54회 행렬의 관측 대상으로 유지한다. 구조·부하·반복 횟수·안전 기준·합격 기준 변경 없음.

## 최종 54회 결과 — 구조 탐색 완료

본 실행은 2026-10-03 06:22:54~06:58:55 UTC(한국 15:22~15:58), 약 36분이었다. 각 회차는 새 Linux ARM64 컨테이너, 1 vCPU·2GiB·swap 0·네트워크 없음, 고정 입력 읽기 전용 volume, 무결성 검사 후 측정 조건이다. 계측 보완 후 추가 18회는 **17회 성공·F 준비 1회 메모리 중단**이다. 이전 이미지의 환경 중단 1회와 최초 A 단일 환경 검사 1회는 별도 보존하며 이 분모에 섞지 않았다.

계측 on/off 준비 2회와 교차 5쌍은 12회 모두 정합성·메모리 감독을 통과했다. 준비를 제외한 off 중앙값 2623.21ms, on 2695.69ms, 차이 **+2.76%**. 쌍별 차이는 -6.79~+8.73%였으며 고정 보정값으로 성능 결과에서 빼지 않는다. on/off는 같은 프로세스이고, 본 54회는 회차별 새 프로세스다.

본 54회는 **48회 성공·6회 메모리 중단·일반 실패 0·환경 미준비 0**. `summarizeComparisons` 결과 valid true/issues 빈 배열, planned/recorded 모두 54다. 중단을 원래 분모에 남기며, 한 번이라도 중단된 구조·부하 조합의 완료 중앙값은 계산하지 않았다. 실제 성공 출력은 golden의 개수/SHA/용량/경로 순서를 유지한다.

| 구조 | 2026 SS 1시즌 중앙값 | 한 브랜드 6시즌 중앙값 | 합성 3브랜드 중앙값 | 메모리 중단 / 9회 |
| --- | ---: | ---: | ---: | ---: |
| A 현재 경로 | 3.648초 | 69.446초 | 69.978초 | 0 |
| B 시즌 병렬·8개 묶음 | 2.712초 | 71.850초 | 69.842초 | 0 |
| C 시즌 병렬·공용 단계 제한 | 1.988초 | 38.003초 | 37.931초 | 0 |
| D 브랜드 내 순차·8개 묶음 | 2.413초 | 60.486초 | — | 1 |
| E 브랜드 내 순차·공용 단계 제한 | 2.013초 | 37.960초 | 37.599초 | 0 |
| F 유한 대상 전체 제출 | 3.265초 | — | — | 5 |

시간은 추출→검토와 승인 후 저장이라는 **분리된 두 구간의 시간 합계**다. 실제 관리자 대기/Cloud Tasks/Firestore 전체 lifecycle 완료 시간이 아니다. 합성 브랜드도 같은 UNAFFECTED 자료를 연도별로 나눈 스케줄링 부하다.

C의 기준선 대비 시간 단축은 단일/6시즌/합성에서 **45.52/45.28/45.80%**, E는 **44.83/45.34/46.27%**다. C와 E의 부하별 중앙값 차이는 약 1.3% 이내이며 이번 3회 탐색으로 통계적 우열을 확정하지 않는다. D는 합성 부하 1/3 중단, F는 6시즌 3/3·합성 2/3 중단이다. 이들은 현재 1 CPU/2GiB 조건에서 실패율 비악화 기준을 충족한 후보로 추천하지 않는다.

### 자원 해석과 한계

- 6시즌 저장 구간의 평균 CPU 사용은 한 코어 기준 약 100%였다. CPU 사용 시간/구간 wall time으로 계산했으며 순간 사용률이 아니다. 이 로컬 부하는 실제 변환 비용이 크고, 업로드·경로 저장은 spy다.
- 6시즌 A/B/C/D/E의 관측 변환 active 최대는 각각 **17/40/2/16/2**, 다운로드 active는 **18/48/4/8/4**였다. active 변환에는 native 처리 대기가 포함되므로 CPU 코어 수와 같지 않다. 같은 부하의 sharp 대기열 최대는 **13/36/0/12/1**이었다. 전체 제출의 작업 수와 실제 처리량을 구분해야 한다.
- C/E의 첫 입력 시즌(2026FW) 저장 완료 중앙값은 6시즌에서 **13.70/13.36초**, 합성에서 **14.11/14.50초**였다. A는 각각 69.18/69.73초였다. 이는 첫 번째 입력 시즌 기준이며 가장 먼저 끝난 임의 시즌 기준이 아니다.
- 본 실험의 모든 부하를 통틀어 관측 최고 컨테이너 메모리는 A **72.71%**, B **83.86%**, C **82.40%**, D **90.30%**, E **82.72%**, F **92.94%**였다. 최고치가 85%를 잠깐 넘는 것과 1초 지속 중단은 다르다. C/E가 A보다 항상 메모리를 적게 쓴다고 결론내릴 수 없다.
- 성공 결과의 자원 표본 최대 간격은 약 **190.69ms**였고, 보완 후 54회에서 환경 표본 지연 중단은 없었다. 메모리 중단 시 진행 중 작업을 회수한 시간도 원본에 남겼다.
- CPU 시간 차이를 만든 native 내부 원인까지 분해한 것은 아니다. 변환 2개가 이 입력에서 유리했다는 실측 근거이며, 모든 CPU/이미지/버킷에서 최적이라는 뜻이 아니다. 다운로드 4/업로드 4의 실제 네트워크 최적성은 로컬 파일/spy로 판단할 수 없다.

### 원본과 후속 추천

동일 실행 루트 `output/lookbook-import-performance/approved-local-272a52df-4371-4b56-a7b5-fef0da5c33fd/` 아래:

- `manifest.json`: 18/54 계획, 입력·소스·이미지·volume·캐시 조건.
- `preparation/*/{plan,started,container,result,finished}.json`: 구조별 준비 6회.
- `overhead/A-single-1/{warmup-*,pair-*,result,finished}.json`: 준비 2회와 교차 5쌍 원본.
- `preparation-completed.json`, `continuation.json`: 준비 종료 및 메모리 중단 보존·재개 근거.
- `main/*/{plan,started,container,result,finished}.json`: 54회 개별 측정과 외부 종료 증거.
- `summary.json`: 프로그램적 54회 집계. `observations.json`: 구간·첫 시즌·CPU·동시성·메모리·개별 반복을 포함한 파생 관측표. 생성기는 `output/lookbook-import-performance/summarize-observations.mjs`다.

종료 후 실행 중 컨테이너가 없음을 확인했다. 입력 volume과 고정 이미지는 후속 비교용으로 유지한다. 필수 게이트 이후 Worker 코드 변경은 없고 하네스와 로컬 결과 연결만 갱신했다.

**추천:** C를 우선 후속 후보로, E를 비교 후보로 남긴다. C/E 속도 차이가 작으므로 브랜드 순차 실행권·대기열·lease 복구 계약이 추가로 필요하지 않은 C가 더 단순하다. 제품 기본값 변경과 최종 채택은 보류한다. 3회 탐색에 합의한 5쌍 반복 악화 판정식을 적용하지 않았으며 Development 실제 업로드/Firestore/분산 동작도 미검증이다.

다음 제안은 **C의 변환 동시성 1/2/4/전체 제출을 6시즌에서 각 3회, 12회로 비교**해 숫자 2를 검증하는 것이다. 다운로드 4·업로드 4·경로 전체·재사용 off 등 나머지는 고정하고, 그 뒤 선택 조합을 3부하에서 재검증한다. 이 추가 회차는 아직 승인·실행하지 않았다. 실제 업로드/다운로드 수치 조정은 네트워크가 있는 Development 비교로 분리한다.

다운로드 재사용 예산별 대조도 별도다. 현재 6시즌 전체 원본 약 112.8MB는 128MiB보다 작고 실제 URL은 needsReview이므로, 128/256/512/all의 용량 차이와 자동 등록 효과를 이 54회로 검증했다고 주장하지 않는다. 통제된 동일 실행 재사용 부하와 추가 회차를 먼저 정리해야 한다. Phase 4 실제 총 5회 claim 계약·수동 재시도/검토 재개 예산, Phase 5 구체 클라우드 실행안 승인은 남아 있다.
