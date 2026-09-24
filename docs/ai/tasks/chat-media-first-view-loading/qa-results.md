# ① 실행 검증 기록 — 2026-09-21

사용자가 자동 테스트→실기기 QA→후속 단계 순서를 승인했다. ①의 실기기 검증이 남아 있으면②로 넘어가지 않는다.

## 환경

- Development iPhone14, Xcode destination `00008110-000168693E91401E`, CoreDevice `A7B8FA1C-C7FF-556C-977E-9E8CE2F5BC84`.
- `OutPick-Development`, DerivedData `/private/tmp/outpick-avatar-device`, 병렬 테스트 비활성.
- 기존 앱 데이터/로그인/미디어 캐시 유지. 자동 QA는 새 서버 메시지·fixture·삭제를 수행하지 않는다. 사용자 직접 전송 결과는 수동 QA로 별도 기록한다.

## 자동 테스트

1. 첫 실행 `/private/tmp/outpick-viewport-device-tests.log`: Swift Testing43개/5suite 통과. ChatAttachmentImageServiceTests, ImageLoadCoordinatorTests, ImageViewerPagePolicyTests, ChatMediaUploadUseCaseTests, ChatRoomMessageUseCaseTests.
2. XCTest 합류 테스트에서 기대값 중복 fulfill로 테스트 runner가 중단됐다. 소비자 수2→3→2→1 중2를 두 번 이벤트로 처리한 테스트 신호 오류다. NSLock 기반 probe에서 합류/승격/해제 신호를 각각1회만 전달하도록 수정했다.
3. 수정 후 `/private/tmp/outpick-viewport-device-retest.log`: ChatMediaViewportPolicyTests2개, ChatMediaViewportControllerTests6개, ChatImagePreviewContinuityTests5개, 총13개0실패·TEST SUCCEEDED. 앞선 Swift Testing43개와 중복 없는 합계56개.
4. `/private/tmp/outpick-viewport-surface-regression.log`: 저장 queue/페이지/FIFO Swift Testing19개와 ImageViewerStateTests10개 통과.
5. UIKit 공유 카드 검증에서 기본 SF Symbol의 alignment inset 때문에 의도한56×56 영역이56×53으로 계산됐다. placeholder/error 이미지의 alignment inset을 zero로 고친 뒤 `/private/tmp/outpick-viewport-real-ui-final.log`에서 ChatMediaViewportSurfaceTests2개 통과. GIF/영상/사진 혼합의 thumbnail-only 요청과 실제 표시, 공유 카드 경로 교체·재사용·56pt 좌표를 검증했다.
6. `/private/tmp/outpick-viewport-final-boundaries.log`: transport 취소를 실패로 기록하지 않고 동일 표시 회차에서 재요청하는 경우, 삭제 직후 취소·늦은 결과 차단2개 통과.
7. 첫 검증 묶음의 중복 실행을 제외한 단위/컴포넌트 회귀 합계89개 통과.
8. 화면 수명 후속: `ChatRoomRouteLifecycleStateTests`5개가 `/private/tmp/outpick-viewport-picker-rotation.log`에서 통과. 일시 가림/취소된 pop의 방 유지, 실제 pop/모달 종료/교체의 단일 종료, 종료 후 재활성 차단을 검증했다. 단위/컴포넌트 누적 **94개 통과**. UI 테스트는 별도이며 앱 전체 테스트 실행은 아니다.

## 화면 수명 후속 QA

- 사용자 실제 회전 보고: 가로에서 셀이 커지고 세로로 복귀하면 줄어들지만 복원이 느리다고 확인했다. 가로 크기 변화 자체는 기존 채팅 폭70% 정책이며, 회전 시 표시 갱신 지연은 별도 결함으로 조사했다.
- `ChatMediaViewportSurfaceTests.testMediaCellResizesWithoutReconfigureAndKeepsRenderedImage`에서1장/30장 셀을390→844→390pt로 변경해 재현. 수정 전844pt에서 미디어 폭273pt가 남고(기대590.8pt),30장 높이910pt가 남았다(기대1969.33pt). `/private/tmp/outpick-media-rotation-repro.log`의4개 assertion 실패. 가짜 이미지/로더로 재현돼 다운로드와 무관한 고정 제약 결함임을 확인했다.
- `ChatMessageCell.configureWithImage`의 고정 폭/높이 제약을 contentView 폭70% 및 공유 배열 높이 비율 제약으로 변경했다. 셀 reconfigure 없이 Auto Layout이 부모 폭 변경을 반영하며 기존 표시 이미지/미디어 크기 정책은 유지한다.
- 수정 후 `/private/tmp/outpick-media-rotation-fixed.log`와 `.xcresult`: Surface3개＋Continuity5개, 실기기 사진 선택 취소/회전 복귀 UI1개 재실행 통과·TEST SUCCEEDED. 새 회전 경계1개를 더한 단위/컴포넌트 누적95개, 기존 UI 재실행은 중복이므로 UI 누적3개 유지. 일반 DEV로 복원하고 사용자의 체감 회전 지연 재확인을 요청했다. 프레임 시간 측정 또는 가로 시각 캡처 정상화까지 검증한 결과는 아니다.

