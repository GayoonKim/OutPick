# OutPick Entrypoints

- **채팅 미디어 7일 만료 구현·개발 QA 완료:** [최종 계약·검증·운영 주의사항](architecture/CHAT_MEDIA_RETENTION.md). 서버 확정 시각+168시간, 모든 채팅 미디어의 서명 URL, 시간당 generation 지정 정리, 캐시·화면·Photos 경계를 적용했다. 운영 배포와 실제 1시간 대기·개인정보처리방침 원문 대조는 별도 후속이다.
- **코드 지도:** [CHAT](entrypoints/CHAT.md) → [DATA](entrypoints/DATA.md) → [FIREBASE](entrypoints/FIREBASE.md) → [TESTS](entrypoints/TESTS.md).
- **프로그램적 검증:** [운영 기준](architecture/PROGRAMMATIC_VERIFICATION.md), `verification/{gate,functions,firestore,ios,chat-media-retention}.json`. 원본·설치는 [tools/verification-gate](../../tools/verification-gate/README.md), 환경 준비는 [verification](../../verification/README.md)를 따른다. 공용 설치본의 로컬 실행이며 GitHub CI 연결을 의미하지 않는다.

- **영상 저장 중 닫기 검증:** `OutPickTests/VideoSaveLifetimeTests.swift`가 실제 UIKit present/dismiss와 지연 resolver/saver를 사용해 두 영상 VC의 준비 중 닫기·제출 후 성공/실패·늦은 UI 차단·재생 링크/저장 파일 해제를 확인한다. 사용자 영상/Photos/서버 자료 없이 전용 임시 파일만 사용.

- **영상 저장 결과 UX:** `Infra/Media/MediaSaveToast`를 두 영상 VC가 사용한다. 사진과 같은 하단 위치/여백/1.2초 유지 후 사라지는 토스트에 “저장 완료”/“저장 실패”만 표시. 중앙 결과 alert와 localizedDescription 노출 제거. 저장 중 진행 UI는 기존 유지.

- **저장 이후 영상 캐시 재생:** `DefaultChatVideoPlaybackResolver.cachedPlaybackAsset`는 bin 캐시를 MP4/MOV 확장자 hardlink(불가 시 사본)로 제공하고 래핑 lease가 재생 링크와 원본 pin을 함께 해제한다. `PhotoLibraryOriginalIntegrationTests`에서 합성 MP4/MOV의 AVURLAsset 재생 가능·Photos 저장·링크 정리/원본 보존 검증.

- **영상 Photos 저장 보완:** `PhotoLibraryOriginalResource.videoType`가 최상위 ftyp major brand로 MP4/MOV를 구분하고 `PhotoLibraryPreparedResource`로 확장자 사본을 제출한다. Photos 실제 합성 MP4/MOV 통합은 `PhotoLibraryOriginalIntegrationTests`, 바이트/잘못된 확장자/손상 헤더는 `PhotoLibraryOriginalResourceTests`. 원본 변환 없음.

- **확대 로딩 표시:** `SimpleImageViewerVC.renderLoadStatus`는 이미지가 보이면 로딩 문구 없이 원본으로 교체한다. 이미지가 없는 로딩은 스피너, 실패는 재시도 버튼을 유지한다. 저장 상태 안내는 별도 기존 흐름 유지.

- **현재 원본 우선:** `SimpleImageViewerVC.scheduleProgressiveLoads`는 현재 lease 확보 전 인접 신규 요청을 보류한다. `startOriginalFileLoad`에서 파일 확보 후 현재 decode와 인접 다운로드를 겹친다. 페이지 전환 시 다른 미확보 요청 취소, 확보 파일 유지. `ImageViewerOriginalFileTests`에 보류/페이지 전환/닫기 회귀 추가.

- **원본 첫 로딩 계측:** `ChatOriginalFileStore`의 `original.cache/transfer/fileGate/networkGate/download/downloadBytes`, `SimpleImageViewerVC`의 `original.viewer/viewerRole/acquire/decode`를 기존 `ImageCacheMetrics`로 수집한다. DEBUG `OUTPICK_IMAGE_BASELINE=1`일 때만 출력하며 key는 해시다. viewer 종료는 이미지 할당·로딩 상태 갱신까지이며 실제 화면 프레임 표시 완료는 아니다.

- **Photos3302 실제 재현/보완:** `PhotoLibraryPreparedResource`가 원본 캐시를 올바른 확장자 고유 임시 사본으로 복사하고 Photos callback 후 정리한다. 형식 옵션만으로는 `.bin` 직접 제출 실패를 해결하지 못했다. 실제 Simulator Photos 검증은 `PhotoLibraryOriginalIntegrationTests`, [결과](tasks/chat-media-first-view-loading/original-media-results.md).

- **원본 Photos 포맷 보완:** `Infra/Media/PhotoLibraryOriginalResource.creationOptions`가 `.bin`/확장자 없는 사진도 ImageIO 실제 타입과 올바른 파일명을 전달한다. `DefaultPhotoLibrarySaver.saveOriginal`에서 사용하며 재인코딩하지 않는다. [실기기 저장 실패·재검증](tasks/chat-media-first-view-loading/original-media-results.md).

- **③ 원본 Phase3·4:** `Chat/Services/OriginalMedia/{ChatOriginalFile,ChatOriginalFileStore,ChatOriginalFileDisk,ChatOriginalFileTransport}` → Container 계정별 service → 뷰어/영상/삭제. 계정별 보관·합산512MiB·lease/SDK 취소 수명, 사진 현재±1/GIF 활성만·원본 파일 저장·영상 스트리밍. `AppCoordinator.ensureChatContainer` 계정 교체와 탈퇴 scrub 연결. [구현·검증/QA 잔여](tasks/chat-media-first-view-loading/original-media-results.md).

