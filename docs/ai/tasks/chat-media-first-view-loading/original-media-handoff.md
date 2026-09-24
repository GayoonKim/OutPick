# ③ 확대 원본·저장·파일 수명 — 새 스레드 인계

> 최신 구현: [2026-09-24 Phase3·4 결과](original-media-results.md). 코드/자동83개 검증 완료, 실기기 QA 대기. 아래 파일 지도·계약은 유지하되 구현 전/미정 설명은 결과 문서가 우선한다.

## 1. 최종 목표와 현재 요청

2026-09-24 사용자 요청으로 **Phase3부터 구현 재개**. 계정별 원본 캐시를 보관하고 같은 계정 재로그인 때 재사용하는 1번 정책을 확정했다. 로그아웃/계정 전환은 요청·세대만 무효화하며 전체 계정 합산 예산을 적용한다. ③ 기존 계획의 Phase3 원본 파일 관리 → Phase4 확대·저장·영상 연결 → 후속 통합 QA가 대상이다.

먼저 이 문서와 `cache-reuse-implementation-plan.md`의 Phase3~5를 읽는다. 표시 준비의 최신 결과는 `display-readiness-plan.md` 상단이다. 오래된 문서의 “QA 대기”, “최대2개”, “환경변수로만 해제”는 과거 상태이며 다시 적용하지 않는다.

## 2. 완료한 작업과 검증

- ① 화면 수요·이탈 취소, ② 다운로드/쓰기 분리 및 취소 파일 수명 필수 회귀 완료. Firebase Storage 취소 경합 수정 SDK12.17.0 적용. 상세는 `download-bottleneck-results.md`.
- ③ Phase1·2: 즉시 메모리 hit, 같은 key/version pending 저장 합류, 셀 수명과 독립된 저장, 삭제/세대 검사 완료. 당시 통합89개 회귀 통과. `cache-reuse-results.md`의 초기 용량/속도 수치는 현재 정책 이전 결과다.
- 이후 표시 준비 개선: 공용 채팅 메모리1GiB LRU·압박 대응, 디스크1GiB/900MiB 정리, 파일 URL ImageIO 디코딩, 현재 불러온 메시지 전체를 가까운 순서로 디스크 준비, 초기 로컬 메시지 힌트부터 준비, 셀 즉시 hit 및 idle 픽셀 유지.
- **세 제한 해제는 일반 실행/Release 기본 동작**: `ChatMediaViewportController`가 준비 `maxConcurrent:nil`, `ChatAttachmentImageService.remote`가 `bypassDirectDiskLimits:true`. 기존 `ChatDiskPreparationExperiment`와 `OUTPICK_UNLIMITED_DISK_PREPARATION` 의존 제거. 네트워크/쓰기/다른 파이프라인/legacy 복구 경로의 제한까지 제거한 것은 아니다.
- 최종 자동26개 통과: viewport15/direct disk5/LRU6. 기기 build/install/일반 실행 성공. 사용자 직접 재실행 후 “완벽하게 이미 로딩되어 있는 것처럼 표시된다” 확인. **재실행 후 빠른 스크롤 표시 개선 완료**. ③ 전체 완료는 아니다.
- 최종 로그 `/private/tmp/outpick-unlimited-default-{tests,build,install,launch}.log`. 마지막 일반 실행에는 계측 옵션이 없어서 CPU/메모리/발열 수치의 최종 재측정은 아님. Release 별도 빌드는 미실행, 무조건 조립 코드로 동일 정책 확인.
- 이전 녹화 `/private/tmp/outpick-spinner-qa.mov` 37초대 빈 사진 묶음은 중간 수동 재실행으로 옵션/계측이 끊긴 뒤였다. 옵션 유지 재검증 `/private/tmp/outpick-spinner-qa2.mov` 및 `outpick-spinner-video2-device.log`는 디코딩339개/셀 hit834/miss0, 사용자 빈 이미지 없음. 다른 프로세스의 로그를 영상 장면에 연결하지 않는다.

## 3. 남은 작업과 확정 사용자 계약

다음은 기존 계획 Phase3→4 순차 진행이다. 아직 구현·검증 완료로 간주하지 않는다.

