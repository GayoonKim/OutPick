# OutPick 게이트 설정

## 제품 룩북 대기열 Q4 복구·정리 로컬 검증(2026-10-05)

Q4 최신 코드는 아래 필수 gate 원본에서 모두 통과했다. 각 summary에는 당시 소스 digest/file count가 있다. 실제 Development/Production deploy, IAM 권한 추가, Cloud Run 종료 로그 확인, 원격 Storage 삭제·복구 호출은 하지 않았다.

| 게이트 | 실행 ID | 결과 |
|---|---|---|
| G-F `functions.json` | `1791209282584-d438daf9-4d01-4b10-aa84-990ca46cf485` | passed, 314 Functions tests |
| G-E `lookbook-product-queue.json` | `1791209301168-92159c88-087b-4a51-b386-03fa600d7821` | passed, 68 Firestore Emulator tests |
| G-W `lookbook-import.json` | `1791209345170-c79b0a40-968f-4321-a4f0-aa394b6cf2ed` | passed, 347 Worker tests + fixture |
| G-R `firestore.json` | `1791209483839-053eae73-ebd6-47bc-ba83-c4950f73c179` | passed, 131 Firestore/Storage tests |
| G-L `lookbook-queue-linux.json` | `1791209548822-14101190-711a-415a-8dd3-a8fb0055b227` | passed, 2 Linux/amd64 container scenarios |

세부 digest·실패 후 수정 이력·Development 미검증 경계는 [Q4 결과](../docs/ai/tasks/lookbook-import-performance/product-queue-q4-results.md)를 따른다.

## 제품 룩북 대기열 Q1 공통 접수 계층

`lookbook-product-queue.json`은 Functions 빌드 후 `firebase.lookbook-queue.json`의 Firestore 에뮬레이터(`demo-lookbook-queue`, `127.0.0.1:8086`)에서 실제 transaction·준비·전달 intent·조회 callable·원본 접근 차단과 미연결 작업 차단15개를 검사한다. Functions/Firestore 게이트는 같은 lib를 빌드하므로 순차 실행한다. `functions.json`은 기존 export 검사를121개(조회 callable 추가)로 갱신하고 순수 로직3개를 추가했다. 기존 task ID 회귀2개도 필수 ID로 명시해 전체 필수19개다. 기존 필수 항목을 제거하지 않았다.

현재 범위는 공통 접수/조회/준비/송신 계층과 기존 trigger/watchdog의 큐 소유 job 제외다. 기존 실행 접수 callable 전체의 adapter 연결, 실제 Worker route, 실 클라우드 task 전달은 아직 완료되지 않았다. G-E 통과를 Q1 전체 또는 제품 FIFO 실행 완료로 해석하지 않는다. [Q1 진행·검증](../docs/ai/tasks/lookbook-import-performance/product-queue-q1-results.md)을 따른다.

## 제품 룩북 대기열 Q0

`contracts/lookbook-import-queue-v1.json`과 Functions/Worker `queue/contracts.ts`, 앱 `LookbookImportQueueContract.swift`의 공통 접수 필드·정책값·상태/오류 분류를 대조한다. 실험 remote version5와 제품 version1은 별개다. 실제 접수·FIFO·저장·복구·앱 Repository 연결은 Q1 이후이며 Q0 통과로 제품 전체를 완료 처리하지 않는다.

- `functions.json`: 기존 필수 검사를 유지하고 PQ00 공통 계약5개 추가. lint·빌드·전체 Functions 테스트.
- `lookbook-import.json`: 기존 필수208개에 PQ00 계약5개 추가. lint·빌드·전체 Worker 테스트·추출 fixture. 로컬 HTTP 포트 접근 필요.
- `lookbook-queue-ios.json`: Q0 현재 범위는 `LookbookImportQueueContractTests`5개를 선택하는 실제 Development Simulator 빌드/xcresult 검사. Q5에서 GRDB·Repository·진행 검사를 추가한다.
- `lookbook-queue-contract.json`: 기존 공용 게이트 자체 회귀13개를 실행하는 초기 구축 검사. 초기 구축용 command 예외를 사용하며 실제 누락·skip·0개·오류 결과·환경 차단·입력 변경 판정을 확인한다.

각 런타임 게이트의 inputs에 공용 JSON을 포함했다. 아직 기능이 없는 emulator `lookbook-product-queue.json`/Linux `lookbook-queue-linux.json`은 Q1/Q2~3에서 실제 검사와 함께 생성한다. 빈 검사나 성공만 반환하는 임시 게이트를 만들지 않는다. Q0에는 rules 변경이 없으며 Firestore 게이트 통과를 주장하지 않는다. [단계별 필수 게이트·남은 범위](../docs/ai/tasks/lookbook-import-performance/product-queue-implementation-plan.md), [Q0 실행 기록](../docs/ai/tasks/lookbook-import-performance/product-queue-q0-results.md)을 따른다.

