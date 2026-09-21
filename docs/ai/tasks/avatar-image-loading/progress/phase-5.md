# Phase 5 — 통합 QA

**최종 상태: 2026-09-21 합의 범위 완료.** VoiceOver 사용자 제외. 일반DEV build57037/install81778/launch33107 성공, QA/테스트 옵션 없이 `complete profile found. Showing main tab.` 확인(`/private/tmp/outpick-avatar-qa-complete-{build,install,console}.log`). 테스트 전용 기기캐시 잔여0, 기존서버fixture/임시코드정리완료. git diff --check통과, 커밋/배포없음. 다음핵심작업 채팅방대표이미지설계는미착수.

## 2026-09-21 잔여 검증 최종 통과

- 잔여1·2: 상위 화면 DI 코드 대조와 실제 상세 factory/UI/spy로 정책 전달, 기존scope 참여상태변경, 원본only 상세/반복확대 확인. 테스트만 보완했고 제품 코드·서비스 API·서버 정책을 변경하지 않았다.
- 잔여3: 실제 중첩 참여자50/UIKit viewport를 iPhone14에서 계측. 생성만으로요청0, offset0/2400/1200의 visible5/6/6·신규12/13/15·활성12/13/15, 허용영역밖신규0·24상한준수·clear0. 후보3명은 기존수동QA+자동로딩비활성/바깥좌표/가시성/선로딩 코드대조로 구분한다.
- 잔여4: iPhone14 실제AvatarImageView/AvatarImageService/pipeline의 같은process에서 댓글memoryOnly→참여방disk허용 동일이미지·디스크저장, 메모리만제거→댓글disk재사용. 전체fetch1·저장bytes유지·프로세스재시작0. 테스트전용fake이미지transport/독립UUID캐시이며 실제앱전체페이지수동이동/실제서버성능계측을 수행했다고 주장하지 않는다.
- 실기기 `build-for-testing`→`test-without-building` 성공. scheme OutPick-Development, Development-Debug, iPhone14 UDID00008110-000168693E91401E, parallel-testing-enabled NO, 선택suite AvatarRouteContractTests/AvatarNestedViewportTests/AvatarImageServiceTests. XCTest4개+SwiftTesting12개=16개 통과. `/private/tmp/outpick-avatar-remaining-device-{build,tests}.log`, xcresult `Test-OutPick-Development-2026.09.21_15-26-34-+0900.xcresult`.
- Simulator 최초 단일 SwiftTesting 함수 필터는 실행0이어서 무효로 분리했다. 이후 서비스전체12개 실행으로 연속테스트포함통과(`/private/tmp/outpick-avatar-continuous-suite-tests.log`), 기기실행에서도 해당시나리오의 실제로그확인.
- 서비스 fixture.cleanup이 전용캐시파일과 빈UUID폴더까지 제거. 기기 Library/Caches 목록 재조회 success/AvatarTests항목0(`/private/tmp/outpick-avatar-after-device-tests-cache.json`). 이번 검증은 서버fixture 추가0/실제사용자사진변경0. VoiceOver는 사용자 제외를 유지한다.
- 기존 회귀112개와 이번16개는 중복되므로 합산하지 않는다. 디스크100/75MiB, 선로딩1.5/0.5·고유24·이탈300ms, 원본30초 정책 유지. 일반DEV복구 완료 여부는 아래 후속 기록 참조.

아래 미검증·대기 기록은 당시 이력이며 위 최종 결과로 대체한다.

## 잔여 QA 순차 진행 (VoiceOver 제외)

- 2번 원본only 집중결과: Route XCTest3개+viewer10개, AvatarImageService SwiftTesting11개 통과(`/private/tmp/outpick-avatar-original-only-tests.log`). 상세/원본확대2회에서thumbnail호출0·원본로더만사용 확인. 테스트 host appearance 경고1건은 기존 viewer UI fixture 구간이며 실패0.
- 3번 중첩 UIKit 계측: 실제 ParticipantsSectionParticipantCell50명은 생성만으로요청0, offset0/2400/1200에서 visible5/6/6, 신규12/13/15, 활성12/13/15·총고유40. 허용선로딩범위밖 신규요청0·활성24이하·clear후0 자동검증통과(`/private/tmp/outpick-avatar-nested-tests.log`). 위임후보는실제상한3명수동QA기존통과 및 scrollView변환/프리패치코드대조, 이번nested테스트를후보화면전체자동화로해석하지않는다. 기기실행은다음.
- 4번 연속테스트 추가: AvatarImageServiceTests의 실제AvatarImageView 메모리only→disk허용 동일UIImage/전송1회/디스크생성, 메모리만제거→댓글뷰disk재사용/추가전송0/bytes유지를같은process에서검증. 독립UUID캐시·가짜사진transport사용, 서버자료변경없음. Simulator build34226 `/private/tmp/outpick-avatar-continuous-build.log` 진행 후검증예정. 사용자가USB/잠금해제준비완료응답, 기기후속실행승인범위내. 아직기기테스트미실행.

- 1번 정책 전달: 상위 AppCoordinator의 룩북memoryOnly/마이페이지memoryAndDisk, ChatContainer의 참여 여부 동적 scope, ChatCoordinator·댓글/답글→UserProfileDetailCoordinator→CompositionRoot의 동일 manager 전달을 코드 대조했다. 새 AvatarRouteContractTests의 실제 상세 factory→UIKit 표시→spy 정책 유지와 동일 scope의 false/true/false read/load/prefetch 전환2개 테스트 통과(`/private/tmp/outpick-avatar-route-{build,tests}.log`). 전체 상위 탭을 자동 이동한 테스트와 구분한다. 앱 제품 코드 변경 없이 기존 경계에서 검증했다.
- 2번 원본only: 같은 테스트 파일에 썸네일nil 공개프로필→실제 상세 표시→확대/닫기2회가 원본 로더만 사용하고 thumbnail cache를 조회하지 않는 시나리오 추가. build-for-testing 통과, 기존 AvatarImageServiceTests/ImageViewerStateTests와 집중 실행 중(`/private/tmp/outpick-avatar-original-only-{build,tests}.log`). 결과 대기.

## 2026-09-21 최종 대조 및 이번 QA 정리 완료

- 다른 계정에서 원래 계정으로 복귀 후 이름·사진/계정 사진 혼입/오류 전부 정상 사용자 확인. 인증 로그의 identity가 원래 owner와 다시 일치함을 내부 비교했다.
- 서버183문서/20이미지 삭제 후 하위·파생문서0 및 원장문서/이미지0 재확인. 기기 미전송쓰기 반영 확인→Firestore 캐시초기화→QA174행/3이미지·제어파일 정리, 다른자료/로그인 보존. 근거 `/private/tmp/outpick-avatar-final-cleanup-console.log`.
- 임시 코드 제거: SceneDelegate/RealtimeSocketService diff0, AvatarImageService 임시 오류 주입 제거. 정상 DEV 빌드·설치·baselineOFF 실행 및 메인탭 확인(`/private/tmp/outpick-avatar-final-restored-{build,install,console}.log`). Mac 생성사진18개·원장·스크립트·생성기·제어JSON 제거, 검증로그 유지.
- 최종 자동 회귀: iPhone17Pro Simulator `05397E0E-7170-4B48-A8D2-D60A5B8865FC`, OutPick-Development/Development-Debug. 정상 소스 build-for-testing 후 parallel-testing-enabled NO의 test-without-building. Swift Testing102개/13suite와 ImageViewerStateTests XCTest10개 통과. 아바타5suite·공용캐시/예산4suite·룩북HTTP/viewport2suite·프로필수정·viewer page/state 포함. `/private/tmp/outpick-avatar-final-regression-{build,tests}.log`, `/private/tmp/outpick-avatar-screens-build/Logs/Test/Test-OutPick-Development-2026.09.21_14-50-29-+0900.xcresult`.
- 체크리스트의 중복·부분검증 항목을 분리했다. 전체route spy/원본only 자동화, 중첩viewport 실요청 계측, 화면 간 캐시재사용·승격 연속 기기 증거는 미검증으로 유지한다. VoiceOver는 2026-09-21 사용자 요청으로 이번 QA 범위에서 제외하며 잔여 작업에 포함하지 않는다. 새 결함이 발견된 것은 아니지만 **Phase5 전체 완료 판정은 아직 하지 않는다.** 커밋·배포 없음.

