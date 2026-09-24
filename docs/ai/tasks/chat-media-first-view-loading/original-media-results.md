# ③ Phase3·4 원본 파일 수명 구현 — 2026-09-24

## 확정 결정과 범위

- **7일 만료 후속 정책 확정:** 기준은 메시지 전송 시각+7일이다. 처음 열어 다운로드한 시각·재다운로드·재로그인은 기한을 연장하지 않는다. Storage 썸네일/원본과 앱 디스크/메모리 모두 동일 만료시각을 따르며, 앱 미실행 중 로컬 물리 삭제는 다음 실행/복귀 때 수행하고 만료 데이터 표시는 차단한다. 사진 앱에 명시 저장한 사본은 제외. 아직 구현 전이며 이번 계정 재사용 QA 통과가 만료 구현 완료를 뜻하지 않는다.

## 계정 재사용 검증 진행 — 2026-09-24

- **다른 계정 왕복 통과:** 사용자 B에서 A 사진 오표시 없음/A복귀 완료 확인. 동일 resource hash `f96855bfa537`가 B에서는 miss→다운로드1875.58ms, A복귀에서는 hit→이미지할당101.02ms. A복귀 인접2장도hit, 재다운로드0. B의 인접2요청은 이탈 시 cancelled로 끝났으며 성공으로 세지 않는다.
- 전후 기기 파일 목록 비교: A namespace80개/162,015,749bytes 그대로 보존, B namespace1개/1,951,642bytes 별도 생성, 원본 temporary0. `/private/tmp/outpick-original-account-a-files.json`, `/private/tmp/outpick-original-account-b-roundtrip-files.json`. 실제 파일 내용/사용자 ID는 수집하지 않았다. 계정분리/재로그인·왕복재사용 실기기 완료.
- 검증 종료 후 일반 실행 복원 console37215 `/private/tmp/outpick-original-account-normal-console.log`, baseline 환경 해제. 7일 만료는 아직 미구현 후속이다.

- 같은 계정 재로그인 사용자 완료 확인. baseline 로그에서 전후 동일 현재사진 hash `f96855bfa537` 및 인접2장 모두 cache hit, 원본 download 이벤트0. 현재 사진 파일 확보12.58→11.52ms, 이미지 할당174.00→99.11ms. 실사용자 로그인 왕복 확인과 로그를 결합한 원본 캐시 재사용 통과이며 이 로그 자체에 계정 신원은 기록하지 않는다. 다음 다른 계정 왕복 실기기 QA.

- store 자동10개 모두 통과(`/private/tmp/outpick-original-account-tests.log`). 실제 로그인 왕복 QA는 사용자 응답 대기, 자동 결과로 실기기 완료를 대체하지 않는다.

- `AppCoordinator.showLogin`에서 기존 ChatContainer 세션 무효화 후 해제, `ensureChatContainer`에서 계정 ID 불일치 시 무효화/재조립, `ChatContainer.invalidateMessageCacheSession`→originalFiles.invalidateSession 연결 확인. 이 경로는 원본 디스크 삭제를 호출하지 않는다.
- 기존 `ChatOriginalFileStoreTests`의 로그아웃 늦은 성공 차단·같은 계정 cache hit·다른 계정 miss·디스크 재시작 회귀를 재실행한다. `/private/tmp/outpick-original-account-tests.log`.
- 실기기 baseline 실행 console70763 `/private/tmp/outpick-original-account-console.log`. 먼저 같은 사진 확대→로그아웃→같은 계정 로그인→동일 사진 확대의 hash/cache hit/download 여부 비교. 이후 다른 계정 왕복. 사용자 로그인은 직접 수행, 캐시 삭제/탈퇴 실행 없음.

