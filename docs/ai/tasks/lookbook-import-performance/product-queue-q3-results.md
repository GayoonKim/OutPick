# 제품 룩북 대기열 Q3 — 이미지 공개·브라우저 자원 격리

2026-10-05. Q3 코드를 queue-owned Worker 경로에 연결하고 G-W/G-E/G-L을 재실행했다. **Q3 전체 완료는 아니다.** 로컬 Worker·Firestore Emulator와 Linux/amd64 컨테이너 경계는 통과했다. 실제 URL/Cloud Storage, production Worker 서버 전체의 SIGTERM·복구, legacy route cutover, Development 검증은 남아 있다. 제품 FIFO는 아직 활성화하지 않았다.

## 구현된 동작

- `queue/asset-paths.ts`는 이미지 쓰기를 execution/epoch/write별 경로로 분리하고, `queue/asset-publication.ts`는 Storage upload 전에 `writes/{writeID}`에 `uploading`과 brand/season/target path 정보를 기록한다.
- 썸네일·상세 객체의 generation과 크기를 확인한 뒤 현재 batch owner/epoch가 유효할 때만 Firestore의 참조 경로를 바꾼다. 둘 중 하나의 업로드/확인/publication이 실패하면 불완전 결과를 앱에 공개하지 않고 기존 참조를 보존한다.
- `queue/browser-gate.ts` singleton은 한 Worker 인스턴스에서 Chromium 하나만 허용하고 browser와 image/hash 작업을 겹치지 않게 한다. browser가 기다리기 시작하면 신규 image/hash 입장을 막고 이미 시작한 이미지 작업을 drain한다. browser permit을 얻을 때 batch `SourceBufferStore`들의 보관 cache를 비운다. 이 정책은 재다운로드를 늘릴 수 있으며 효과는 Development에서 측정해야 한다.
- `processor.ts` import 렌더링, `season-discovery.ts` discovery 렌더링, `extraction/dedupe.ts` content hash 다운로드, 이미지 sync를 공유 gate에 연결했다. abort는 queue signal로 전달하고 browser를 닫는다.
- Functions `deletion/assetWriteFence.ts`는 `status=uploading` ledger가 남은 post/season/brand 범위 purge를 차단한다. 삭제 조회 실패도 fail-closed다. terminal write 상태가 되면 삭제 fence가 풀린다. `firestore.indexes.json`에 필요한 collection-group 복합 인덱스 3개를 추가하고 queue Emulator에 이 인덱스 파일을 연결했다.
- retryable import 실패는 사용자가 확정한 대로 추가 대기 없이 즉시 재시도하며, 최초 시도 포함 총5회 제한을 유지한다.
- G-L은 현재 Worker 코드를 Linux/amd64·CPU 1개·메모리 2 GiB 제한에서 빌드/실행한다. 실제 Chromium을 띄워 gate의 browser/image 배타 경계, cache 반환, cgroup 표본과 browser child의 SIGTERM 종료를 확인한다. 별도 192 MiB container에서 worker image의 Node allocator를 실행해 kernel OOM kill 증거를 확인한다.

## 변경 파일

- Worker: `tools/lookbook-import-worker/Dockerfile`; `src/queue/browser-gate.ts`, `browser-gate.test.ts`, `batch-runner.ts`, `asset-publication.ts`; `pipeline/source-buffer-store.ts`, `pipeline/pipeline.test.ts`; `processor.ts`, `season-discovery.ts`, `extraction/dedupe.ts`; `scripts/{queue-linux-smoke,queue-linux-sigterm-child,queue-linux-gate.test,run-queue-linux-tests}.mjs`.
- Functions/Firestore: `functions/src/lookbook/deletion/assetWriteFence.ts`, `deletion/functions.ts`, `firestore.indexes.json`, `firebase.lookbook-queue.json`.
- 검사: `firestore-tests/lookbook-import-queue.emulator.test.mjs`, `verification/{lookbook-import,lookbook-product-queue,lookbook-queue-linux}.json`.
- 하네스: `docs/ai/ENTRYPOINTS.md`, `docs/ai/ADR.md`, `docs/ai/DATA_SCHEMA.md`, `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`, `docs/ai/entrypoints/{DATA,FIREBASE,LOOKBOOK,TESTS}.md`, `verification/README.md`, `product-queue-design.md`, `product-queue-implementation-plan.md`, `HANDOFF.md`.

## 필수 검증 결과