아래 기록은 진행 당시의 이력이며 임시 자료가 남았다는 과거 상태는 위 정리 완료 기록으로 대체한다.

- 다른 DEV 계정 로그인 후 사용자 이름·사진 정상, 홈↔마이페이지3회 동안 이전 사진 노출/오류 없음 확인. console44101 최신 인증 identity가 원래 fixture owner와 다른 것을 내부 비교로 확인(식별자 출력 없음). 원래 계정 복귀 확인은 다음 단계. 기기 캐시 목록 `/private/tmp/outpick-avatar-account-switch-other.json` 기록.

- 타계정 QA의 로그아웃 단계: 사용자 로그인 화면 확인. 기기 AvatarImageCache 전7항목→로그아웃0→추가15초 뒤0, 세 devicectl JSON 모두 success(`/private/tmp/outpick-avatar-account-switch-{before,logout,logout-idle}.json`). 관찰 구간 이전 디스크 캐시 재생성 없음. 다른 계정 로그인·화면 검증과 원래 계정 복귀는 아직 대기하며 전체 계정 전환 QA 완료는 아니다.

- 사용자 새81메시지·QA05번호사진 정상 확인 완료. 스크롤/새 표시 계기 재시도 수동 검증 통과(실제 Socket 전송은 범위 밖). 다음 다른 계정 전환에 사용할 기존 DEV 계정이 있다는 응답을 받았으며 전환 전 캐시→로그아웃 캐시→타계정 표시 확인을 순차 진행한다. 최종 체크리스트 대조에서 과거 자동 로그 immediate46/5suite 및 originaltimeout19/2suite+viewer10 성공을 재확인했고, 남은 세부 항목은 일괄 통과 처리하지 않았다.

- 새 메시지 QA 실행: 사용자 하단 준비 완료 후 QA05 실제 injected26/body0 확인, 오류 제어파일 해제→서버 seq81 한 건 생성(원장183문서/20이미지)→기존 ingress 큐 한 번 주입. console44101에서 enqueued=true seq81, QA05 seq1933 원격13396bytes/seq1951 caller success1134.90ms 확인. 스크롤 없이 새 메시지·사진이 보이는지 사용자 확인은 대기 중. 실제 Socket 전송 검증과 구분한다.

- 2026-09-21 사용자 승인 후 DEV QA 방·작성자05·seq81 한정 기존 수신 큐 주입장치를 RealtimeSocketService에 임시 추가. 빌드/설치 성공, console44101 `/private/tmp/outpick-avatar-message-qa-console.log` 실행. 초기 화면 확인 후 오류 해제와 메시지 생성/주입을 순서대로 진행할 예정이며 아직 seq81 생성·주입·복구 검증은 하지 않았다. 일회성 진단이므로 영구 테스트 추가 대신 빌드·로그·수동 QA로 검증한다. 종료 시 코드·서버자료·기기 제어파일 전부 정리하며 실제 Socket 전송 검증으로 해석하지 않는다.

- 2026-09-21 스크롤 재시도 통과: 사용자 QA04 번호사진 복구/QA05 기본사진 유지 확인. reset-console seq3491 QA04 원격 body12834bytes, seq3514~3519 caller success 확인. 새 메시지 계기는 아직 미검증. Firestore 문서 직접 생성은 Socket 전송을 발생시키지 않으므로, 실제 계정 추가 없이 진행할 DEV 한정 수신 ingress 주입 방식은 별도 논의 후 구현한다. 실제 Socket 전송 QA와 구분하며 임시 자료 정리는 아직 남아 있다.

## 2026-09-20 댓글·답글·참여자 QA 재개

- 실제오류주입 초기화면 사용자재확인 후 추가15초 로그snapshot: QA04실패15회/QA05실패16회 누적이 두snapshot에서동일, 관찰구간추가0. 화면초기구성/진입구간의누적31회를동일표시계기중복없음증명으로사용하지않는다. 앱재시작없이기기JSON을QA05만차단하도록교체성공(`/private/tmp/outpick-avatar-retry-only05.json`). QA04스크롤이탈/복귀복구 및QA05기본유지 사용자검증요청,실제복구결과대기.

- 캐시선행조건 수정 후 진단설치/실행 성공. reset-console.log에 bootstrap전scope캐시초기화, QA05 seq235/QA04 seq241 transientFailure injected 실제확인. 사용자다시초기표시/15초정지 확인요청, 이전캐시적중관찰은실패검증에서제외. 스크롤복구는아직미검증.

- 첫 오류상태 사용자확인 뒤 로그 대조에서 QA04/05 retry.jpg의 injected failure0, memory/disk hit 성공 확인. 실패 상태 검증으로 인정하지 않음. 서버fixture준비~진단설치 사이 이전앱이 해당사진을 캐시했을 가능성이 있으나 원인시점은 미확정. SceneDelegate에 DEV/env/QA경로 한정 app bootstrap 전 정확한2경로 캐시 삭제 임시코드 추가, 메모리는 재실행으로 초기화. 기기빌드61585 `/private/tmp/outpick-avatar-retry-qa-reset-build.log` 후재설치/실제injected로그확인 필요. 다른 캐시 삭제 없음. 종료시SceneDelegate추가코드/import도모두제거.

- 오류주입 DEV 빌드/설치 및 기기JSON전송/명시env실행 성공. console75449 `/private/tmp/outpick-avatar-retry-qa-console.log`. 사용자온라인 ‘잔여 QA 후보’ 메시지목록 하단 QA01정상/QA04·05기본이미지 확인 및스크롤없는대기 요청. 아직주입해제/재표시복구검증전, 최종임시코드제거미완료.

- 사용자 DEV QA 경로 오류 주입 선택. AvatarImageService DEBUG helper: bundle/project/env/path 모두 한정, Documents/avatar-retry-qa.json의 blockedPaths만 transient networkConnectionLost로 종료. 실제인터넷/일반사진정책변경없음. QA04/05 새thumb/retry.jpg2개 및 기존후보방 메시지80개/멤버2명 추가(원장 **182문서20이미지**), 실제계정/Auth변경없음. `/private/tmp/outpick-avatar-retry-blocked.json` 생성. 기기빌드35534 `/private/tmp/outpick-avatar-retry-qa-build.log` 진행중, 설치/제어파일전송/실행 후 QA04·05 기본이미지와 idle재요청 확인 예정. 오류해제시 앱재시작 없이 파일만교체하므로 재표시계기를 구분할 수 있다. 종료후 임시helper/import/call·기기JSON·fixture전부제거필수.

- 2026-09-21 미참여방 목록 빠른왕복/사진번호 및 검색→01·06방 메시지아바타/복귀 사용자 전부확인. 최초 안내한 미참여 프로필상세는 앱에서 접근불가라는 사용자지적을 받아 즉시 제외·정정했고 참여방상세 QA로 대체한 사실을 구분한다. 기기 `/private/tmp/outpick-avatar-remaining-browse-cache.json`에서 정책 재대조. 다음2번 썸네일 실패 재표시/새메시지 검증방식 논의: 실제 차단은 SDK600초 재시도 가능, DEV QA경로만 transient 오류 주입→해제 후 실제이미지복구 방식 추천. 선택전 코드변경없음, fixture100문서18이미지사용중·최종정리필수.

