# 표시 준비 개선 — 우선순위 변경

## 최종 QA — 직접 재실행 후 표시 준비 개선 완료

사용자가 수정 앱을 직접 재실행한 뒤 “완벽하게 이미 로딩되어 있는 것처럼 표시된다”고 확인. 이번 대상인 재실행 후 빠른 스크롤의 빈 이미지 표시 개선은 완료로 판정한다. 기본 제한 해제 적용, 자동26개 통과·기기 빌드/설치/일반 실행 성공을 근거로 한다. 이번 마지막 일반 실행에는 계측 옵션을 넣지 않았으므로 CPU/메모리/발열 수치를 새로 측정했다는 의미는 아니다. 모든 기기·모든 데이터량에서 즉시 표시를 보장하지 않으며, ③의 확대 원본·저장·파일 수명 후속 범위까지 완료한 것은 아니다.

## 최신 — 세 동시 제한 해제를 기본 동작으로 적용

검증 결과: 자동26개 통과(TEST SUCCEEDED), 기기 BUILD SUCCEEDED, 기존 캐시 유지 설치 완료, git diff --check 통과. 앱 코드에서 기존 실험 enum/환경변수 참조0 확인. 일반 실행·사용자 직접 재실행 QA 결과 대기. 별도 Release 빌드는 수행하지 않았으며 Release 적용은 무조건 조립 코드로 확인.

사용자 재확정 및 최종 검증 승인. ChatDiskPreparationExperiment 및 환경변수/DEBUG 분기 제거. ChatMediaViewportController의 준비 maxConcurrent:nil, ChatAttachmentImageService.remote의 bypassDirectDiskLimits:true를 모든 실행 구성에 직접 적용. 재실행 후에도 준비/직접 디코딩/읽기 게이트 상한 해제 유지. 네트워크·쓰기·다른 이미지 파이프라인·legacy 복구 경로, 메모리 LRU/압박 대응, 파일 보호·취소·병합은 기존 유지. DI/API/계정 보존 정책 변경 없음.

회귀 테스트는 실제 viewport 기본 조립에서 5개 동시 준비/전체 취소를 검증하도록 기존 테스트를 강화하고, 직접 디스크 게이트 우회·파일 보호 및 LRU 압박 대응을 함께 실행한다. `/private/tmp/outpick-unlimited-default-tests.log`, 기기 빌드 `/private/tmp/outpick-unlimited-default-build.log`. 완료 기준은 자동 회귀 통과·기기 설치 후 홈 아이콘으로 직접 재실행한 상태의 빠른 스크롤 체감 확인. 최종 실기기 결과는 대기.

## 최신 — 옵션 유지 재시작 QA에서 빈 이미지 미재현

에이전트가 앱 terminate-existing 후 계측/제한 해제 옵션을 주입해 실행. 세션13888, `/private/tmp/outpick-spinner-video2-device.log`, 녹화 `/private/tmp/outpick-spinner-qa2.mov` 저장. 사용자 빠른 스크롤 결과 빈 이미지 없음. 로그 unlimitedDiskPreparation=true, 실제 diskFile.decode completed339, cellCache hit834/miss0, 실제 사진 spinner 기록0. 따라서 이전 프로세스 메모리 재사용만으로 통과한 검증이 아니며 디스크에서 준비한 결과를 셀이 재사용함. 첫 metric 대비 willAppear43.558초, localMedia43.686초, firstPosition44.892초, 실제 decode 종료 범위43.771~45.841초. 초기 화면 배치 이후에도 일부 준비가 진행됨. 일반 실행과 제한 해제 실행 간 차이가 유력한 조사 대상이나 스크롤 시작 시점/경로가 통제되지 않아 단독 원인 확정은 하지 않는다. 직접 홈 아이콘 재실행 시 옵션이 사라지는 QA 조건 차이를 먼저 해소해야 하며, 이번에는 앱 코드/정책 변경 없음.

## 최신 — 실기기 녹화에서 빈 사진 묶음 확인, 재실행 조건 분리 필요

- QuickTime iPhone 화면 녹화 `/private/tmp/outpick-spinner-qa.mov` 저장. 추출 비교 `/private/tmp/outpick-placeholder-evidence.jpg`. 영상 37.3~37.4초에 사진 묶음 대부분이 `photo` placeholder로 보이고, 37.5~37.8초에 여러 칸이 순차적으로 실제 사진으로 채워짐. 이 장면은 회전 스피너가 아닌 셀의 빈 이미지 자리 표시임을 확인. 정확한 각 셀 지연은 아직 측정하지 않음.
- 영상 약26~30초에 사용자가 앱 전환기에서 앱을 종료하고 홈 화면에서 재실행. devicectl console 세션93412는 종료됨. 재실행에는 주입한 `OUTPICK_UNLIMITED_DISK_PREPARATION=1` 환경변수와 `-ImageLoadingBaseline` 실행 인자가 유지되지 않으므로, 이후 재현을 제한 해제 QA 결과로 해석하지 않는다. 해당 옵션은 코드상 일반 실행에서 false.
- `/private/tmp/outpick-spinner-video-device.log`의 cellCache hit328/miss0, 실제 spinner0은 종료 전 프로세스 기록이다. 종료 후 영상37초대 placeholder 장면에 이 집계를 대응시키면 안 된다. 첫 진입 공용 overlay는 기록상 약1.529초. 사진 묶음 현상과 구분한다.
- 확정: 빠른 스크롤에서 빈 묶음이 먼저 보이는 현상은 실제 존재. 미확정: 해당 장면에서 디코딩 미완료인지, 메모리 이미지의 셀 전달 지연인지. 다음 검증은 에이전트가 계측/제한 해제를 주입해 재시작하고 녹화한 뒤, 사용자는 앱 재시작 없이 방 진입·스크롤만 수행하여 동일 프로세스 영상과 로그를 확보한다. 동시 실행 수/캐시 정책/앱 코드는 이번 분석에서 변경하지 않음.