1. **원본 파일 저장소/소비자 수명**: 표시 캐시와 독립된 namespace·유한 예산. 동일 원본/version 전송 합류, 소비자별 취소, 마지막 소비자 종료 시 전송 취소. SDK 종료 전 permit/임시파일 반환 금지. 재생·저장 중 lease로 파일 보호. 큰 파일은 임시 사용 후 해제 가능, 기존 파일 합산 사용량 관측. 축소 JPEG를 원본으로 승격 금지. outbox/사용자 보호 파일은 정리 대상 제외.
2. **사진 확대**: 현재 + 바로 앞뒤 각1페이지의 정적 사진 원본만 준비. GIF/영상 페이지를 건너 더 먼 사진까지 확장하지 않는다. 페이지 이동 시 범위 밖 소비자 취소. GIF·영상 원본은 실제 열 때만 요청.
3. **저장**: 축소 화면 이미지 대신 원본 파일 저장, 실패 시 재시도. 확대 화면 닫으면 저장 다운로드/준비 소비자 취소하고 뒤늦은 성공·실패 안내 금지. 다른 소비자의 공유 요청은 유지. Photos 제출 직전 취소/세대 확인. 이미 Photos에 제출된 취소 불가능한 작업/완료 저장을 되돌린다고 약속하지 않는다.
4. **영상**: 원격 재생은 전체파일 다운로드 완료를 기다리지 않는다. 기존 파일 있으면 재사용. 스트리밍과 별도 detached 전체 다운로드를 자동 중복 시작하지 않는 구조. 스트리밍 바이트와 저장 요청의 완전 병합/custom resource loader는 기본 범위 밖.
5. **삭제·계정 수명**: 메시지 삭제/로그아웃/계정 전환 후 늦은 완료·캐시 부활 차단. 사용자 확정: 계정별 namespace로 파일을 보관하며 동일 계정 재로그인만 재사용한다. 전체 계정 합산 512MiB를 QA 시작값으로 사용하고 사용 중 파일은 lease로 보호한다. 기존 계정 탈퇴의 기기 전체 캐시 scrub은 유지한다. 7일 서버/로컬 만료는 아직 구현된 것으로 취급하지 않는다.

표시 실패 재시도는 화면에서 이탈 후 재등장 또는 방 재진입 기준 유지. 업로드 규격·수신1024px decode·원문 표시 디스크 파일 유지. 추가 압축/크기 버킷/예산 최적화는 필요할 때 QA로 결정. **7일 후 서버 썸네일·원본 삭제 및 만료 버블은 별도 미래 작업**이며 포함하지 않는다. 완료한 아바타 원본·일반 룩북 URL 경로도 확장하지 않는다.

## 4. 파일 지도와 작업 트리 주의

이번 인계 턴은 문서만 변경. 현재 working tree는 이전 여러 단계의 앱/테스트/설정 변경이 다수 남아 있고 커밋하지 않았다. `git status --short`를 먼저 확인하고 사용자 변경을 되돌리지 않는다. 특히 `ChatVideoAssetLoading.swift`, `ChatVideoAssetService.swift`, `ChatVideoAssetServiceTests.swift`는 삭제 상태이므로 과거 경로대로 복원하지 않는다.

후속 코드 진입점(존재 확인, 세부 흐름은 다음 착수 시 재확인):

- `OutPick/Infra/Media/ImageViewer/SimpleImageViewerVC.swift`: saveTapped, pageLoadTasks, 원본 cached/network/Data 로더, 취소/닫기, 인접 페이지 정책. 공용 뷰어라 아바타·룩북 호환 영향 확인.
- `OutPick/Infra/Media/PhotoLibrarySaver.swift`: 현재 저장 API와 파일 저장 경계.
- `OutPick/Features/Chat/Services/MediaPreview/ChatMediaPreviewServices.swift`, `Managers/Implementations/OPVideoDiskCache.swift`, `Views/ChatVideoPlayerViewController.swift`: 영상 resolver/cache/player 수명.
- `OutPick/Features/Chat/ChatContainer.swift`, `ChatCoordinator.swift`, `Controllers/ChatViewController.swift`: 원본 공유 서비스 주입·확대/재생 라우팅.
- `OutPick/Features/Chat/Domain/UseCases/ChatDeletionSyncUseCase.swift`, `OutPick/Features/MyPage/AccountDeletionLocalDataScrubber.swift`: 삭제 연결. 로그아웃/계정 전환 실제 호출 지도는 재확인 필요.
- `OutPick/Infra/Cache/ImageCache/`: ImageCachePipeline, ImageLoadCoordinator, ImageCachePersistence, ImagePipelineProcessor/Resources, ImageCacheDiskStore, ImageCacheReadLease. 기존 pipeline 공유 계약/삭제 세대/SDK 취소 완료 경계 보존.
- 테스트: `OutPickTests/ImageViewerPagePolicyTests.swift`, `ImageViewerStateTests.swift`, `ChatMediaPreviewServicesTests.swift`, `GRDB/AccountDeletionLocalDataCleanupTests.swift`, `GRDB/GRDBChatDeletionSyncStoreTests.swift`. 원본 lease 전용 fake/barrier 테스트는 후속 추가 대상.

표시 준비에서 변경한 파일 목록과 검증 이력은 `display-readiness-plan.md`, 구현 전체 상태는 git diff를 기준으로 한다. `docs/portfolio/`, `firestore-debug.log`, 기존 HANDOFF 내용은 사용자 자료로 보존. 임의 커밋·force-add·서버 배포 없음.