- 2026-09-21 위임 후보 수동QA: QA01~03 이름/사진번호·선택변경·닫기재진입 세항목 사용자확인. 실제위임/퇴장미실행. 기기캐시해시 대조 후보thumb3/original0, 미참여용QA04~09thumb0/original0(`/private/tmp/outpick-avatar-remaining-candidates-cache.json`). fixture100문서18이미지유지. 다음미참여목록미리보기 및 검색→미참여방 진입 QA 진행.

- 2026-09-21 사용자 잔여4항목 순차 진행 승인, USB 연결/DEV 홈 확인. 1번 범위 확인: 위임 후보는 정책상 관리자 최대3명, 검색 결과 행은 방 대표 이미지만 표시하므로 검색 결과 자체의 아바타 검증은 해당 없음. 검색→미참여방 메시지/프로필 경로를 대신 확인한다. 기존 아바타 수정 범위를 확장하지 않는다.
- fixture `qa-avatar-remaining-20260921` 100문서/18이미지 생성. ‘잔여 QA 후보’ 실제owner+가상moderator3, ‘잔여 QA 검색 01~06’ 미참여방6/가상QA04~09/각미리보기메시지3. 가상프로필총9, Auth생성·실제초대없음, 실제위임미수행. 원장 `/private/tmp/outpick-avatar-remaining-qa/manifest.json` 및 같은이름.cjs, 생성기 `/private/tmp/outpick-avatar-remaining-images.swift`. baseline1 기기console21277 `/private/tmp/outpick-avatar-remaining-console.log`, 로그인identity원장일치확인. 후보표시/선택/재진입부터 사용자검증대기. 끝나면서버·파생·기기·임시파일전부정리필수.

- **네트워크 QA 정리 완료:** 서버8문서/2이미지 삭제 후 방·가상 사용자 하위 및 현재계정 QA 상태 잔여0. 기기 pendingWrites=acknowledged→firestoreCache=cleared→deletedRows=1/deletedImages=1/unrelated=preserved/auth=preserved. SceneDelegate 임시코드 제거(diff0), 정상 DEV 빌드/설치/메인 탭 실행 확인, baselineOFF. `/private/tmp/outpick-avatar-network-{cleanup,restored}-{build,install,console}.log` 참고. 생성사진2개/원장/seed·cleanup스크립트/생성swift삭제 완료. 실제30초 개선은 유지. 전체 Phase5 완료 판정은 미검증 항목과 자동 계약 최종 대조 후 별도 진행.

- 실기기 원본30초/오프라인 QA 통과: 사용자 파란 썸네일 유지·재시도 표시 및 온라인 재시도/줌 정상 확인. 연결 유지된 `/private/tmp/outpick-avatar-original-timeout-console.log` 원본 caller seq305→331 cancelled 30,720.53ms, 재시도 seq404→454 success1,093.45ms, file body34,088bytes 확인. 앱이 자동 반복한 것이 아닌 사용자 재시도 표본이다. SDK 취소 완료 지연/스케줄링이 있어 30초 정확한 UI계측으로 환산하지 않음. fixture8docs/2images, 하위·현재계정 QA room 상태 추가파생0 확인. 미전송 쓰기 확인 후 기기 캐시 정리용 DEV 빌드 성공, 정리 진행 중.

- 재연결 후 원본30초 개선 DEV 데이터 유지 설치 성공 및 baseline1 실행(console60597 `/private/tmp/outpick-avatar-original-timeout-console.log`). 기존 설치 실패 해소. 온라인 QA NET 상세→오프라인 확대 약30초 실패/썸네일 유지 수동 재검증 요청. 아직 실제기기 결과 대기.

- 원본30초 기기 빌드 성공. 설치는 CoreDeviceError1011(기기를 찾지 못함)로 실패(`/private/tmp/outpick-avatar-original-timeout-install.log`), 개선 버전 실기기 미설치. 사용자 비행기모드 해제/인터넷·USB 복구 및 잠금 해제 요청. 재연결 후 설치·실기기30초 검증 필요.

- 원본30초 제한 최종 회귀 통과: Swift Testing19개/2 suites 및 ImageViewerStateTests XCTest10개, `/private/tmp/outpick-avatar-original-timeout-final-tests.log` TEST SUCCEEDED. diff check 통과. 기기 빌드 `/private/tmp/outpick-avatar-original-timeout-device-build.log` 시작, 실제 오프라인30초/온라인 재시도는 재검증 전.

- 재검증에서 기존 viewer10개 통과 후 신규 timeout/retry 테스트 대기. 취소를 무시하는 가짜 첫 file 전송이 diskWrites=1 permit을 보유한 채 재시도 성공을 먼저 기다린 테스트 순서 문제 확인. 재시도 Task 생성→첫 전송 gate 해제→재시도 결과 확인으로 수정(제품 자원 제한은 유지). 해당 xcodebuild17114 INT종료, 최종36616 `/private/tmp/outpick-avatar-original-timeout-final-tests.log` 재실행. 실제 SDK 완료 전 permit 보유와 재시도 시간 억제를 혼동하지 않는다.

- 최초 원본제한 테스트 빌드는 Task.sleep(for:)의 iOS16 가용성 때문에 실패. 기존 최소 타깃과 호환되는 Task.sleep(nanoseconds:)로 수정 후 재실행16727 `/private/tmp/outpick-avatar-original-timeout-verified-tests.log`. 빌드 성공/테스트 전체 결과는 아직 대기.

- 사용자 원본30초 제한 승인. AvatarImageService 원격original만 타이머와 pipeline 소비자 경합, 초과URLError.timedOut/나머지취소. 로컬파일·썸네일·전역SDK설정 유지. 기존공용취소 경로로 마지막소비자 SDK취소 및 실제완료 전 permit보유를 유지한다. 타이머주입형 서비스테스트3개추가, 기존session/viewer 포함 시뮬레이터 테스트43714 실행중(`/private/tmp/outpick-avatar-original-timeout-tests.log`). 실제30초 오프라인 재검증/기기설치는 아직 전.

- 네트워크 QA: 온라인 QA NET 썸네일 표시 사용자 확인→비행기모드/Wi-Fi 차단 뒤 확대에서 ‘불러오는 중’ 지속 제보. 로컬 FirebaseStorage Storage.swift:92/283 기본 maxDownloadRetryTime600초, StorageDownloadTask.swift:114에서 request.timeoutInterval에 적용. 앱 소스에 별도 override 없음. 네트워크 차단 중 devicectl console이 CoreDeviceError3/연결무효화로 종료되어 원본 요청의 실제 시작/종료·내부 재시도 횟수는 미확인, 앱 무한 재요청으로 단정하지 않음. 제안: 프로필 확대 원본만30초 대기 한도/초과시 취소와썸네일유지·수동재시도표시, 다른이미지전역설정은유지. 새로운 시간 정책이므로 사용자 선택 대기, 코드 미수정. 오프라인 실패 QA 미통과, fixture8문서/2이미지 정리 전 유지.

- 동일 계정 재로그인 후 홈/원래 사진 정상 사용자 확인. 닉네임 임시 변경→사진 유지 확인→원래 닉네임 복구도 사용자 전부 완료 응답. 다음 온라인 상태 유지 확인 후 원본 비저장 특성을 이용한 네트워크 QA 준비.
- 새 최소 fixture `qa-avatar-network-20260920`: DEV ‘아바타 네트워크 QA’ 방1, 가상 QA NET 프로필1, 실제 QA 사용자 membership, 총8문서/2이미지 생성 완료. Auth 계정 생성/외부 사용자 초대 없음. 원장 `/private/tmp/outpick-avatar-network-qa/manifest.json`, seed/verify/cleanup `/private/tmp/outpick-avatar-network-qa.cjs`, 사진생성기 `/private/tmp/outpick-avatar-network-images.swift`. 실제기기 DEV `OUTPICK_IMAGE_BASELINE=1` console64790 `/private/tmp/outpick-avatar-network-console.log`로 재실행. 온라인에서 방설정→QA NET 상세까지만 진입해 썸네일을 먼저 표시하고, 이후 오프라인 확대→실패/썸네일 유지→온라인 재시도 검증 예정. 아직 네트워크 실패/복구는 검증 전이며 종료후 원장·파생·기기 QA 캐시 및 생성 파일 정리 필수.