## 최신 — 실제 회전 표시 원인 추적 (정책 변경 없음)

재현1: 사용자가빠른스크롤중표시를보고멈췄다고보고. `/private/tmp/outpick-spinner-trace-device.log` seq정렬분석에서 actual chatPreview.spinner0/spinnerState0/loadingResolution0/loadingDelivery0, cellCache651모두hit, imageAssigned configure665/render6960. uploadConfirmation/latestJump0. 공용globalOverlay는진입시31.803~33.226(약1423ms)1회, 스크롤셀기록은이후35~39초에주로발생. 이결과는사용자가본표시를설명하지못하며현상부정/디스크병목/셀표시버그어느쪽도확정하지않는다. 표시위치(개별사진/묶음/화면전체)질문중. 추가정책수정없음. 이번재현과다른실행을섞어원인단정금지.

검증: XCTest11+SwiftTesting5=16개 통과, 기기 BUILD SUCCEEDED. 기존캐시유지설치후 `/private/tmp/outpick-spinner-trace-device.log` 실제스피너계측재현예정. 캐시/동시성수치추가변경없음,원인판정대기.

사용자 분석 진행 지시. 최근 `/private/tmp/outpick-media-entry-transition-device.log`에서도 cellCache hit389/miss0, presentation loading0, cellIdle retained377, 메모리퇴거/압박/네트워크0. 이는 회전 표시가 없었다는 증거가 아니다. 이전 계측은 로더 요청과 일부 셀캐시조회만 기록하여 사용자가 본 실제 indicator 시작과 동일이미지/동일시점을 연결하지 못했다. 원인 미확정.

- `ChatImagePreviewCell`의 실제 startAnimating 직전에 `chatPreview.spinner` span 시작(이미 회전 중이면 중복없음), represented thumbnail 경로를 hash key로 기록. `spinnerState`는 전달직전 캐시조회 결과 및inWindow/offWindow, parent로span연결. inWindow는 화면교차/실제프레임표시 증명이 아니다.
- imageAssigned(configure/render)→spinner 종료(image/configureImage/configureEmpty/idle/failed/reset/deinit)를같은span으로연결. 종료시간은UI상태변경시간이며GPU프레임완료시간아님.
- collection loadingResolution은imageAvailable/memoryMiss, loadingDelivery는cell/noCell. 기존메모리조회결과를사용해추가디스크읽기나우선순위변경없음. 셀 캐시 hit기록과 spinner키를연결하고파일준비/memory.store/cacheIdentity와대조한다.
- 다른표시도구분: chatSpinner.uploadConfirmation(전송확인회전), latestJump(최신이동), globalOverlay(공용화면로딩start/stop). globalOverlay는앱공용이므로채팅방이미지스피너라고간주하지않는다. 원본URL/메시지ID출력없음.
- 분석시멀티스레드출력순서가아닌seq/time으로정렬한다. 확인기준은실제spinner begin/end이며span key에대해준비완료/메모리조회/셀할당을연결한다. 캐시전체히트집계만으로표시버그확정금지.
- 자동검증: 실제loading중복호출에도span하나, image후loading에서스피너미시작, reset종료 및새경로독립span. 기존surface/metrics회귀 `/private/tmp/outpick-spinner-trace-tests.log`, 기기빌드 `/private/tmp/outpick-spinner-trace-device-build.log`. 기존캐시/제한해제 QA 조건유지, 성능수치나표시정책추가조정없음.

## 최신 — 전환 중 표시 활성화 및 이탈 시 픽셀 유지

자동25개 통과(TEST SUCCEEDED), 최종 cellIdle 계측포함 기기 BUILD SUCCEEDED. 기존 캐시·제한해제옵션 유지 설치 후 `/private/tmp/outpick-media-entry-transition-device.log`에서 전환/셀idle 확인 예정. 사용자 체감은 미검증.

사용자 추천안 진행 승인. 직전 `/private/tmp/outpick-local-early-media-device.log`는 cellCache hit540/miss0, chatPreview.presentation loading0, memoryImmediate1203, network0/pressure0였다. 사용자가 보는 loading 느낌을 새 다운로드/디코딩 대기라고 단정할 근거가 없다. 로컬힌트→서버렌더는 관측7회 약134~1150ms이며 전환 시작 계측이 없어 전환 이후 지연 전체로 해석하지 않는다.

코드상 기본 nav.pushViewController(animated:true)로 이미 오른쪽→왼쪽 전환을 사용한다. 바꾼점: mediaViewport 활성/bind/resume를viewWillAppear부터도 수행해 전환완료 전 표시 허용. 초기 snapshot 완료 콜백에서 즉시 layout→latest/read marker 위치→layout→viewport 갱신, 이후 기존 안정화 루프는 유지. chatEntry.willAppear/didAppear/firstPosition 계측으로 서버렌더와 전환구간 구분. 서버 확인 전에 표시하거나 모든 이미지 준비까지 진입을막지 않는다.

