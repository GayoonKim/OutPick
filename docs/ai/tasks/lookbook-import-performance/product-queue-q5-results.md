# 제품 룩북 FIFO Q5 — 앱 요청·진행 연결

2026-10-06. 승인된 제품 큐 구현 계획의 Q5를 로컬에서 마쳤다. 사용자가 확정한 재시도 정책은 자동 대기 없이 즉시 재시도, 최초 시도 포함 총 5회다. 이번 단계에는 배포, IAM 변경, 실제 Development URL/Storage 작업이 포함되지 않는다.

## 구현

- `lookbookImportRequest` GRDB migration 27과 Record/Store를 추가했다. 요청은 계정 UID별로 분리하고, 동일 계정·kind·payload digest의 미확정 요청은 같은 requestID로 재사용한다. 성공 확정 영수증은 30일 뒤 정리하며 미확정/장애 상태는 정리하지 않는다. 계정 삭제 경로도 새 테이블을 지운다.
- `LookbookImportQueueRequestCoordinator`가 requestID·생성 시각·payload digest를 전송 전에 저장하고, HTTP 응답 유실은 미확정으로 보존한다. 재요청은 같은 ID와 입력을 재사용한다. 영수증은 contract version·requestID·brandID·kind가 요청과 일치해야 수락한다.
- 브랜드 생성과 최초 시즌 탐색은 기존 원자적 `createBrand` 서버 transaction에서 같이 접수한다. 앱은 반환된 discovery job을 관찰만 한다. 새 시즌 후보 batch, URL import, 목록 수동 갱신·재시도, asset 재시도, 추출 검토 승인·수동 재시도, 시즌 보수 분석·적용도 접수 envelope와 GRDB 기록에 연결했다. `insufficientImages`는 새 Worker 작업을 만들지 않는 기존 검토 갱신으로 남긴다.
- 후보 선택·시즌 관리 화면은 대기/처리/재시도 대기/검토/실패/복구 확인을 구분하고 requestID로 상태를 복원한다. 활성 화면에서만 3초/10초 polling을 하고 조회 오류는 10→20→40→60초로 늦춘다. 화면 닫기는 서버 작업을 취소하지 않는다. 자산 재시도 action은 큐가 끝날 때까지 polling을 직접 기다리지 않고 기존 단일 polling task만 시작한다.
- 공용 `LookbookRepositoryProvider.live`가 AppCompositionRoot의 GRDB store와 UID provider를 모든 queue adapter에 주입한다. 신규 navigation이나 구버전 앱 호환은 추가하지 않았다.

## 변경 위치

- DB: `OutPick/DB/GRDB/Core/AppDatabase.swift`, `Migrations/GRDBMigrationRegistry.swift`, 신규 `Records/LookbookImportRequestRecord.swift`, `Stores/GRDBLookbookImportRequestStore.swift`.
- 앱 계약/연결: `Features/Lookbook/Domains/Entities/LookbookImportQueue{Contract,Receipt}.swift`, `LookbookImportRequest.swift`, `UseCases/LookbookImportQueueRequestCoordinator.swift`, `StartSeasonImportExtractionUseCase.swift`, queue 관련 Cloud Functions adapters, `LookbookRepositoryProvider.swift`, `AppCompositionRoot.swift`, `LookbookContainer.swift`.
- 진행 UI: `SeasonImportManagementViewModel.swift`, `SeasonImportManagementView.swift`, `CreateBrandCandidateSelectionView.swift`, `CreateBrandFlowView.swift`.
- 회귀/검증: `OutPickTests/GRDB/GRDBLookbookImportRequestStoreTests.swift`, `OutPickTests/StartSeasonImportExtractionUseCaseTests.swift`, queue contract·Cloud Functions·migration·계정 삭제 tests, `verification/lookbook-queue-ios.json`.
- 하네스: `docs/ai/ENTRYPOINTS.md`, `docs/ai/entrypoints/{LOOKBOOK,DATA,TESTS}.md`, `docs/ai/DATA_SCHEMA.md`, 계획서, 이 결과, `HANDOFF.md`.

## 검증 증거

필수 G-I 명령:

```sh
node tools/verification-gate/gate.mjs --project . --config verification/lookbook-queue-ios.json
```

최종 실행 `1791215160798-bdd8851f-126d-4ab1-8591-b0e5da69d48d`: `passed`, 실패 0, 차단 0, 테스트 28개/8개 suite. 대상은 iPhone 17 Pro, iOS 26.2 Simulator다. 필수 케이스는 계약 6, GRDB 요청 store 2, 요청 유실/동일 envelope 1, migration suite 2, 계정 삭제 1, 브랜드 adapter 2, 시즌 import/discovery/review/repair adapter 4, ViewModel 회귀 1개다. ViewModel suite 전체 10건도 함께 통과했다.

게이트 입력 기준 HEAD `1d67d61faa04984783083971688a7c628df74748`, digest `62eefec21efe6f59579c3f22ee5b08bf42dbe4c6ef683e3bbfb5940b95ac49ff`, 981 files. 최종 원본은 `output/verification/1791215160798-bdd8851f-126d-4ab1-8591-b0e5da69d48d/summary.json`, Xcode 전체 로그는 해당 실행 폴더의 `lookbook-queue-contract-ios/stdout.log`, 테스트 bundle은 `lookbook-queue-contract-ios/tests.xcresult`다. 이전 통과 `1791214456301-810127a2-fa62-46b3-9387-2e46e34a4644`는 polling 보강 전 코드의 18개 결과다.

반복 실행도 보존한다. `1791214221244-91214a5f-9e42-4a19-aa94-0050216a7803`은 `defer` 내부의 Swift 컴파일 오류로 테스트 0개, `1791214287098-79135a8c-121e-45f6-b6ff-8a570f555bfb`은 테스트 initializer 인자 순서 오류로 테스트 0개, `1791214343484-8a135dc6-ec04-4766-93a9-84459dc990ab`은 GRDB expiry 테스트 fixture가 같은 payload digest를 재사용해 18개 중 1개 실패했다. 18개가 통과한 뒤 자산 재시도 action이 큐 종료를 기다리지 않도록 수정하고 ViewModel 회귀를 추가했으며, 현재 코드의 최종 실행 28개가 통과했다. 합격 기준을 바꾸거나 검사 대상을 제거하지 않았다.

Simulator 시작 중 Firebase Remote Config가 Installations keychain 오류를 로그에 남기고 기본값 fallback을 사용했지만, 선택된 Q5 테스트들은 모두 통과했다. 실제 원격 Functions/Firestore/Storage 동작을 검증한 것은 아니다.

## 후속 단계

- Q6 로컬 통합은 완료했다. 현 코드 digest 기준 Functions/Worker/Firestore Emulator/Linux/iOS 필수 게이트, discovery/continuation activation, 14분 HTTP 응답 경계와 관련 제한은 [Q6 결과](product-queue-q6-results.md)에 기록했다.
- Q7은 Development의 현재 revision·resource·IAM을 read-only로 대조한 뒤 실제 URL 다운로드/Storage 업로드·Cloud Run 종료/복구 증거·수동 앱 QA를 위한 요청 수와 비용이 제한된 실행안을 준비한다. Q5/Q6 동안 배포하지 않았고 실제 Development URL/Storage 트래픽을 발생시키지 않았다.
- 사람이 직접 확인할 화면 QA와 Development 연동은 G-I 통과로 완료 처리하지 않는다.
