# 채팅 메시지 검색 — 최종 계약

2026-10-02 기준 구현·자동 검사·DEV QA를 완료했다. 운영 배포와 기존 데이터 backfill은 이번 완료 범위에 포함하지 않는다.

## 사용자 동작과 조회 예산

- 정규화된 본문에 검색어를 포함하는 메시지를 최신순으로 찾는다. 예: ㅋㅋ는 ㅋㅋㅋㅋㅋ와 뭐야 ㅋㅋ 모두에 일치한다. 임의 초성 확장은 없다.
- 검색 시작 시 방의 seq 상한을 고정한다. 이후 도착한 메시지는 새 검색에서 반영한다.
- 최초 검색과 명시적 ‘계속 찾기’는 후보 100개씩 최대 5페이지를 읽는다. 신규 유효 결과를 얻거나 소진하면 즉시 멈춘다. 후보가 있지만 해당 예산 내 일치가 없으면 0개와 계속 찾기를 제공한다.
- 사용자 과거 방향 이동 성공 후 남은 확보 결과가 10개 이하이면 후보 1페이지를 선로딩한다. 자동 선택·개수 발행·유휴 상태에서 예산을 보충하거나 전체를 계속 조회하지 않는다.
- 현재 순번/확보한 유효 결과 수를 1/14처럼 표시한다. 분모는 최종 전체 개수가 아니며 추가 수요에 따라 늘 수 있다. 삭제/차단은 줄일 수 있다. 실제 메시지 표시 성공 뒤 분자를 확정한다.
- 하단 capsule의 중앙 숫자·오른쪽 화살표를 사용한다. 목록 하단을 검색 바 위로 옮겨 마지막 메시지를 가리지 않는다. 이동/선로딩에는 스피너 없이 숫자만 갱신한다.
- 오프라인 또는 네트워크 실패는 로컬 고정 snapshot을 별도 검색 세대로 읽고 결과 수가 제한될 수 있음을 안내한다. 연결 복구 뒤 자동 전체 재조회 없이 새 검색으로 서버 검색을 시작한다. 접근 상실·방 종료를 로컬 검색으로 우회하지 않는다.

## 공통 문자열 v2

원본 본문/표시는 보존한다. Swift ChatMessageSearchIndex와 Socket messageSearchIndex.js가 같은 규칙을 사용한다.

1. NFD → Unicode 15.1.0 CaseFolding C/F(F 우선, S/T 제외) → NFD.
2. 고정 Unicode 자료의 Diacritic=true이며 Mn 또는 Me인 scalar만 제거한 후 NFC 재조합한다. 앱은 한글 경계의 Foundation 동작을 맞추기 위해 재조합 전 NFD를 명시한다.
3. 고정 공백 집합의 연속을 U+0020 하나로 바꾸고 양끝 공백을 제거한다. 집합은 U+0009–000D, U+0020, U+0085, U+00A0, U+1680, U+2000–200A, U+2028–2029, U+202F, U+205F, U+3000이다.

기기 locale에 의존하지 않는다. ZWJ·variation selector·피부색 modifier와 U+200B/U+FEFF는 임의 제거하지 않는다. CAFÉ/cafe, Straße/STRASSE는 같은 정규화 결과이며 ı는 i와 다르다.

searchChars는 공백을 제외한 고유 scalar, searchNgrams2는 공백도 포함한 연속 2 scalar의 고유 token이다. 한 scalar 검색은 searchChars, 그 이상은 처음 2 scalar token으로 후보를 얻는다. 최종 판정은 동일 Swift 함수의 문자소 단위 literal contains다. 이모지 일부 scalar가 후보여도 최종 일치는 아닐 수 있다.

원본·라이선스·SHA-256·생성기는 contracts/chat-search/에 있다. 고정 fixture 25개, folding 1,530개, 제거 기호 707개, 정규화 corpus 19,074행을 검증한다. 원본 자료는 테스트 번들에만 포함하고 앱에는 생성 상수와 라이선스를 포함한다.

## 저장·조회·일관성