- 로그아웃 후 로그인 화면 표시 사용자 확인. 기기 AvatarImageCache 실제 파일 목록: 로그아웃 전 `.bin`4개→로그아웃 후0개→15초 이상 대기 후 재조회0개. `/private/tmp/outpick-avatar-{before-logout,after-logout,after-logout-idle}-cache.json` 각 outcome success. 관찰 구간에서 디스크 재생성 없음 확인이며 메모리 해제 계측/다른 계정 전환/의도적 진행 중 요청 경합을 실기기로 증명한 것은 아님(기존 자동 테스트 근거 별도). 다음 동일 계정 재로그인 및 복구 사진 표시 확인 대기.

- 사용자 원래 캐릭터 사진 표시 복구 확인. 로컬 백업 이미지2개·manifest·backup/restore 스크립트 삭제 완료(삭제 전 manifest 상태/파일집합/hash 검증). 서버의 복구된 실제 프로필 사진은 유지. 사진 변경→제거→복구 및 재진입 수동 QA 완료. 다음 로그아웃/동일 계정 재로그인 검증 진행.

- 본인 사진 변경→탭 왕복/편집 재진입3항목, 제거→기본 이미지/탭 왕복/편집 재진입3항목 모두 사용자 확인 완료. 원래 캐릭터 사진 복구: 현재 서버 avatar 두 필드 null 및 active 계정 확인, 백업 해시 검증 후 이전 경로 삭제 재시도와 충돌하지 않는 새 경로로 동일 bytes 2개 업로드. 문서 lastUpdateTime 조건으로 avatar 두 필드/updatedAt만 갱신, 나머지 프로필 필드 동일 검증 및 서버 파일 hash 일치 확인. 기존 원본 경로 객체 잔여0. 앱 재실행·복구 사진 사용자 확인 대기, 백업은 확인 전 보존. 복구 스크립트 `/private/tmp/outpick-profile-restore.cjs`, 원장 status `restored-awaiting-device`. 임시로 선택한 다른 사진의 Storage 잔여 여부는 별도 미확인(그 경로 원장 없음).

- 본인 사진 원본이 iPhone에 없다는 사용자 응답에 따라 현재 DEV 프로필만 read-only 백업. `/private/tmp/outpick-profile-restore-20260920`에 썸네일500×339 JPEG/원본588×399 JPEG 및 복구원장 보관, 해시 재확인·이미지 열기·generation/updateTime 안정성 검증 통과, 서버쓰기0. 현재 이미지는 노란 우주복/연필 캐릭터로 이전 표본과 달라 앱 표시와 일치 여부 확인 후 실제 변경 QA 진행. 변경/제거는 아직 미수행이며 복구 완료 전 백업 삭제 금지.

- 사용자 마이페이지 탭 왕복3회·프로필 편집 저장 없이 열기/닫기2회 결과 “누락/깜빡임/오류 전부 이상 없음”. 해당 재진입 수동 QA 통과. 사진 변경·제거/닉네임 변경/네트워크 실패/로그아웃 검증과 구분한다. 다음 실제 사진 변경·제거는 기존 이미지 삭제 후 복구할 원본 확보 여부 확인부터 진행.

- 후속 QA 진행 승인. iPhone14 연결 확인, 마이페이지 탭 왕복3회 및 프로필 편집 저장 없이 열기/닫기2회 수동 확인 요청 중. 마이페이지 자체 사진 확대 액션은 코드에 없어 처음 안내의 확대2회는 즉시 정정·제외했다. 실제 사진 변경/제거는 UpdatePublicProfileUseCase가 성공 후 기존 Storage 경로를 삭제하므로 현재 사진 복구 수단을 확보한 뒤 별도 단계로 진행해야 한다. 아직 사진·닉네임 변경 또는 로그아웃은 하지 않았다.

- **이번 화면 QA·정리 완료.** 서버 fixture 377문서/120이미지 삭제 후 재귀 하위 및 현재 계정 QA 상태까지 잔여0 확인. 기기 로그 `pendingWrites=acknowledged`→`firestoreCache=cleared`→`completed deletedRows=50 deletedImageFiles=50 unrelatedRowsAndFiles=preserved auth=preserved`. QA roomID/작성자ID/이미지 해시 정확 일치만 삭제했고 실제 로그인 유지. SceneDelegate 임시 정리 코드 제거(diff0), 정상 DEV 빌드·설치·실행 및 `complete profile found. Showing main tab.` 확인. 생성 이미지120개·원장·seed 스크립트·생성기 소스/실행파일 삭제 완료. 검증 로그/trace는 근거로 유지. `/private/tmp/outpick-avatar-screens-{cleanup,restored}-{build,install,console}.log` 참고. Phase5 전체가 아닌 댓글·답글·참여자 및 발견 UI 결함 검증 완료이며 미검증 항목은 qa-checklist에 유지.

- 사용자 최종 재검증: “완전 만족, 깜빡임과 첫 네 명의 사진 표시 정상”. 즉시 메모리 표시 개선의 실기기 체감 검증 통과. 377문서·120이미지 fixture 정리 시작, 방/브랜드/가상 사용자 하위 및 현재 계정의 QA 상태 검사에서 추가 파생 문서 0개. 미전송 쓰기 확인→Firestore 캐시 초기화→QA 전용 GRDB/이미지 정리용 임시 DEV 빌드 성공. 정리 완료와 정상 빌드 복구는 아직 대기.

- 즉시 표시 최종 회귀: 5개 suite 46개 테스트 통과(`/private/tmp/outpick-avatar-immediate-verified-tests.log`). 세션 정리·사진 무효화 중 즉시 조회 차단, 기존 캐시 공유/디스크 승격, 늦은 결과 차단 포함. 기기 빌드 및 데이터 유지 DEV 설치 성공. 실기기 깜빡임 개선 효과는 사용자 재검증 대기이며 임시 QA 자료 정리는 아직 미완료.

- 직렬 재검증에서 새 `immediateReadCannotRestoreRetiredPhotoDuringInvalidation` 테스트의 AvatarTestGate 단일continuation에 old/old-original 두동시호출이들어가leaked continuation으로정지. fixture가원본경로도생성하는점을놓친테스트문제. old썸네일경로만대기하도록수정,이번xcodebuild12513 INT종료후87129 test재실행(`/private/tmp/outpick-avatar-immediate-verified-tests.log`). 앱코드원인으로단정하지않으며최종회귀결과대기. 앞서세션clear차단및서비스즉시조회·승격테스트통과확인.

- 즉시표시 첫통합테스트에서서비스/정책/표시일부통과출력후 시뮬레이터 DEV 재launch FBSOpenApplicationServiceError로대기, 전체통과처리안함. 이번xcodebuild PID8990만INT종료. 병렬테스트NO로 test-without-building 재실행75120 `/private/tmp/outpick-avatar-immediate-serial-tests.log`, 결과대기. 제품코드컴파일오류는없음.

- 사용자 `깜빡임까지 개선·재검증 후 정리` 선택. cachedAvatarImmediately 읽기 경로를 기존 NSCache에 연결(추가 이미지캐시0). session의 lock gate는enabled/retired+unavailable/pending invalidation count 보호, 전환중·사진삭제중 반환차단. SwiftUI body즉시조회와 presentation initialImage로 기본이미지첫프레임완화. async loader 유지해참여방승격누락방지, 원본/로컬파일즉시조회없음. 세션/서비스/표시 테스트4개추가 및 기존viewport/storepolicy 회귀실행중46073 `/private/tmp/outpick-avatar-immediate-tests.log`, simulator05397E0E-7170-4B48-A8D2-D60A5B8865FC. 아직빌드/테스트/실기기효과미판정.
- 참여자 확대뒤disk 재조회 QAthumb50/original0(`/private/tmp/outpick-avatar-after-expand-cache.json`). 확대원본미저장유지.