스크롤 이탈 idle은 작업취소이며 표시완료 UIImageView 픽셀을지우지않도록 ChatImagePreviewCell.render를변경했다. viewport entry/collection renderedImages 참조 해제는기존유지, UIKit이 보유한 셀의이미지는reuse/reset/remote경로변경에서해제한다. 이전 코드의idle즉시삭제가빈칸을만들수있는경로를제거한것이며사용자가본모든빈칸의원인확정은아니다. cellIdle retained/empty 추가. 캐시1GiB 외 셀 소유이미지의메모리는기기QA로함께본다.

검증: 기존continuity에image→loading→idle보존 및reuse해제추가, remote경로교체이전이미지차단/viewport취소/surface회귀. `/private/tmp/outpick-media-entry-transition-tests.log`, 기기빌드 `/private/tmp/outpick-media-entry-transition-device-build.log`. 전환자연스러움은기기QA필요. 제한해제 QA 조건과기존캐시는유지.

## 최신 — 로컬 메시지 확보 시점 준비 + 셀 최초 메모리 표시

자동 XCTest25+SwiftTesting19=44개 통과(`/private/tmp/outpick-local-early-media-tests.log`), 기기 BUILD SUCCEEDED. 설치 후 기존 제한 해제 QA 옵션을 유지한 `/private/tmp/outpick-local-early-media-device.log`에서 로컬 준비 이벤트/서버렌더/셀 hit를 구분한다. 사용자 체감 미검증.

사용자는 무제한 QA에서 확실히 빨라졌지만 진입 후 갑자기 채워지는 느낌과 빠른 스크롤 loading이 남는다고 보고했다. `/private/tmp/outpick-unlimited-disk-preparation-device.log`: 준비요청 최대339/실제 fileDecoder 최대6, 디스크 decode339/네트워크0/메모리압박0/퇴거0. phys_footprint peak175.25MiB, CPU peak463.60%(한코어100%기준), thermal0. 준비요청 수와 실제 CPU 동시 작업 수를 구분한다.

추가 확인: 온라인 초기 진입은 로컬 창을 읽어도 서버조회/삭제정합화/저장 후에만 replaceWindow 이벤트를 내보냈다. 기존 초기준비는 그 뒤 snapshot 직전이었다. 또 사진 셀 최초 configure는 버블 내부 renderedImages만 보며 공용 캐시 확인은 후속 viewport에서 진행됐다. 두 지점을 함께 개선한다.

- UseCase `ChatInitialLoadEvent.prepareLocalMedia(localWindow)`를 온라인 참여방의 로컬조회 직후/서버창조회 전에 yield. VM은 기존 세대/취소검사 후 그대로 전달한다. VC는 store/snapshot에 로컬창을 삽입하지 않고 cache-only 준비에만 사용한다. 실제 표시는 기존 서버/삭제확인 이후 유지. latestSeq/lastReadSeq 조회 자체는 여전히 로컬창 조회 전이며 그 대기도 제거됐다고 표현하지 않는다.
- VC는 willAppear 전 힌트를 임시 보관하고 화면 활성 시 시작한다. 서버창 렌더 시 해제·후보 교체, 실패/이탈 시 준비취소·힌트해제. 초기 빈 viewport가 힌트의 후보를 지우지 않게 한다. 메모리·동시성 QA 옵션 유지.
- VC 주입 `cachedMemoryImageImmediately`→ChatMessageCell.configureWithImage(cachedImage:)→preview collection. 중첩 셀 최초 configure에 공용 메모리 hit를 동기 적용한다. loading 이벤트 직전 캐시가 채워져도 즉시 image로 전달. 파일I/O/네트워크 추가 없음. remote 경로변경 시 기존이미지제거/늦은 이전경로 결과 거절 유지.
- 계측 chatEntry.localMedia/initial/renderWindow 및 chatPreview.cellCache hit/miss로 로컬힌트→서버허용 렌더→셀 준비 상태 구분. 사용자 빠른스크롤 전체0ms 표시는 아직 미확정.
- 검증: 이벤트 VM 전달이 render를 만들지 않음, 셀 첫구성 cache hit/경로변경 차단, configure 이후 hit와loading 경합, 기존viewport/continuity/VM회귀. 서버 대기를 포함한 실 UseCase 이벤트 순서는 코드검토 및 기기계측으로 확인하며 새 VM fake 시험만으로 서버통합검증을 주장하지 않는다. `/private/tmp/outpick-local-early-media-tests.log`, 기기 `/private/tmp/outpick-local-early-media-device-build.log`.

## 최신 — 세 동시 실행 제한 해제 실험 승인

최종검증: XCTest26+SwiftTesting8=34개 통과(`/private/tmp/outpick-unlimited-disk-preparation-tests-final.log`). decode/IO 점유중 QA경로 진행/5후보동시시작 테스트 포함. 기기 BUILD SUCCEEDED(`/private/tmp/outpick-unlimited-disk-preparation-device-build-final.log`). 초기 빌드는 readLease 반환문 누락으로 실패했으며 수정 후 위 최종 검증 통과. 기존 캐시 유지 설치 후 QA 옵션 활성 로그와 진입 즉시 스크롤 체감은 별도 확인한다.