룩북 최신 원격 계약은 [A~J version5 고정8회](../docs/ai/tasks/lookbook-import-performance/ten-brand-connection-results.md)다. Worker 전체316개·필수208개에 TB07~09를 추가했고 RN01/03·RC01·emulator RD05를8회로 갱신했다. 아래 version4/313개는 이전 단계 기록이다. 새 검증의 원본 로그와 이미지 대조는 연결 검증 기록을 따른다.

룩북 A~J 준비의 로컬 기능 검사는 [검증 기록](../docs/ai/tasks/lookbook-import-performance/ten-brand-validation.md)을 따른다. `verification/lookbook-import.json`은 전체313개·필수205개이며 TB01/02의10브랜드·시즌6/null·공용 단계 한도와 TB03~06의100ms 접수·취소·정리·타이머 오류를 검사한다. `arrival-runner.ts`의 로컬 연결이며 원격18시즌·8회 manifest/집계 연결 완료를 의미하지 않는다.

룩북 최신 계약은 [역순3회(version4)](../docs/ai/tasks/lookbook-import-performance/development-reverse-comparison.md)다. RN01/03/05·RC01·RD05는 준비→SP→PP 순서, 이전계약/초과 회차 거부, 단일 관측/미판정 집계를 검사한다. 과거5회와21회 검증은 당시 코드 상태의 기록이다.

프로젝트 루트에서 작업에 합의된 설정을 실행한다. 기본 설정 통과가 다른 설정의 통과를 대신하지 않는다.

```sh
node tools/verification-gate/gate.mjs --project . --config verification/gate.json
```

| 설정 | 범위 | 준비 조건 |
| --- | --- | --- |
| `gate.json` | 공용 자체 검사, Firebase 환경 shell 검사, Socket 구문·테스트 | Node 22 이상, Socket 의존성 |
| `functions.json` | Functions lint·빌드·테스트 | PATH의 Node 24, Functions 의존성 |
| `lookbook-import.json` | Worker lint·빌드·전체 Node 테스트·추출 fixture, TB01~09/AP/AR/RN 포함 필수 ID208개 | PATH의 Node24, Worker 의존성·공용 계약 fixture·로컬 HTTP 포트. 최신 실행 원본은 [A~J version5 검증](../docs/ai/tasks/lookbook-import-performance/ten-brand-connection-results.md) 참조. 실제 원격 성능은 별도 |
| `lookbook-product-queue.json` | Functions/Worker build와 Firestore Emulator의 제품 FIFO·asset publication/deletion 경합 | Node24·Java·Firebase CLI·Functions/Worker/Emulator 의존성·로컬 포트. 원격 Firestore/Storage 배포는 하지 않음 |
| `lookbook-queue-linux.json` | Linux/amd64 Docker에서 Chromium·cgroup 표본·browser/image gate·SIGTERM child drain·격리 OOM | PATH의 Node24·Docker daemon/socket·AMD64 에뮬레이션 또는 호스트 지원. 제품 URL/Storage 네트워크는 호출하지 않음 |
| `lookbook-remote.json` | 원격 연결 build·로컬 Firestore 실행권 경합·version5 고정8회/추가회차 거부와 Storage/Firestore 접근 차단5개 | Node24·Java21·Firebase CLI·Worker와 firestore-tests 의존성. `firebase.lookbook-performance.json`으로 demo-lookbook-performance,127.0.0.1:8085/9195만 사용 |
| `firestore.json` | Firestore/Storage Emulator·트랜잭션·seed 검사 | PATH의 Node 24, Java, Firebase CLI, Functions 및 rules 테스트 의존성, 로컬 포트 접근 |
| `ios.json` | Development Simulator 빌드, AppRuntimeConfigurationTests 13개, KeyboardDismissSupportTests 4개 | Xcode, iPhone 17 Pro/iOS 26.2 Simulator, 프로젝트의 로컬 Development 설정 |
| `chat-media-retention.json` | 만료·캐시·영상 갱신·Photos·계정 경계 28 suite/필수 ID 91개 | Xcode, 지정 iPhone 17 Pro Max/iOS 26.2 Simulator, Development 설정, photos-add 권한 |

Node 24를 사용하도록 PATH를 준비한 후 위 명령의 설정 파일을 바꾼다. 설치된 Node 버전이 다르면 게이트가 차단한다. 의존성·Simulator·로컬 Firebase 설정을 준비하지 않은 clone은 통과로 기록하지 않는다. 비밀 설정과 실행 로그는 저장소에 커밋하지 않는다.

프로젝트의 `inputs`는 관련 테스트·설정·실행 스크립트·의존 코드를 포함해야 한다. 입력 경로나 필수 테스트를 추가/제거하는 변경은 해당 작업의 계획에서 검토한다. Node 필수 ID는 초기 연결 확인용 기준이며 새로운 기능의 요구사항을 자동 검증하지 않는다. iOS 설정은 명시한 환경 경계 13개와 키보드 터치 경계 4개를 검증한다. 제품 UI/실기기/운영 배포 검사는 별도 연결 대상이다.