- 사용자 참여자2명 상세→확대/줌→닫기/목록복귀 번호/오류 확인완료 응답. 해당수동검증완료로기록. 댓글초고속placeholder는 새표시State 초기image=nil이고 메모리조회도 session actor→pipeline/coordinator async를거쳐첫렌더후반영되는구조가후보. 메모리직접조회추가는현재세션/retiredPath/무효화검증을우회하면안되므로단순View수정으로처리하지않음. 캐시상한/원본미저장정책유지, 보완범위논의필요. fixture사용종료및정리는최종검증범위결정후진행.

- 사용자 설정최초방정보상단/목록끝에서만3버튼/끝까지스크롤후닫기재진입상단 모두정상확인. 참여자번호·이미지·스크롤이상없음과함께설정UI회귀통과.
- 기기AvatarImageCache와fixture hash 대조: 댓글전용QA01~10 썸네일0, 댓글/참여자공통QA11~20 썸네일10, 참여자전용QA21~60 썸네일40, QA원본0(`/private/tmp/outpick-avatar-participants-cache.json`). 참여자50명누락0. 댓글전용disk미저장/참여방disk허용 실제사용처검증. 공통10은저장확인이나재시작을거쳤으므로이번결과만으로메모리→disk승격경로실행증명은아님.
- 사용자에게참여자서로다른2명 상세→확대→줌→닫기→목록복귀/번호일치·누락오류확인요청. 댓글초고속스크롤placeholder깜빡임은별도잔여, fixture정리미실행.

- 설정스크롤 변경 빌드/설치/실행성공, 사용자최초상단·스크롤끝버튼·닫기재진입상단확인대기(`/private/tmp/outpick-settings-scroll-{build,install,launch}.log`). diff check통과. QA fixture정리·전체완료는아직아님.

- 사용자 중간시작은 목록스크롤위치라고확인. ChatRoomSettingViewController 초기비동기layout 중 사용자첫drag전 top(-adjustedContentInset.top) 유지, 참여자뒤actionsSection에기존3버튼이동/고정bottom제약·추가inset제거. API/권한/버튼동작미변경. 기기빌드59797 `/private/tmp/outpick-settings-scroll-build.log` 진행중. 순수UI 배치는 자동테스트추가없이 빌드+50참여자실기기재진입/하단도달/위로복귀 QA로검증, 수정효과아직미확인.

- 사용자 참여자 QA 사진/이름번호·빈사진·깜빡임·끊김 문제없음 확인. 설정 중간시작 및 나가기/차단사용자/알림 하단고정 불편 제보. 코드상 ChatViewController.presentSettingPanel은 오른쪽70%폭/전체높이 child panel이며 중간높이sheet 아님. ChatRoomSettingViewController.configureBottomButtons는 버튼을 collection 바깥 view.safeArea.bottom에고정하고 contentInset을추가. 버튼은참여자뒤스크롤콘텐츠로이동추천, 중간시작은contentOffset인지panel위치인지사용자질문대기. 원인확정없는설정UI수정은아직안함. 아바타QA 후속 캐시검증/정리는계속남음.

- 사용자 답글 large 확장/스크롤 `완전 편해짐` 확인. 답글 첫표시·재진입·스크롤과 확장 사용성 정상. 다음 ‘아바타 화면 QA 50’→방설정→참여자50 끝까지확인/빠른왕복2회/번호일치·깜빡임질문대기. 역할변경/퇴장없이목록QA, 참여방disk허용검증은 사용자스크롤뒤기기hash조회예정. 댓글초고속placeholder깜빡임은잔여이슈유지.

- 답글확장 기기빌드/설치/실행 성공(`/private/tmp/outpick-avatar-reply-expand-{build,install,launch}.log`), diff check통과. 사용자 상단손잡이위로드래그 확장/스크롤확인대기. 현재console미연결/baseline꺼짐. 다른QA와임시자료정리완료아님.

- 사용자 답글 첫사진/닫기/재진입/15초스크롤 모두 정상 확인. 답글 화면이 작아 위로 끌어 확장 요청. 기존62% 단일 detent에 large 추가(PostCommentsSheetView.repliesSheet), 시작높이/내용/캐시정책 유지. 단순시트설정은 별도 자동테스트 추가 없이 기기빌드와 확장 수동QA로검증. 설치후확장확인 필요.

- 댓글 유효계측45.897498초 전체표본: frame-lifetimes1790행, OutPick DEV PID10584 hitch5건 합83.35ms/최대16.68ms. XML `/private/tmp/outpick-avatar-comments-hitch-events.xml`. 전체기록에는사용자20초스크롤전후정지구간포함, 1790/45.9를FPS로환산하지않음. placeholder깜빡임 원인/성능합격과분리, 첫2개등앱update및1개offscreen14passes 잠재이슈태그는진단가설이지근본원인확정아님.

- Animation Hitches 저장 성공45.897498초. TOC `/private/tmp/outpick-avatar-comments-hitches-toc.xml`, frame-lifetimes export `/private/tmp/outpick-avatar-comments-frames.xml` 실제 row 존재 확인. 프레임 lifetime duration은 표시간격/FPS와 같지 않으므로 역수FPS나 드롭률로 보고하지 않음. 실제 hitch별표본 추가분석 필요. 이전 저장대기기록은해소됨.

- 사용자45초계측 중20초댓글스크롤 완료: 누락/번호불일치/기타문제없으나 아주빠른상하스크롤에서잠깐기본이미지깜빡임. 정상합격으로묻지않고잔여이슈로유지. 공용cachedAvatar가async이고 새SwiftUI표시state의첫렌더placeholder→Task캐시반영 구조를후보로확인(확정원인아님). Hitches45초종료후저장중 세션71227, 아직유효trace미확인. 답글60 첫표시/닫기재진입/15초스크롤사용자질문대기. 참여자진입전정책검증순서유지.

- 사용자 댓글사진표시·스크롤 준비 완료. DEV PID10584에 Animation Hitches45초 attach 시작 로그 확인(`/private/tmp/outpick-avatar-comments-hitches.log`), 기록세션71227/output `.trace`. 시작 직후 사용자20초 스크롤/이상여부 질문. 기록 저장·사용자완료·frame export 결과 아직 대기이며 프레임QA 통과 미판정.

- 임시 수명 로그 제거 후 기기빌드/설치/실행 성공. baseline 미활성 성능console83409 `/private/tmp/outpick-avatar-screens-performance-console.log`. 댓글 화면 재진입 준비 응답 후 프레임계측 시작 예정. 기기AvatarImageCache 파일목록과 QA120경로 hash 대조0개(`/private/tmp/outpick-avatar-screens-comment-cache.json`)로 참여자진입전 댓글memoryOnly 디스크미저장 확인. 현재증거는 모든 cold/warm·답글·참여자QA완료를 뜻하지 않는다.

- 사용자 `아 이제 제대로 로딩 된다` 확인. fixed-console에서 상단01~04 모두 최신identity→configure/start/loaded 확인. 원인 조사용 avatarSwiftUI/avatarPresentation 로그 제거, 실제 수정은 CommentSafetyAvatarView의 콜백 next 전달만 유지. 캐시/서비스 정책 변경 없음. 정상 코드 기기빌드50434 진행 중(`/private/tmp/outpick-avatar-screens-clean-build.log`), 이후 스크롤/답글/참여자/프레임QA 재개.