사용자가 요청 준비2/공용 decode2/디코딩을 감싸는 IO2 제한을 모두 해제해 QA 후 조정하도록 승인했다. `OUTPICK_UNLIMITED_DISK_PREPARATION=1`인 DEBUG 실행만 `ChatDiskPreparationExperiment`가 활성화한다. 일반 실행/Release는 기존 제한을 유지한다.

- controller maxConcurrent:nil로 현재 후보 전체를 메모리 허용 여부를 확인하며 제출한다. 경로별 병합/후보 제거 취소/화면 이탈 취소 유지. 메모리 사전 검사는 전체 작업 중 임시 디코딩 메모리의 예약이나 상한 보장이 아니다.
- 채팅 remote pipeline만 bypassDirectDiskLimits:true. 직접 disk hit는 decode 게이트와 IO읽기 게이트를 우회한다. readLease의 짧은 metadata IO 게이트도 우회하지만 actor의 파일/세대 보호, 하드링크 및 취소 검사 유지. fileDecoder는 기존1024px이며 네트워크/쓰기/다른 이미지 캐시 제한은 바꾸지 않는다.
- 플랫폼 executor/CPU의 실제 병렬 실행까지 무한대로 만들지 않는다. legacy fallback은 기존 보호 경로로 남으며 실제 발생 여부를 로그로 확인한다.
- 메모리1GiB/LRU/압박 대응/setIfRoom 무퇴거 삽입 유지. 동시 디코딩 임시 메모리 피크는 캐시1GiB 한도와 별개다. 이 QA 경로는 앱 게이트가 제공하던 visible 우선 입장을 우회하므로 실제 화면 버벅임을 함께 확인한다.
- 계측 `diskFile.decode`는 실제 동기 fileDecoder 호출 구간/active 수, `chatDiskPreparation`는 대기를 포함한 요청 수. `ChatMediaQAMetrics`는 getrusage 프로세스 CPU 누적량의200ms차이/벽시간으로 CPU% 산출(100%=한 코어, 전체 기기 비율 아님), peak와phys_footprint/thermal 기록. 200ms보다짧은순간피크 보장 없음.
- 자동 테스트: 준비5개 동시 제출과전체취소, decode/IO 슬롯을점유해도QA disk hit진행. 기존 일반경로/파일보호/세대/메모리회귀 포함. `/private/tmp/outpick-unlimited-disk-preparation-tests.log`; 기기빌드 `/private/tmp/outpick-unlimited-disk-preparation-device-build.log`. 기존 캐시 유지, 진입 즉시 빠른 스크롤/대량 왕복 후 결과에 따라 상한 재결정.

## 최신 — 진입 직후 잔여 대기 / 준비 동시성 QA 조정

검증 완료: XCTest20개+SwiftTesting coordinator8개, 총28개 통과. 기기 BUILD SUCCEEDED, 기존 캐시 유지 설치 후 `/private/tmp/outpick-dual-disk-preparation-device.log` 계측으로 진입 직후 스크롤 QA 진행. 효과는 미확정.

초기 준비 앞당김 후에도 사용자가 진입 즉시 빠른 스크롤 loading 보고. `/private/tmp/outpick-early-disk-preparation-device.log`: 초기 candidates339 확보, ready915회(고유339)/취소1, network0/용량퇴거0/압박0. loading1304회 모두 해당 경로 준비 완료 전 발생. 첫 준비 후1초 loading305/2초614, 이후 메모리 즉시 표시가 주로 관찰됨. file prepare p50 21.54/p95 34.98ms, decode입장p50 55.85/p95233.6ms. 표본/사용자 이동이 달라 이전과 절대속도 직접 비교 금지.

QA 수치 조정: ChatMediaViewportController가 ChatDiskPreparationController(maxConcurrent:2)를 주입. 기존 공용 decode2/IO2/낮은 준비 우선순위 유지, 처리량을 무제한 늘리지 않는다. 경로별 Task 사전으로 중복/진행 개수 제한, 완료마다 최신 거리순 후보 선택과 예산 재검사. 후보 제거는 해당 Task만 취소, 방 이탈은 전체 취소. 메모리 삽입은 기존 원자적 setIfRoom으로 무퇴거·압박 차단 유지. 이미 실행 중인 디코딩을 선점하는 구조는 아니므로 현재 화면 영향은 실기기 QA 필요.

추가 자동 테스트: 두 후보 동시 시작/세 번째 미진입/예산 부족 시 추가 시작 차단. 기존 viewport 취소·세대, LRU, coordinator 회귀 `/private/tmp/outpick-dual-disk-preparation-tests.log`. 기기 빌드 `/private/tmp/outpick-dual-disk-preparation-device-build.log`. 모든 진입 직후 먼 사진 즉시 표시를 보장하지 않는다.

## 최신 — 방 진입 초기 준비 시작 앞당김

검증: 집중 자동29개 통과(TEST SUCCEEDED), 최종 초기배치 guard 포함 기기 BUILD SUCCEEDED. 기존 캐시 유지 설치 후 `/private/tmp/outpick-early-disk-preparation-device.log`로 진입 즉시 빠른 스크롤을 계측한다. 사용자 체감 결과는 대기 상태다.