## 5. 구조·이유·트레이드오프

- MVVM-C/Repository/UseCase/DI 유지. Container가 원본 store/service를 공유 조립하고 Coordinator가 화면 전환을 담당. View에서 저장소/SDK 직접 생성 금지.
- 표시 이미지와 원본 파일을 분리해 원본 다운로드/보관이 버블 표시 캐시를 밀어내지 않도록 한다. 파일 lease로 사용 중 파일 보호와 퇴거를 분리한다. 공용 pipeline API 및 DI 의존이 겹치므로 순차 구현.
- 먼 준비/직접 decode/IO 제한 해제는 사용자 확정. 순간 CPU·임시 디코딩 메모리 증가는 캐시1GiB와 별개이며, 실제 버벅임/발열/크래시가 생기면 QA로 재조정한다. 임의로 기존2로 복원하지 않는다.
- 저장은 파일 원본 보존을 우선하며 표시 이미지 fallback 저장은 채택하지 않는다. 즉시 영상 재생을 유지하되 스트리밍 전체 바이트 캐시 병합은 추가 설계로 보류한다.

## 6. 재확인 필요와 금지 사항

- Phase3 서비스 이름/API/기본 예산·기존 원본 캐시 실제 형식·합산 migration 예산은 착수 시 코드로 확인. 현재 문서만으로 이미 구현됐다고 간주하지 않는다.
- 공용 뷰어 initializer/adapter, 현재 GIF Data 경로, Photos 저장 취소 경계, 영상 스트리밍과 저장 소비자 연결은 재확인 필요. Apple API의 취소 가능성은 필요한 공식 문서 확인.
- 기존 캐시 전체 삭제/새 다운로드 표본 강제 생성은 승인하지 않았다. 사용자는 기존 캐시 유지 QA를 선택했다. 서버 메시지·파일 생성/삭제 또는 전송 금지. read-only 및 독립 fake 테스트 우선.
- 원시 기기 로그에는 AppCheck 등 비밀 값이 포함될 수 있어 통째로 출력 금지. `[ImageBaseline]`/`[MediaQA]` 안전한 집계만 출력. 원문 URL·계정/메시지 ID 대신 hash.
- 이전 실행 세션은 현재 살아 있다고 가정하지 않는다. 최종 앱은 실행 인자 없는 일반 DEV이며 녹화는 모두 종료·저장됨.

## 7. 다음 스레드의 첫 실행 순서

1. HANDOFF 상단 → 이 문서 → 기존 계획 Phase3~5 → ENTRYPOINTS/CHAT/TESTS 필요한 항목, git status 확인. 사용자 “진행” 요청이 있는 경우 구현 재개, 정리 요청만 있으면 멈춤.
2. 위 원본/저장/영상/삭제 진입점만 읽어 실제 호출 지도와 변경 파일·테스트 계획 확정. 이미 합의한 제품 정책을 다시 질문하지 말고, 기존 동작·계정 보존 변경이 필요할 때만 해당 부분 논의.
3. Phase3 파일 store/lease/병합·취소·세대 검증부터 구현하고 Phase4 연결은 그 결과에 이어 순차 진행. fake transport/barrier로 공유 소비자, 마지막 취소, 늦은 성공, 핀/퇴거, 용량 초과, 계정/삭제 세대 검증. 기존 공유 캐시 회귀 포함.
4. Phase4 저장 권한/실패/닫기·빠른 페이지 이동·GIF 활성 수명 검증 후 실기기 사진 ±1/GIF/영상/원본 저장 QA. 완료된 대량 버블 스크롤은 영향이 생긴 경우 회귀 확인하며 처음부터 다시 조사하지 않는다.

기기: CoreDevice `A7B8FA1C-C7FF-556C-977E-9E8CE2F5BC84`, UDID `00008110-000168693E91401E`, bundle `GayoonKim.OutPick.dev`, scheme `OutPick-Development`. Simulator `05397E0E-7170-4B48-A8D2-D60A5B8865FC`.
DerivedData: simulator `/private/tmp/outpick-avatar-device`, device `/private/tmp/outpick-firebase-12.17-device`. 실행 전 연결/잠금은 재확인.

검증 명령 형태:
```sh
xcodebuild -project OutPick.xcodeproj -scheme OutPick-Development -destination 'platform=iOS Simulator,id=05397E0E-7170-4B48-A8D2-D60A5B8865FC' -derivedDataPath /private/tmp/outpick-avatar-device -parallel-testing-enabled NO -only-testing:OutPickTests/<대상Suite> test
xcodebuild -project OutPick.xcodeproj -scheme OutPick-Development -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/outpick-firebase-12.17-device build
```

테스트/빌드 로그는 `/private/tmp` 별도 파일로 리다이렉트한다. 문서·코드 진입점·테스트 계약 갱신을 각 Phase 완료 기준에 포함한다.