- 수정기기빌드 성공·설치·실행 완료, console29991 `/private/tmp/outpick-avatar-screens-fixed-console.log`. 사용자 상단사진 스크롤없이표시/닫기재진입2회 확인 요청 중. 진단mark 제거는 재검증 뒤 진행, 최종 QA 완료 선언하지 않음.

- 진단 재현 결과(사용자 첫4명 기본이미지 유지): uptime275116.214~.235에서 상단4개 avatarSwiftUI.appear/configure와 identity/configure 모두 빈 경로 해시, start 없음. 이전 scroll 이탈 로그는 최신 QA01~04 경로, 재등장 시 configure/start/loaded 정상. `onChange(of: identity) { _ in configure() }`가 이벤트 새 값을 버리고 캡처된 이전 View의 빈 경로를 적용하는 문제로 좁힘. 콜백 next identity를 `configure(next)`에 직접 전달하도록 수정. 표시 상태/캐시/재시도 정책은 그대로. 수동 재진입 회귀가 핵심 검증이며 순수 상태 unit test로 SwiftUI 캡처 문제를 대신 검증했다고 주장하지 않는다. 수정빌드7217 `/private/tmp/outpick-avatar-screens-fix-build.log` 진행 중.

- 진단빌드 성공·기존 자료 유지 설치 완료. 새 실행 console29551 `/private/tmp/outpick-avatar-screens-diagnostic-console.log`, OUTPICK_IMAGE_BASELINE=1. 사용자에게 댓글 진입→닫기→재진입 후 첫4명 기본이미지 상태 그대로(스크롤하지 않기) 응답 요청. 아직 원인/수정 미확정. 기존 fixture 유지, 프레임 및 다른화면 QA 대기.

- 사용자 확인: 재진입 후 대기해도 첫4명 기본이미지 유지, 화면이탈→복귀 시 사진 표시. 다운로드속도만으로 설명하지 않음. 원인 구분을 위해 CommentSafetyAvatarView appear/identity/disappear와 AvatarImagePresentationState configure/start/loaded/error/suspend를 기존 opt-in ImageCacheMetrics에 추가(원문경로/UID 미출력). 동작정책 미변경, 진단빌드 세션24664 `/private/tmp/outpick-avatar-screens-build.log`, DerivedData `/private/tmp/outpick-avatar-screens-build`. 빌드/설치 후 같은 재진입 재현 요청 필요. 수정 전 회귀 재현이 목적이며 자동 테스트 추가는 실제 원인 확정 후 결정.

- 후속 사용자: 첫진입 확실히 느림, 재진입 시 첫4명 기본이미지/아래는 로딩됨. 정상 판정 보류. 01~20 각각 body1회 및 메모리 재사용 확인, 상단01~04도 최근 caller success 확인했으나 프리패치/표시 요청 구분이 없어 실제 행 표시 성공 증거는 아님. CommentSafetyAvatarView의 onAppear/configure/resume·onChange(identity)·onDisappear/suspend, AvatarImagePresentationState, authorProfileStore/VM 순서 점검 중. 사용자에게 3~5초 대기와 상단행 화면이탈→복귀 시 복구 여부 질문(첫4행 특정·지속미표시 vs 잠깐지연 구분). 원인 확정/수정 없음, 다른 화면 QA와 프레임 계측은 이 결함 조사 후 계속. fixture 삭제 아직 하지 않음.

- 사용자 댓글 사진 표시 확인, 로딩이 조금 느리다고 제보. 최초 로그 QA 썸네일 path 및 imageCache|path 해시 대조: network.body.received20건. 성공 caller 중 메모리 hit parent가 아닌24건 중앙730.09ms/최대1446.48ms, 메모리 hit caller184건 중앙0.15ms/최대3.08ms(분석 시점). 요청 완료 시간이며 화면 표시까지 전체시간/순수 네트워크 RTT가 아니다. 재다운로드 반복은 이 표본에서 관찰되지 않음. 첫 방문 다운로드 영향 후보지만 정상으로 단정하지 않고, 앱 종료 없이 이미 본 구간 왕복 및 첫진입/재표시/목록자체 지연 구분 질문 대기.

- 생성 완료:377문서/120이미지, seed exit0. DEV main tab 로그 확인. 사용자에게 룩북 아바타 QA→댓글·답글 QA→포스트→댓글 진입과 QA 댓글001/사진 표시 확인 요청. 댓글 memoryOnly 확인 전 QA 참여자 방 진입 보류 안내.

- 사용자 실제 계정 추가/연동·초대 없이 임시 댓글/답글/가상 참여자 자료를 충분히 생성하고 QA 후 제거하는 범위 승인, DEV 홈 정상 및 USB 재연결 확인.
- 유선 연결/booted 확인 후 DEV를 OUTPICK_IMAGE_BASELINE=1로 재실행. console `/private/tmp/outpick-avatar-screens-console.log` (세션95292). 이전 /private/tmp 빌드와 로그는 현재 없으므로 Development 설정 plist와 새 실행 계정 기준으로 검증한다.
- fixture `qa-avatar-screens-20260920`: 독립 브랜드 `아바타 QA`→시즌 `댓글·답글 QA`→포스트1, 루트 댓글80/첫 댓글 답글60, 방 `아바타 화면 QA 50` 가상 참여자50+현재 사용자1. 가상 작성자60명 공개 프로필·users/moderation 상태만 생성하며 Auth 계정/초대 없음. QA01~10 댓글전용, QA11~20 댓글/참여자 공통, QA21~60 참여자전용. 관리자3명은 후보 표시 검증용이며 실제 권한 이전하지 않는다.
- 생성기 `/private/tmp/outpick-avatar-screens-images.swift`, 실행파일 동명, 자료·삭제 원장 `/private/tmp/outpick-avatar-screens-qa/manifest.json`, 생성/검증/원장삭제 스크립트 `/private/tmp/outpick-avatar-screens-qa.cjs`. 이미지 AppKit 500/1000px JPEG0.8 총120개. 등록 세션6508 결과 확인 필요. **QA 종료 후 원장 기반 서버·파생 문서·Storage와 기기 QA 캐시·임시 파일 정리 필수**, 전체 Firestore 캐시는 기존 승인된 미전송 쓰기 반영 확인 절차 준수.
- 제품 코드·보안규칙·배포 변경 없음. 성공 기록 전 생성/화면QA/프레임 통과로 처리하지 않는다.

## 2026-09-19 최신 결과 및 정리 상태

### 정리 완료 (아래 진행 중 기록보다 우선)

- 사용자 승인 후 실제 기기 로그 `pendingWrites=acknowledged` → `firestoreCache=cleared` → `completed deletedRows=24 deletedImageFiles=12 unrelatedRowsAndFiles=preserved auth=preserved` 확인. QA 외 GRDB 행 수/아바타 파일 집합 및 로그인 동일성을 검증했다. 서버 반영 확인 실패 시 초기화하지 않는 순서로 실행했다.
- 정상 소스에서 SceneDelegate 임시 분기/import 전체 제거, 해당 파일 git diff0. 정상 Development 빌드·업데이트 설치 성공, 실행 로그 `complete profile found. Showing main tab.` 확인. 기존 앱 삭제 없음.
- 최종 서버 재확인: 원장 문서0/이미지0, QA 방·가상 사용자 하위 파생 문서0, 실제 사용자 하위 QA 방 ID 전용 문서0. 운영 자료·실제 계정 보존.
- 기기 이미지 다운로드 임시 폴더4개 파일은 모두 QA 생성(2026-09-18T14:45:53Z) 이전 파일이며 크기도 가상 원본과 다르므로 보존. 이번 QA 이미지 디스크12개는 정확 경로 해시로 삭제했다.
- Mac의 생성 이미지24개·삭제 원장·fixture 스크립트·이미지 생성기 제거 완료. 검증 로그/trace는 결과 증거이며 삭제용 원장과 구분한다. 정리 후 `git diff --check` 통과. 남은 수동 QA 항목 및 프레임 계측은 아래와 같다.