- Socket messagePayload/sequenceStore가 서버 본문으로 searchNormalized/searchChars/searchNgrams2/searchIndexVersion=2를 생성한다. 외부 검색 필드를 신뢰하지 않는다. 빈 본문·삭제·서버 안내 등 제외 대상은 projection을 제거한다. 이미 seq가 있는 재전송의 기존 저장/ACK 의미는 유지한다.
- Firestore Messages의 COLLECTION 범위에 searchChars 또는 searchNgrams2 CONTAINS + seq DESC + __name__ DESC 인덱스 2개를 사용한다. 서버 source, seq 상한, 최대 100개, 마지막 원본 후보의 값 cursor로 조회한다.
- FirebaseChatSearchRepository는 cache/pending 응답, 잘못된 순서·상한·버전·projection을 거부한다. 후보 cursor는 세션·방·검색어·상한에 묶여 있으며 최종 불일치·삭제 후보도 원본 cursor상 소비한다.
- GRDB 26번째 migration의 session/hit/blockedAuthor는 일반 메시지 캐시와 분리된다. 결과 본문 전체 대신 ID·seq·작성자만 저장한다. 페이지 hit/cursor/소진을 한 transaction으로 반영하고 accountEpoch/generation/visibilityRevision을 검증한다.
- 캐시 prune은 검색 hit를 지우지 않는다. 주변 본문은 이동 시 anchor+전후 60개로 읽는다. 검색 종료·방 종료·계정 정리·앱 재시작은 임시 검색 자료를 정리한다.
- 차단 집합은 해당 세션 동안 누적한다. 차단 해제 결과는 새 검색에서 복구한다. 삭제 write 시작 시 발행을 무효화하고 완료/실패 확인 전에 공개하지 않는다. 이미 반영한 동일 tombstone은 scrub을 유지하면서 중복 검색 무효화만 생략한다.
- 검색 중 과거 메시지 로딩·표시는 미읽음 frontier를 전진시키지 않는다. 검색을 닫고 최신 메시지를 실제 표시하면 기존 읽음 흐름을 따른다.
- 조립은 ChatContainer/ChatManagerProvider, 실행은 ChatRoomSearchSessionUseCase와 SessionController/Navigator, 화면 상태는 PresentationController/State가 담당한다. 화면이 Firestore/GRDB를 직접 생성하지 않는다.

## 차단 사용자 목록 후속 변경

내 정보 ACTIVITY의 브랜드 요청 내역 아래에 차단한 사용자 메뉴를 배치한다. MyPageCoordinator → MyPageContainer.makeBlockedUsersViewController로 이동한다.

BlockedUsersViewModel은 표시 행의 공개 프로필만 조회한다. 사진·최신 닉네임·우측 차단 해제 버튼, 조회 실패 시 기존 닉네임/기본 사진, 목록 실패 재시도, 중복 해제 억제와 늦은 응답 배제를 제공한다. 프로필 상세 이동은 없다. 서버 API/데이터 계약 변경은 없다.

## 자동 검증 증거

모든 아래 실행의 기준 HEAD는 149ddf1fa527f9457a2928ef60bec86777d9cb94이며 해당 실행 당시 미커밋 변경을 포함한다. 서로 다른 시점의 증거를 현재 전체 코드의 단일 통과로 간주하지 않는다. 원본은 로컬 output/verification/<실행 ID>/summary.json 및 check별 로그/xcresult에 보존하며 공개 저장소에는 올리지 않는다.

| 범위 | 게이트 / 실행 ID | 실제 결과와 한계 |
|---|---|---|
| PR 직전 최종 앱 검색 회귀 | chat-search/search-toolbar.json / 1790937966713-b588aad1-2ebe-4714-9850-39485e62282c | 차단 목록 UI까지 포함한 앱에서 iOS 121개, 필수 72개 및 자체/config 통과. 실패·차단 0, digest 3646d75fc9a526e355de615662b628d3c4799351dae0348c8cb4d268b8c2eed9 |
| 최종 검색 위치·UI·삭제·세션 | chat-search/search-toolbar.json / 1790930163129-107b4bad-4d46-4360-84a0-4062ee75514c | iOS 121개, 필수 72개 및 자체/config 통과. 이후 차단 목록 UI 변경 전 기록 |
| 차단 목록 UI | blocked-users.json / 1790934729719-24b3d112-5732-4743-850e-d2a9cc7c8d1b | 38개, 필수 7개 통과. digest 3c69de1b7f5baa281a7b5a6a6c63a5b1151180b7a24ce3d6478663f9267af59d |
| 수요 기반 누적·규모 | chat-search/phase-6.json / 1790923957287-9c43bcec-4a34-48f2-a73f-38d5c8d1dab1 | iOS 118개+scale 1개(18규모/분포), Socket 122개, Firestore 131개, 자체 13개 통과. 선로딩 10개/UI 보완 전 기록 |
| 기존 차단 함수 DEV 반영 전 | functions.json / 1790933442340-2e0e5ef4-64df-470b-9774-b9700d03f8c7 | lint 오류 0/기존 경고 14, build·299개 통과. 이번 PR에 Functions 제품 코드 변경 없음 |
| DEV 실제 인덱스 | 로컬 dev-live / 1790928021730-bb47961d-8eeb-4409-9836-15b8c919afc7 | 관리자 SDK 검사 1개, 22페이지/2,067후보. 인증 규칙/앱 UI 검사는 별도 |