- 사용자 확정: 원본은 계정별 보관하고 같은 계정 재로그인 시 재사용한다. 로그아웃/전환은 세션과 진행 요청을 무효화한다. 기존 계정 탈퇴의 기기 전체 캐시 scrub 정책은 유지한다.
- 새 원본 namespace `Caches/ChatOriginalFiles/v1/cache/{accountHash}/{resourceHash}.{versionHash}.{ext}`. 전체 계정 합산 QA 기본 512MiB, 접근 시각 기반 LRU, 사용 중 pin은 퇴거 제외. 단일 초과/모두 pin 상태는 임시 사용 후 마지막 lease에서 삭제한다.
- 표시 캐시 1GiB/1GiB와 준비 제한 해제는 유지. 기존 `ChatImageCache`/`Videos`를 원본으로 자동 승격하지 않는다. 계정 소유권 불명인 구 영상과 축소 JPEG 혼합 이미지 캐시를 무검증 재사용하지 않기 때문이다. 기존 폴더는 임의 삭제하지 않으며 새로운 영상 detached 채우기를 제거해 중복 증가를 막는다. `store.usage()`는 새 cache/temporary/legacy 합산 바이트를 조회한다. 이 합계는 실기기에서 아직 측정하지 않았다.
- 버전 기본값은 현재 불변 첨부 경로를 사용하는 `path-v1`; API는 별도 version도 지원한다. 기존 metadata/서버 계약 변경 없음. 7일 서버 및 로컬 만료는 별도 미구현 후속이다.

## Phase3 — 구현

- `ChatOriginalFile.swift`: resource/purpose, 계정 고정 service, 즉시 세션 무효화, 명시 release/deinit lease. 저장소 전체 세대는 탈퇴 후 오래된 service의 새 요청도 차단한다.
- `ChatOriginalFileStore.swift`: 계정/path/version 전송 합류, 소비자별 취소, 마지막 소비자 취소 시 SDK task 취소. 취소 중 새 수요는 별도 UUID 임시 파일을 사용한다. 이전 SDK callback 전 network/files permit 및 임시 파일은 회수하지 않는다. 인접 수요에 현재/저장 수요가 합류하면 gate 우선순위를 올린다.
- `ChatOriginalFileDisk.swift`: 원본만 별도 namespace에서 보관/스캔/접근 시각 관리. 프로세스 재시작 때 이 namespace의 고아 임시 파일만 정리한다.
- `FirebaseChatOriginalFileTransport`: 기존 Firebase 파일 완료·취소 adapter 재사용. 로컬/outbox 원본은 복사하며 원본 파일을 이동·삭제하지 않는다. 직접 HTTP URL은 파일 다운로드·상태코드/크기 검증 후 인계한다.
- `ChatContainer`가 동일 scoped service를 삭제 cleaner/뷰어/영상에 주입한다. 기존 `invalidateMessageCacheSession`이 원본 세션도 무효화한다. `AppCoordinator.ensureChatContainer`는 계정이 달라졌으면 이전 container를 무효화하고 재조립한다. `AccountDeletionLocalDataScrubber`는 새 store 전체 세대와 파일을 무효화한다.
- 자동 첫 10개 통과: `/private/tmp/outpick-original-phase3-tests.log`. 이후 세대 보강은 아래 최종 회귀로 별도 검증한다.

## Phase4 — 구현

- `ImageViewerOriginalPolicy`는 현재±1 중 정적 인접 사진만 포함한다. 원래 첨부 위치를 전달해 사진 전용 페이지에서 빠진 영상 첨부도 건너뛰지 않는다.
- `SimpleImageViewerVC`의 주입된 원본 모드만 새 정책 사용. 기존 아바타/룩북 adapter는 유지한다. 범위 밖 요청/lease/원본 이미지 해제, GIF 현재 페이지에서만 요청·프레임 재생. 파일에서 정적 이미지는 확대 표시 QA 상한 4096px로 decode하며 저장 파일은 변환하지 않는다. GIF는 mapped file Data와 기존 lazy frame loader 사용.
- 사진 저장은 독립 저장 소비자→원본 lease→Photos 파일 제출. 저장 도중 닫기 취소, 세대 확인, 후속 UI 차단. 실패 시 다시 저장 가능하고 thumbnail/현재 UIImage로 fallback하지 않는다.
- `DefaultChatVideoPlaybackResolver`는 scoped original cache hit만 파일 lease로 재사용한다. miss는 URL만 반환하고 detached 전체 다운로드는 시작하지 않는다. 명시적 저장은 원본 service에 합류한다. 두 영상 VC는 닫기 시 player/저장 task/lease 해제와 늦은 안내 차단을 수행한다.
- 설정 갤러리에도 같은 service를 Coordinator→CompositionRoot→설정→갤러리로 주입한다. 원본 없는 항목은 thumbnail을 원본으로 승격하지 않는다.
- PhotoKit는 `addResource(with:fileURL:options:)`에 원본을 전달하고 `shouldMoveFile=false`. 권한 응답 뒤/제출 직전/change block 내부 취소·lease 세대 검사. 이미 제출한 작업을 되돌리는 보장은 하지 않으며 callback까지 lease를 유지한다.