- **실제 스피너 추적:** ChatImagePreviewCell.spinner span/state/imageAssigned/종료이유↔collection.loadingResolution/Delivery. 전송확인/최신이동/공용overlay 별도계측. 동일hash key+span+seq/time으로연결,전체캐시hit만으로원인확정금지. [진단계획](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **전환/이탈 픽셀 유지:** ChatViewController.viewWillAppear부터viewport활성, applyInitialWindowSnapshotAndWait 완료콜백에서첫위치즉시조정. ChatImagePreviewCell.render(.idle)는픽셀유지,reset/reuse/remote경로교체는제거. chatEntry 전환시점 및cellIdle 계측. [검증/한계](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **로컬 단계 준비/셀 즉시 표시:** ChatInitialLoadUseCase.prepareLocalMedia→VM 세대검사→VC 별도 준비(서버확인 전 렌더없음). VC cachedMemoryImageImmediately→ChatMessageCell.configureWithImage→ChatImagePreviewCollectionView의 최초configure/loading 캐시조회. chatEntry.localMedia/renderWindow 및 chatPreview.cellCache 계측. [검증](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **채팅 디스크 준비 제한 해제:** `ChatMediaViewportController` maxConcurrent:nil / `ChatAttachmentImageService` remote pipeline bypassDirectDiskLimits:true를 일반 실행·Release에 동일 적용. 환경변수 의존 제거, 재실행 유지. processor directDiskValue/readLease에서 decode/IO 게이트 우회. 실제 decode/CPU·메모리 계측은 ImageCacheMetrics/ChatMediaQAMetrics. [계약](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **먼 디스크 준비 동시성:** ChatMediaViewportController→ChatDiskPreparationController(maxConcurrent:nil), 경로별 Task 취소·병합, 메모리 여유 검사·무퇴거 삽입 유지. [최신 근거](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **채팅 진입 초기 준비:** `ChatViewController.setMessageWindow`→snapshot 전 `+MediaViewport.prepareInitialDiskImages`→policy.initialDiskPreparationPaths→viewport.prepareDiskBeforeLayout. 최신/unread 메시지 순서로 먼저 시작, 초기 위치 안정화 후 실제 프레임 순서로 전환. willAppear/willDisappear와 활성 guard로 수명 관리. [검증](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **방 전체 디스크 준비:** `ChatMediaViewportPolicy.diskPreparationPaths`→`ChatMediaViewportController` 내부 `ChatDiskPreparationController`→Container 주입 service→pipeline.prepareDiskImage. 현재 snapshot 전체 거리순으로 동시 제출, cache-only/최저 우선순위, LRU 여유·압박 검사와 setIfRoom 무퇴거 삽입. 기존 주변 다운로드는 유지. [진행/QA](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **빠른스크롤 예측선로딩:** ChatMediaViewportPolicy의속도기반최대4화면+UIKit예상도착/0.35초구간,near/destination교대선택24상한. ChatViewController delegate→+MediaViewport의속도/target수명관리→controller.cancelOutsideImmediately. 빠른범위밖300ms유예제거/캐시유지. 자동30통과,기기체감QA전. [상세](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **채팅 disk 직접준비:** `ImageCachePipeline`/`ImagePipelineProcessor.usesDirectDiskFileDecoding` opt-in→`ImageCacheDiskStore.readLease`→`ImageCacheReadLease` hardlink→ImageIO fileDecoder. 채팅 remote는 Data예산/파일내용복사 및 decode/IO 게이트 대기 없이 처리. 교체/삭제중 파일 보호·세대 차단·실패 legacy 복구 유지. [검증/후속선로딩](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **채팅 표시 1GiB QA:** `ChatAttachmentImageService.makePipelines` remote 메모리1GiB/LRU, 디스크1GiB/trim900MiB. `ImageCacheMemoryStore` opt-in→`ImageLRUMemoryStore` 최근사용정리·stride비용·압박warning/critical/normal. 다른기능NSCache 기본유지, 파일규격동일. [계획·검증](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **③ Phase1·2 완료:** 자동89개 및 기기근접재방문QA 통과, memoryImmediate140회/저장282success/관측gate종료0. 일반DEV복원. 첫진입대기·용량퇴거 및 원본분리(Phase3~5)는 잔여. [결과·검증한계](tasks/chat-media-first-view-loading/cache-reuse-results.md).

- **③ Phase2 저장 재사용:** `ImageCachePersistence.wait(forKey:revision:)`→coordinator.waitForPendingWrite→pipeline.cachedValue의 같은키 pending 합류. `storeImageData`는 beginPreparedStore 세대확보 후 storePrepared로 독립 persistence에 payload/lease 인계. 준비 중 삭제는 거절. [검증·기준선](tasks/chat-media-first-view-loading/cache-reuse-results.md).

- **③ Phase2 첫 개선:** `ChatAttachmentImageLoading.cachedMemoryImageImmediately`→service remote 메모리 조회→`ChatContainer.makeChatMediaViewportController` 주입. viewport는 memory hit일 때 loading 없이 image 전달. 로컬 파일 읽기는 제외. 기준선 반복28건 중27건 용량퇴거 연결, pending 저장합류는 다음. [결과](tasks/chat-media-first-view-loading/cache-reuse-results.md).

- **2026-09-23 최신:③ Phase1 계측 착수.** `ImageCacheMetrics.linkCacheKey`가 resource/storage/file hash를 연결하고 memory.lookup/store·disk.lookup/eviction·diskWrite.total·persistence.pending·chatPreview.presentation/load/preserveLocal을 기록한다. 정책/재사용 행동은 아직 유지, Phase2 전 기준선 QA. [실행 기록](tasks/chat-media-first-view-loading/cache-reuse-results.md).

- 다운로드② SDK 취소 경합: Firebase12.3.0→12.17.0 공식 상태 보호 적용(`project.pbxproj`, `Package.resolved`), SDK 직접 재현 포함87개 회귀 통과. 구버전 비교와 실기기 최종QA 진행,③ 미착수. [근거·의존성 영향](tasks/chat-media-first-view-loading/download-bottleneck-results.md).

- 2026-09-22 다운로드② QA **잔여 발견**: 저장 실패 suite7개 통과·실제 병렬6 유지, 대량 반복 후 신규 임시 파일3개 잔존. Firebase cancel callback의 완전 종료 가정을 재검토해야 한다. [최신 판정](tasks/chat-media-first-view-loading/download-bottleneck-results.md),③ 구현 보류.

- 2026-09-22 다운로드② 저장 실패 자동 검증7개 통과. `FirebaseImageDownload.file` opt-in SDK 취소/callback 계측 추가, 실기기 QA 진행 중. [검증 진입점](entrypoints/TESTS.md), [진행·한계](tasks/chat-media-first-view-loading/download-bottleneck-results.md).

- 2026-09-22 채팅 미디어: [③ 캐시 재사용 구현 계획](tasks/chat-media-first-view-loading/cache-reuse-implementation-plan.md) 작성·구현 전. 닫기 저장 취소·영상 즉시 재생, 수치/표시 파일 정책은 QA 결정. 현재 [② 병렬 다운로드 재점검](tasks/chat-media-first-view-loading/download-bottleneck-plan.md)으로 복귀했다.

- 채팅 미디어③ [표시 캐시/원본 설계 초안](tasks/chat-media-first-view-loading/display-original-cache-design.md): 앱 캐시 분리 우선 사용자 확정. `ChatAttachmentImageService`의 원문 저장·1024px decode, `ChatViewController`의 확대 원본 선로딩, `SimpleImageViewerVC.saveTapped`의 표시 이미지 우선 저장이 주요 경계. 구현 전 설계 논의 중이다.

- 다운로드② 실기기 결과: 파일 전송 최대6개 동시 확인, 자동75개 통과. 기존 캐시 QA에서 반복 완료53건/캐시 정리5회 관찰; 표시 속도 전체 해결 아님. 원인별 한계·일반 DEV 복원·③ 잔여는 [실행 기록](tasks/chat-media-first-view-loading/download-bottleneck-results.md).

- 다운로드② 구현: `ImagePipelineProcessor.downloadFile`은 network/files로 SDK 파일 전송을 제한하고 앱 io(write)를 전송 동안 점유하지 않는다. 기본 수치 유지. `ImageFileDownloadSchedulingTests`6개 및 관련75개 회귀 통과, 실제 기기 계측 QA 진행. [결과·한계](tasks/chat-media-first-view-loading/download-bottleneck-results.md).

- 채팅 미디어② [세부 구현 계획](tasks/chat-media-first-view-loading/download-bottleneck-plan.md) 작성 완료·구현 전: ImagePipelineProcessor의 파일 전송을 앱 io(write)에서 분리, 기존 network/files 상한 및 취소/저장 소유권 유지.4개 Phase·자동 경계/실기기 비교·공용 경로 영향 명시. 최신 상태는 [진행](tasks/chat-media-first-view-loading/progress.md).

- 채팅 회전 지연 수정: `ChatMessageCell.configureWithImage`는 미디어 폭을 contentView의70%, 높이를 공유 배열 비율 제약으로 연결해 reconfigure 전의 고정 크기를 없앤다. `ChatMediaViewportSurfaceTests`의1장/30장 폭 왕복·이미지 보존 회귀 및 실기기 회전 재검증 통과. 누적95개/UI3개, 체감 QA 대기. [최신 기록](tasks/chat-media-first-view-loading/qa-results.md).

- 채팅 미디어 화면 수명 QA: 단위/컴포넌트 누적94개·UI3개 통과. 키보드/검색 종료/설정/사진 선택 취소/세로 복귀 확인, 가로 캡처와 실제 화면 대조 대기. 테스트 확장은 `ChatMediaViewportDevelopmentUITests`; [실행 기록](tasks/chat-media-first-view-loading/qa-results.md)이 아래 이전 상태보다 우선한다.

- 채팅 미디어① 검증: iPhone14 단위/컴포넌트89개＋기존 미디어 방 UI1개 통과. 공유 카드56pt 좌표 보정. 신규 사진·영상·GIF 전송/스크롤 복귀/방 재진입/확대·재생 사용자 QA 통과. 키보드/설정 등 잔여 검증이 있으며② 미착수. [실행 근거와 잔여](tasks/chat-media-first-view-loading/qa-results.md), [테스트 진입점](entrypoints/TESTS.md).

- 채팅 과거 미디어 첫 표시 ① 로컬 구현: `ChatMediaViewportPolicy`/`ChatMediaViewportController`→`ChatViewController+MediaViewport`→사진·공유 카드 표시 연결. 초기/수신/최신 이동/스크롤 전체 warmup을 제거했다. 실제 frame·재등장 재시도·취소·DI/QA 진입점은 [채팅](entrypoints/CHAT.md), 구현/검증 한계는 [진행](tasks/chat-media-first-view-loading/progress.md).②다운로드 병목·③캐시/원본 관리는 후속이다.

- 아바타 PR 리뷰 보완: `AvatarViewportObserver`는 items 변경 콜백의 최신 경로를 선로딩에 직접 전달한다. `AvatarNestedViewportTests.testSwiftUIViewportPrefetchesChangedPathWithoutScrolling`이 스크롤 없는 nil→사진→다른 사진 변경을 검증한다. [리뷰 기록](tasks/avatar-image-loading/review.md).

- 아바타 Phase0~5 완료(2026-09-21, VoiceOver사용자제외): 구현·QA·임시자료정리·일반DEV복구완료. 최종 iPhone14 16개검증의 범위/기존112개회귀와중복 여부는 [Phase5](tasks/avatar-image-loading/progress/phase-5.md), 다음작업 진입점은 [현재 상태](tasks/avatar-image-loading/progress.md) 참조.

- 잔여 QA2~4: `AvatarRouteContractTests`의 원본only 상세/확대2회, `AvatarNestedViewportTests`의 중첩 참여자50 UIKit 요청계측, `AvatarImageServiceTests`의 연속 아바타뷰 메모리승격/디스크재사용. 실기기 실행 여부와 결과는 [Phase5](tasks/avatar-image-loading/progress/phase-5.md)에서 구분한다. 서버 fixture 추가와 제품 코드 변경은 없다.

- 아바타 잔여 QA1 자동 경계: `OutPickTests/AvatarRouteContractTests.swift`는 실제 UserProfileDetailCompositionRoot→화면→주입 로더 요청의 정책 유지와 기존 scope의 참여 상태 변경 후 read/load/prefetch 정책 재평가를 검증한다. 상위 AppCoordinator/ChatCoordinator 조립은 코드 대조로 구분하며 앱 구조 변경은 없다. 실행 결과는 [Phase5](tasks/avatar-image-loading/progress/phase-5.md) 참조.

- 2026-09-21 아바타 후속 QA: 위임 후보·미참여 방·실패 후 스크롤/새 메시지 재시도·다른 계정 왕복 확인. 임시 오류/메시지 주입 및 정리 코드는 제거했고 서버183문서/20이미지·기기QA174행/3이미지를 정리했다. 검증 범위와 미검증 항목은 [Phase5](tasks/avatar-image-loading/progress/phase-5.md), [체크리스트](tasks/avatar-image-loading/qa-checklist.md) 참조.


- 프로필 확대 원본 30초 제한: `AvatarImageService.loadRemoteAvatar`에서 원본 소비자만 제한하고 기존 공용 pipeline 취소에 연결한다. 썸네일/로컬 파일·SDK 전역 설정은 유지. 테스트와 실제 오프라인 QA는 [프로필 진입점](entrypoints/PROFILE.md), [Phase5](tasks/avatar-image-loading/progress/phase-5.md) 참조.

- 아바타 즉시 메모리 표시: `AvatarImageManaging.cachedAvatarImmediately` → `AvatarImageService` → `AvatarImageSessionController.immediateReads` → 기존 `ImageCachePipeline` NSCache. 추가 이미지 캐시 없이 첫 렌더를 보완하며 전환/경로 무효화는 동기 read gate로 차단. 검증은 `AvatarImageSessionTests`/`AvatarImageServiceTests`/`AvatarImagePresentationStateTests`, 진행은 아바타 Phase5.

- 방 설정 스크롤: `ChatRoomSettingViewController`의 초기 상단 위치 유지와 `actionsSection/actionsItem`(참여자 뒤 나가기·차단 사용자·알림). [채팅 진입점](entrypoints/CHAT.md), 실제 QA는 아바타 Phase5 기록 참조.

- 답글 창 확장: `PostCommentsSheetView.repliesSheet`의 detent `[.fraction(0.62), .large]`. 상단 드래그로 최대 높이 확장, iOS16+ 적용. [룩북 진입점](entrypoints/LOOKBOOK.md).

- 2026-09-20 댓글 재진입 상단 사진 수정: `CommentSafetyAvatarView.onChange(of: identity)`에서 콜백의 최신 identity를 `configure(_:)`에 직접 전달한다. 실기기 사용자 정상 및 상단4행 loaded 확인, 원인 조사용 로그 제거. [검증](tasks/avatar-image-loading/progress/phase-5.md).

- 아바타 Phase5 통합 QA: [진행 기록](tasks/avatar-image-loading/progress/phase-5.md). `AvatarImagePrefetchController.loadingPaths`는 진행 상태를 읽는 내부 진단 값이며 `AvatarViewportPrefetchTests`가 고정 yield 횟수 대신 실제 실패 처리를 기다리는 데 사용한다. 기기 서명 복구와 실기기 QA 상태는 진행 기록에서 확인한다.

- 아바타 Phase4: `AvatarViewportPrefetchPolicy`/`AvatarCollectionViewport`/`AvatarImagePrefetchController`와 SwiftUI `AvatarViewportObserver`가 방향1.5/0.5·고유24·이탈300ms 수요를 관리한다. UIKit 메시지/방 목록/중첩 참여자/위임 후보, SwiftUI 댓글/답글/대표 댓글의 일괄 선로딩을 교체했다. 새 visible 메시지·재등장·수동 갱신의 재시도 및 session unavailable 경로 차단. [구현·검증·QA 잔여](tasks/avatar-image-loading/progress/phase-4.md).

- 아바타 Phase3 표시 수명 구현: `AvatarImagePresentationState`/`AvatarImageView` → UIKit 프로필/채팅 셀·SwiftUI CommentSafetyAvatarView. 같은 사진 유지, 재사용/화면 이탈 취소, 늦은 성공·실패 차단, SimpleImageViewerVC의 프로필 transient 종료 정리. [구현·검증](tasks/avatar-image-loading/progress/phase-3.md). Phase4 viewport/추가 표시 계기와 Phase5 실기기 QA는 남음.

- 아바타 Phase2 완료: `AvatarImageRequest`/`ScopedAvatarImageManager`/`AvatarImageSessionController` → 단일 `AvatarImageService` → App/Chat DI와 `AvatarObservingPublicProfileRepository`·`UpdatePublicProfileUseCase`. 댓글 memory-only·참여방/내 프로필 disk100/75MiB·원본 transient·세션/사진 무효화 연결. JPEG0.8 실제 사진 비교, 최종48개/10suite 통과. [구현·검증·남은 범위](tasks/avatar-image-loading/progress/phase-2.md). Phase3 화면 수명·Phase4 viewport/retry·Phase5 실기기 QA는 남아 있다.

- 아바타 Phase1 공용 기반: `Infra/Cache/ImageCache/ImageCachePipeline.swift`의 `.transient`/`promotionEncoding` → `ImageLoadCoordinator.swift`의 비저장 완료·메모리 hit 승격/세대 → `ImageCachePromotionEncoding.swift`의 준비/출력 예산. `OutPickTests/ImageCacheStorePolicyTests.swift`. [검증](tasks/avatar-image-loading/progress/phase-1.md).

- 아바타 전체 작업: [설계](tasks/avatar-image-loading/design.md) → [Phase0~5 계획](tasks/avatar-image-loading/plan.md) → [현재 상태](tasks/avatar-image-loading/progress.md). 서비스 기반과 화면 적용의 완료 범위를 구분한다. 상세 출발점은 [PROFILE](entrypoints/PROFILE.md).

- 이미지 로딩 최종 공개 검증 요약: [구조·설정·자동/실기기 QA·성능 한계](qa-image-loading-concurrency-2026-09-16.md). 머지 전 리뷰 보완은 `LookbookHTTPImageCache.cachedImage`의 디스크 크기 확인→바이트 예약→본문 읽기 순서와 `LookbookHTTPImageCacheTests.diskBodyWaitsForDecodeBudgetBeforeReadingAndHandlesEviction`에서 확인한다.

- 이미지 Phase 0~5 완료(2026-09-16): 자동90개/UI1개·룩북 기능 실기기 QA·Phase0 CPU/메모리/프레임 비교 후 사용자가 현 D07 값 채택과 Phase5 완료를 승인했다. 설정은 `ImagePipelineLimits.swift`, 화면 수요는 `LookbookImagePrefetchController.swift`; 최종 수치·표본 한계·로그는 [Phase 5](tasks/image-loading-stage-concurrency/phase-5-validation.md). 실패 fixture는 `LookbookUITestFixtureRepositoryProvider.swift`의 `--uitest-lookbook-image-fail-once`, 테스트는 `LookbookSmokeUITests.testImageRetryDoesNotOpenCardDetail`. 채팅 과거 사진 첫 표시 개선은 별도 작업이다. 아래 phase별 미착수/진행 문구는 당시 이력이다.

- 이미지 Phase 4: `Views/Shared/LookbookViewportObserver.swift`(frame·방향·미배치 행 추정) → 홈/브랜드 상세/시즌 상세 View → 각 ViewModel의 `updateViewport` → `Services/ImageLoading/LookbookImagePrefetchController.swift`(희망 집합·300ms 해제) → 공용 캐시. 목록 데이터 선표시·앞선 page 트리거·카드 실패 재시도 연결. [시작값·실기기 QA 잔여](tasks/image-loading-stage-concurrency/phase-4-lookbook-screens.md).


- 이미지 Phase 3: `LookbookAssetImageRequest`가 공용 카드 표시와 브랜드 상세/시즌 상세 프리패치의 Storage→외부 URL 후보를 통일. `BrandImageCacheProtocol` → `LookbookHTTPImageCache`가 URL·Referer·maxBytes별 메모리/디스크 캐시, HTTP TTL/304/200, shared 네트워크·준비·I/O 예산, stale→fresh UI 교체를 소유. [정책·구현 범위](tasks/image-loading-stage-concurrency/phase-3-http-cache.md), [테스트](entrypoints/TESTS.md). 관리자 검토 preview/확대 원본은 별도 경로 유지, Phase4 목록·viewport 미구현.


- 이미지 QA 최종: ImagePipelineLimits decodeBytes/writeBytes 각16MiB 유지, network6/decode2/I/O2(write1). 성공body 계측 추가. A/B/C 체감 차이 미확인, network6/예약회수는 확인. [실측·한계](tasks/image-loading-stage-concurrency/phase-2-qa.md).

- 이미지 QA 비교 진행: ImagePipelineLimits.writeBytes8→16MiB 후보, 나머지 한도 유지. 실제 cold 로그의 저장 예약 대기 최대2.3초를 근거로 비교 중이며 최적값 확정 아님. [비교 결과](tasks/image-loading-stage-concurrency/phase-2-qa.md).

- 이미지 cold QA 계측: ImagePipelineProcessor의 network.body.received는 성공한 이미지 body 바이트만 기록(전체 회선 사용량 아님). [QA 진행·Instruments 연결 문제](tasks/image-loading-stage-concurrency/phase-2-qa.md). 사용자 DEV 삭제/재설치 승인, USB 연결 대기.

- 이미지 Phase2 실기기 QA: 테스트 이미지 배율 보정 후26개 함수 전체 통과. [측정 기록·상태](tasks/image-loading-stage-concurrency/phase-2-qa.md). 아모멘토 화면 계측과 초기값 튜닝은 자동 fake 회귀와 별개로 진행.

- 2026-09-16 이미지 Phase 2: Infra/Cache/ImageCache의 ImagePipelineLimits(QA 초기값) → ImagePipelineResources/ImageStageGate(공유 단계 gate) → ImagePipelineProcessor(예약·Data/파일·준비) → ImageCachePersistence/ImageCacheDiskStore(비동기 저장·세대). DB/Firebase/DatabaseManager/Repositories/FirebaseImageDownload.swift는 SDK 취소 adapter. [실제 범위·제한·QA](tasks/image-loading-stage-concurrency/phase-2-implementation.md). 기존 서비스 fileFetcher 조립 변경, Container/화면 이동/서버 계약 유지. Phase3 외부 URL 폴백 통합·Phase4 viewport 미구현.

- 2026-09-16 이미지 로딩 Phase 1 구현: `Infra/Cache/ImageCache/ImageRequest.swift` → `ImageLoadCoordinator.swift`(원자 요청 통합·소비자별 취소·세대) → `ImageCachePipeline.swift`(캐시/기존 permit·disk 세대 검사), `ImagePipelineResources.shared`(기능별 캐시/공용 합산6). 룩북 카드 취소 후 fallback 차단. [실제 계약·제한](tasks/image-loading-stage-concurrency/phase-1-implementation.md). 최종 앱/테스트 대상 compile 통과, 새14개 시나리오 실행·실기기 QA는 보류. Phase 0 비교 소스 별도 보존. 큐 우선순위·단계 예산은 Phase 2.

- 2026-09-16 이미지 로딩 Phase 0 계측 구현: `Infra/Cache/ImageCache/ImageCacheMetrics.swift` → 기존 pipeline/cache/permit/fetch/decoder와 룩북 ViewModel/카드. Debug opt-in `OUTPICK_IMAGE_BASELINE=1` 또는 `-ImageLoadingBaseline`, 기본 꺼짐. 정책6/프리패치 유지·앱 Simulator build 통과·실기기 미측정. [사용·한계](tasks/image-loading-stage-concurrency/baseline-instrumentation.md), [진행](tasks/image-loading-stage-concurrency/progress.md). 테스트 실행 보류, 다음 측정 대상 OutPick-DEV 아모멘토.

- 2026-09-16 이미지 로딩 단계 분리 **계획 작성/미구현**: [설계](tasks/image-loading-stage-concurrency/design.md) → [Phase 0~5 계획](tasks/image-loading-stage-concurrency/implementation-plan.md) → [검증 계획](tasks/image-loading-stage-concurrency/qa-checklist.md). 공용 `ImageCachePipeline`·`BrandImageCache`·룩북 세 화면 적용과 다른 소비자 회귀 범위다. 현 코드의 제한/우회와 계획을 구분하며 구체 미정은 설계 D01~D08 참조. 코드·테스트·성능 측정은 미수행.

- 2026-09-14 동시성 적용·Development QA 완료: 원본4/준비전체/PUT4/FIFO1, 계약3 서버조회·서명·취소정리전체. iPhone41개/Socket124개와3장/70장/실패재전송 확인, 계측해제. [진행·증거](tasks/chat-media-concurrency-qa-rollout/progress.md). 커밋/PR 및 Production은 미수행.

- 2026-09-14 최종 동시성 로컬 구현: `ChatMediaPipelineLimits` 기본 원본4/준비전체/PUT4, QA 미지정 값은 기본값 보존. 계약3 `directMediaUploadService`의 조회·서명·취소 정리는 요청 대상 전체 실행, `createProductionDependencies`에서 계약3 폭 주입 제거. [진행·검증](tasks/chat-media-concurrency-qa-rollout/progress.md), [계획](tasks/chat-media-concurrency-qa-rollout/plan.md). Development 서버 미배포, 결합 QA 대기.

- 2026-09-14 원본 확보 비교 완료:4/all/4/all 각각1.630/0.411/0.505/0.437초,280장 앱 성공·사용자 조작 확인. QA 해제/기본4 복원, 최종 정책 논의 대기. [측정과 한계](tasks/chat-media-preview-continuity/acquisition-diagnosis.md).

- 2026-09-14 원본 확보 동시성 비교 준비: DEBUG Development QA의 `OUTPICK_MEDIA_QA_ACQUISITION=4|all`로 원본 확보만 비교한다. 기본4 유지. `ChatMediaSelectionUseCaseTests`의 확보 완료/실패 정리를 두 폭으로 검증하며, 실제 비교 상태는 [원본 확보 진단](tasks/chat-media-preview-continuity/acquisition-diagnosis.md) 참조.

- 2026-09-12 준비·업로드·metadata 실기기 개별 비교 완료: [측정 결과](qa-media-upload-concurrency-2026-09-12.md). 8회560장 정상 저장. 업로드4 유지, 준비all 및metadata60은 속도 개선 후보. 결합 조합·다중 사용자 부하는 미검증. 실험 후 기본4 복원.

- 2026-09-12 동시성 비교 QA: `ChatMediaPipelineLimits.forCurrentProcess`가 DEBUG Development에서만 `OUTPICK_MEDIA_QA=1`, `OUTPICK_MEDIA_QA_UPLOADS=4|all`, `OUTPICK_MEDIA_QA_PREPARATION=4|all`을 적용한다. `ChatMediaQAMetrics`가 메모리200ms 표본/1초 로그를 기록한다. 공용 FIFO1은 유지하며 서버 metadata 설정은 별도로 확인한다. 상세 CHAT 진입점 참조.

- 채팅 캐시 동기화 완료(2026-09-11): 합의된 QA 및 PR 리뷰 보완 후 핵심 48개 회귀 통과. Development iOS 빌드·연결 iPhone 14 설치/실행 확인. 앱 코드·테스트·하네스 커밋으로 정리하며 서버 배포 대상 변경은 없다. VoiceOver 제외·실기기 장시간 보류 범위 유지.

- 참여 완료 UI QA: `ChatViewController.joinRoomBtnTapped` 성공 경로는 이전 참여 버튼을 숨긴다. 캐시 동기화 progress의 2026-09-11 19:18 실제 재참여·재진입 검증 및 QA fixture 관리자 상태 보완 기록 참조.

- 오픈채팅 목록 삭제 원문 재노출 방지: `RoomListUseCase.cachedTopRooms()`는 비동기 로컬 삭제 마커 적용 후 미리보기를 반환한다. `ChatContainer`의 GRDB sanitizer 주입 → `RoomListsViewModel`의 복귀 시 이전 본문 제거·조회 세대 검사 → `RoomListsViewModelDeletionTests`를 참조한다. 서버 조회 추가 없음.

- 삭제 조회 도중 Socket revision 상승 경합 검증은 [TESTS](entrypoints/TESTS.md)의 `GRDBChatDeletionSyncStoreTests`를 참조한다. 실제 계정 간 QA와 제외·보류 범위는 캐시 동기화 task progress의 최신 상태를 따른다.

- 채팅 캐시 동기화 구현: 실제 seq 검사·혼합 범위 복구·공용 저장5회·삭제 transaction 보호·페이지 세대. [코드](entrypoints/CHAT.md), [진행·검증](tasks/chat-message-cache-sync/progress.md).

- 공용 이미지 확대 화면: `Infra/Media/ImageViewer/ImageViewerChromeView.swift`(왼쪽 상단 닫기·하단 저장/번호/신고) → `SimpleImageViewerVC.swift`(제스처·페이지별 요청 식별/실패 재시도·저장 중복 방지). 채팅/갤러리/룩북/프로필 공용, 생성자·loader·저장 주입 계약 유지. [구현 계획·검증](tasks/shared-image-viewer-editorial/implementation-plan.md).

- 사진300MB·실패 사진 복구: `ChatPhotoSizePolicy` → `ChatImageTransportSourceNormalizer`/`ChatMediaSelectionChunker` → `ChatMediaSelectionUseCase.failedImages`/`preserveFailedImages` → `ChatViewController+MediaSelection` 기존 선택 원장 복원·재시도·삭제. 서버 `Socket/src/media/directMediaUploadService.js`. [계약·구현·검증](tasks/chat-media-preview-continuity/photo-size-failure-recovery.md).

- 원본 확보 지연 계측(2026-09-11): `ChatMediaSelectionUseCase`의 사진별 slot 대기 → `ChatMediaSourceAcquisition`의 provider 대기/파일 복사 → VC의 취소 사유. [분석 방법·재현 상태](tasks/chat-media-preview-continuity/acquisition-diagnosis.md).

- 미디어 버블 이미지 깜빡임 개선: `ChatMessageCell` → `ChatImagePreviewItem.stableID` → `ChatImagePreviewCollectionView`의 ID snapshot/최신 payload 분리 → `ChatImagePreviewCell`의 동일 첨부 이미지·로딩 유지. [구현·검증 기록](tasks/chat-media-preview-continuity/implementation.md), 상세 CHAT/TESTS 진입점 참조. 직접 업로드는 Development 배포/3장·70장 전송 확인 완료, Production 미배포다.

- 실제 직접 업로드 QA의 동시 초기화 회귀: `ChatMediaForegroundUploadService.swift`에서 URLSession 최초 접근/작업 생성을 stateQueue로 직렬화한다. `ChatMediaForegroundUploaderTests.swift`가 URLProtocol fake로 동시 첫 업로드 30개의 완료를 검증한다.

- 최신 직접 업로드 구현(미배포): `ChatImageTransportSourceNormalizer`/`ChatGIFMetadataStripper` → 파일 기반 `ProcessedImage`/`PreparedVideo` → `ChatMediaUploadUseCase` 첨부당 display/thumbnail → `RealtimeSocketService` 계약3 → `Socket/src/media/directMediaUploadService.js` 최종 경로 signed PUT·metadata 확인·메시지 원자 확정. `functions/src/chat/media/directUploadCleanup.ts` 취소/만료 정리. 상세 구현·QA는 CHAT와 `tasks/chat-media-bounded-parallel-upload/direct-upload-detailed-design.md` 참조.

- 최신 순차 묶음 전송: CHAT의 「최신: 묶음 순차 전송」. `ChatViewController+MediaSelection` 최종버블 선표시 → Container FIFO1 → UploadUseCase 묶음내 PUT4 → VC 메시지 UI 반영/실패후 반환. `ChatMediaBatchProgress` 합산진행률, PendingStore/Cell/ProgressView 고정원형+장수. [승인 설계](tasks/chat-media-bounded-parallel-upload/design.md).

- 원본 확보 중복콜백 크래시: `ChatMediaSourceAcquisition.swift` 최초callback gate, `OutPickTests/ChatMediaSourceAcquisitionTests.swift` 오류→취소/중복성공/동시콜백 회귀. CHAT 진입점과 서버pipeline QA 보고서 최신항목 참조.

- 사진 선택 후 버블 없음 진단: CHAT의 원본 확보 DEBUG 항목. `ChatViewController+MediaSelection.swift` → `ChatMediaSelectionUseCase.swift` → `ChatMediaSourceAcquisition.swift`에서 대기열/원장/파일 provider/복사 단계와 오류 domain·code만 기록한다.

- 정상 이미지 처리 후30초재시도 제거: FIREBASE의 dispatcher 완료 barrier 항목. `functions/src/chat/media/{functions,orchestrationService,readyService}.ts`가 worker 완료→ready/slot반환→Task응답 순서를 연결한다. 상세 QA/설계는 `tasks/chat-media-bounded-parallel-upload/qa/server-pipeline-optimization.md`.

- 미디어 finalize 통합·서버 제한 병렬: `tasks/chat-media-bounded-parallel-upload/qa/server-pipeline-optimization.md`. 앱 복구 계약은 CHAT, Socket/worker 설정·측정은 FIREBASE, 자동 회귀는 TESTS 진입점 참조. 실측 최적값 미확정.

- 미디어 전송 진행 표시: `OutPick/Features/Chat/Views/ChatMediaUploadProgressView.swift` → `ChatMessageCell.applyMediaUploadRecoveryState` → `ChatViewController.pendingRecoveryState`/`updateVisibleRecoveryIfPossible`. 원본 확보 후 사진 덮개·원형 진행, 서버 확인 중 회전, 성공 제거, 실패 회전 제거/기존 복구 버튼. 상태·재사용·렌더링 테스트 `OutPickTests/ChatMediaUploadProgressViewTests.swift`.

- 실제 미디어 전송 QA·방 내부 사진 보기 취소 결함: `docs/ai/tasks/chat-media-bounded-parallel-upload/qa/iphone14-live-transmission.md` → `ChatViewController.viewDidDisappear`/`finishRouteLifecycleForCoordinator`, `ChatRoomRouteLifecycleStateTests`. 최초70장 전송은 실패이며 사용자 최초 성공 답변은 정정됐다. 최신 수정·재검증 상태는 task progress 최상단을 따른다.

## 목적

기능 수정이나 새 기능 추가 시 AI 에이전트가 어디부터 봐야 하는지 빠르게 확인하기 위한 인덱스 문서다.

루트 문서는 공통 진입점과 세부 문서 링크만 유지한다. 기능별 상세 진입점은 필요한 문서만 추가로 읽는다.

## 공통 진입점

- iPhone 14 미디어 성능 QA: `OutPickTests/ChatMediaDevicePerformanceTests.swift` → `docs/ai/tasks/chat-media-bounded-parallel-upload/qa/iphone14-performance.md`. synthetic17회는 참고 자료이며 현재 `ChatMediaPipelineLimits.imagePreparation=4`는 실제 전송·스크롤 비교 후보다. 사용자가 실제 picker로 전송하고 Instruments Animation Hitches + Activity Monitor로 기록한다. ‘미디어 QA 방’ 실제 사진3장 ready/첨부3 확정 확인,70장 및2/4비교 진행 상태는 task progress 최상단. 영상은 후속, XCUITest 조작은 미검증.

- 미디어 제한 병렬 전송(2026-09-10 로컬 구현): `ChatViewController+MediaSelection.swift` → `ChatMediaSelectionUseCase`/`ChatMediaSelectionRepository` → `ChatMediaUploadTurnQueue`/`ChatMediaUploadUseCase` → `ChatOutgoingOutboxUseCase`. 전체 원본 확보 barrier, 준비·업로드 제한, queued 직후 실행권 반환, 중단 후 대표 실패 복원은 `entrypoints/CHAT.md`와 `tasks/chat-media-bounded-parallel-upload/`를 따른다. 서버 배포·실기기 QA는 별도다.

- 방별 자동 승계 50초 제한·부분 성공·실패 방 재처리: `functions/src/chat/moderation/{roomSuccessionPolicy,roomSuccessionJobs,roomMembershipSweep,roomMembershipSweepFunctions}.ts` → `firestore-tests/room-succession-deadline.emulator.test.mjs`; 상세는 `entrypoints/FIREBASE.md`와 `DATA_SCHEMA.md`
- 부모 승계 작업 장애 격리: `roomSuccessionJobs.ts`의 `parentFailurePatch/drainFailedParentRooms/terminalRoom`과 `roomMembershipSweepFunctions.ts` 예약 → 동일 deadline Emulator suite의 부모 실패·claim 경쟁·watchdog·replay 회귀. 실패한 부모의 진단은 자식 성공과 독립 보존한다.
- 채팅 역할 receipt·outbox TTL 배포 계약: `firestore.indexes.json` → `firestore-tests/room-role-indexes.contract.test.mjs`; 원격 배포 확인은 `entrypoints/FIREBASE.md` 참조
- 채팅 역할·읽음 최종 리뷰 회귀: `ChatMessage.init(from:)`, `ChatRoomRoleSession` → `OutPickTests/{RoomRoleEventPayloadTests,ChatRoomRoleSessionTests}.swift`; 세부 계약은 `entrypoints/{CHAT,TESTS}.md` 참조

- 앱 시작/루트 라우팅: `OutPick/App/AppCoordinator.swift`
- iOS Development/Production 빌드 환경: `Configurations/` → `OutPick.xcodeproj/xcshareddata/xcschemes/` → `scripts/build/validate-and-copy-firebase-config.sh` → `OutPick/Info.plist`
- Scene 연결/초기 DI와 bootstrap 실패 복구: `OutPick/App/SceneDelegate.swift`, `OutPick/App/Bootstrap/`
- 탭 조립: `OutPick/App/TabBarController/Composition`
- 기능 코드: `OutPick/Features`
- 공통 인프라: `OutPick/Infra`
- iOS Cloud Functions 공통 transport: `OutPick/DB/Firebase/CloudFunctions/Core/FirebaseCloudFunctionsTransport.swift`
- iOS Cloud Functions 기능 adapter: `OutPick/Features/*`의 `CloudFunctions*Repository/Client`와 Lookbook `CloudFunctionsMappers/`
- iOS local database bootstrap/Store: `OutPick/DB/GRDB/Core/AppDatabase.swift`, `OutPick/DB/GRDB/Stores/` (`AppDatabase.live()`는 `throws`)
- Chat persistence 계약/조립: `OutPick/Features/Chat/Persistence/`
- Firestore 문서 ID 경계: `docs/ai/tasks/firestore-document-id-boundary-cleanup/`, ADR-020
- 공통 키보드 dismiss helper: `OutPick/Infra/Utility/Support/KeyboardDismissSupport.swift`
- 로컬 DB/데이터 schema: `docs/ai/entrypoints/DATA.md`
- Firebase Functions flat export: `functions/src/index.ts`
- Firebase Functions 공통 runtime/callable: `functions/src/core/`
- Firebase Functions 기능 구현: `functions/src/{auth,brand,chat,lookbook,moderation,profile,styleMoods}/`
- 채팅 메시지 신고 evidence 계약·transaction·copy/cleanup: `functions/src/moderation/messageEvidence/{contracts,service,evidenceCopy,evidenceStorage,evidenceCleanup,evidenceFunctions,evidenceRuntime}.ts` → `functions/src/index.ts` → `functions/scripts/qa-message-evidence-development.mjs` → `firestore.indexes.json` → `functions/src/moderation/reports/contracts.ts` → `contracts/chat-moderation-v1.json` → `functions/src/moderation/messageEvidence/{contracts,evidenceCopy}.test.ts` / `firestore-tests/moderation-reports.emulator.test.mjs`; Phase 7.4C-2/C-3은 Development bucket/IAM/세 Function/필수 인덱스 3개와 30장·350MiB E2E까지 완료했고 Rules·TTL·관리자 조회·Production은 후속 승인 gate다.
- Kakao custom-token 함수·전용 runtime identity: `functions/src/auth/{functions,kakaoService,runtime}.ts`
- 계정·공개 프로필 서버 경계: `functions/src/profile/`, `functions/src/shared/accountStatus.ts`
- 계정 삭제 서버 상태 머신·정리 worker: `functions/src/accountDeletion/` → `firestore.rules`/`storage.rules`/`firestore.indexes.json`
- 계정 capability·삭제 차단: `functions/src/shared/accountStatus.ts`/`functions/src/accountDeletion/repository.ts` → `moderationAccounts/{uid}` schema v2 → `firestore.rules`/`storage.rules`와 `Socket/src/auth/socketAuthMiddleware.js`/`Socket/src/handlers/connectionHandlers.js`
- 스타일 무드 서버·seed·할당: `functions/src/styleMoods/`, `functions/src/shared/styleMoodAssignmentPolicy.ts`, `functions/src/lookbook/admin/seasonMoodFunctions.ts`, `functions/seeds/style-moods.v1.json`
- 브랜드·채팅 개발 데이터 선택 초기화: `functions/src/developmentReset/brandChatManifest.ts` → `functions/scripts/audit-brand-chat-reset.mjs` → 승인 후 `functions/scripts/reset-brand-chat-data.mjs`
- iOS 스타일 키워드 관리자·검색: `LookbookAdminHomeView.swift` → `LookbookCoordinator.pushStyleMoodManagement()` → `StyleMoodManagementViewModel.swift` / `StyleMoodManagementView.swift`
- iOS 브랜드·시즌 스타일 검색/선택: `AdminBrandManagementViewModel.swift` / `AdminBrandManagementView.swift` → `SeasonMoodManagementView.swift` / `StyleMoodSelectionSection.swift`
- iOS 브랜드 search-first picker 정책: `StyleMood.swift`의 `StyleMoodPickerPolicy` → `StyleMoodSelectionSection.swift` → `CreateBrandView.swift` / `AdminBrandManagementView.swift`
- Phase 5.1 스타일 관리 UX 구현·QA: `StyleMoodEditorView.swift` / `StyleMoodSelectionSection.swift` / `SeasonMoodManagementView.swift` → `docs/ai/tasks/style-mood-personalization-account-privacy/plan.md`의 Phase 5.1 → `decisions.md` D62~D64 → `qa-checklist.md`
- iOS 계정 bootstrap·새 온보딩: `AppCoordinator.swift` → `LoadCurrentUserBootstrapUseCase.swift` → `ProfileCoordinator.swift` → `ProfileSetupViewController.swift` → `StyleMoodOnboardingViewController.swift`
- iOS 계정/공개 프로필 read·mutation: `FirestoreCurrentUserAccountRepository.swift`, `FirestoreUserPublicProfileRepository.swift`, `CloudFunctionsProfileMutationRepository.swift`
- iOS 마이페이지 프로필·관심 스타일 편집: `MyPageCompositionRoot.swift` → `MyPageCoordinator.swift` → `ProfileEditViewController.swift` / `StylePreferenceEditViewController.swift` → `UpdatePublicProfileUseCase.swift` / `UpdateStylePreferencesUseCase.swift`
- iOS 일반 사용자 브랜드 요청·내역: `LookbookHomeView.swift` 검색 빈 결과 → `BrandRequestView.swift` → 제출 후 `MyBrandRequestsView.swift`; 재진입은 `MyPageViewController.swift`의 `ACTIVITY` → `MyPageCoordinator.swift` → `DefaultAppContentRouter.openMyBrandRequests()`
- iOS 계정 삭제·취소·로컬 scrub: `MyPageCoordinator.swift` → `AccountDeletionConfirmationViewController.swift` / `AccountDeletionPendingViewController.swift` → `RequestAccountDeletionUseCase.swift` / `CancelAccountDeletionUseCase.swift` → `AccountDeletionReceiptStore.swift` / `AccountDeletionLocalDataScrubber.swift` → `AppCoordinator.swift`
- iOS 환경/Firebase bootstrap: `AppRuntimeConfiguration.swift` → `AppDelegate.configureFirebaseApp(runtimeConfiguration:)` → `OutPickAppCheckProviderFactory.swift` → Debug 구성·Simulator Debug Provider / Release 실기기 App Attest → `OutPick.Debug.entitlements` / `OutPick.entitlements`
- 계정 삭제 provider 재인증: `DefaultSocialAuthRepository.swift` → Google pending sign-in/동일 세션 reauthenticate 또는 Kakao 강제 login prompt → callable
- iOS 관심 스타일 브랜드 홈·전체 보기: `CurrentUserStylePreferenceStore.swift` → `LoadInterestedStyleBrandsUseCase.swift` → `LookbookHomeViewModel.swift` / `InterestedStyleBrandListViewModel.swift` → `LookbookCoordinator.swift`
- iOS 좋아요 에디토리얼 화면·독립 섹션 상태: `LikedView.swift` → `LikedBrandCardView.swift` / `LikedSeasonCardView.swift` / `LikedPostCardView.swift` → `LikedViewModel.swift` → `LookbookCoordinator.swift`
- iOS 브랜드 생성·로고 업로드 재시도: `CreateBrandView.swift` → `CreateBrandViewModel.saveBrand()` → `CloudFunctionsBrandStore.createBrand/updateLogoPaths` + `LookbookStorageService` → `CreateBrandFlowView`
- Lookbook import extraction core/evidence/version: `tools/lookbook-import-worker/src/extraction/`, `processor.ts`, `season-discovery.ts`
- 시즌 목록 durable discovery: `functions/src/lookbook/import/seasonDiscoveryJobs.ts` → `tools/lookbook-import-worker/src/season-discovery-processor.ts` → `brands/{brandID}/seasonDiscoveryJobs/{jobID}`. 생성 흐름 상태 owner는 `CreateBrandDiscoveryViewModel.swift`이며 infrastructure 오류 원문은 내부 로그로만 남기고 브랜드 등록 화면에는 안정된 사용자 문구를 전달한다. 관리자 issue projection/fixed 재시도 상태 owner는 `SeasonImportManagementViewModel.swift`와 `SeasonCandidateDiscoveryResult.extractionIssueUserState`다.
- 시즌 대표 이미지 보강 Phase 7: `tools/lookbook-import-worker/src/extraction/{image-candidates,season-cover}.ts` → `season-discovery.ts` → `season-discovery-processor.ts`. 상세 계약은 `docs/ai/tasks/lookbook-extraction-issue-operations/phase-7-season-cover-enrichment.md`이며 기존 iOS nullable `coverImageURL` 표시 계약은 유지한다.
- Lookbook import worker HTTP/OIDC 경계와 배포 계약: `tools/lookbook-import-worker/src/server.ts`, `config.ts`, `oidc-auth.ts` → `scripts/ai/deploy-lookbook-import-worker.sh` → `docs/ai/runbooks/LOOKBOOK_IMPORT_WORKER_DEPLOYMENT.md`
- Chat media Phase 7.0 feasibility worker: `tools/chat-media-processing-worker/src/index.ts` → `imageProcessor.ts`의 sharp/libvips JPEG·PNG·GIF 정규화와 raw HEIC/HEIF 거부, `videoProcessor.ts`의 ffprobe/ffmpeg stream-copy remux. animated GIF 출력은 `keepDuplicateFrames: true`로 연속 중복 frame까지 frame 수·delay·loop를 보존하며 `imageProcessor.integration.test.ts`가 회귀를 막는다. `runtimeVerification.ts`와 `benchmark.ts`가 codec·resource gate다. 사용자 HEIC 선택은 Phase 7.3 iOS가 고품질 JPEG로 준비한다.
- Chat media Phase 7.1 로컬 구현: Socket `mediaHandlers.js`/`mediaUploadService.js`의 v2 preflight·finalize·status·cancel → `Rooms/{roomID}/MediaUploads/{uploadID}` 단일 원장 → `functions/src/chat/media/`의 queue trigger·private dispatcher·고정 execution slot·watchdog → `tools/chat-media-processing-worker/src/cloudJob.ts`의 Quarantine download·정규화·ready staging manifest 기록. 전용 upload Rules는 `storage.chat-media-quarantine.rules`, client deny와 watchdog query/TTL은 `firestore.rules`/`firestore.indexes.json`이다. Phase 7.2 전에는 message·seq·broadcast를 만들지 않는다.
- Chat media Phase 7.2 로컬 구현: `functions/src/chat/media/readyService.ts`와 worker-completed trigger가 room seq transaction으로 message·media index·preview·delivery job·ready 상태를 원자 생성하고, 검증된 `actualFormat`·`frameCount`·`animated`를 attachment의 `mediaFormat`·`animated`로 투영한다 → `Socket/src/media/mediaDeliveryWatcher.js`가 job lease 후 기존 media event/FCM을 at-least-once 전달 → `reconcileChatMediaObjectCleanup`이 source·고아 ready cleanup을 재시도한다. 새 ready Storage read gate는 `storage.rules`, 전용 bucket deploy config는 `firebase.chat-media.json`, server-only job deny와 cleanup/TTL index는 `firestore.rules`/`firestore.indexes.json`이다.
- Chat media Phase 7.3 iOS 구현: `ChatImageTransportSourceNormalizer.swift`/`ChatMediaSelectionChunker.swift`가 metadata 제거·HEIC→JPEG·GIF 보존과 30장/150 MiB 분할 → `ChatMediaUploadTurnQueue.swift`/`ChatMediaUploadUseCase.swift`가 image/video 독립 FIFO, kind별 로컬 1건 실행, Socket `active_upload_limit` 동일 identity backoff와 relaunch `uploading` status-only 2·4·8초 reconciliation을 적용 → `ChatMediaForegroundUploadService.swift`가 이미지와 영상을 attachment당 하나의 V4 signed PUT으로 foreground direct upload·응답 유실 1회 서버 reconciliation·finalize/status 처리 → `ChatOutgoingOutboxUseCase.swift`/GRDB가 보호된 local source와 실패 후 재시도/삭제 계약을 보존하되 signed PUT URL·필수 header는 영속화하지 않음 → `ChatAttachmentImageService.swift`가 같은 이미지 upload source를 최대 1024px로 메모리 다운샘플링하고 animated viewer에 원본 data를 공급 → `ChatImagePreviewCell.swift`가 확정 GIF만 정적 thumbnail 우하단 `GIF` badge로 표시 → `SimpleImageViewerVC.swift`의 Kingfisher `AnimatedImageView`가 탭한 원본 GIF를 전체 frame 선로딩 없이 현재 page에서만 재생한다. `ChatPendingMediaUploadStore.swift`/`ChatViewController{,Extension}.swift`/`ChatMessageCell.swift`는 대기·활성·재실행 pending의 무표시 로컬 버블, failed/expired의 시간 위치 소형 재시도·삭제 아이콘과 ready delivery reconciliation을 담당한다. 일반 이미지·영상 실패는 전역 팝업 없이 버블 액션만 사용하고 ban 중단 안내만 유지한다. 미디어 실패 overlay, 전송 중 진행률·취소 UI와 background `URLSession`/자동 PUT 복원은 사용하지 않는다.
- Lookbook extraction adapter registry: `tools/lookbook-import-worker/src/extraction/adapters/{registry,cafe24,types}.ts`
- Lookbook extraction review/trust/resume: worker `src/extraction/review.ts`, Functions `src/lookbook/import/{functions,reviewContract}.ts`, iOS `LookbookExtractionReview*`
- Lookbook extraction count-based review gate/UI: worker `src/extraction/{quality,review}.ts`, iOS `LookbookExtractionReview.swift`, `LookbookExtractionReviewViewModel.swift`, `LookbookExtractionReviewView.swift`
- Lookbook expected-count 활성 gallery scope: worker `src/extraction/expected-count.ts`, YOUTH incident fixture/test
- Lookbook 시즌 상세 pagination·이미지 prefetch: `LoadSeasonDetailUseCase.swift`, `SeasonDetailViewModel.swift`, `SeasonDetailView.swift`, 공용 `BrandImageCache`→`ImageCachePipeline`
- Lookbook extraction evidence/issue 자동 기록(Phase 2 완료): worker `src/extraction/{retained-evidence,issue-policy,issue-recorder}.ts`, `processor.ts`, `season-discovery-processor.ts` → Functions `src/lookbook/import/evidenceCleanup.ts`. 배포 경합의 구형 occurrence 지연 도착은 `issue-recorder.ts`가 cluster blocked runtime을 단조 증가시키고 fixed/verified runtime의 job 재시도 projection을 복원한다.
- Lookbook extraction issue 공통 계약: `contracts/lookbook-extraction-issue-v1.json` → Functions `extractionIssueContract.ts` → Worker `extraction/issue-contract.ts` → `docs/ai/tasks/lookbook-extraction-issue-operations/`
- Lookbook extraction issue 내부 운영: Functions `src/lookbook/issueOperations/{contract,auth,service,functions}.ts` → CLI `tools/lookbook-extraction-issue-ops/src/{config,gcloud,index}.js`의 exact operator IAM Credentials `generateIdToken` → `docs/ai/runbooks/LOOKBOOK_EXTRACTION_ISSUE_OPERATIONS.md`
- Lookbook extraction fix 검증: Worker `src/{runtime-contract,server,processor}.ts`의 `/runtime-contract`, `/smoke/extraction` → Functions `src/lookbook/issueOperations/{releaseContract,releaseExternal,releaseService,releaseFunctions}.ts` → CLI `verify-fix`
- Lookbook extraction fixed-only iOS 재시도: `SeasonCandidateDiscoveryResult.swift` / `SeasonImportJob.swift` / `LookbookExtractionReview.swift` → 각 Cloud Functions Repository → `SeasonImportManagementViewModel.swift` / `LookbookExtractionReviewViewModel.swift` → 관리자 두 화면. 서버 entrypoint는 `retrySeasonDiscoveryAfterExtractionFix`, `retryLookbookExtractionAfterFix`다.
- Lookbook existing-season reconcile: worker `src/extraction/reconcile.ts`, Functions `src/lookbook/import/{functions,repairContract}.ts`, iOS `LookbookSeasonRepair*`
- Lookbook 관리자 remote preview 이미지: `Services/ImageLoading/LookbookRemotePreviewImage{Loading,Loader}.swift`, `Views/Shared/LookbookRemotePreviewImageView.swift`
- Lookbook extraction fixture/differential gate: `tools/lookbook-import-worker/src/fixture/`, `tools/lookbook-import-worker/fixtures/`, `npm run test:fixtures`
- Lookbook Cafe24 underscore-detail discovery 회귀: `tools/lookbook-import-worker/src/season-discovery.ts`, `fixtures/discovery/platform/cafe24-underscore-detail-list/`
- Socket bootstrap/application: `Socket/index.js`, `Socket/src/app/`
- Socket 기능 경계: `Socket/src/{auth,handlers,rooms,messages,media,lifecycle,runtime}/`
- Socket message idempotency 공통 경계: `Socket/src/messages/messageDeliverySingleFlight.js`, `Socket/src/messages/sequenceStore.js`
- iOS Socket 단일 ingress/admission/routing/reconnect: `OutPick/Infra/Realtime/RealtimeSocketListenerBinder.swift`의 `RealtimeSocketMessageIngressQueue`, `OutPick/Infra/Realtime/RealtimeSocketService.swift`의 `RealtimeSocketAdmissionState`·`RealtimeRoomRoutingState`·`RealtimeRoomJoinState`·Socket generation·visible strict suspend/rejoin, `OutPick/Infra/Realtime/RealtimeChatIngressOrdering.swift`, `OutPickTests/RealtimeSocketListenerBinderTests.swift`, `OutPickTests/RealtimeChatIngressOrderingTests.swift`
- iOS Chat route·비동기 진입 경쟁·edge-pop/방 생성 차단 정책: `OutPick/Features/Chat/ChatNavigationController.swift`, `OutPick/Features/Chat/ChatNavigationStackPolicy.swift`, `OutPick/Features/Chat/ChatOpenRoomRequestState.swift`, `OutPick/Features/Chat/ChatOpenRoomRequestRegistry.swift`, `OutPick/Features/Chat/ChatRoomRouteLifecycleState.swift`, `OutPick/Features/Chat/Controllers/{ChatViewController,RoomCreateViewController}.swift`, `OutPick/Features/Chat/ChatCoordinator.swift`, `OutPickTests/{ChatNavigationControllerTests,ChatNavigationStackPolicyTests,ChatOpenRoomRequestStateTests,ChatOpenRoomRequestRegistryTests,ChatRoomRouteLifecycleStateTests}.swift`
- iOS Chat background tap·native message context menu·announcement long press·cell action gesture 책임: `OutPick/Features/Chat/Controllers/{ChatViewController,ChatViewControllerExtension}.swift`, `OutPick/Features/Chat/Domain/Policies/ChatMessageActionPolicy.swift`, `OutPick/Features/Chat/Views/Cell/ChatMessageCell.swift`
- iOS Profile modal edge-swipe dismiss: `OutPick/Features/Profile/Views/UserProfileDetailViewController.swift`, `OutPick/Features/Profile/UserProfileDetailCoordinator.swift`, `OutPick/Infra/Utility/Transitions/ChatModalTransitionManager.swift`
- iOS visible Chat strict ordering/recovery: `OutPick/Infra/Realtime/RealtimeChatIngressOrdering.swift`, `OutPick/Infra/Realtime/FirebaseChatRealtimeGapRecoveryLoader.swift`, `OutPickTests/RealtimeChatIngressOrderingTests.swift`
- iOS lightweight Banner presentation/retry: `OutPick/Infra/Banner/BannerManager.swift`의 `RealtimeBackgroundRoomSessionOpening`·`BannerSubscriptionRetryPolicy`, `BannerPresentationQueueState.swift`, `OutPickTests/BannerPresentationQueueStateTests.swift`
- iOS 방별 fan-out 최종 dedupe: `OutPick/Infra/Realtime/RealtimeSocketService.swift`의 `ChatRoomSessionActor`, `OutPickTests/ChatRoomSessionActorTests.swift`
- Chat moderator delegation Phase 1 호환 데이터 기반: Room owner canonical/fallback은 `ChatRoom.swift` → `ChatRoomFirestoreDTO.swift` → `ChatRoomFirestoreMapper.swift`, role/read projection은 `JoinedRoomListItem.swift`, 공개 역할 이벤트 계약은 `ChatMessageType.swift`/`ChatMessage.swift`, 로컬 보존은 `ChatMessageRecord.swift` → `ChatMessageRecordMapper.swift` → `GRDBMigrationRegistry.addRoomRoleEventToChatMessage`다. 집중 검증은 `ChatRoomFirestoreMapperTests`, `JoinedRoomProjectionTests`, `RoomRoleEventPayloadTests`, GRDB mapper/migration tests다.
- Chat moderator delegation Phase 2 서버 권한 코어: `functions/src/chat/moderation/roomRoleService.ts`의 transaction resolver·임명/회수/사임/퇴장/이전·24시간 receipt·role event/outbox → `roomBanService.ts`/`service.ts`의 owner/moderator 제재 matrix → `functions.ts`/`functions/src/index.ts` callable export → `firestore.rules` private state·role mutation deny → iOS `ChatModerationLifecycleRepository.swift` access/mutation mapping. 검증은 `contracts.test.ts`, `index.contract.test.ts`, `firestore-tests/{chat-moderation.emulator,moderation-capabilities.rules.test}.mjs`, `CloudFunctionsChatModerationLifecycleRepositoryTests.swift`다.
- Chat moderator delegation Phase 5 자동 승계·계정 정리: 영구 정지/계정 삭제 transaction → `roomOwnershipSuccessionJobs` → `roomSuccessionJobs.ts`의 부모/방별 상태·계정 fence → `roomMembershipSweep.ts`의 관리자 전용 후보·no-candidate 종료 → `roomMembershipSweepFunctions.ts`의 방별 50초·실패 후 5/15/20초 예약과 5분 watchdog → account deletion `cleanup.ts`/`drain.ts` finalizer gate·role event 익명화 → iOS 동일 ID privacy 갱신. 수동 복구는 `functions/scripts/replay-room-ownership-succession.mjs --room ...`, 검증은 `room-succession-deadline.emulator.test.mjs`와 관련 suite다.
- Chat moderator delegation Phase 6 migration·rollout gate: `functions/scripts/migrate-room-moderator-cutover.mjs`가 dry-run/apply orchestration을, `room-moderator-cutover-plan.mjs`가 ownerUID·dual frontier·owner role·moderatorCount 보정 계획과 conflict/blocker·exact-count/hash gate를 소유한다. 앱 시작 gate는 `OutPick/App/Rollout/` → `AppCompositionRoot.swift` → `AppCoordinator.swift`, 채팅 화면 feature snapshot은 `ChatContainer` → `ChatCoordinator` → `ChatRoomSettingViewModel`, 서버 신규 권한 생성 gate는 `functions/src/chat/moderation/rollout.ts` → `functions.ts`다. fixture·gate 검증은 `room-moderator-cutover-plan.test.mjs`, `rollout.test.ts`, `AppRolloutGateTests.swift`, 운영 절차는 task `migration-runbook.md`다. 실제 Firebase migration·배포·설정 변경은 수행하지 않았다.
- Chat moderator delegation Phase 3 timeline/unread: Socket 일반 message는 `Socket/src/messages/sequenceStore.js`, media ready는 `functions/src/chat/media/readyService.ts`에서 `seq + unreadMessageSeq`를 원자 증가한다. 역할 outbox는 `Socket/src/roles/roleEventDeliveryWatcher.js` → `createProductionDependencies.js` → iOS `RealtimeSocketListenerBinder.swift`/`RealtimeSocketService.swift` 공통 ingress로 전달되고 Messages pagination이 복구 원장이다. iOS dual read frontier는 `ChatReadStateStore.swift`/`ChatRoomReadStateStore.swift`/`ChatRoomViewModel.swift` → `UserProfileRepository.updateReadFrontier`, 표시·제외 정책은 `RoomRoleEventCollectionViewCell.swift`, `ChatMessageActionPolicy.swift`, `BannerManager.swift`, `GRDBChatMessageStore.swift`가 소유한다.
- Chat moderator delegation Phase 4 iOS 역할 화면: 현재 방 단일 listener는 `ChatRoomRoleRepository.swift` → `ChatRoomRoleUseCase.swift` → `ChatRoomRoleSession.swift`이며 `ChatContainer`가 같은 세션을 `ChatRoomViewModel`과 `ChatRoomSettingViewModel`에 주입한다. 참여자 pinned pagination·정렬은 `FirebaseChatRoomRepository.fetchPinnedRoomMembers` → `LoadChatRoomParticipantsUseCase`, 임명·회수·사임·이전 UI는 `ChatRoomSettingViewController`, 메시지 작성자 현재 역할 지연 판정은 `ChatRoomViewModel.resolvedMessageActionPolicy` → `ChatMessageActionPolicy`다. 검증은 `ChatRoomRoleSessionTests`, `ChatRoomParticipantRolePolicyTests`, `ChatMessageActionPolicyTests`, `ChatRoomExitUseCaseTests`다.
- 현재 Socket ingress 순서 보장 task: `docs/ai/tasks/socket-ingress-ordering-hardening/`
- iOS Socket candidate QA: `RealtimeSocketService.swift`의 DEBUG 전용 `SocketDebugQAConfiguration`, `OutPickTests/SocketDebugQAConfigurationTests.swift`
- iOS 발신 ACK 수렴: `ChatMessageSendReceipt.swift`, `ChatViewController.reconcileServerConfirmedOutgoingMessage`, `LookbookChatShareViewModel`의 동일 ID retry
- Socket room summary 단일 소유권: `Socket/src/messages/sequenceStore.js`가 seq transaction 안에서 `Rooms.lastMessage*`를 갱신하며, iOS `RealtimeSocketService`의 ACK 경로는 room summary를 직접 쓰지 않는다.
- Socket 자동 검증: `Socket/test/`, `Socket/scripts/run-tests.mjs`
- Phase 6 텍스트 전송 보호: Socket `src/utils/rateLimit.js`와 text/Lookbook/media handler가 canonical moderation principal·room·kind별 2초 bucket을 공유하고, Functions `src/lookbook/comments/{contracts,service,functions}.ts`가 댓글·답글 합산 분당 20회 Firestore transaction quota와 UUID 멱등 문서 ID를 소유한다. iOS 입력 상한/재시도 ID는 `ChatRoomMessageUseCase.swift`, `ChatUIView.swift`, `Create{PostComment,CommentReply}UseCase.swift`, 댓글 ViewModel/InputBar가 담당한다.
- Phase 6 메시지 개인정보 최소화: 신규 메시지의 `senderEmail`은 Socket/FCM/iOS `ChatMessage`/GRDB에서 제외하며 `GRDBMigrationRegistry.removeSenderEmailFromChatMessage`가 기존 로컬 column을 제거한다.
- Chat UGC safety/moderation v1 계약: `contracts/chat-moderation-v1.json` → ADR-024 → `docs/ai/tasks/chat-ugc-safety-room-moderation/{decisions,plan,phase-7-implementation-plan,progress,qa-checklist}.md`
- Chat moderation Phase 1 구현·Development rollout: iOS `CloudFunctionsCurrentUserModerationRepository`/`LoadCurrentUserBootstrapUseCase`/`AppCoordinator`/`ModerationNoticeViewController`, Functions `src/moderation/`와 `scripts/backfill-moderation-principals.mjs`, Socket `src/moderation/capabilities.js`, `firestore.rules`/`storage.rules` → 상세 `entrypoints/APP.md`, `entrypoints/CHAT.md`, `entrypoints/FIREBASE.md`, `entrypoints/TESTS.md`
- Chat moderation Phase 2 신고·관리자 API: iOS `ChatModerationReport.swift` → `ChatModerationReportingRepository.swift` → `SubmitChatModerationReportUseCase.swift`; Functions `src/moderation/{reports,admin,audit}/`; Rules/index/transaction QA `firestore.rules`, `firestore.indexes.json`, `firestore-tests/moderation-{capabilities.rules,reports.emulator}.test.mjs`
- Chat deletion revision legacy 감사·cutover: `functions/scripts/audit-chat-deletion-revisions.mjs`가 revision·cleanup·reply/media 잔존을 읽기 전용·비식별 집계한다. `apply-chat-deletion-field-index.mjs`는 Development 단일 field index를 exact patch하고, `repair-chat-deletion-cutover.mjs`는 expected hash/count/head와 confirmation fence 아래 cleanup 재개·revision backfill을 분리 수행한다. 순수 gate/정렬은 `chat-deletion-cutover-plan.mjs`와 test가 소유한다.
- Chat moderation Phase 3 삭제·Phase 3.1 공용 종료 tombstone: iOS `FirebaseChatRoomRepository.fetchJoinedRoomList`/`ChatModerationLifecycleRepository.swift` → `ChatRoomClosureAcknowledgementUseCase`/`JoinedRoomsViewModel`/`ChatCoordinator.handleRoomClosure`; 실시간·오프라인 확인 직후 목록 제거와 같은 세션 stale fetch 차단은 `ChatRoomClosureListUpdating`, `JoinedRoomsViewModel.removeRoomAfterRealtimeClosure`/`acknowledgeClosedRoom`; Functions `src/chat/{moderation,cleanup}/`의 `acknowledgeRoomClosure`와 `content → retention` cleanup; Socket `roomClosureWatcher.js`; Rules/transaction QA `firestore-tests/{moderation-capabilities.rules,chat-moderation.emulator}.test.mjs`
- Chat moderation Phase 4 전역 차단: `OutPick/Features/Moderation/{UserBlockVisibilityStore,UserBlockSnapshotStore,UserBlockSessionController}.swift` → `AppCompositionRoot`/`AppCoordinator` bootstrap → Chat·Lookbook·Profile·MyPage 공용 UseCase/Store; Functions `src/lookbook/safety/{blockContracts,functions}.ts`의 `blockUser`/`unblockUser`; Socket `src/push/chatPushService.js`의 수신자별 차단 push 억제 → 상세 `entrypoints/{APP,CHAT,FIREBASE,TESTS}.md`
- Chat moderation Phase 7.4D 관리자 queue/current-revision Evidence: Functions `src/moderation/admin/{contracts,service,functions,messageResolution,evidenceAccess}.ts`, Evidence retention drain `src/moderation/messageEvidence/{evidenceCleanup,evidenceFunctions}.ts`, Firestore deny/index/TTL `firestore.{rules,indexes.json}`, 전용 Storage target/rules `.firebaserc`·`firebase.chat-media.json`·`storage.moderation-evidence.rules`, 자동 검증 `functions/src/moderation/admin/*.test.ts`·`firestore-tests/{moderation-reports.emulator,moderation-evidence-storage.rules.test}.mjs` → 상세 `entrypoints/{FIREBASE,TESTS}.md`
- Chat moderation Phase 7.5E 사용자 메시지 신고: `ChatViewController.handleReport`와 `SimpleImageViewerVC.onReport` → `ChatCoordinator.presentMessageReport` → `ChatMessageReportViewController`/`ChatMessageReportViewModel` → `SubmitChatModerationReportUseCase.submitMessageReport` → `CloudFunctionsChatModerationReportingRepository` → callable `submitMessageReport`/`submitMessageReportService`. 중복 판정은 서버 transaction이 소유하고 iOS는 별도 GRDB·신고 캐시 없이 현재 신고 화면의 네트워크 재시도 동안만 UUID와 입력을 유지한다. 신고 화면은 OutPick editorial token을 사용하며 상세 입력 밖 tap과 scroll drag로 키보드를 닫는다. `신고` CTA는 사유 선택 전 비활성이고 선택 직후 활성화되며 ViewModel도 사유 누락을 재검증한다. reason title·symbol, multiline 안내·placeholder와 가변 높이 CTA는 Dynamic Type에 맞춰 재구성되고 선택·제출 상태는 글자 크기 변경 중에도 유지한다.
- Chat moderation Phase 7.5A~D queue-only·공통 deletion mutation·Socket fast path·iOS reconciliation: 서버는 `functions/src/chat/deletion/mutation.ts`, Socket은 `Socket/src/deletion/deletionDeliveryWatcher.js`, iOS는 `ChatDeletionSyncUseCase.swift` → `ChatDeletionSyncRepository.swift` → `GRDBChatDeletionSyncStore.swift` → `ChatMessageRecordMapper.swift`를 진입점으로 사용한다. 최초 삭제만 tombstone·Room revision·cleanup/outbox를 원자 생성하며 iOS는 account+room cursor·방 수명 삭제 마커·durable cleanup queue로 누락을 복구한다. 서버가 직접 반환한 같은/더 최신 tombstone은 legacy marker의 sender 익명화 정책을 교정하고, 오래된 visible payload에는 marker가 계속 우선한다. 기존 Firestore 삭제 listener는 제거됐다.
- Chat moderation Phase 5 room ban UX 보정: `ChatMessageActionPolicy`/`ChatViewController`의 방장 메시지 `내보내기`, `ChatRoomSettingViewController`의 방장 전용 `차단 사용자` 버튼 → `ChatRoomBannedUsersViewController` 독립 관리 화면, 참여자 프로필·별도 관리 버튼, `ChatModerationLifecycleRepository.fetchMyRoomAccess` → Functions `getMyRoomAccess`의 서버 권위 `member | joinable | banned | closed` 판정.
- Chat account capability v2·Storage reservation 보정: `functions/scripts/backfill-account-capabilities.mjs`, `functions/scripts/audit-{firebase-rules,firestore-indexes}.mjs`; Rules 회귀 `firestore-tests/chat-media-storage.rules.test.mjs`
- Platform admin 운영: `functions/scripts/manage-platform-admin.mjs` → `functions/src/moderation/admin/platformAdminOperations.ts` → `docs/ai/runbooks/PLATFORM_ADMIN_OPERATIONS.md`
- Phase 6 통합 회귀/배포 gate: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-integration-tests.md`, `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-deployment.md`
- Firestore rules: `firestore.rules`
- Firestore indexes: `firestore.indexes.json`
- Firebase/Storage 운영 권한 확인: `docs/ai/entrypoints/FIREBASE.md`
- 단위 테스트: `OutPickTests`
- UI 테스트: `OutPickUITests`

## 세부 진입점

- 앱 조립, 탭, 주요 Feature: `docs/ai/entrypoints/APP.md`
- Chat 앱 화면/검색/채팅방 흐름: `docs/ai/entrypoints/CHAT.md`
- Lookbook 앱 화면/도메인: `docs/ai/entrypoints/LOOKBOOK.md`
- Profile 생성/수정/상세: `docs/ai/entrypoints/PROFILE.md`
- Data/GRDB/Repository boundary: `docs/ai/entrypoints/DATA.md`
- Firebase Functions/Firestore: `docs/ai/entrypoints/FIREBASE.md`
- 테스트: `docs/ai/entrypoints/TESTS.md`

## 작업별 진입점

| 포인터 | 문서 |
| --- | --- |
| 현재 작업과 최근 완료 상태 | `docs/ai/tasks/active.md` |
| 세션 복원 | `HANDOFF.md` |
| 장기 결정 | `docs/ai/ADR.md` |
| 데이터 계약 | `docs/ai/DATA_SCHEMA.md` |

최근 작업은 `active.md`에서 관련 task의 `decisions.md`와 `progress.md`로 들어간다. phase 전체 이력은 루트 인덱스에 복사하지 않는다.

## 변경 목적별 빠른 경로

| 변경 목적 | 읽기 순서 |
| --- | --- |
| 핵심 인프라 모듈화 | `tasks/core-infrastructure-modularization/design.md` → `contracts/README.md` → `active.md`가 가리키는 현재 phase 결정/계획/테스트 → decisions/plan/progress → ADR-019 → 네 현재 대형 진입점 |
| 삭제 purge queue/장애 | task decisions/progress → ADR-018 → `lookbook/deletion/purgeDrain.ts` → `lookbook/deletion/functions.ts` scheduler/query → `purgeLease.ts` → test |
| 삭제 요청 앱 목록/retry | task progress → `LOOKBOOK.md` 삭제 관리 → `FIREBASE.md` 삭제 lifecycle → iOS/Functions 구현 |
| 룩북 import/진단 | task progress → `architecture/LOOKBOOK_IMPORT_WORKER.md` → `FIREBASE.md` URL import → worker/앱 구현 |
| 브랜드 요청/관리 | `LOOKBOOK.md` 관리자 흐름 → `FIREBASE.md` 권한·요청 → 관련 task progress |
| 관심 스타일 브랜드 | 현재 task Phase 6 decisions/data contract → `LOOKBOOK.md` 관심 스타일 브랜드 → `FirestoreBrandRepository.swift` → 관련 ViewModel/View/테스트 |
| 계정 삭제 iOS | 현재 task Phase 8 decisions/plan → `PROFILE.md` 계정 삭제 iOS 흐름 → MyPage 화면/UseCase/Repository → `AppCoordinator.swift` → `TESTS.md` Phase 8 |
| 스타일 무드/seed | 현재 task decisions/seed spec → `DATA_SCHEMA.md` 스타일 무드 계약 → `functions/src/styleMoods/` → `firestore.rules`/indexes → rules test |
| 새 사용자 온보딩/프로필 | 현재 task progress → `PROFILE.md` → `AppCoordinator.swift` → Profile UseCase/Repository → Functions profile module/rules |
| Chat membership/cache | `CHAT.md` → `DATA_SCHEMA.md` Chat 계약 → 관련 task decisions/progress |
| Chat 신고·차단·삭제·room ban·계정 제재·미디어 격리/evidence | `tasks/chat-ugc-safety-room-moderation/decisions.md` → Phase 7.5 신고 UX·Deletion Sync `phase-7-5-design.md` → `phase-7-implementation-plan.md` → `contracts/chat-moderation-v1.json` → ADR-024 → `CHAT.md`/`FIREBASE.md`/`TESTS.md` → task plan/progress/QA |
| Chat route/lifecycle/gesture 완료 변경 | `CHAT.md`의 `Route/lifecycle/gesture 변경 파일 빠른 지도` → `tasks/chat-route-lifecycle-hardening/progress.md` → `TESTS.md`의 Chat route lifecycle hardening tests → task QA checklist |
| Firestore 문서 identity | ADR-020 → `DATA_SCHEMA.md` → `CHAT.md`/`LOOKBOOK.md` 문서 ID 경계 → `DATA.md` Repository boundary → `FIREBASE.md` rules → `TESTS.md` 경계 테스트 → task progress/QA |
| Chat 대규모 unread/read frontier | `tasks/active.md` → `tasks/socket-ingress-ordering-hardening/phase-6-unread-catch-up-read-frontier.md` → `CHAT.md` read frontier/realtime-only 3초 preview·즉시 persistence 및 진단 계측 진입점 → `TESTS.md` Phase 6-A~C 회귀·Phase 6-D QA |

작업 시작 시 이 문서와 `docs/ai/tasks/active.md`만 먼저 읽고, 표가 가리키는 세부 문서만 추가로 확인한다.
# 2026-09-22 다운로드② 최종 검증

취소·파일 수명 필수 잔여 완료: Firebase12.17.0 공식수정, 구SDK 취소 후 재시작/파일생성 재현 및 수정SDK 통과, 공용87개 회귀. 실기기 취소87건·임시파일90개정리·신규잔여0, 사용자 지속빈화면아닌 빠른스크롤직전 로딩으로 확인. 진단 없는 일반DEV 복원 성공. `docs/ai/tasks/chat-media-first-view-loading/download-bottleneck-results.md`에 근거와 한계, 다음③은 `cache-reuse-implementation-plan.md`에 있으며 구현 전.