최초 blocked-users 게이트는 sandbox의 Simulator/캐시 접근 제한으로 차단됐고 같은 설정의 허용 환경 재실행이 통과했다. 미디어 게이트의 migration 필수 ID를 26번째 이름으로 맞췄지만 미디어 전체를 다시 검사했다는 뜻은 아니다.

규모 시험의 100만 고빈도 사례는 최초 후보 100개 약 0.00865초, 유휴 추가 요청 0이었다. 명시적 계속 찾기 9,999회로 전량 reference를 비교한 약 624초는 로컬 fake/GRDB 시험이며 실제 Firestore 지연·과금·운영 SLA가 아니다. 초기 전량 집계 방식의 611초 결과는 현재 구조의 자동 동작이 아니다.

재현 명령은 Node 24에서 node tools/verification-gate/gate.mjs --project . --config verification/<설정>.json이다. iOS는 설정의 Xcode/Simulator/DEV Firebase plist, Firestore는 Java/Firebase emulator가 필요하다. 같은 derivedData를 쓰는 iOS 게이트와 같은 Functions 산출물을 만드는 서버 게이트는 각각 순차 실행한다. 로컬 DEV harness는 정리한 fixture에 의존하므로 일반 회귀 설정으로 배포하지 않는다.

## DEV QA 완료

사용자 iPhone 14와 iPhone 17 Pro Simulator에서 다음을 확인했다.

- 신규 전송 검색, 3,000개 캐시 밖 과거 QA 2 이동, ㅋㅋ 포함 검색·강조.
- 13개 → 위 화살표 두 번 → 14개 후 정지, 양방향 경계·현재 위치, 희귀어 0개 후 계속 찾기.
- 삭제된 주변 메시지의 반복 이동 수정, 검색 바의 마지막 메시지 가림과 이동 로딩 제거.
- 오프라인 시작·중간 연결 단절의 제한 안내/로컬 전환·무한 로딩 없음, 재연결 후 새 검색 복구.
- 본인 결과 삭제, 차단 시 결과 제외·해제 후 새 검색 복구, 차단 목록 새 UI/해제.
- 방 설정 왕복·앱 재실행, 같은 기기 계정 왕복의 이전 검색 상태 제거.
- 과거 검색을 유지한 채 새 메시지 수신 시 읽음 보존, 검색 종료 후 최신 실제 표시 시 읽음 전진. 서버 read frontier 3501 → 3502 대조.
- 검색 중 방 종료 안내·검색 종료·목록 복귀. 전용 QA방 하위 자료/참여 정보와 합성 계정·프로필 정리.

종료방 tombstone/cleanup job은 정상 14일 정책에 따라 2026-10-16 19:25:58 KST 자동 만료 대기다. 미완료 QA가 아니다. 기존 사용자 계정과 승인된 Simulator DEV App Check 등록은 유지했다. 상세 로컬 증거는 output/chat-search-dev-qa/와 무시된 task 기록에 보존한다.

## 배포 경계와 잔여 한계

DEV outpick-test의 검색 인덱스 2개 READY와 Socket outpick-socket-development-search-1002 트래픽 100%를 확인했다. DEV의 구버전 blockUser/미배포 unblockUser도 기존 최신 소스로 두 함수만 반영하고 차단/해제 QA를 완료했다.

운영 배포는 별도다. writer·인덱스 READY·기존 데이터 처리 방침 및 이미 병합된 미디어 7일 만료의 서버 호환성을 확인한 뒤 범위를 확정해야 한다. 인덱스 필드가 없는 기존 메시지는 token query에 나타나지 않아 앱에서 누락을 탐지할 수 없다. 기존 자료 backfill·삭제를 자동 실행하지 않는다.

외부 검색 서비스, 최종 전체 개수, 유휴 전량 집계는 제공하지 않는다. 고빈도 token은 한 페이지의 최종 일치율이 낮을 수 있어 후보 읽기 비용과 반복 계속 찾기 지연을 운영에서 관찰할 필요가 있다. 자동 검증·DEV QA 완료가 운영 배포나 무제한 규모의 성능 보장을 의미하지 않는다.