| 게이트 | 결과 | source digest / 범위 | 원본 |
| --- | --- | --- | --- |
| G-W `verification/lookbook-import.json` | 통과: lint/build/fixture, Worker 테스트342개, 실패·취소·skip0 | `9974b69f2f7a5b1c2dc298723dcba00f815eb5ec109fc29ff191ee953f4309f1`, 222 files | [summary.json](../../../../output/verification/1791204616659-cd78fe1e-aef6-49e2-b259-528722c17cf5/summary.json) |
| G-E `verification/lookbook-product-queue.json` | 통과: Worker/Functions build, Firestore Emulator59개, 실패·skip0 | `8cb8f2ad95a25e4afbb6861324cc8019fbded38113b12044802d6f1520230cd1`, 271 files | [summary.json](../../../../output/verification/1791202927198-85bb5ef3-5200-4b48-826b-81e92b2814a1/summary.json) |
| G-L `verification/lookbook-queue-linux.json` | 통과: Linux/amd64 1 CPU·2 GiB Chromium/메모리 guard/SIGTERM drain + 192 MiB cgroup OOM, 테스트2개·실패/skip0 | `e041d9d408877d08cc589282adf1965d99d06698be54bd0290764ae827ca06b8`, 220 files | [summary.json](../../../../output/verification/1791204563869-6a8fd235-05d9-4145-84d2-b3dfa48de383/summary.json), [원본 테스트/계측](../../../../output/verification/1791204563869-6a8fd235-05d9-4145-84d2-b3dfa48de383/queue-linux-container/node-result.jsonl) |

G-W는 browser/image admission의 active 작업 drain·새 admission 차단·취소·FIFO 단일 browser·cache purge와 pipeline/hash 경계를 포함한다. G-E는 실제 batch runner가 browser 전환 시 공유 batch cache를 비우는지, asset upload 중 삭제 fence가 post/season/brand 단위로 작동하고 terminal 뒤 풀리는지 확인한다.

G-L 계측은 Linux x64, CPU quota1, cgroup v2 메모리 limit 2,147,483,648 bytes를 확인했다. Chromium 동작 중 표본18개, 최대 표본 간격131.98ms, container 최대 사용률35.21%, event loop 최대 지연116.72ms였고 supervisor의 memoryStop/admissionStop은 null, gate/SourceBuffer 잔여량은0이었다. 실제 cgroup 메모리를 천천히 올린 추가 검사에서는 약17.23초 뒤 85%가 1초 지속되어 `memory:sustained-high`가 발생했고, 새 투입 신호가 중단됐다. 관측 최고 비율은88.58%, 표본159개였다. SIGTERM 뒤 실제 Chromium 프로세스4개가 종료됐고 browser gate가 완전히 비었다. 별도192MiB container는 `OOMKilled=true`, exit137로 기록됐다. 이는 제품 환경 성능 결과가 아니며 Storage/Firestore 연결·실제 Worker HTTP 서버 복구·Cloud Run 종료 동작을 검증하지 않는다.

재현 중 최초 G-W 시도는 게이트 자식 프로세스에 Node24 `PATH`가 전달되지 않아 `worker-lint`에서 차단됐다([원본](../../../../output/verification/1791202710676-f7f4381f-d9ef-4fc4-a258-e128ad6105dc/summary.json)). 최초 G-E는 새 Emulator 테스트가 resource evidence를 잘못된 객체 경로에서 읽어 1개 실패했다([원본](../../../../output/verification/1791202846711-9f3e02c3-d2c0-467f-8532-1798e4c3cc74/summary.json)). 테스트는 실제 `SourceBufferStore` 스냅샷을 검사하도록 수정했고 Node24 PATH를 명시해 위 최신 게이트를 재실행했다. 실패/차단 원본은 보존했다.

## 완료되지 않은 조건과 다음 단계

- Gate는 Mac 로컬 Worker와 Firestore Emulator에 한정된다. 실 네트워크 다운로드·Cloud Storage 쓰기·실제 Functions/Cloud Run 설정/요금·Development 성능은 측정하지 않았다. Firestore index도 파일에만 있으며 원격 배포 여부는 확인하지 않았다.
- Linux gate는 실제 Chromium launch/close, browser-image 겹침0, cgroup 표본 공백, child SIGTERM drain, 2GiB cgroup의 85%/1초 중단 및 별도 OOM container를 검사했다. 아직 실제 Worker HTTP server를 띄운 Cloud Run 방식 종료/Firestore owner 복구는 검사하지 않았다.
- 보호는 queue-owned path에 한정된다. legacy direct processor가 같은 저장 ledger/publication/fence를 사용하도록 cutover하거나 우회 실행을 완전히 차단하기 전에는 제품 FIFO를 활성화하지 않는다.
- Q4 stale `uploading` ledger의 증거 기반 inspect/resume 및 미참조 객체 정리를 구현/검증해야 한다. 원장만 남은 상태는 자동으로 삭제/해제하지 않는다.
- Q2의 14분 hard drain, Functions Cloud Tasks sender/trigger와 discovery/continuation 실행도 미완료다.

이번 턴에는 Functions/Firestore 인덱스 배포, Cloud Tasks 송신, Firebase 제품 데이터 변경, 실제 삭제, URL/Storage 네트워크 실험을 하지 않았다. [단계별 구현 계획](product-queue-implementation-plan.md)을 이어 따른다.