Apple 공식 확인(2026-09-24): [파일 resource 추가](https://developer.apple.com/documentation/photos/phassetcreationrequest/addresource%28with%3Afileurl%3Aoptions%3A%29), [performChanges 완료 경계](https://developer.apple.com/documentation/photos/phphotolibrary/performchanges%28_%3Acompletionhandler%3A%29). 기존 addOnly 권한과 사용자 저장 버튼 계기를 유지한다. 서버/개인정보 수집 항목/권한 범위 추가 없음.

## 검증 상태와 남은 QA

### 영상 저장 중 닫기 자동 검증 완료

- `VideoSaveLifetimeTests`에서 두 실제 UIViewController를 UIWindow에 present/dismiss하며 지연 resolver/saver로 준비 중 닫기·제출 후 성공·제출 후 실패 각3개, 총6개 통과. `/private/tmp/outpick-video-lifetime-tests.log`.
- 준비 후 늦게 반환된 lease는 해제되고 saver 호출0. 제출 후 닫기는 callback 전 저장용 파일 유지, callback 후 파일 제거·lease1회 해제. 두 경로 모두 늦은 결과 토스트/alert 없음, AVPlayer 해제·재생용 링크 삭제·원본 bytes 보존 확인.
- 제품 코드 수정 없이 테스트만 추가했다. Photos 자체의 취소를 보장하는 검증이 아니며 fake 완료 경계로 화면/파일 수명 계약을 검증했다. 실제 사진/서버 자료 사용 없음. 추가 실기기 설치는 불필요. 다음 계정 전환·같은 계정 재로그인 수동 QA(기존 store 자동 회귀는 통과 상태).

### 영상 저장 실패 보완

- 사용자 요청으로 영상 저장 완료/실패 결과를 사진과 같은 하단 토스트로 통일했다. `MediaSaveToast`를 두 영상 VC에서 사용하며 “저장 완료”/“저장 실패”만 표시, 중앙 결과 alert/영어 기술 오류 제거. 표시 변경으로 새 자동 테스트 없이 기기 build·사용자 시각 QA를 수행한다. 저장 중 진행 표시/비동기 취소 계약은 유지.

- 캐시 재생 보완 검증: 실제 합성 JPEG/MP4/MOV3개+resolver8개 총11개 통과(`/private/tmp/outpick-video-playback-tests.log`). MP4/MOV는 AVURLAsset.isPlayable/Photos 저장/링크 해제·원본 바이트 보존 확인. 기기 build 성공(`/private/tmp/outpick-video-playback-build.log`). 실제 기기 화면/소리 성공은 사용자 확인 대기.

- 후속 사용자: 수정본에서 같은 영상 재생 불가 보고. 저장용 사본만 보완하고 `DefaultChatVideoPlaybackResolver` cache hit가 bin을 AVPlayer에 직접 넘기는 경로 누락 확인. 캐시 재생에는 실제 확장자 hardlink(실패 시 copy)를 제공하고 wrapper lease가 링크/원본 pin을 함께 유지·해제하도록 수정. 저장 sourcePath는 원본 유지. 합성 MP4/MOV AVURLAsset.isPlayable+Photos 저장+해제 후 원본 바이트 보존 및 resolver 회귀 검증 중. 실제 기기 재생 성공은 재확인 필요.

- 수정 후 실제 JPEG/MP4/MOV Photos 통합3개(skip 없음)+형식/바이트 회귀6개, 총9개 통과(`/private/tmp/outpick-video-save-green.log`). 기기 build 성공(`/private/tmp/outpick-video-save-build.log`), diff check 통과. Simulator 합성 영상에는 소리가 없으므로 실제 저장본 소리는 사용자 기기 QA가 필요하다.

- 사용자 영상 재생은 잠깐 지연 뒤 시작, 저장 실패 보고. 실기기 기존 로그 오류 코드 없음. 영상 분기는 사진과 달리 형식·확장자 보완을 건너뛰고 있었다. 합성 MP4 `.bin` 실제 Simulator Photos 저장에서3302 재현(`/private/tmp/outpick-video-save-red.log`).
- `PhotoLibraryOriginalResource.videoType`가 최상위 atom 최대128개를 헤더/seek로 읽고 ftyp major brand에서 QuickTime/MP4를 구분한다. 본문 decode/재인코딩 없음. 구형 ftyp 없는 기존 mov/mp4/m4v 확장자는 Photos 검증에 맡기며 알 수 없는 bin은 거부한다. Photos 완료까지 실제 확장자 사본을 유지하고 정리한다. 실제 MP4/MOV 통합 및 바이트 보존 회귀 검증 진행.
- 형식 근거: [Apple ftyp 문서](https://developer.apple.com/documentation/quicktime-file-format/file_type_compatibility_atom). 실기기 사용자 저장 성공은 아직 미확인, 재생 지연 개선은 이번 수정 범위 아님.

### 현재 우선 실기기 순서 확인 및 다음 QA

- 사용자 기존 GIF 확대 애니메이션·저장·사진 앱 저장본 애니메이션 확인 완료. GIF 실기기 QA 통과(사용자 확인 기준). 다음 기존 영상 재생 시작·Photos 저장 및 저장본 재생 확인.

- 사용자 로딩 문구 변경 확인 완료. `/private/tmp/outpick-original-current-first-console.log` 성공 다운로드20건 중 시작 역할 current이고 cache miss인3건을 분리했다. 약0.24/1.13/1.15MB, 다운로드1017.4/1088.0/1011.1ms, 이미지 할당1056.1/1163.9/1080.9ms. 각 현재 다운로드 종료 후 약8~9ms 뒤 인접 두 요청이 시작됐으며 현재 decode와 겹쳤다. 확정한 현재 파일 우선 순서 실기기 확인.
- 이전 1.95MB 표본과 파일/네트워크 조건이 달라 속도 개선율 단정 불가. adjacent 역할은 요청 시작 당시 기준이며 페이지 이동 후 current가 될 수 있으므로 current 다운로드3건을 모든 실제 페이지 대기 횟수로 해석하지 않는다. 취소된 전송은 성공 표본에서 제외.
- 일반 실행 복원 완료(`/private/tmp/outpick-original-loading-ui-console.log`, console70079). 다음 사용자 기존 GIF 재생·Photos 저장/애니메이션 확인 → 영상 스트리밍·저장 → 저장 중 닫기 → 계정 왕복 순서. 서버 fixture/캐시 전체 삭제 없음.

- 사용자 승인 로딩 UX 변경: 사진이 보이는 동안 “불러오는 중…” 문구 제거. `renderLoadStatus`는 실패 시 재시도만 노출하고 이미지 없는 로딩의 spinner 유지. 저장 상태 안내 유지. 두 줄의 표시 조건 변경으로 새 자동 테스트는 추가하지 않고 기기 build/수동 QA로 검증한다. 현재 원본 우선 다운로드 정책 유지.

### 첫 로딩 실측 — 2026-09-24

- 현재 우선 수정 후 뷰어7개 테스트 통과(`/private/tmp/outpick-original-current-first-tests.log`), 기기 build 성공(`/private/tmp/outpick-original-current-first-build.log`). 실제 시간 비교는 다른 미확대 사진 표본이므로 파일 크기/네트워크 차이를 고려해야 하며 동일 조건 A/B 성능 개선을 단정하지 않는다.

- 현재 우선 구현: viewer 현재 lease 확보 여부로 인접 신규 요청을 제한하고 acquire 완료에서 인접 요청을 시작한다. 페이지 이동 시 미확보 다른 페이지 요청 취소, 확보한 파일/진행 decode 유지. 진행 중 인접이 현재가 되면 해당 전송은 이어받는다. fake를 지연시켜 현재 완료 전 인접0/전환 후 이전 완료 무시/현재 완료 후 양옆2 동시 요청/닫기 후 인접0을 검증한다. `/private/tmp/outpick-original-current-first-{tests,build}.log` 검증 진행.

- **사용자 확정:** 현재 사진의 원본 파일을 먼저 확보한 뒤 인접 정적 사진 다운로드를 시작한다. 구현 승인된 다음 작업이며 아직 코드에는 기존 동시 요청 방식이 남아 있다. 인접 두 장끼리는 병렬, 공용 다운로드6개 제한·동일 파일 요청 병합·계정/lease 수명은 유지한다. 완료 경계는 현재 파일 확보이며 디코딩 완료까지 기다릴 필요는 없다.

- `/private/tmp/outpick-original-latency-console.log`에서 성공 다운로드3건(현재1/인접2), 중단된 인접1건을 구분했다. 기존 캐시 hit는 신규 다운로드 표본에서 제외했다.
- 현재 사진 약1.95MB: 다운로드1918.59ms, viewer 이미지 할당까지2017.06ms. 같은 key 재열기98.48ms(캐시 hit). 인접 약2.69MB/1.30MB는 다운로드2655.05/2871.87ms, 이미지 할당2906.23/2936.69ms. file gate0.14~0.76ms, network gate0.11~0.41ms로 앱 gate 대기는 주요 병목이 아니었다.
- 세 원본을 동시에 받았으므로 인접 선로딩의 네트워크 경합 가능성은 있으나 인과는 미확정. 다운로드 시간에는 SDK/네트워크/파일쓰기 구간이 포함되며 서버 응답과 순수 전송은 아직 분리하지 않았다. 실제 프레임 표시 완료 시간도 아니다.
- 다음 선택: 현재 사진 확보 후 인접 다운로드 시작(A: 첫 사진 우선, 즉시 페이지 이동 불리 가능) 또는 기존 현재±1 동시 유지(B: 페이지 이동 우선). A 추천을 사용자와 논의 후 결정하며 아직 정책 코드는 변경하지 않았다. 계측 종료 후 환경변수 없는 일반 실행으로 복원.

### 첫 실기기 피드백과 저장 보완

- **최신 사용자 확인:** 두 번째 수정본에서 사진 저장 완료를 확인했다. 사진 저장 실패 QA는 해결 확인. 사용자가 다음 원본 첫 로딩 속도 조사 진행 승인.
- 첫 로딩 계측: 기존 `ImageCacheMetrics`에 원본 cache/합류/gate/download/bytes 및 viewer/acquire/decode 구간 연결. 개인정보 원문 없이 해시 key 사용. 계측만 추가하므로 동작을 복제하는 새 테스트는 작성하지 않으며 실기기 빌드와 미확대 사진 수동 QA를 수행한다. 아직 병목·개선 수치는 미확정.

- **최신 재현:** 형식 옵션만 전달한 첫 수정도 사용자 사진 전체 실패. 기기 DEBUG 로그에서 `PHPhotosErrorDomain/3302`, cancelled=false 10회 확인. Simulator 합성 JPEG `.bin`을 실제 `DefaultPhotoLibrarySaver`→Photos에 제출해 동일3302를 재현했다(`/private/tmp/outpick-original-photos-reproduction.log`). 앞선 helper 테스트19개 성공은 Photos 실제 저장 성공 근거가 아니었다.
- 두 번째 보완: `PhotoLibraryPreparedResource`가 실제 형식 확장자를 가진 고유 임시 사본을 만들고 Photos callback까지 보관·완료/오류/취소 후 정리한다. 캐시 파일 이동/재인코딩 없음. 실제 Photos 통합 및 사본 수명 회귀21개(XCTest16+Swift Testing5) 통과(`/private/tmp/outpick-original-photos-staged-tests.log`), 기기 build 성공(`/private/tmp/outpick-original-photos-staged-device-build.log`). 실제 Photos 통합1개는 skip 없이 성공했으며 Simulator의 합성 16px 이미지로만 실행했다. 사용자 기기 사진/서버 자료를 테스트 fixture로 사용하지 않았다. 실기기 저장 성공은 사용자 재확인 대기.

- 사용자: 사진 확대/빠른 왕복은 최초 원본 준비 때 지연이 있으나 완료하면 로딩 표시가 사라지고 화질 정상. 같은 사진 재열기는 로딩 표시 없이 즉시 표시됨. 캐시 재사용 체감 정상으로 확인했으며 최초 다운로드/디코딩 시간은 분리 실측하지 않았다.
- 사진 저장은 사용자 보고상 모두 실패. 당시 로그에는 Photos 오류 코드가 없었다. 실제 캐시4개 모두 `.bin`인데 Photos에 파일 실제 타입을 지정하지 않는 결함을 확인했다. 이것이 실기기 실패의 직접 원인인지는 수정본 저장 재검증으로 확정한다.
- `PhotoLibraryOriginalResource.creationOptions` 추가: ImageIO로 실제 JPEG/PNG/GIF 타입을 읽어 iOS26 `contentType`/이전 `uniformTypeIdentifier` 및 올바른 원본 파일명 확장자를 전달한다. 캐시 파일 삭제/변환/재다운로드 없음. `.bin` JPEG·확장자 없는 2frame GIF·잘못된 JPEG 확장자의 PNG·잘못된 이미지 거부 회귀 추가.
- `SimpleImageViewerVC`는 DEBUG 저장 실패에 domain/code/cancelled만 `[MediaQA]`로 기록하며 원문 경로·사진·계정 정보는 출력하지 않는다. 권한 거부는 기존 권한 오류 문구로 구분한다.
- 근거: [Apple Photos resource 타입 지정](https://developer.apple.com/documentation/photos/phassetresourcecreationoptions). 타입 미지정 시 resource type/URL 확장자로 추론하므로 캐시 확장자만으로 실제 포맷을 가정하지 않는다.
- 보완 자동19개 통과(XCTest15+새 형식4), `/private/tmp/outpick-original-photo-type-tests.log`. 기기 build 성공(`/private/tmp/outpick-original-photo-type-device-build.log`). 기존83개와 중복 합산하지 않는다. 설치/실제 저장 재검증 진행 중.
- 수정본 업데이트 설치 success(`/private/tmp/outpick-original-photo-type-install.json`), 일반 실행 console65220 `/private/tmp/outpick-original-photo-type-console.log`. 같은 사진의 저장 재시도 사용자 확인 대기. 기존 캐시 유지.

- 첫 통합: 기존 XCTest10, 신규 뷰어 XCTest5 중4 성공/1 테스트 fixture 오류, SwiftTesting32 성공. 실패 원인은 테스트 경로의 Optional 문자열 보간이며 명시 Int로 수정했다. 최초 DI 주입 위치 오류도 빌드에서 발견해 수정했다. 최초 실행을 전체 통과로 세지 않는다.
- 최종 통합: **83개 통과**(XCTest15 + SwiftTesting68/9 suites), `/private/tmp/outpick-original-final-tests.log`, Simulator build/test 성공. `ChatRoomSettingViewModelTests` 필터는 해당 suite가 없어 실행 근거가 아니며 설정 DI/갤러리 원본 매핑은 코드 대조·빌드로 확인했다.
- Development 실기기 build 성공: `/private/tmp/outpick-original-device-build.log`, DerivedData `/private/tmp/outpick-firebase-12.17-device`. `git diff --check` 통과. 기기 조회 당시 iPhone14는 disconnected여서 설치/실행은 하지 않았고 사용자에게 연결·잠금 해제를 요청했다.
- 이후 사용자 연결·잠금 해제 완료 응답. iPhone14 DEV 업데이트 설치 success(`/private/tmp/outpick-original-install.json`), 일반 실행 및 main tab 진입 확인. 콘솔 `/private/tmp/outpick-original-device-console.log`, 세션96030. 실행 인자/진단 환경변수 없음, 기존 캐시/앱 데이터 보존. 사용자에게 사진 묶음 확대·빠른 왕복·재열기·사진 앱 저장 첫 QA를 요청했고 결과 대기 중이다.
- 첫 기기 원본 파일 관찰: cache4개/18,383,128bytes, temporary0. `/private/tmp/outpick-original-qa-start-files.json`. 사용자 조작이 시작된 뒤일 수 있어 캐시가 비어 있었다거나 선로딩 동시 범위를 이 관찰 하나로 판정하지 않는다. 원본 파일 내용은 읽지 않았고 목록/크기만 조회했다.
- `ChatOriginalFileStoreTests`: 공유 취소, 마지막 취소의 SDK 수명, 취소 중 재요청, 계정 격리/재로그인/늦은 성공, 삭제/version, pin/overflow/전체 계정 예산, 재시작, 실패 재시도, 탈퇴 scrub.
- `ImageViewerOriginalFileTests`: 실제 UIKit 뷰어 원본 저장·실패 재시도·닫기 전후 안내 차단, 인접/GIF/영상 경계, 실제 페이지 이동 요청 범위.
- `ChatMediaPreviewServicesTests`: 캐시 miss에서 스트리밍 URL 즉시 반환 및 다운로드0, 저장 시 lease 요청, scoped cached 파일 pin 재사용. 공용 cache/revision/resources, 기존 viewer/avatar 및 GRDB 삭제 회귀 통과. 실제 계정 탈퇴를 실행한 것은 아니다.
- 실기기: 사진 확대 화질·빠른 왕복·GIF 애니메이션·Photos 실제 사진/GIF/영상 저장·스트리밍 시작·닫기 수명·계정 왕복은 아직 미검증. 기존 캐시 전체 삭제/서버 fixture 생성·전송·삭제 없이 기존 미디어로 확인한다. 전체③ 완료 판정은 보류한다.
