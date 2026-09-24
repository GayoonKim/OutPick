# Phase 1 — 수요·재시도·취소 계약

상태: 승인된 세부 계획. 로컬 구현 결과와 검증 상태는 [진행](../progress.md)을 참조한다. 아래 타입·메서드 이름은 계획 시 후보이며 제품 동작은 [설계](../design.md)를 따른다.

## 목표와 변경 파일

기준 디렉터리는 `OutPick/Features/Chat/Services/ImageLoading/`이다.

| 파일 | 변경 |
| --- | --- |
| `ChatMediaViewportPolicy.swift` 신규 | 프레임·표시 영역·방향에서 visible/prefetch 수요를 결정하는 순수 로직 |
| `ChatMediaViewportController.swift` 신규 | 방 세션의 표시 회차, 요청 Task, 취소 유예, 결과 전달 소유 |
| `ChatAttachmentImageLoading.swift` | 명시적 요청 우선순위를 받는 조회 계약 추가 |
| `ChatAttachmentImageService.swift` | 우선순위를 기존 ImageCachePipeline까지 전달 |
| `OutPickTests/ChatMediaViewportPolicyTests.swift` 신규 | 영역·정렬·상한 검증 |
| `OutPickTests/ChatMediaViewportControllerTests.swift` 신규 | 실패·취소·동시 소비자·늦은 응답 검증 |
| 기존 첨부 로더 fake/spy | 새 계약 채택. 기존 업로드·뷰어 테스트 의미 보존 |

공용 ImageLoadCoordinator의 합류/마지막 소비자 취소를 사용한다. 캐시 크기, 디스크 형식, 네트워크/I/O 슬롯 수는 변경하지 않는다.

## 입력·출력 계약

- 항목 입력: 안정적인 item ID, 최신 resource 경로, 콘텐츠 revision, 개별 이미지 frame. 사진/GIF 정적 썸네일/영상 썸네일/공유 카드가 동일 계약을 사용한다.
- 정책 입력: collection 좌표계의 유효 viewport, 최근 스크롤 방향, 후보 항목. 미배치 항목은 전체 로딩으로 대체하지 않는다.
- 정책 출력: visible 항목 집합, 우선순위가 정해진 화면 밖 고유 resource 최대24개. 현재 보이는 resource와 중복된 후보는 추가 슬롯을 소비하지 않는다.
- controller 후보 API: `update(snapshot:)`, `suspend()`, `resume(snapshot:)`, `endSession()`. 상태 변경 콜백은 item ID/revision과 표시 상태를 전달하며 MainActor에서 적용한다.
- 서비스: 기존 `loadImage(for:maxBytes:)` 소비자는 유지하고 우선순위 인자를 받는 경로를 추가한다. 일반 조회는 visible, 새 주변 요청은 prefetch로 전달한다. 프로토콜 기본 구현으로 우선순위를 무시하는 우회는 만들지 않는다.

## 수요 계산 순서

1. 실제 viewport와 이미지 frame이 교차하면 visible이다. visible 요청에는24개 상한을 적용하지 않는다.
2. 스크롤 진행 방향1.5화면/반대0.5화면 안의 나머지 항목을 후보로 만든다. 최초 방향은 기존 스크롤 상태에서 얻고 방향이 없을 때는 viewport 거리순으로 처리한다.
3. viewport 거리, 진행 방향, 안정적인 항목 순서로 후보를 정렬하고 resource 중복 제거 후24개를 고른다.
4. 이전 수요와 비교해 추가/승격/유지/해제를 결정한다. 동일 snapshot 반복은 요청 또는 재시도 회차를 만들지 않는다.
5. 범위 이탈 소비자는300ms 유예한다. 재진입하면 예약 해제를 취소한다. 삭제·세션 종료·완전 가림·백그라운드는 즉시 해제한다.

## 상태 분리와 경합 처리

| 상태 | 저장 범위 | 갱신 원칙 |
| --- | --- | --- |
| 실제 표시 여부·표시 회차 | item+revision | 실제 밖→안에서만 새 회차. 단순 셀 재구성은 유지 |
| 실패한 회차·선로딩 실패 | item+revision | 같은 회차 반복 금지. 새 표시/방 세션에서 재시도 가능 |
| 실행 Task·요청 세대·우선순위 | resource+다운로드 계약 | 중복은 공용 pipeline 합류. 세대가 다른 완료는 무시 |
| 해제 예약 | 해당 소비자 | 표시 회차와 독립.300ms 내 재등장도 새 표시 회차 가능 |
| 성공한 표시 이미지 | 현재 바인딩/필요한 표시 범위 | 별도 방 전체 UIImage 캐시를 추가하지 않음 |

- prefetch→visible 승격은 기존 작업을 먼저 끊지 않는다. 기존 pipeline의 소비자 우선순위 합류를 이용해 visible 소비자 등록 후 이전 prefetch 소비자를 정리한다. 공용 계약에 등록 완료를 확인할 수단이 필요한지는 구현 시 확인하고, 다운로드 재시작 없이 승격되는 테스트로 경계를 검증한다.
- 같은 경로를 여러 항목이 표시하면 요청을 합류하되 재시도 허용은 각 항목의 표시 회차로 판단한다. 한 항목의 재등장 재시도가 같은 회차에서 무한 반복되는 계기가 되지 않도록 실패 기록을 요청 결과와 함께 갱신한다.
- 성공 적용 전에 session/item/revision/resource/request generation을 검사한다. 취소에 협조하지 않는 fake가 늦게 성공해도 현재 셀을 덮지 못한다.
- suspend는 실행 소비자만 해제하고 실패 회차를 보존한다. resume 자체는 실패 재시도 사유가 아니다. endSession은 회차와 예약 작업까지 정리한다.
- 실패 metadata는 현재 보유한 메시지 항목에 한정한다. 셀 재사용이나 주변 후보 탈락만으로 지우지 않고 실제 메시지 제거/세션 종료에서 정리한다.
- 로컬→서버 경로 변경은 revision을 갱신하되 같은 첨부의 이미 표시된 사진은 유지한다. 미완료 로컬 요청은 최신 원격 경로의 결과를 덮지 못한다.

## 테스트와 완료 기준

제어 가능한 지연과 수동 완료/실패 loader를 주입한다. 실제300ms sleep에 의존하지 않는다.

- visible30개+prefetch24개, 동일 resource 중복, 방향 반전, 빈 경로/삭제 항목 제외.
- 실패→계속 visible은1회, 실제 밖→안은 추가1회, 선로딩 실패→첫 표시 재시도.
-300ms 이내 재등장 시 실패 회차는 갱신되고 실행 중 요청은 중복되지 않음.
-299ms 복귀는 기존 요청 유지,300ms 해제는 해당 소비자만 취소.
- 다른 뷰어/항목 소비자가 남으면 공용 다운로드 유지, 마지막 소비자 해제 시 취소.
- 취소→재요청 가능, 이전 성공/실패 응답 차단, suspend/resume 시 실패 반복 없음, 새 방 세션에서 재시도.
- 우선순위 승격에 따른 공용 다운로드 시작 횟수1회와 visible 전달 확인.

Phase 1 완료는 UI 연결 전 독립 계약과 fake 채택이 준비된 상태다. 실제 방 동작 변경 완료로 보고하지 않는다. 테스트 실행은 별도 사용자 요청 시 수행한다. 추가 제품 논의 사항은 현재 없다.