공용 원본과 설치 방법은 [실행기 설명](../tools/verification-gate/README.md), 실행 결과와 남은 범위는 [진행 기록](../docs/ai/tasks/programmatic-verification-gates/progress.md)을 따른다.

채팅 미디어의 [최종 계약·개발 QA 결과·한계](../docs/ai/architecture/CHAT_MEDIA_RETENTION.md)를 함께 확인한다. Functions와 Firestore 게이트는 동일 Functions 산출물을, 두 iOS 게이트는 동일 derived data를 사용하므로 각각 순차 실행한다. Simulator 테스트 후 로그인 QA용 앱은 서명한 일반 DEV 실행으로 복구한다. GitHub CI/status check 연결은 포함하지 않는다.
# 룩북 대용량 준비 검사 추가(2026-10-03)

대용량 준비7회 당시 필수 ID139개·전체247개를 검사했다. `large-input.test.ts`의7개가 독립 합성 입력·엄격7회 계획·실제JPEG·예산/실패/취소·trace 경계·분모를 검증한다. [해당 실행 결과와 원본](../docs/ai/tasks/lookbook-import-performance/phase-3-large-input-design.md)을 따른다.

P4 비재사용 대조군 단계에서는 필수142개·전체250개가 Mac/Linux에서 통과했다. [당시 코드 식별자·원본·단일 실측](../docs/ai/tasks/lookbook-import-performance/phase-3-p4-off-control.md)을 따른다.

브랜드FIFO 비교 단계는 BF01~12를 추가한 필수157개·전체265개가 Mac/Linux에서 통과했다. 브랜드전환의 저장·정리 경계, 총5회 재시도, 엄격20회 행렬, 대기 포함 지표, 불완전 쌍 미판정과 OOM 경계 기록을 검사한다. [당시 소스 식별자·게이트 원본·실측 상태](../docs/ai/tasks/lookbook-import-performance/phase-3-brand-fifo-results.md)를 따른다.

현재 AD2a는 Mac/Linux 필수184개·전체292개와 로컬18/18회·42변환을 통과했다. [최종 코드·원본·범위](../docs/ai/tasks/lookbook-import-performance/adaptive-ad2a-results.md)를 따른다. AD1·이전 Development/emulator 결과는 당시 기록에 보존한다. 예약·R 이미지 연결·원격 비용/성능 검증은 별도다.

# 제품 큐 Q3 저장·브라우저 검증 (2026-10-05)

Q3 최신 로컬 G-W `1791204616659-cd78fe1e-aef6-49e2-b259-528722c17cf5`는 Worker lint/build/fixture 및 전체342개 테스트 통과, 실패·취소·skip0이며 source digest `9974b69f2f7a5b1c2dc298723dcba00f815eb5ec109fc29ff191ee953f4309f1`/222 files다. G-E `1791202927198-85bb5ef3-5200-4b48-826b-81e92b2814a1`는 Worker/Functions build 및 Firestore Emulator59개 통과, 실패·skip0이며 digest `8cb8f2ad95a25e4afbb6861324cc8019fbded38113b12044802d6f1520230cd1`/271 files다. G-L `1791204563869-6a8fd235-05d9-4145-84d2-b3dfa48de383`는 AMD64 Linux/1CPU/2GiB 실제 Chromium·cgroup·85%/1초 중단·SIGTERM 및 별도192MiB OOM 시나리오2개 통과, 실패·skip0이며 digest `e041d9d408877d08cc589282adf1965d99d06698be54bd0290764ae827ca06b8`/220 files다. [실행 기록·세부 범위](../docs/ai/tasks/lookbook-import-performance/product-queue-q3-results.md).

G-W/G-E/G-L은 모두 로컬 검사다. Linux 일반 browser sample은18개, 최대 간격131.98ms, container 최대 사용률35.21%, event loop max116.72ms였다. 메모리 압박 때 85%/1초 stop은 159개 표본·최고88.58%·17.23초에서 확인했고, SIGTERM 뒤 Chromium process4개 종료, 별도 OOM `true/137`이었다. 실제 URL·Cloud Storage, Worker HTTP server/Firestore owner 복구, 배포된 복합 인덱스, Development 비용·성능은 확인하지 않았다. 이번 실행에서 Node24 경로가 처음 전달되지 않아 G-W 1회 차단됐고, 첫 G-E에서는 새 통합 테스트가 잘못된 증거 경로를 읽어 실패했다. G-L 첫 시도는 Playwright `Browser.process()` 미지원 API로 실패했으며 `/proc` 증거 확인으로 수정했다. 각 실패 원본은 보존하고 최신 게이트에서 필요한 검사를 재실행했다.
