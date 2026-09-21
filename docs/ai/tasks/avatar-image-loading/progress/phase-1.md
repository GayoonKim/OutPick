# Phase 1 — 공용 비저장·디스크 승격 구현

2026-09-18. 공용 기반 구현·자동 회귀 완료. 아바타 서비스/화면 연결은 다음 phase.

## 구현

- ImageCacheStorePolicy.transient/ImageRequest.Work.transient: 메모리·디스크 조회/저장을 생략하고 기존 processor/resources·소비자 취소 사용. transient끼리 합류하고 cacheable과 identity 분리.
- ImageLoadCoordinator.cachedMemoryImage: 메모리 hit 즉시 반환, encoder 주입 pipeline만 백그라운드 승격. 경로별 단일 작업, 진행 중 persistence 수렴 및 기존 disk 존재 확인 후 필요한 경우만 변환.
- 신규 ImageCachePromotionEncoding: 형식 주입·출력 최대 바이트. writeBytes 예약→decode gate 인코딩→disk I/O. 실패/취소 예약 반환.
- remove/store/전체 clear는 승격 취소·세대 변경. 늦은 변환 결과 저장 차단 및 payload 반환.
- 기존 서비스에는 encoder를 주입하지 않아 기본 동작 유지. 테스트 PNG fixture는 제품 형식 채택이 아니다.

## 파일·경계

OutPick/Infra/Cache/ImageCache/{ImageCachePipeline,ImageRequest,ImageLoadCoordinator}.swift, 신규 ImageCachePromotionEncoding.swift, 신규 OutPickTests/ImageCacheStorePolicyTests.swift.

DI/Container/화면/서버 변경 없음. Phase2 이후 서비스 연결 필요. 썸네일3MiB는 합의됐지만 기존2/3/5MiB 호출은 아직 교체하지 않았다.

## 검증

- Development Simulator build-for-testing 성공: `/private/tmp/outpick-avatar-phase1-build.log`.
- 추가 테스트 첫 실행은 테스트 target 최소 iOS 버전의 ContinuousClock 사용 불가로 컴파일 실패. Date deadline으로 수정 후 동일 suite 재실행 중.
- 명령: `xcodebuild -project OutPick.xcodeproj -scheme OutPick-Development -destination 'platform=iOS Simulator,id=05397E0E-7170-4B48-A8D2-D60A5B8865FC' -derivedDataPath /private/tmp/outpick-avatar-build -parallel-testing-enabled NO -only-testing:OutPickTests/ImageCacheStorePolicyTests -only-testing:OutPickTests/ImageLoadCoordinatorTests -only-testing:OutPickTests/ImageCacheRevisionTests -only-testing:OutPickTests/ImagePipelineResourcesTests -only-testing:OutPickTests/LookbookHTTPImageCacheTests -only-testing:OutPickTests/LookbookViewportPrefetchTests test`.
- 첫 회귀49개/6suite 통과 후 원본 임시 파일 성공·실패 정리 테스트를 추가했다. 최종 **50개/6suite 통과**, `TEST SUCCEEDED`: `/private/tmp/outpick-avatar-phase1-tests-verified.log`.
- 신규 ImageCacheStorePolicyTests는12개 테스트 메서드(인자별14시나리오)를 포함한다. 최종 결과 bundle: `/private/tmp/outpick-avatar-build/Logs/Test/Test-OutPick-Development-2026.09.18_21-25-10-+0900.xcresult`.
- git diff --check 통과. 서버 배포·기기 설치·실기기 QA·커밋 없음.

## 한계·다음

화면별 정책·원본 provider·로그아웃 연결은 미구현. 실제 JPEG/PNG 비교·3MiB 기존 자료 QA 미수행. 원본도 현 processor의 Data/파일 예약을 사용한다. 출력 예산이 UIImage 픽셀 메모리나 인코딩 임시 할당까지 완전히 제한하는 것은 아니다. 비교 후 encoder 선택/서비스 조립으로 이어간다.