사용자 QA: 기다린 뒤 빠른 왕복은 정상, 방 진입 직후 빠른 위 이동에는 loading 노출. `/private/tmp/outpick-room-disk-preparation-device.log`에서 cache-only ready418회/고유339경로, network0/용량퇴거0/압박0. 준비 완료 전 loading 시작851회, 완료 후1회(약1.4ms 차이). 표시 이벤트 횟수는 고유 사진 수가 아니다. 준비 처리량 증가 효과는 아직 검증하지 않았다.

사용자 추천안 진행 승인에 따라 시작 시점만 앞당긴다. `setMessageWindow`에서 허용된 메시지를 store에 반영한 직후, snapshot/layout await 전에 `prepareInitialDiskImages` 호출. 최신 입장은 마지막 메시지부터, unread 입장은 경계 다음 메시지 인덱스부터 양방향 거리순/경로중복제거. 현재 viewport 준비와 동일 controller를 사용해 중복 worker를 만들지 않는다. viewWillAppear에서 이미 확보한 store도 준비하고 viewWillDisappear에서 조기 준비를 취소한다. background/이탈 이후 도착 이벤트는 활성 guard로 차단한다.

초기 위치 안정화 전에는 임시 상단 viewport가 초기 후보 순서를 덮어쓰지 않으며 완료 후 실제 프레임 순서로 전환한다. 표시용 viewport 활성 시점/다운로드 수요/화질/동시 준비1/예산은 유지. DI/서버/API 변경 없음. 계측 `chatDiskPreparation.initial`은 후보 수만 기록한다.

자동 검증: 배치/viewport resume 전 준비 및 이탈 취소, 초기 최신/unread 순서·중복/빈 후보와 기존 디스크/LRU 회귀. `/private/tmp/outpick-early-disk-preparation-tests.log` 실행 중. 기기빌드 `/private/tmp/outpick-early-disk-preparation-device-build.log`. 실기기 QA는 앱 재실행 후 방 진입 즉시 빠른 이동으로 확인하며 모든 미준비 사진의 즉시 표시를 보장하지 않는다.

## 최신 — 현재 불러온 메시지 전체의 디스크 준비

검증 결과: 집중 XCTest37개 통과(`/private/tmp/outpick-room-disk-preparation-tests.log`), 공용 coordinator SwiftTesting8개 통과(`/private/tmp/outpick-room-disk-preparation-coordinator-tests.log`), 합45개. 기기 빌드 성공(`/private/tmp/outpick-room-disk-preparation-device-build.log`) 및 기존 캐시 유지 설치 성공. 진단 실행 `/private/tmp/outpick-room-disk-preparation-device.log` 확인 후 수동 QA 진행. 체감 개선은 아직 미검증이다.

사용자 확정: 화면 거리순으로 현재 불러온 메시지 전체를 준비하되 메모리 여유까지만 진행한다. 서버 썸네일/원본 만료 및 만료 버블은 별도 작업이다. 과거 메시지 추가 pagination, 먼 구간 다운로드, 캐시 삭제, 업로드 규격 변경은 포함하지 않는다.

- 원인 근거: predictive QA에서 사용자는 크게 빨라졌으나 loading이 남는다고 보고. 해당 로그에서 network.body.received 0, diskFile.prepare success339/cancelled42, decode.wait acquired384/cancelled490. 이 횟수는 고유 사진 수나 프레임 지연 시간이 아니다.
- 구현: +MediaViewport가 현재 snapshot의 모든 미디어 좌표를 수집하고 policy.diskPreparationPaths로 거리순/경로 중복 제거. 기존 주변 수요24/visible 로딩은 유지한다. ChatContainer가 service의 디스크 준비와 예산 조회를 viewport 내부 ChatDiskPreparationController에 주입한다.
- 한 번에 하나의 디스크 준비 요청만 시작한다. 다음 요청은 최신 거리순을 사용한다. 후보 삭제 시 진행 요청 취소, suspend/endSession 시 취소·후보 초기화. 실패/miss는 해당 회차에서 반복하지 않는다. 페이지 이동/추가 시 후보 갱신, 무관한 이미지 참조 보관 없음.
- service→pipeline.prepareDiskImage→cachedValue(.diskPreparation)만 사용하므로 miss에서 다운로드하지 않는다. 공용 .cache 작업 합류/세대/삭제 차단 유지. 새로운 우선순위는 prefetch보다 낮고 visible 합류 시 기존 coordinator가 승격한다.
- 채팅 LRU만 준비 허용. 정상 압박 상태이고 잔여8MiB 이상일 때 시작(QA 시작값, 1024px 한 장과 현재 화면 작업의 여유). 완료 시에도 원자적으로 setIfRoom 검사해 기존 캐시 퇴거 없이 삽입한다. warning/critical 중 삽입 거절. 일반 visible/prefetch의 기존 LRU 정책은 그대로다.
- 자동 검증: 거리순/먼 구간/중복, 최신 후보 재정렬·예산 중단·이탈 취소, 디스크 miss 다운로드0/hit 메모리 준비, 무퇴거 삽입/압박 차단. `/private/tmp/outpick-room-disk-preparation-tests.log` 실행 중. 실기기 첫 진입 대기 후 빠른 장거리 스크롤/발열/빈 사진은 후속 QA.
- 한계: 메모리 여유가 없는 상태에서는 먼 구간 준비를 멈춘다. 입장 즉시 모든 사진이 준비된다는 보장은 없으며, 아직 불러오지 않은 메시지까지 서버에서 읽지 않는다.

