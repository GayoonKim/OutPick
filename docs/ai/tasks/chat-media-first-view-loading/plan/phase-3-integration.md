# Phase 3 — 초기·스크롤·수신 일괄 다운로드 제거

선행: [Phase 2](phase-2-surfaces.md)의 viewport 렌더링 연결. 공용 service/VC/DI를 함께 변경하므로 순차 진행한다.

## 제거·교체할 진입점

경로는 `OutPick/Features/Chat/` 기준이다.

| 파일/심볼 | 작업 | 보존할 계약 |
| --- | --- | --- |
| `Domain/UseCases/ChatInitialLoadUseCase.swift`의 `ChatInitialLoadEvent.warmMedia` | 이벤트와 preview/offline/server의3개 yield 제거 | 메시지 render·participant session·completed 및 저장 순서 |
| 같은 파일 정책 resolver, `Domain/Models/ChatInitialLoadModels.swift` | `mediaPrefetchConcurrency` 제거 | latestTail/unreadAfter/unreadBefore 조회 개수 |
| `Controllers/ChatViewController.swift`의 warmMedia switch, `scheduleInitialMediaWarmup` | 방 전체 미디어 Task 제거 | render 후 viewport 갱신 |
| 수신 append 분기의 미디어 TaskGroup | 전체 사진/영상 cache await 제거 | 메시지 action 판정·추가·저장 경로 접수·중복 방지 |
| collection prefetch, `mediaPrefetchPad`, `startThumbnailPrefetch` 및 영상 prefetch/cleanup | 메시지±60 단위 요청과 전용 task 사전 정리 | 메시지 pagination/아바타 prefetch/뷰어 원본 소비자 |
| `thumbnailImage`, `lookbookShareThumbnailImage` | 본문 썸네일의 원본/MP4/원격 포스터 fallback 제거 | 사용자 확대/재생 경로 |

## 수신 흐름의 목표 순서

1. 기존 sanitize, pending 대응, 메시지 action 판정을 유지한다.
2. 이미 표시된 로컬 미리보기의 item 대응 정보를 확보하고 서버 확정 경로를 바인딩한다.
3. append/update/persistOnly 분기를 기존 의미대로 처리한다. 이미지 다운로드 완료는 어느 분기의 선행 조건도 아니다.
4. 기존 저장 queue로 메시지를 전달한다. 저장 자체를 새로운 비구조화 Task로 옮기거나 FIFO를 변경하지 않는다.
5. snapshot/layout이 갱신되면 viewport가 필요한 thumbnail만 요청한다.

`preserveLocalPreview`가 필요한 기존 경로는 유지하되 전체 첨부 원격 다운로드 대기와 구분한다. 로컬 미리보기 보존 때문에 표시 지연이 남는 경우 먼저 현재 전달 순서를 확인하고, 업로드 확정/삭제 책임을 임의로 이동하지 않는다. 새로운 save queue/outbox 설계는 이번 범위가 아니다.

## 요청 경로를 닫는 기준

- 본문에는 명시적인 thumbnail 경로 또는 해당 전송의 로컬 preview만 사용한다. 썸네일 부재/실패 시 placeholder를 표시한다.
- `ChatImagePreviewItem.previewPaths`의 thumb→original 관행이 본문에 남지 않도록 호출자를 대조한다. viewer용 attachment 원본 정보는 삭제하지 않는다.
- 정적 GIF thumbnail 실패로 `loadImageData`를 호출하지 않는다.
- 영상 thumbnail 실패로 Storage URL을 해석해 MP4를 이미지로 받거나 원격 poster를 생성하지 않는다.
- 공유 카드도 동일 원칙을 따른다. 이미 개선된 일반 룩북 URL 로더는 수정 범위에 넣지 않는다.
- 기존 imageViewer prefetch는 별도의 소비자다. 본문 취소와 섞지 않고 이번 단계의 원본 관리 개선 완료로 보고하지 않는다.

## 미사용 API 정리 절차

일괄 경로 제거 후 `cacheImagesIfNeeded`, `prefetchThumbnails`, `cacheVideoAssetsIfNeeded`, `prefetchVideoAssets`, VideoAsset loader/factory, videoThumbnailGenerator 참조를 `rg`로 다시 확인한다.

실제 다른 소비자가 없어진 API만 protocol/구현/Container/Coordinator/VC 생성자/fake에서 함께 제거한다. 이름이 비슷하다는 이유로 영상 playback resolver, OPVideoDiskCache, 업로드 poster 생성까지 제거하지 않는다. 살아 있는 API는 기존 동작을 유지한다. `ChatVideoAssetServiceTests`도 구현이 실제 제거된 경우에만 불필요한 사례를 정리한다.

## 자동 테스트 설계

- 신규 `ChatInitialLoadUseCaseTests`: preview/offline/server 초기 경로에서 render/완료 이벤트와 기존 조회 크기 유지. 미디어 작업 없이 진행되는지 확인한다.
- 신규 수신 통합 테스트 후보 `ChatMediaIncomingPresentationTests`: 미디어 로더를 영구 대기시킨 상태에서도 append/update 및 저장 spy 접수까지 도달한다. 실제 네트워크 타임아웃을 기다리지 않는다.
- pending→확정, 중복 Socket 이벤트, persistOnly, 이미지 없는 메시지의 기존 action 결과를 비교한다.
- thumbnail 실패 fake에서 원본 image/Data/video URL/poster spy 호출0을 확인한다. 사용자가 viewer를 열었을 때의 정상 원본 호출은 허용한다.
- 초기 진입+scroll+새 수신을 연속 수행해 요청마다 viewport 수요가 존재함을 기록한다. 기존 일괄 loader 우회 호출0을 확인한다.

## 완료·검증 경계

앱의 본문 thumbnail 요청은 viewport로 설명 가능해야 한다. cold 네트워크를 hold해도 메시지 표시/기존 저장 경로 접수가 진행돼야 한다. 초기 조회·페이지·읽음·전송 FIFO·로컬 확정 표시의 기존 계약을 보존한다.

구현 후 관련 참조 검색과 앱/테스트 target 빌드로 삭제 누락을 확인한다. 자동 테스트 실행은 사용자 요청 후 수행한다. 이 단계까지 통합하기 전에는 ① 완료로 표시하지 않는다. 현재 추가 제품 결정 사항은 없다.