- 사용자 `미전송 쓰기 확인 후 DEV 캐시 초기화` 승인. SceneDelegate에 DEV bundle/project/명시 실행 인자 제한 일회성 정리 분기 준비: 화면 조립 전 waitForPendingWrites→terminate→clearPersistence, QA roomID/가상 작성자12 정확 일치 GRDB 삭제 및 다른 행 수 보존 비교, SHA256 QA 이미지 파일만 삭제·다른 파일 집합 보존 비교. 완료 후 임시 코드 제거·정상 빌드 재설치 필요. 원격 방/가상 사용자 하위 파생 문서도0 확인.

- 사용자 두 번째 20초 스크롤→프로필 확대/닫기3회→15초 대기 완료, 이상 없음 확인.
- 유효 Activity Monitor 반복 표본59개: CPU 최대51.50%, physical footprint 시작60.45MiB/최대77.25MiB/종료62.11MiB. 확대 종료·대기 뒤 메모리 감소를 확인했으며 이 구간의 지속 증가 징후는 없었다. 장시간 누수 부재나 이전 구현 대비 개선을 입증하는 결과는 아니다. 프레임/hitch 계측 미확보.
- 승인된 DEV 원장190문서·24이미지 cleanup 성공, 재조회 잔여0/0. 실제 계정/운영 데이터와 별도 승인된 DEV App Check 등록 유지.
- 기기 GRDB/아바타 이미지 캐시 정리와 임시 파일 제거는 아직 남음. Firestore SDK clearPersistence는 다른 캐시와 pending writes도 제거하므로 임의 실행하지 않음. 사용자에게 미전송 쓰기 확인 후 DEV Firestore 캐시 전체 초기화 또는 QA 전용 캐시만 정리할지 선택 요청 중. SDK 근거: FIRFirestore.h clearPersistence 설명.
- 댓글/답글·다수 참여자·내 프로필 수정·실제 실패/로그아웃 등 미검증 수동 항목은 남아 있으며 Phase5 전체 완료 아님.

아래 기록은 진행 당시 이력이며 이 최신 상태를 우선한다.

## 사용자 승인 임시 QA 자료 — 생성 완료, QA 후 삭제 필수

### 스크롤·확대 수동 결과

### USB 유효 Activity Monitor 표본

- 앱 단독 PID9697 Activity Monitor30.901초 기록 저장 성공. 사용자 기록 중20초 스크롤 완료 확인. 구간2026-09-18 23:56:53~23:57:23 KST, trace `/private/tmp/outpick-avatar-phase5-usb-app.trace`, `activity-monitor-process-live` export `/private/tmp/outpick-avatar-phase5-usb-app-activity.xml`.
-26개 표본 CPU 최대61.04%, physical footprint 최대64.91MiB, 마지막62.99MiB. 초반2~11MiB/후반상호작용약58~65MiB로 표본 상태가 달라 초기→종료 차이를 누수로 단정하지 않는다. warm cache 현재빌드1회, 이전 구현과 비교 아님. 프레임 수치는 없음.
- 반복 스크롤/확대 종료 안정 구간 확인을 위해60초 두 번째 Activity Monitor 기록 시작. `/private/tmp/outpick-avatar-phase5-usb-repeat.trace`, 로그동명`.log`, 세션2673. 사용자20초 스크롤→확대닫기3회→15초 대기 응답과 저장 결과 대기.

- USB 재연결 후 devicectl `transportType=wired`, `bootState=booted`, `ddiServicesAvailable=true`, 개발자 모드enabled 확인. 첫 Hitches+Activity60초 기록은 늦게 시작돼 스크롤 요청 전에 종료, 저장 단계2분 이상 정체하여 이번 xctrace PID38782만 INT→TERM 종료. 다음 전체 기기 기록은 kperf 잠금 충돌로 실패. 데이터 확보/스크롤 성공으로 처리하지 않음.
- Instruments GUI는 iPhone14와 프로세스를 인식했다. 이어 실제 DEV PID9697만 `Activity Monitor`30초 attach 성공(`/private/tmp/outpick-avatar-phase5-usb-app.log`, trace `/private/tmp/outpick-avatar-phase5-usb-app.trace`, 세션3781). 시작 로그 확인 직후 사용자20초 스크롤 요청. 저장 완료·사용자 완료·유효 표본 결과는 아직 확인 중.

- devicectl cache 파일 목록(JSON `/private/tmp/outpick-avatar-phase5-cache-files.json`, 조회 success)과 원장 경로 SHA256을 대조: QA 썸네일12개/원본0개. 디스크 정책 확인이며 메모리 해제나 성능 측정의 대체 증거는 아니다.

- 사용자 첫 빠른 왕복3회: 전체가 아니라 한두 사진이 기본 이미지로 잠시 보였다가 로드되는 현상 관찰. 캐시 메모리 읽기도 비동기 Task를 거쳐 표시하는 현재 코드가 짧은 placeholder 구간의 후보이나 원인 확정 아님.
- DEV 로그 재연결(세션34225, `/private/tmp/outpick-avatar-phase5-qa-console.log`) 후 같은 방 빠른 왕복1회에서 사용자가 `없다고 봐도 무방한듯?` 응답. fixture path/hash 대응 이벤트에서 thumbnail disk read12/disk hit12·memory hit473 확인 시점까지, QA 썸네일 network body 이벤트0. 재다운로드 반복 결함으로 판단하지 않으며 코드 미변경. 최초 관찰은 유지한다.
- 사용자 프로필 상세→확대→줌→닫기3회 `사진·확대 모두 정상` 확인. 현 로그에서 QA 원본 파일 download1건 확인 시점이며 3회 모두 개별 재다운로드했다고 주장하지 않는다. 디스크에 원본 파일이 없는지도 별도 확인한다.
- Instruments 두 방식 연결 실패를 해소하기 위해 USB 재연결/잠금 해제 요청 중. 성능 수치 미확보 상태 유지. QA 자료 cleanup은 아직 미실행이다.

- 사용자 방 진입·사진들 표시·측정 준비 확인. 원격 verify190문서/24이미지 일치. 빠른 상하 왕복3회·번호 일치/빈 사진/스크롤 점프 질문 대기.
- Instruments `Animation Hitches + Activity Monitor`45초 및 `Activity Monitor`30초 모두 `Waiting for device to boot` 후 timeout. devicectl은 paired/available로 보이나 Instruments 연결 실패라 CPU/메모리/프레임 수치 없음. trace 생성 성공으로 해석하지 않는다.
- 기존 console11783은 앱 exit0으로 종료된 것을 확인. 이전 로그는 QA fixture의 hash 키와 일치하는 이벤트0으로 현재 QA 측정에서 제외. 화면 QA 결과와 계측 확보를 분리한다. 다음 로그 수집은 사용자 스크롤 완료 후 DEV 재실행하여 연결해야 한다.