## 최신 — direct disk 기기결과 및 예측 선로딩 구현

사용자 direct-only빌드에서매우빠른스크롤시전체loading노출보고. 로그 `/private/tmp/outpick-direct-disk-device.log`: direct성공342/legacy fallback0/재다운로드0, 보호링크378생성·378삭제. diskFile.prepare success342/failure36의failure는취소종료가failure로기록된이전계측오류(상위취소분기·fallback0과대조)여서새코드defer에서Task.isCancelled를cancelled로분류하도록수정했다. 실제파일준비 p50 24.04/p95 41.30ms, decode입장p50 205.89/p95 473.54ms. 압축Data대기는제거됐으나decode줄서기가남았다. 사용자속도/방문표본이다르므로이전p95와단순비교하여성능개선확정금지. 일반DEV복원후다음빌드진행.

### 3단계 구현·검증

기기설치/진단재실행성공. `/private/tmp/outpick-predictive-prefetch-device.log` session40665 수집중. 사용자동일빠른위스크롤에서이동중loading감소/정지화면즉시표시를분리확인하고근접왕복/빈사진/버벅임보고요청. 완료답변대기,효과확정전. 기존디스크캐시유지.

- `ChatMediaViewportPolicy`: 진행방향 범위max(1.5,min(4,속도×0.45초/화면높이)), 반대0.5화면유지. 초당2화면초과일때UIKit targetContentOffset 또는0.35초예측(최대±3화면)구간추가. 가까운순/도착중앙순후보를번갈아선택해고유선로딩24상한공유. visible은항상우선·상한밖유지,중간긴구간전부요청하지않음.
- `ChatViewController+MediaViewport`: 실제사용자drag/deceleration의contentoffset시간차속도,예상구간과현재주변교차행만수집. delegate의WillEndDragging에서도착offset저장. 방향전환/새drag/scroll종료/화면이탈/비사용자이동시예상값리셋. 수치는QA출발값이다.
- `ChatMediaViewportController.update(cancelOutsideImmediately:)`: 빠른이동에서수요밖작업은300ms유예없이소비자취소/entry이미지해제. 공용메모리캐시는유지. 느린이동기존유예/실패재등장정책유지. fastScrollReleased계측추가.
- 자동30개통과(`/private/tmp/outpick-predictive-prefetch-tests.log`): viewport10/policy4/surface3/directdisk3/files10. 새정책테스트는near·destination12/12선택/24상한/중간구간제외/예측거리상한/빠른범위밖즉시취소포함. 기기build성공(`/private/tmp/outpick-predictive-prefetch-device-build.log`),설치진행. 체감아직미검증.

## 최신 — 파일 URL 직접 준비 및 속도/도착구간 선로딩 승인

사용자가 두추천안확정/진행지시. 먼저2단계direct disk만비교한뒤3단계선로딩을적용해효과분리한다. 압축파일/화질/1024px표시decode/동시decode2 유지.

### 2단계 구현

최신: 자동47개통과(XCTest13+SwiftTesting34/4suite), TEST SUCCEEDED(`/private/tmp/outpick-direct-disk-tests.log`). 기기build/install/diagnosticlaunch 성공. `/private/tmp/outpick-direct-disk-device.log` session13182 수집 중, 사용자같은과거구간빠른스크롤/1왕복/방밖15초 및첫로딩체감확인 요청. 디스크캐시유지·메모리초기화, 선로딩정책은아직기존그대로. 답변/실제fallback·직접준비·대기·링크해제 계측검토후3단계진행.

- pipeline/processor `usesDirectDiskFileDecoding` 기본false, ChatAttachmentImageService remote만true. disk hit에서 decode슬롯확보→disk.readLease→파일URL decoder→반환 순. 압축Data전체읽기/decodeBytes예약/다운로드files슬롯/임시내용복사 불필요. decode·IO상한유지.
- `ImageCacheReadLease`: store actor가짧은IO쓰기슬롯에서캐시파일하드링크생성. 디코더실행은store actor밖IO읽기슬롯에서진행하여스토어전체를디코딩동안잠그지않음. 동시에링크가보호하는작업은decode2로제한. 캐시교체/삭제는원래경로에적용되고기존읽기는기존inode유지,후속결과는coordinator세대검사. 해제시링크삭제,강제종료시이전전용tmp링크는다음프로세스첫사용때정리. 기존캐시/다른임시폴더삭제없음.
- 링크/파일디코드실패는기존Data/복사경로fallback,취소는fallback하지않음. fileDecoder는파일해제전표시준비를완료해야하며채팅ImageIO ShouldCacheImmediately사용. URL전달자체가zero-copy/무제한메모리절약을보장하지않음.
- 새계측 diskReadLease.created/released, diskFile.prepare, diskFile.fallback, cache outcome diskDirect. 기존diskRead/Data지표와단순시간비교하지않고chatPreview.load전체/메모리/재다운로드를함께본다.
- 테스트 `ImageDirectDiskDecodingTests`3개: 교체/삭제동안기존내용보호·해제시링크삭제, 압축byte/files슬롯점유중directhit진행, fileDecoder실패legacy복구. 관련회귀 `/private/tmp/outpick-direct-disk-tests.log`;기기build `/private/tmp/outpick-direct-disk-device-build.log`성공. 실기기비교전이다.

