# Compatibility and Transition Proposals

## D4. 외부 wire와 data contract를 보존한다

상태: 확정 — 2026-07-13 사용자 승인

추천 결정:

- Functions export 이름, payload, response, HttpsError code를 유지한다.
- Socket event, payload, ACK, 인증 handshake를 유지한다.
- GRDB schema, migration identifier/order, transaction 결과를 기본적으로 유지한다.
- 내부 type과 file 경계만 변경한다.

이유:

- 구조 리팩터링과 계약 변경을 함께 수행하면 실패 원인과 rollback 단위가 커진다.
- Functions와 Socket은 현재 운영 배포된 런타임이다.

예외 처리:

- 계약 오류 또는 dead API가 발견되면 이번 phase에 섞지 않고 별도 결정으로 분리한다.
- Phase 3에서는 별도 사용자 승인을 받은 D15로 미배포 legacy migration/table/API를 clean break하고, D18로 FTS partial commit을 strict rollback으로 수정한다. 이 두 항목은 D4의 승인된 예외이며 나머지 GRDB 계약은 유지한다.

## D5. 계약을 먼저 고정하고 영역별로 순차 전환한다

상태: 확정 — 2026-07-13 사용자 승인

추천 순서:

1. 외부 계약과 transaction characterization.
2. iOS Cloud Functions boundary.
3. GRDB boundary.
4. Firebase Functions source modules.
5. Socket source modules.
6. 통합 검증과 하네스 갱신.

이유:

- 네 영역은 같은 파일을 직접 공유하지 않지만 wire/data 계약으로 연결된다.
- 앱 내부 경계를 먼저 좁히면 서버 모듈화 시 소비자 계약을 명확히 비교할 수 있다.
- 운영 배포된 Functions와 Socket을 후반에 다뤄 검증 기반을 먼저 만든다.

대안:

- Functions와 iOS client를 동시에 변경하면 API mapping을 한 번에 정리할 수 있지만 계약 변경과 구조 변경이 결합된다.
- 네 영역을 병렬 구현하면 기간은 줄 수 있지만 공통 계약 결정과 문서 갱신 충돌 위험이 크다.

## D6. giant manager façade는 phase 내부에서만 임시 허용한다

상태: 확정 — 2026-07-13 사용자 승인

추천 결정:

- phase 시작 시 임시 adapter/facade로 compile 가능한 중간 상태를 만들 수 있다.
- 해당 phase 완료 기준에는 모든 승인 대상 소비자의 새 Protocol 전환과 giant manager public surface 제거를 포함한다.
- 영구 compatibility facade를 남기지 않는다.

이유:

- 한 patch 안의 변경량과 compile break를 줄일 수 있다.
- façade를 영구 유지하면 새 코드가 다시 giant dependency를 사용하게 된다.

## D8. callHelloUser 직접 호출을 제거한다

상태: 확정 — 2026-07-13 사용자 승인

확인 결과:

- RoomListsCollectionViewController.viewDidLoad가 CloudFunctionsManager.shared.callHelloUser를 직접 호출한다.
- 현재 functions/src/index.ts export 목록에는 helloUser가 확인되지 않았다.

추천 결정:

- 해당 ViewController 직접 호출과 CloudFunctionsManager의 callHelloUser API를 제거한다.
- 실제 운영 health check가 필요하면 별도 운영 진단 경계로 설계한다.

이유:

- View가 Firebase SDK wrapper를 직접 호출해 현재 아키텍처 원칙을 위반한다.
- 채팅방 목록 화면의 제품 동작과 관련 없는 디버그 호출로 보인다.

확실하지 않음:

- 외부 또는 다른 branch에서 helloUser 함수를 사용하는지는 현재 workspace만으로 확인할 수 없다.