- 사용자가 실제 상대 사진 다수 방이 없어 가상 메시지 자료를 제안했고, 완료 후 전부 삭제 조건으로 생성 승인했다. 홈 정상 진입은 사용자 확인 완료.
- DEV `outpick-test`에 `Rooms/qa-avatar-20260918-12x150`, 이름 `아바타 QA 150` 생성. 가상 작성자12명의 공개 프로필/읽기 상태 문서36개, 메시지150개, 방/현재 QA 계정 member/joinedRooms/roomModerationStates4개 =190문서. Firebase Auth 계정 추가·다른 실제 사용자 초대·알림 없음. 생성은 관리자 SDK의 원장 기반 create로만 수행했고 기존 문서 충돌 시 중단한다.
- 기본 DEV Storage `profileImage/qa-avatar-20260918-12x150-author-01..12/{thumb,original}/qa.jpg` 총24개. AppKit으로 번호·색상 구분 이미지 생성(500/1600px JPEG0.8). 실제 인물 사진·개인 사진 복제 없음. 가상 작성자 users.accountStatus 및 moderationAccounts.accountStatus는 기존 읽기 규칙을 충족하는 QA 문서로만 생성, 보안 규칙 변경 없음.
- 현재 QA 계정만 실제 member이며 가상 작성자는 member가 아니다. 메시지 스크롤/상세 확대 표본이며 다수 참여자 QA까지 통과로 처리하지 않는다.
- 삭제 원장 `/private/tmp/outpick-avatar-qa-fixture/manifest.json`(mode0600); 작성 스크립트 `/private/tmp/outpick-avatar-qa-fixture.cjs`, 이미지 생성기 `/private/tmp/outpick-avatar-qa-images.swift`. 초기 Admin SDK custom credential 불가 오류는 원격 쓰기 전 발생, Google Cloud SDK OAuth 연결 후 생성 성공.
- 원격 검증 `node /private/tmp/outpick-avatar-qa-fixture.cjs verify`; QA 완료 후 `cleanup`은 qaFixture 표식 및 문서 updateTime/Storage generation을 검사한 뒤 원장 대상만 삭제한다. 생성 원장 밖 자동 read-state 등과 기기 GRDB/이미지 캐시 잔여도 별도 확인해야 한다. cleanup을 아직 실행하지 않았으며 사용 중 자료를 먼저 지우지 않는다.
- 마지막으로 사용자에게 방 진입·사진 표시·측정 준비 응답 요청. 임시 코드/파일·기기 캐시까지 정리하고 잔여 없음 확인 후 최종 완료 보고. 별도로 등록한 DEV App Check 인증은 테스트 방 자료와 구분한다.

> 최신: 사용자 `QA용으로 등록해` 명시 승인 후 현재 iPhone14 DEV 토큰을 outpick-test 앱에 `iPhone 14 Avatar Phase 5 QA 2026-09-18`로 등록 성공. 등록 직후 CLI OAuth client의 직접 exchange 검증은401이었으나 실제 앱 재실행에서 bootstrap 실패0/Unauthenticated0, `complete profile found. Showing main tab.` 확인. 실제 SDK 인증 경로 복구. 운영 프로젝트 변경 없음. 새 console 세션11783 `/private/tmp/outpick-avatar-phase5-device-restored-console.log`; 이전57643은 재실행으로 종료 대상. 사용자의 홈 확인·채팅 표본 준비 응답 대기. 아래 승인 대기는 해소됨.

## 범위와 현재 상태

2026-09-18 사용자 Phase5 진행 승인. Phase1~4의 아바타 정책·경합 자동 회귀와 실제 화면/성능 QA를 진행한다. 아직 완료 판정하지 않았다.

- 연결 기기: iPhone14, CoreDevice `A7B8FA1C-C7FF-556C-977E-9E8CE2F5BC84`, paired/available. `GayoonKim.OutPick.dev` 설치 확인. 운영 앱도 설치되어 있으므로 DEV만 대상으로 한다.
- Simulator: iPhone17Pro iOS26.5 `05397E0E-7170-4B48-A8D2-D60A5B8865FC`.
- 자동 검증: OutPick-Development, DerivedData `/private/tmp/outpick-avatar-build`, 로그 `/private/tmp/outpick-avatar-phase5-tests.log`.
- 실기기 최신 빌드 준비: generic iOS, DerivedData `/private/tmp/outpick-avatar-device`, 로그 `/private/tmp/outpick-avatar-phase5-device-build.log`.
- 기기 조회는 샌드박스 CoreDeviceService 접근 실패 후 권한 확장 조회로 성공했다.

## 검증 계획

아바타 viewport/presentation/service/session/profile observer/store policy와 기존 coordinator/revision/resources/HTTP cache/profile mutation/edit/viewer/comment author/room preview/chat profile sync 회귀를 실행한다. 화면 happy path 테스트를 추가 복제하지 않고 실기기 QA로 확인한다.

실기기는 기존 계정/캐시를 유지한 업데이트 빌드로 먼저 확인한다. 앱 삭제·운영 데이터 변경·사진 변경·로그아웃을 임의 수행하지 않는다. 사용자가 채팅방/댓글 포스트 표본을 지정하면 첫 표시·재진입·왕복 스크롤·참여자·프로필 확대 반복을 나눠 기록한다. 기존 캐시 표본을 cold 측정이라고 보고하지 않는다.

## 남은 검증

### 초기 데이터 인증 복구 승인 대기

사용자가 `앱 데이터를 준비하지 못했어요` 확인. 기기 로그에서 getMyModerationState의 Unauthenticated 재현. Firebase CLI read-only 조회로 outpick-test 프로젝트 접근 및 기존 iPhone14 Phase5/Phase4 QA 등록 확인. 현재 기기 debug token의 직접 exchangeDebugToken 검증 요청은 자동 승인 검토가 자격 정보 payload·외부 destination의 명시 승인 부족으로 거절하여 실행되지 않았다. 사용자에게 현재 iPhone14 DEV 토큰을 Firebase 공식 API/outpick-test/OutPick Development에 검증 및 미등록 시 등록하는 구체적 승인 요청. 승인 전 우회/등록하지 않는다. App Check가 원인일 가능성은 있지만 교환 응답 검증 전 확정하지 않는다.

### 23:33 자동 검증·실행 복구

- 보완 후 Swift Testing106개/16suite＋XCTest10개, 총116개 통과. `/private/tmp/outpick-avatar-phase5-verified-tests.log`, `TEST SUCCEEDED` 확인.
- `-allowProvisioningUpdates` 기기 빌드 성공. `GayoonKim.OutPick.dev` 업데이트 설치 성공, 앱 삭제 없음. 이후 devicectl launch 성공과 ImageBaseline 로그 발생 확인.
- 현재 console 수집: `/private/tmp/outpick-avatar-phase5-device-console.log`(세션57643). 민감한 인증 로그를 문서에 복사하지 않는다. 사용자에게 홈/로그인/오류 화면과 QA 표본 확인 요청 중. 프로세스 실행 성공을 로그인/화면 정상 검증으로 대신하지 않는다.

### 진행 중 발견 및 보완

- 최초 통합 실행: Swift Testing106개 중 `joiningRoomRetriesTransientFailureButNotUnavailablePhoto`의 실패 완료 대기 경합1건. fake continuation을 실패시킨 뒤 고정30회 Task.yield로 완료를 가정해, 아직 running 상태에서 정책 이벤트가 전달될 수 있었다. 내부 `loadingPaths` 상태를 읽고 실패 처리가 끝난 뒤 이벤트를 전달하도록 동일 패턴3곳을 보완했다. 실제 사용자 재시도 정책은 변경하지 않았다. 재검증 로그 `/private/tmp/outpick-avatar-phase5-verified-tests.log`.
- 첫 기기 빌드에서 DEV provisioning profile 누락으로 실패. 기존 팀의 `-allowProvisioningUpdates`로 다시 빌드 중(`/private/tmp/outpick-avatar-phase5-device-build2.log`).
- 사용자가 기존 DEV 실행 불가를 알렸다. 새 빌드 설치 전 기존 앱 직접 launch에서 iOS Security/invalid signature·entitlements·untrusted profile 오류를 재현했다. 오류만으로 세 원인 중 하나를 단정하지 않는다. 최신 개발 서명 빌드로 앱 데이터를 유지한 업데이트 복구를 우선한다.

- DEV 계정 및 자료 접근·시각 화면 확인.
- 대표 채팅/댓글 표본 선정(사용자 답변 대기), 스크롤·중첩 참여자·확대 QA.
- 요청/캐시/CPU/메모리/프레임 계측 및 초기값 판정.
- 전체 체크리스트에서 미확인 항목은 별도 유지. 서버 배포·커밋 없음.
