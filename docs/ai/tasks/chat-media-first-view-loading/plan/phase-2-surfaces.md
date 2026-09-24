# Phase 2 — 개별 이미지 좌표·표시·화면 수명

선행: [Phase 1](phase-1-demand.md)의 상태/서비스 계약. Phase 3까지 연속 통합해야 기존 일괄 요청이 제거된다.

## 목표와 변경 파일

아래 경로는 `OutPick/Features/Chat/` 기준이다.

| 파일 | 메서드/책임 변경 |
| --- | --- |
| `Views/ChatImagePreviewCollectionView.swift` | `updateCollectionView`, 셀 configure를 표시 바인딩 중심으로 전환. 개별 frame/표시 이미지 조회 제공 |
| `Views/Cell/ChatImagePreviewCell.swift` | 자체 다운로드 Task 제거. item/revision에 맞는 idle/loading/success/failure 렌더링과 재사용 reset |
| `Views/Cell/ChatMessageCell.swift` | `configureWithImage`, `makePreviewItems`, 행 배치 계산, reconfigure/reuse 연결 |
| `Views/LookbookShareMessageContentView.swift` | `configure`의 매번 reset/자체 Task를 외부 표시 상태로 전환. 실제 썸네일 frame 제공 |
| `Views/Cell/ChatMessageCell+LookbookShare.swift` | 공유 카드 metadata/이미지 상태 바인딩 분리 |
| `Views/ChatMediaPreviewLayout.swift` 신규 후보 | 묶음의 행 구성·크기·개별 frame 계산을 렌더링과 공유 |
| `Controllers/ChatViewController+MediaViewport.swift` 신규 | 후보 구성, 화면 이벤트 전달, 결과를 현재 바인딩에 적용 |
| `Controllers/ChatViewController.swift` | data source configure, scroll/layout/lifecycle에서 위 extension 호출 |
| `ChatContainer.swift`, `ChatCoordinator.swift` | 화면별 controller factory와 VC 생성자 주입 |

## 연결 순서

1. 기존 행 구성과 attachment index를 공용 layout 계산으로 옮긴다. 단일/다중 묶음의 현재 크기·간격을 유지한다. 새로운 디자인 변경을 섞지 않는다.
2. 실제 셀이 있으면 attachment image frame을 outer collection 좌표로 변환한다. 내부 collection의 `visibleCells`만으로 판정하지 않는다.
3. 주변 셀이 없으면 outer layout attributes의 메시지 frame과 동일 공용 계산을 사용한다. 보낸/받은 메시지의 nickname/profile 여백과 이미지 위치를 반영한다. 불확정 배치는 layout 완료 후 갱신하고 셀을 강제로 생성하지 않는다.
4. 공유 카드는 전체 카드가 아닌 현재56×56 thumbnail 영역을 사용한다. 실제 배치와 예상 배치의 일치 여부를 테스트한다.
5. data source는 metadata와 현재 표시 상태만 바인딩한다. cell/공유 카드가 독자적으로 async 조회하는 경로를 없앤다.
6. controller 결과를 적용할 때 현재 셀 item/revision을 다시 비교한다. 재사용된 셀, 삭제된 메시지, 이전 경로 결과를 버린다.

## 이미지 표시 연속성

- 동일 item의 반복 configure는 성공 이미지와 spinner 상태를 불필요하게 초기화하지 않는다.
- 로컬 미리보기→확정 메시지는 attachment 대응을 유지하고 이미 표시한 UIImage를 넘겨준다. 원격 경로로 바뀌었다는 이유만으로 placeholder를 먼저 표시하지 않는다.
- 다른 메시지로 재사용되면 이전 이미지·콜백·식별을 reset한다. 로컬 유지와 다른 항목 누출을 구별한다.
- `currentImages`의 뷰어 초기 미리보기 제공은 유지한다. 뷰어 원본 요청 및 확대/저장 정책은 변경하지 않는다.
- 실패 상태는 spinner를 종료하고 기존 placeholder를 사용한다. 새 재시도 버튼을 추가하지 않는다.

## 갱신·수명 이벤트

| 이벤트 | 처리 |
| --- | --- |
| 최초 snapshot/layout 완료 | 실제 viewport 계산 후 수요 갱신 |
| scroll/방향 변화 | 같은 run loop의 중복 갱신을 합치되 실제 밖→안 전이를 놓치지 않음 |
| 과거 페이지 prepend/새 메시지/삭제/경로 수정 | 최신 item 집합과 layout을 함께 전달 |
| 회전/키보드/inset 변경 | 유효 표시 영역 재계산 |
| 완전 가림/백그라운드 | 즉시 suspend. 채팅 미디어 소비자만 해제 |
| 복귀 | 현재 위치에서 resume. 실패 표시 회차는 보존 |
| 방 종료/deinit | endSession, 예약/관찰/콜백 정리 |

현재 Coordinator 전환과 UIKit 표시 수명을 조사해 fullScreenCover/push와 부분 sheet를 구별한다. 부분 sheet를 무조건 방 종료로 취급하지 않는다. 기존 업로드 수명과 읽음/라우팅 상태에는 새 미디어 취소를 전파하지 않는다.

## DI·통합 경계

- Container에 `makeChatMediaViewportController()` 후보 factory를 추가한다. 기존 attachmentImageLoader를 주입하며 방마다 pipeline을 새로 만들지 않는다.
- Coordinator의 `makeChatRoomViewController`에서 새 controller를 만들고 VC 생성자로 전달한다. 방별 visibility/실패 정보가 다른 방에 공유되지 않는다.
- 새 viewport는 기존 cell Task를 대체한다. 기존 initial warmup/수신 대기/범위 prefetch는 Phase 3에서 제거한다. 두 단계 사이를 사용자 QA 완료 상태로 배포하지 않는다.
- 새 Swift 파일은 프로젝트의 synchronized group 편입을 확인하고 예외가 없으면 pbxproj를 불필요하게 수정하지 않는다.

## 검증·완료 기준

- 기존 `ChatImagePreviewContinuityTests`를 외부 상태 전달 구조로 갱신하되 동일 첨부 유지/재사용 초기화의 검증 목적은 보존한다.
- UIKit layout harness:1장/여러 행/30장, 보낸·받은 메시지, 공유 카드, 화면 경계 교차, 회전 너비 변경을 검증한다.
- 신규 `ChatMediaViewportIntegrationTests` 후보: 내부 collection의 많은 셀이 구성돼도 외부 화면 밖 항목은 요청하지 않음, 검색 이동/페이지 prepend 후 좌표 일치.
- 화면 가림/복귀 시 실패 회차 유지, 실제 스크롤 재등장 재시도, 다른 화면 소비자 유지 검증.
- 완료: 셀 자체 네트워크 요청0, 실제 개별 frame 기반 수요, 동일 첨부 표시 유지, 화면별 DI/해제 연결. 추가 논의 사항 없음. 기존 전환이 확정 정책으로 분류되지 않는 경우에만 구체적인 화면을 제시한다.