### 3단계 예정

현재고정1.5화면/반대0.5화면을속도에따라유한범위에서확대하고, UIKit예상targetContentOffset구간도후보로포함한다. 현재visible최우선,고유선로딩24상한/영역밖취소유지. 현재화면과먼도착구간사이전체를일괄선로딩하지않는다. 방향전환/손가락재접촉/방이탈시낡은예상도착위치를폐기한다. 세부QA시작값·실제이벤트연결·정책테스트를별도기록후순차구현.

## 확정·구현 시작

### 재실행 QA 완료 — 다음은 디스크 표시 준비 대기

사용자 빠른위스크롤에서아주잠깐loading후표시확인. `/private/tmp/outpick-display-budget-relaunch-device.log`: network.body.received0, disk.lookup hit358/miss0, disk용량퇴거0, memoryImmediate1734, pressure0. 재다운로드없는디스크재사용을확인했으나실제프레임전체0ms표시를의미하지않는다. chatPreview.load 성공443개 p50 120.53ms/p95 554.59ms, decode입장p50 52.8/p95 232.56ms, decodeBytes입장p50 .07/p95 395.47ms, IO입장p95 13.98ms, 실제diskRead p50 1.76/p95 3.56ms. 서로다른표본의분위수를합산하지않는다. 남은병목후보는disk읽기자체보다decode·압축data입장/표시준비다.

decode/io/decodeBytes 최종사용0·대기0. network/files는이번실행이벤트없으므로실측0으로표현하지않는다. 앱phys_footprint peak140.35MiB/마지막51.63MiB/thermal0. 사용자지속빈사진보고없음. 일반DEV복원요청(`/private/tmp/outpick-display-budget-relaunch-normal.log`). 1단계예산확대/기존파일유지QA 완료, 다음2단계기존diskhit 디코딩/입장대기검토. 선로딩속도정책은3단계이며아직미변경. 현재1GiB는이기기QA값이며전체기기출시안전성검증완료아님.

### 1GiB 장거리 왕복 실기기 결과

사용자 반복로딩전혀없음/버벅임·발열·빈사진없음 확인. `/private/tmp/outpick-display-budget-qa2-device.log`: memoryImmediate2043회, 캐시최종339개/계산비용928.99MiB, 용량LRU퇴거0·disk용량퇴거0·pressure이벤트0. memory.eviction replaced254는같은key교체이며용량부족퇴거와구분. 다운로드완료85건/고유85개로관측구간동일리소스반복완료0, 저장85success·임시파일해제85absent, network/files/decode/io/decodeBytes 최종사용0·대기0.

앱200ms sampler의 `phys_footprint` 최고126.35MiB/마지막51.99MiB, thermal0. 캐시픽셀비용합929MiB와OS프로세스footprint는다른지표이며차이의구체원인을확정하지않는다. raw RSS나앱이실제로929MiB물리상주했다고표현하지않는다. 실제pressure미발생,압박축소동작은앞선자동주입시험근거다. 한기기한구간QA를모든지원기기안전성으로확장하지않는다.

왕복계측종료후 재실행진단launch성공. `/private/tmp/outpick-display-budget-relaunch-device.log` session53004 수집, 사용자같은과거사진빠른이동/1왕복 체감확인요청. 디스크유지/메모리초기화상태 재사용검증진행중. 추가예산조정·선로딩변경은아직없음.

QA 재개: 사용자 `진행` 후 이전 session42614는 exit0 종료 확인(원인 미확정, 메모리종료로 단정하지 않음). 기존로그보존, 새 `/private/tmp/outpick-display-budget-qa2-device.log` session53055로 진단launch 성공. 사용자 충분히채움/장거리3왕복/방재진입/밖에서15초 요청, 답변대기. 이전 실행과 새 실행 표본을 혼합해 성능판정하지 않는다.

**최신 검증:** 공용회귀57개(XCTest23+SwiftTesting34) 통과. 최종디스크최근접근시험 추가후LRU집중5개 통과, 고유합계58개(중복4개합산금지). `/private/tmp/outpick-display-budget-tests.log`, `/private/tmp/outpick-display-budget-lru-final-tests.log`. 실기기build/install/진단launch 성공, `/private/tmp/outpick-display-budget-device.log` 수집 중(session42614). 사용자 전체채움→장거리3왕복→방재진입→밖에서15초 요청, 체감/발열/멈춤/종료/미표시 답변대기. 앱재실행QA는후속. 기존캐시보존, 실기기결과전1GiB 최종안전성/성능확정금지.

사용자 **기존 파일 유지/채팅 공용 디스크1GiB·정리900MiB + 표시 메모리1GiB/LRU/압박 시 축소** 확정. 숫자는 QA 시작값이며 출시 전 모든기기 안전기준 확정이 아니다. 아래 답변대기 문구는 이전검토 상태다.

변경: `ChatAttachmentImageService.makePipelines` remote에만 적용. outgoing80MiB·GIFData45MiB·다른기능NSCache 및 영상캐시는 유지. `ImageCacheMemoryStore(usesLRU:true)`가 새 `ImageLRUMemoryStore`로 위임하며 기본false는 기존NSCache. 실제 CGImage stride×height로 보관비용계산, 조회·교체는 최신순, 한도초과는 최오래사용순제거, 한도보다큰단일이미지는 미보관. 디스크파일규격/업로드/1024px decode는 유지.

