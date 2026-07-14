# Phase 1 Contract Inventory

## 목적

네 대형 인프라 파일을 분리하기 전에 외부에서 관찰되는 계약과 원자적 처리 경계를 고정한다. Phase 2~5는 이 기준선을 변경하지 않고 내부 소유권과 의존성만 바꾼다.

## 확정 기준

1. Firebase callable 이름, payload/response, `HttpsError` 의미를 보존한다.
2. Socket event, payload, ACK, 인증 handshake와 side-effect 순서를 보존한다.
3. GRDB는 Phase 1 당시 19개 migration 기준선을 기록하되, 미배포 개발 단계에서 승인한 D15 clean break와 D18 strict rollback은 Phase 3에서 의도적으로 변경한다.
4. iOS → GRDB → Functions → Socket 순서로 영역별 전환한다.
5. giant façade는 해당 phase의 컴파일 가능한 중간 상태에만 허용하고 phase 완료 전에 제거한다.
6. Socket에는 `node:test` 기반 최소 계약 테스트를 추가한다.
7. `callHelloUser`와 화면의 직접 디버그 호출은 Phase 2에서 제거한다.

## 기준선 요약

| 영역 | 현재 진입점 | 기준선 | 목표 진입점 | 상세 |
| --- | --- | --- | --- | --- |
| iOS Functions | `CloudFunctionsManager.swift` | public method 41개: callable wrapper 40개 + 제거 승인된 debug API 1개 | 공통 transport + 기능별 capability Protocol/Client | [iOS Functions](ios-cloud-functions.md) |
| iOS local DB | `GRDBManager.swift` | migration identifier 19개, 현재 table 8개, 기능별 operation과 transaction | `AppDatabase` + migration registry + 기능별 Store | [GRDB](grdb.md) |
| Firebase Functions | `functions/src/index.ts` | export 49개: callable 43, Firestore trigger 3, scheduler 3 | 기능별 module + 기존 이름의 flat export | [Firebase Functions](firebase-functions.md) |
| Socket Cloud Run | `Socket/index.js` | HTTP health 3개, 인증 middleware, Socket event/ACK와 persist/fanout 순서 | bootstrap + middleware/handler/service/runtime state | [Socket](socket.md) |

## Phase 2~5 공통 회귀 비교 항목

- 이름: Swift public capability, Firebase export, Socket event, DB migration/table/index.
- 입력: key, nullability, 기본값, cursor와 limit.
- 출력: key, 중첩 구조, optional 처리, ACK success/error shape.
- 오류: 인증/권한/validation/not-found/rate-limit/idempotency 의미.
- 실행 옵션: region, timeout, memory, schedule, timezone, trigger path.
- 처리 순서: DB transaction, Socket persist → emit → push → ACK, cleanup 순서.
- 의존성: singleton/concrete type 직접 사용을 좁은 Protocol 주입으로 교체한다.

## Phase 1에서 발견한 추가 논의 항목

Phase 1 완료를 막지는 않지만 해당 구현 phase 전에 결정해야 한다.

| ID | 상태 | 발견 | 결정/추천안 |
| --- | --- | --- | --- |
| N1 | Phase 2 확정 | `discoverSeasonCandidates`, `getLatestLookbookExtractionDiagnostic` iOS wrapper의 현재 소비자를 찾지 못했다. | 서버 export는 유지하고 iOS wrapper는 새 adapter에 복제하지 않는다. |
| N2 | Phase 2 확정 | 서버 callable `listBrandRequests`, `updateBrandRequestStage`, `resolveBrandRequest`는 현재 iOS manager wrapper가 없다. | 서버 계약은 유지하되 iOS wrapper를 새로 추가하지 않는다. |
| N3 | Phase 3 확정 · D15 | GRDB의 legacy `roomImage` API와 no-op migration identifier가 남아 있다. | 앱 미배포를 근거로 no-op 3개와 `createRoomImage` migration/table/API를 제거한다. 별도 drop migration 없이 개발 DB를 초기화한다. |
| N4 | Phase 3 확정 · D16 | `ChatMessageManager`가 message와 profile cache를 함께 사용하고 room cleanup은 여러 table을 횡단한다. | 소비자별 Protocol로 나누고, 여러 table을 바꾸는 transaction은 해당 operation 전용 Store가 소유한다. |
| N5 | Phase 3 확정 · D17 | `ChatMessage` 같은 domain entity와 GRDB record 분리 범위가 확정되지 않았다. | 메시지·프로필·미디어의 복잡한 row/JSON mapping만 persistence record로 분리하고 기존 read model과 OutboxRecord는 유지한다. |
| N6 | Phase 3 확정 · D18 | 메시지 저장 중 FTS 오류를 내부에서 삼켜 message/media만 commit될 수 있다. | FTS 오류를 전파해 message/FTS/media write 전체를 엄격하게 rollback한다. |

## 완료 판정

- 현재 계약, 소비자, 목표 소유자, 회귀 위험을 네 영역별로 기록했다.
- 제거가 확정된 API와 단순 미참조 후보를 구분했다.
- Phase 2~5에서 비교할 export/event/schema/transaction 기준선을 기록했다.
- 코드, schema, runtime option, 배포 설정은 변경하지 않았다.
