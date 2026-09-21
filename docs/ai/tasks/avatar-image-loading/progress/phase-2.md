# Phase 2 — 아바타 서비스·정책·세션

## 범위와 구현

- `AvatarImageRequest`가 썸네일3MiB/원본20MiB와 memoryOnly/memoryAndDisk/transient를 구분한다. 기존 화면의 maxBytes 인자는 호환을 위해 남지만 실제 썸네일 한도는 서비스에서3MiB로 통일한다.
- AppCompositionRoot의 단일 AvatarImageService와 ScopedAvatarImageManager를 사용한다. 댓글/답글 memoryOnly, MyPage memoryAndDisk, ChatContainer는 요청 시 JoinedRoomsSessionStore.contains(roomID)로 참여 여부를 확인한다. 방 목록의 마지막 발신자도 행별 정책 factory를 사용한다. 다른 사용자 상세는 출발 화면의 manager를 전달받는다.
- disk100/75MiB 유지. 메모리 hit도 persistent 정책이면 백그라운드 승격하며 cache-only hit 경로도 승격한다. 표본 비교 후 JPEG0.8 encoder를 앱 DI에서 주입한다.
- 원본은 명시 API로 transient 요청한다. UserProfileDetailViewController의 기존 일반 표시 원본 업그레이드를 제거하고 viewer provider를 명시 원본 API로 연결했다. 화면 전체 수명·재시도 개선은 Phase3/4 잔여다.
- AvatarImageSessionController가 요청 입장/취소/완료 세대, 마지막 authoritative profile, 제거 경로를 소유한다. 사진 제거는 seed fallback 대신 nil을 수락한다. 이전 updatedAt 및 제거한 경로를 되살리는 무시각 snapshot은 거부한다.
- AvatarObservingPublicProfileRepository는 기존 서버 조회 결과만 관찰한다. 새 listener/추가 조회 없음. batch 누락은 사진 삭제가 아니다. UpdatePublicProfileUseCase는 서버 변경 성공 후 이전 경로를 무효화하고 실패 시 기존 캐시를 유지한다.
- 로그아웃·계정 변경은 이전 요청 차단과 취소→캐시 정리→새 세션 입장 순서다. AppCoordinator는 이전 reset을 취소하지 않고 기다린다. AccountDeletionLocalDataScrubber도 서비스 세션부터 종료한다. 동일 계정 앱 재실행은 소유자 marker를 비교해 디스크를 유지하며, marker가 없거나 다른 계정이면 지운다.
- 로컬 아바타 파일은 공용 decode/I/O gate를 통과하며 디스크 캐시로 복사하지 않는다.

## 실제 사진 저장 형식 비교

사용자가 선택하고 동일 사진임을 확인한 OutPick-DEV 본인 프로필 썸네일(지하철/LMC 사진)을 iPhone14 앱 캐시에서 읽었다. 원본 파일 JPEG33,082bytes,500×259px. 파일은 `/private/tmp`에만 두며 repo에 넣지 않는다.

UIKit Simulator에서 동일 UIImage를30회 인코딩한 중앙값이다. 기기 CPU 측정값이 아니며 단일 사진 결과를 모든 사진에 일반화하지 않는다.

| 형식 | bytes | 중앙 인코딩ms | 기존 디코딩 픽셀 대비 PSNR |
| --- | ---: | ---: | ---: |
| PNG | 211,022 | 7.17 | 무손실 |
| JPEG0.8 | 33,006 | 1.31 | 49.31dB |
| JPEG0.9 | 38,669 | 1.17 | 48.83dB |

JPEG0.8은 PNG보다84.4% 작고 기존 업로드 형식과 같다. 실제 크기로 확인한 이미지에서 눈에 띄는 차이를 찾지 못해 시작값으로 적용했다. JPEG0.9가 이 표본에서 더 정확하지 않은 것은 JPEG0.8로 이미 압축된 사진의 재인코딩 비교라는 한계와 함께 해석한다. 확대 원본에는 이 재인코딩을 적용하지 않는다. 임시 비교 테스트는 측정 후 삭제했다.

## 검증

- 첫 앱/전체 테스트 target `build-for-testing` 통과: `/private/tmp/outpick-avatar-phase2-build.log`.
- 초기39개/8suite 중38개 통과, 로컬 파일 테스트의 renderer 기본 배율 때문에 크기1개 실패. fixture scale=1로 보정했다. 비교 측정 로그: `/private/tmp/outpick-avatar-phase2-tests.log`.
- 최종48개/10suite 전부 통과(`TEST SUCCEEDED`): `/private/tmp/outpick-avatar-phase2-verified-tests.log`. 앱/전체 테스트 target 컴파일 포함. `git diff --check` 통과.
- 추가 테스트: AvatarImageServiceTests(정책 공유/승격·원본 비저장·로그아웃·제거·로컬), AvatarImageSessionTests(늦은 성공/실패·정리 직렬화·삭제·세션 token·동일 계정 재실행), AvatarObservingPublicProfileRepositoryTests(이전 세션 결과·batch 누락). UpdatePublicProfileUseCaseTests에 성공 관찰/실패 미관찰 추가.

## 남은 범위

Phase3 각 화면 동일 입력 유지·재사용/이탈 취소·늦은 UI 결과 차단·viewer 해제, Phase4 viewport/표시 계기 재시도, Phase5 실제 스크롤/메모리/시각 QA는 미완료다. 이번 작업으로 기기 앱 설치·서버 변경·커밋·PR은 하지 않았다. 기기 작업은 사용자가 지정한 사진 읽기만 수행했다.