압박정책: DispatchSource normal/warning/critical 및 UIKit메모리경고 관찰. warning은 현재보관분해제+최대예산1/4(256MiB), critical은해제+보관0. critical 뒤 warning은0유지, normal에서1GiB복귀. 디스크는삭제하지않고 화면이별도소유한UIImage까지강제로해제하지않는다. 실제RSS상한보장이아닌 캐시소유비용상한이다.

검증: `ImageLRUMemoryStoreTests`의 메모리최근사용정리/중복교체비용/삭제/압박시재유입제한·복귀/초과이미지미보관/NSCache중복보관없음/디스크read의최근사용보호, 기존revision·취소·채팅·아바타·룩북 회귀. `/private/tmp/outpick-display-budget-tests.log` 실행중, `/private/tmp/outpick-display-budget-device-build.log` 기기빌드중. 기기기존캐시보존, 가짜메모리압박자동검증과 실제압박발생여부는별도로기록한다.

사용자가 승인한 순서: (1) 표시 파일/공용 디스크 예산 → (2) 디스크 표시 대기 → (3) 스크롤 선로딩. 기존 원본 분리 Phase3~4보다 먼저 진행한다. 앱 전체 이미지를 무제한 보관하거나 모든 사진을 메모리에 상주시키는 목표는 아니다. 사용자가 본 이미지를 재사용하고 일반 스크롤에서 화면 진입 전 준비하는 것이 목표다.

## 1. 표시 파일과 공용 예산

- 근거: 최근3개 QA 로그의 고유 다운로드275개 합398.29MiB,137개가1MiB초과. 개선QA 단독264개379.62MiB,중앙값939.76KiB,p95 3.65MiB,최대4.41MiB. 앱 전역 계측 표본이며 QA방 전체 파일 수와 동일하다고 가정하지 않는다.
- 기기 `Library/Caches/ChatImageCache` 읽기전용 목록254개314.12MiB(`/private/tmp/outpick-display-cache-inventory.json`). 기존350MiB 상한/280MiB 정리목표로 표본 전체를 유지하기 어렵다.
- 추천안(사용자 답변 대기): 현행 파일/1024px 표시decode/메모리 예산 유지, 채팅방 공용 디스크 최대1GiB/정리900MiB. 최근접근 우선 보관. 방별 무제한 캐시로 분리하지 않는다. 이 값은 QA 시작값이며 앱전체 캐시총합 상한을 뜻하지 않는다(아바타/룩북/영상은 별도).
- 변경후보: ChatAttachmentImageService.makePipelines의 ChatImageCache 예산, 필요시 정책상수. 서버/업로드/화면/DTO/계정별 보존·삭제 계약 변경 없음. 기존파일 일괄삭제/재인코딩 없음.
- 검증: 최근접근 파일 보존/오래된 파일 퇴거 자동검증, 기존 QA 구간 채운 뒤 왕복/재진입/재실행 다운로드·퇴거량. 파일규격이 동일하므로 용량 변경에 따른 화질변화는 없고 추가축소의 화질QA는 이번안에 포함하지 않는다.
- 완료: 수용범위내 이미받은 동일파일의 용량퇴거 재다운로드 감소를 실측. 방문범위/기존캐시가 다르면 단순총량비교 금지.

## 2. 디스크 표시 대기

- 1번 효과 측정 후 잔여 disk-hit load의 read/decode/files 대기를 분리한다. 현재 파일입장4초대 지표는 다운로드 files슬롯도 포함하며 디스크읽기가4초라는 의미가 아니다.
- 변경후보: ImagePipelineProcessor/Resources, coordinator/persistence. 기존 다운로드6/decode2/IO2/write1을 무조건 늘리지 않는다. 전송과 준비/저장이 같은 files 예약을 유지하는 계약과 소유권을 먼저 확인한다.
- 완료: disk hit의 실제 다운로드0/불필요복사·대기 원인설명 및 개선. 취소/세대/슬롯누수/공용 아바타·룩북 회귀필수. 실제병목이 없어 변경불필요하면 근거기록하고3번 진행.

## 3. 스크롤 선로딩

- 현행방향만사용: forward1.5화면/backward0.5화면/선로딩고유경로24개. 속도·도착화면 기반 정책은 미구현이다.
- 변경후보: ChatMediaViewportPolicy, ChatViewController+MediaViewport 및 스크롤 이벤트 연결. 현재화면우선/상한유지/범위밖취소/재등장실패재시도 유지.
- 속도/도착위치 추정은 단계시작 때 이벤트지도와 계측결과로 구체화한다. 요청증가로현재화면을늦추지않는지 검증, 장거리점프 후 이전구간잔류작업차단.
- 검증: 방향/속도/점프 정책 deterministic 테스트와 같은기기 빠른왕복/앱재실행 QA. 모든장거리스크롤에 무조건0ms를 보장하지 않는다.

## 현재 상태

1번 추천예산/파일유지 선택 질문중. 제품 정책코드 변경 전. 질문 답변 전2·3번을 임의 구현하지 않는다. 이후 단계에서 사용자동작/계정보존 정책 변경이 필요하면 해당부분만 논의한다.