- `ChatMediaViewportDevelopmentUITests.testKeyboardSettingsSearchAndCancelledBackRestoreMedia`: 키보드 표시→검색 모드→취소로 키보드 닫기, 설정 패널 표시→dim 탭으로 닫기, 화면 폭20%의 짧은 edge drag 후 같은 방 유지와 썸네일 복귀를 검증했다. 제스처의 UIKit 내부 transition callback 진입은 별도 계측하지 않았으며 취소 상태 계약은 위 단위 테스트로 확인했다.
- `testPhotoPickerCancellationAndRotationRestoreMedia`: 사진 선택 화면 열기→선택 없이 취소→썸네일 복귀, 가로/세로 viewport 좌표와 로딩 완료 상태를 검증했다.
- 첫 회전 검사는 `isHittable`의 activation point 계산 오류로 중단됐다. 당시 UI 구조의 셀은 loaded였고, 표시 검증을 실제 collection viewport와 셀 frame의 교차 영역으로 보정했다. 제품 코드 변경은 없다.
- 최종 `/private/tmp/outpick-viewport-lifecycle-final.log` 및 `.xcresult`: 위 UI2개 통과(30.255초/25.674초). 기존 UI1개와 중복 없는 UI 누적3개. 캡처/구조는 `/private/tmp/outpick-viewport-lifecycle-final-attachments/manifest.json`.
- 키보드/설정 패널과 복귀, 세로 복귀 캡처를 확인했다. 가로 캡처는 화면이 잘려 보이나 접근성 구조는844×390 viewport 및 loaded 셀을 보고한다. 자동 상태 검사 통과만으로 가로 시각 QA까지 통과 처리하지 않고 사용자 육안 대조를 요청했다.
- 종료 후 진단 인자 없는 일반 Development 앱으로 복원했다. 이 후속에서는 앱 코드 변경·신규 메시지 전송·삭제·배포·커밋 없음.

## 실제 Development UI

- `ChatMediaViewportDevelopmentUITests`는 기존 미디어 QA방 `mIWx69f7sfwWdWXkWWqR` 읽기/스크롤/확대/복귀/재진입만 수행한다. 환경 `OUTPICK_MEDIA_VIEWPORT_QA=1` 명시 시에만 실행한다.
- 첫 실행은 테스트 메서드 시작 전 UI automation mode 활성화 timeout으로 실패했다. 앱 기능 실패나 UI QA 통과로 분류하지 않는다. `/private/tmp/outpick-viewport-real-ui.log`, `/private/tmp/outpick-viewport-real-ui.xcresult`.
- 사용자가 자동화 허용·잠금 해제를 완료했다. 재실행에서 참여 방 목록의 셀 식별자 차이를 확인해 테스트 선택자를 기존 방 제목으로 수정했고, 진입 후에는 roomID 식별자를 확인한다.
- `/private/tmp/outpick-viewport-real-ui-final.log`, `/private/tmp/outpick-viewport-real-ui-final.xcresult`: 기존 방 진입→과거 사진 스크롤→사진 확대/닫기→왕복 스크롤→백그라운드 복귀→방 재진입 UI1개 통과(63.779초). 과거 사진·왕복·재진입 캡처를 육안으로 확인했다. 보이는 사진과 공유 카드 썸네일이 채워져 있었다. 전체313장 무결성 검증이나 cold-cache 성능 측정은 아니다.
- 캡처와 UI 구조: `/private/tmp/outpick-viewport-ui-final-attachments/manifest.json`. 임시 산출물의 영구 보존을 보장하지 않는다.
- room/message collection/back 버튼에는 UI 테스트 식별자만 추가했다. 썸네일 loaded/placeholder 값은 DEBUG의 `-ChatMediaViewportQA` 실행에서만 노출해 일반 VoiceOver 설명을 바꾸지 않는다.
- 자동 UI 실행 당시 실제 방에 남은 GIF/영상이 없었다. 이후 사용자의 신규 영상 전송·재생 확인은 아래 수동 QA 결과로 구분한다.

## 남은 확인 및 현재 상태

- 최종 사용자 확인: 수정본의 가로→세로 복귀 체감이 좋아졌으며 다음 단계 진행에 동의했다.① 구현·집중 회귀·사용자 실기기 QA 결과를 수용한 상태로② 상세 설계에 진입한다. 아래 미검증 항목은 검증 한계로 보존하며 사용자 확인 범위를 전체 서버/성능 검증으로 확대하지 않는다. 이전의 체감 확인 대기·② 진입 보류 기록은 해소됐다.

- 사용자 수동 QA 통과: 신규 사진 여러 장·짧은 영상 전송 후 스크롤 복귀/방 재진입 시 정상 표시, 사진 확대, 영상 재생까지 정상임을 명시 확인했다. 자동 테스트 수89개/UI1개와 별도인 실제 사용 흐름 검증이다.
- 사용자 추가 수동 QA 통과: GIF도 새로 전송한 뒤 스크롤 복귀→방 재진입→확대·재생까지 정상임을 확인했다. 앞선 파일 부재로 인한 GIF 미검증 상태를 해소했다. 사진·영상·GIF 모두 실제 전송 후 해당 흐름을 통과했다.
- 키보드/설정/사진 선택 취소/검색 모드 종료와 세로 복귀는 후속 QA로 확인했다. 사용자가 회전 시 크기 복원 지연을 보고해 고정 제약 결함을 재현·수정했고, 수정본 체감 QA 답변 대기다.
- 신규 수신 선표시/저장의 실제 Socket 경로, 검색 결과로 과거 메시지 이동, 전송 확정 순간 깜빡임, 실제 SDK 실패 후 재등장은 아직 별도 실기기 확인되지 않았다. 삭제·취소·실패 재등장 정책의 제어 가능한 자동 테스트와 구분한다.
- 오류 주입·새 서버 전송이 필요한 검증은 기존 데이터를 임의 변경하지 않고 범위를 명시한다.
- ① 전체 QA 완료를 선언하지 않는다.②다운로드 병목·③캐시/원본 분리는 미착수다.
