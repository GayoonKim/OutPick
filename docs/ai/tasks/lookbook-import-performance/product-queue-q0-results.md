# 제품 룩북 대기열 Q0 — 계약·검증 연결

2026-10-05. 사용자 구현 승인으로 Q0 공통 계약·검증 연결을 완료했다. [단계별 계획](product-queue-implementation-plan.md)의 공통 계약 기준과 세 런타임 검사 연결이며, 제품 접수·실행 API에 활성화하지 않았다. Q1~Q7과 제품 전체 검증은 미완료다.

## 변경 범위

- `contracts/lookbook-import-queue-v1.json`: 확정 정책, 공통 requestID/requestCreatedAt/queueContractVersion 입력, 정상·오류·시간 경계 예제, 상태/오류 분류. 실험 version5와 제품 version1을 구분한다.
- `functions/src/lookbook/import/queue/contracts.ts` 및 test: 공통 envelope 파싱, 신규 접수 시간 판정, batch 상태 파싱. 기존 영수증 조회 전에 시간 만료를 검사하지 않도록 파싱과 시간 판정을 분리했다. 아직 callable에서 호출하지 않는다.
- `tools/lookbook-import-worker/src/queue/contracts.ts` 및 test: 같은 계약을 독립 런타임에서 검사. Functions의 rootDir 밖 소스를 import하지 않는다.
- `OutPick/Features/Lookbook/Domains/Entities/LookbookImportQueueContract.swift`, `OutPickTests/LookbookImportQueueContractTests.swift`: Codable 공통 필드·정책/상태 및 동일 golden 경계. 기존 앱 Repository/UseCase/DI는 변경하지 않았다. Xcode의 동기화 그룹으로 자동 포함한다.
- `verification/functions.json`, `lookbook-import.json`: 기존 필수 ID를 유지하고 PQ00 각5개와 공용 fixture 입력 추가.
- `verification/lookbook-queue-ios.json`: Q0 계약5개 전용 xcresult 게이트. `lookbook-queue-contract.json`: 기존 자체 회귀13개를 실행하는 초기 구축용 게이트. 공용 실행기/runner는 변경하지 않았다.

## 검증과 범위

최종 검증은 공용 fixture의 UUID 끝 줄바꿈 거절과 기존 Domains/Entities 경로 반영 이후 코드다. 각 summary의 source digest는 해당 설정 inputs 범위이며 서로 다른 게이트 사이에 같은 값일 필요는 없다. Git HEAD는 `1d67d61faa04984783083971688a7c628df74748`이고 기존 미커밋 변경을 포함한 실제 작업 트리를 검사했다.

| 게이트 | 결과·실제 실행 | 최종 원본 |
|---|---|---|
| Functions | passed: lint·build·전체304개, 필수14개(기존9+PQ00 5) | [summary](../../../../output/verification/1791184899943-34eab245-06c2-4498-8756-9f12daf189cf/summary.json) |
| Worker | passed: lint·build·전체321개, 필수213개(기존208+PQ00 5), 추출 fixture | [summary](../../../../output/verification/1791184907040-bdd7fc42-208c-4f15-a02d-e079e173e232/summary.json) |
| iOS | passed: Development Simulator 빌드·계약5개, 필수5개 | [summary](../../../../output/verification/1791184904367-fe297173-2c32-4809-8855-29cecde9b2a6/summary.json) |
| 게이트 자체 회귀 | passed: 기존 자체 테스트13개. 누락/skip/0개/오류/환경/입력 변경 차단 포함 | [summary](../../../../output/verification/1791184525472-f33725ad-ecbf-458a-929d-3f12476175d8/summary.json) |

Functions input digest: `19e1ec309194fa6a532c60221c69782797c4f72634903e1918b19f938808c922`.
Worker input digest: `2d10c2da7199d5666477a0bd0fe501e8205e6f67d170b6068460d61004b41951`.
iOS input digest: `82e2307ac4f8d57e696c54503adb562b1cfa50c495d7741f7a325877e2356985`.
자체 게이트 input digest: `94925def2afa457580706936ecc14013f175c8c420dcd8b40edfc1c6af1eca68`.

중간 결과 보존:

- [첫 Functions failed](../../../../output/verification/1791184513867-7ce9f19b-3cc0-4461-8729-4e0eb40fe82a/summary.json): 새 코드 max-len/comma-dangle4건 수정. 기존 경고는 별도이며 기준을 완화하지 않았다.
- [첫 iOS blocked](../../../../output/verification/1791184525473-a97c3cc7-0437-4b43-9165-c00fd3867567/summary.json): 샌드박스의 Simulator·Swift 캐시 접근 거절로 xcresult 해석 불가. 로컬 허용 권한에서 동일 게이트를 재실행했다.
- [첫 Worker blocked](../../../../output/verification/1791184525473-bc9c6db7-ab2e-44af-afdd-f6e2f073bd69/summary.json): 새 lint 오류와 로컬 HTTP listen EPERM5건. 실행 중 lint 수정으로 입력 변경도 검출됐으므로 통과로 사용하지 않았다. 종료 확인 후 같은 로컬 게이트를 포트 허용 환경에서 다시 실행했다.
- [보완 전 Worker passed](../../../../output/verification/1791184695075-a7924fd6-4725-43c0-8ae2-a3e856576b03/summary.json):321개/필수213개 통과. 이후 UUID 경계가 바뀌어 이 결과를 최종 코드 통과로 재사용하지 않았다.

단위 검사는 실제 룩북 다운로드/Storage 업로드를 요청하지 않는다. iOS 검사는 앱 호스트를 실행하므로 기존 앱 시작의 SDK 초기화 로그가 발생한다. 전체 네트워크 트래픽0이나 실기기 UI 검증을 주장하지 않는다. 제품 배포·IAM·실험 Worker 요청·실제 데이터 삭제는 수행하지 않았다.

Q0 검사는 24시간/미래5분의 정확한 경계를 허용하고1ms 초과를 거절하는지, malformed 입력·실험 계약 버전·알 수 없는 상태를 거절하는지 확인한다. 오래된 공통 envelope는 파싱 가능하므로 기존 영수증 우선 조회를 후속 admission에 연결할 수 있다. **실제 영수증 조회 순서/중복/권한/FIFO/복구를 Q0가 검증했다는 뜻은 아니다.**

G-E/G-L은 아직 구현할 동작이 없으므로 Q1/Q2~3에서 실제 검사와 함께 연결한다. G-I의 GRDB/화면/API 검사는 Q5에서 확장한다. PQ01~15는 후속 필수 범위로 유지하며 완료를 주장하지 않는다. 기존 Firestore rules/indexes는 변경하지 않아 이번 게이트 범위에서 실행하지 않는다.

## 후속

Q0 결과를 분석한 뒤 Q1 접수·중복 방지·순번·전달 의도로 이어간다. 요청 종류별 DTO·응답 projection·실제 상태 전이는 해당 기능 구현과 함께 검사한다. Development 배포·유료 실험·IAM 변경·실제 데이터 삭제는 별도 실행안 승인 전 수행하지 않는다.
