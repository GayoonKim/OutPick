# ② 다운로드 병목 해소 — 구현·검증 기록

## 최종 — ② 취소·파일 수명 필수 회귀 완료

진단 인자 없는 일반DEV 복원 성공(`/private/tmp/outpick-sdk-fixed-normal-restore.log`). 커밋·서버배포·기존 캐시 삭제 없음.

사용자가 빈 이미지는 **빠른 스크롤·방 이탈 직전에만** 보였다고 추가 확인했다. 정지 후 지속 빈 화면 결함으로 보고하지 않는다. 공식12.17.0 적용 후 취소87건, 생성/해제90개, 신규 임시 파일0, 측정 gate 종료 사용/대기0. 구12.3.0 취소 후 재시작·파일 생성 재현 실패 / 수정12.17.0 동일 테스트 통과, 공용87개 통과 및 실기기 빌드·취소 QA를 근거로② 필수 잔여를 종료한다. 일반 DEV 복원 실행 요청. 다음은③ 계획의 취소·파일 수명·캐시 재사용 구현이며 크기/용량/표시 파일 정책은 QA로 결정한다.

한계: 이전 잔여3개 각각의 생성 원인을 역추적해 입증한 것은 아니다. 이번 실제 전송은 취소 표본87건이고 완료 다운로드0이므로 새 SDK 대량 성공 전송 속도 비교 결과로 사용하지 않는다. 공식 수정·fake control 성공·기존 병렬성 검증을 함께 근거로 삼는다. 이번 sampler peak133.66MiB/종료45.47MiB/thermal0. 기존 임시 파일13개와 기존 캐시는 보존했다.

## 공식 SDK 수정 적용·회귀 진행

- 최종 수정 SDK 단독 테스트도 통과(`/private/tmp/outpick-firebase-cancel-after-final.log`,1개/실패0/TEST SUCCEEDED). 앞선87개와 중복 합산하지 않는다.
- 사용자 최종 취소 QA3회 완료, 앱 멈춤 없음·빈 이미지 잔류 보고. 계측상 SDK 취소 callback87건, temporaryFile 생성90/해제(absent)90, 사후 폴더13→13 신규0(`/private/tmp/outpick-sdk-fixed-files-after.json`), network/files/decode/diskIO/decodeBytes 마지막 사용0·대기0. caller success1127/cancelled476/returnedAfterCancellation2, non-cancel failure 관측0. 빠른 이탈 표본에서 SDK 성공 전송0으로 지속 대기 후 표시까지 입증하지는 않는다. 사용자의 빈 이미지가 정지 후에도 남는지 확인 질문 중이며② 전체 완료를 서두르지 않는다.

- 구12.3.0 비교 재현 완료(`/private/tmp/outpick-firebase-cancel-before.log`): 동일 테스트1개에서 예상3개 assertion 실패(취소 후 fake HTTP 재시작, state success로 변경, 목적지 파일 생성). 최초 비교 빌드는 snapshot.state API 차이와 격리 프로젝트 LocalSecrets 경로 누락으로 실행 전 실패했으며 각각 task.state 공통 API/원래 설정 read-only symlink로 맞춘 뒤 실제 실행했다. 이 실패는 이전 잔여3개를 개별적으로 증명하지 않지만 SDK 취소 후 재시작 결함을 직접 입증한다.
- 수정 DEV 설치·계측 실행 성공. QA 전 파일13개(`/private/tmp/outpick-sdk-fixed-files-before.json`), 기존 캐시·파일 삭제 없음. 사용자에게 빠른 과거 스크롤/로딩 중 방 이탈3회/마지막15초 대기 요청. `/private/tmp/outpick-sdk-fixed-device.log` 수집 중. 최종 상태 검사 API만 공통으로 맞춘 수정 SDK 단독 재검증도 진행 중(`/private/tmp/outpick-firebase-cancel-after-final.log`).

- 실기기 빌드: 기존 DerivedData에서 Firestore bridge 타입 컴파일 실패. 새 `/private/tmp/outpick-firebase-12.17-device` DerivedData에서 동일 lock/소스로 BUILD SUCCEEDED(`/private/tmp/outpick-firebase-cancel-clean-device-build.log`). SDK 추가 변경 없이 빌드 산출물 격리로 해결됐다. 최종 설치·기기 QA는 진행 중.

- 현재 lock의 Firebase12.3.0에서 발견한 취소 상태 경합은 공식 커밋 `c6b30ac647c48bcae590aa85fad2706872539137`(2026-07-09, Fix StorageUploadTask cancel, StorageDownloadTask도 포함)에서 상태 lock/초기 취소 guard/비동기 준비 후 재검사/취소 후 success 차단으로 보완됐다. 공식12.17.0 태그에서 해당 guard를 확인했다. https://github.com/firebase/firebase-ios-sdk/commit/c6b30ac647c48bcae590aa85fad2706872539137
- 프로젝트의 Firebase 최소 버전을12.17.0으로 올리고 lock도12.17.0(`33a468adfdb75b53f05a37e7c886ca7c962b5c17`)으로 갱신했다. 기존 upToNextMajor 정책 유지. 연동 AppCheck11.3.2/GoogleAppMeasurement12.17.0/GoogleAdsOnDeviceConversion3.6.1 변경 및 swift-protobuf pin 제거가 resolver에서 발생했다. 임의 URLSession 전송 교체·서버 변경·동시 제한 변경 없음.
- `FirebaseDownloadCancellationRegressionTests`는 실제 SDK task를 먼저 취소하고 나중에 enqueue하는 순서에서 전송 재시작/파일 생성이 없는지 검증한다. SDK 내부 테스트 접근은 테스트 target에만 사용한다. 유효한 앱 호스트 설정에 고유 가짜 bucket 서비스를 분리하고 해당 서비스의 authorizer를 해제·HTTP testBlock을 설정한다. 실제 Storage 요청/캐시 삭제 없음. 정상 control 전송도 확인해 fake 미실행을 성공으로 오인하지 않는다.
- 신규 테스트 초기 컴파일 타입 표기 오류 수정. 별도 dummy FirebaseApp 구성은 호스트 구성과 맞지 않아 XCTest에서 런타임 종료가 발생했고, 기존 호스트+독립 bucket 방식으로 수정 후 단독 통과했다. 이 실패를 제품 회귀 통과로 숨기지 않는다.
- `/private/tmp/outpick-firebase-cancel-all-regression.log`: **XCTest16 + Swift Testing71/7suite =87개 통과**, TEST SUCCEEDED. SDK 직접 재현1, 파일 scheduling7, viewport8 및 pipeline/coordinator/revision/채팅 이미지/업로드/아바타/룩북 공용 회귀.
- `/private/tmp/outpick-sdk-cancel-baseline`은 구SDK 비교용 격리 프로젝트(코드 read-only symlink), 별도 derived data로 같은 테스트 실행 중. 작업 프로젝트를 되돌리지 않는다. 수정 전 실패 결과와 수정 후 실기기 반복 잔여0 확인 전② 완료/③ 착수로 표시하지 않는다.

## 파일 생명 주기 추가 계측 재현 결과

사용자 빠른 스크롤/이탈3회 완료 후 `/private/tmp/outpick-file-lifetime-device.log`에서 temporaryFile.created350 / released(absent)350 / removeFailed0 / 미해제 key0. SDK callback cancelled330/success19, callback 뒤 progress 이벤트0. network/files/decode/IO 최종 사용0·대기0. `/private/tmp/outpick-lifetime-before.json`13개와 `/private/tmp/outpick-lifetime-after.json`13개가 동일하며 신규 잔여0.

이는 이번 표본에서 정상 정리된 증거이지 앞선 신규3개 원인 규명/수정 완료가 아니다. 늦은 쓰기와 deinit 사이의 직접 경합은 이번에 재현되지 않았다. `GTMSessionFetcher`는 다운로드 완료 시 목적지 부모 디렉터리를 생성하는 코드도 있어 작업별 디렉터리 삭제만으로 늦은 파일 생성을 차단할 수 있다고 가정하지 않는다. 실제 종료 경계를 보장할 대안의 인증·취소·서버 계약 영향 검토가 필요하다. 무작정 재현 QA 반복으로 사용자 부담을 늘리거나 임의 지연 삭제를 적용하지 않는다. 계측 후 일반 DEV 복원 실행.

## 2026-09-22 잔여 검증 진행

### 최종 판정 — 파일 정리 잔여 발견, ② 완료 처리 금지

18:03:35 진단 인자 없는 일반 DEV 실행 복원 성공. 이번 제품 동작 수정은 없고 SDK 관찰 계측·테스트·하네스만 변경했다.

- 사용자 약3분 대량 반복 완료, 멈춤·점진적 느려짐 없음. 취소 QA 포함 약6분 계측에서 network 동시 최대6, 관측된 network/files/decode/io/decodeBytes 종료 사용0·대기0. writeBytes는 이번 파일 경로에서 이벤트가 없어 실측0으로 단정하지 않는다.
- 공용 완료 body306건/고유hash217개/453,554,252bytes. SDK callback success306/cancelled635/failure1. 같은 디코딩 요청의 캐시 계층을 중복 합산하지 않는다. 전체 앱/취소/반복 조회가 섞인 표본이며280장 각각의 재다운로드 원인 판정이나 동일 cold 비교가 아니다.
- 단계별 p95: network 입장0.08ms, files 입장2234.82ms, decode 입장210.44ms, IO 입장5.12ms, 실제 diskRead2.68ms/diskWrite2.03ms. files 대기가 크지만 네트워크/디코딩/저장 중 어느 보유 단계 때문인지 이 집계만으로 확정할 수 없다.
- 200ms 샘플러 내부 peak137.02MiB, 최종 보고 구간 약52.49MiB(마지막15개1초 로그 동일), thermal0. 장시간 모든 누수 부재를 입증한 결과가 아니다.
- **실패 발견:** `/private/tmp/outpick-repeat-files-after.json`에서 시작 전10개 외 신규3개(0/202788/3776791bytes)가 남았다. 수정 시각17:58:29~31로 이번 QA 중 생성됐다. 슬롯0이어도 임시 파일 잔여0 조건은 실패했다. 기존10개 포함 삭제하지 않았다.
- **이전 취소 해석 정정:** 실제 FirebaseStorage `StorageDownloadTask.cancel(withError:)`는 `fetcher?.stopFetching()` 후 즉시 failure observer를 발행한다. `enqueueImplementation`은 fetcher service 획득을 await한 뒤 별도 진행하며 앱 completion은 failure observer에 연결된다. 따라서 public completion 수신을 내부 모든 네트워크/파일 쓰기 종료의 보장으로 취급하면 안 된다. 첫6건8~9ms는 취소→SDK callback 지연이며 실제 transport 완전 종료 시간이 아니다. 신규3개가 이 경합 때문인지 앱 참조 잔존 때문인지는 파일별 create/deinit/SDK 상태 연결이 없어 미확정이다.
- 기존 fake 종료 barrier 테스트는 앱 소유권 계약만 검증하며 실제 SDK 내부 취소 의미를 대신하지 않는다. 신규 설계 쟁점: SDK 공개 API로 실제 종료/파일 소유권을 어떻게 보장할지. 임의 sleep/주기 삭제로 증상을 숨기거나 transport 전체를 승인 없이 교체하지 않는다.
- 집계 `/private/tmp/outpick-download-remaining-summary.json`. 원본 콘솔은 민감한 타 기능 로그가 포함될 수 있어 외부 공유하지 않는다. QA 종료 후 진단 인자 없는 일반 DEV 복원 요청. 후속은 실패 재현/원인 연결과 취소·임시 파일 수명 보완이며③ 캐시 정책 튜닝과 구분한다.

### 실기기 취소 1회차 결과

- 사용자 로딩 중 방 이탈 확인. 실SDK file 취소6건 모두 callback outcome=cancelled, 요청→callback8.11~8.98ms(이 표본에 한함).
- 이후 network/temporaryFiles/decode/diskIO 최종 reserved가 모두 active0/waiting0. callback 개별 parent와 gate metric parent는 실행 맥락이 달라1:1 슬롯 대응으로 과장하지 않는다. SDK callback 뒤 continuation 반환 코드 및 fake 종료 barrier 테스트와 함께 해석한다.
- 임시 폴더 사후 `/private/tmp/outpick-cancel-files-after.json`: 기존10개 목록 그대로, 이번 실행 신규 잔여0. 기존 잔여의 발생 원인은 과거 강제 종료 등 가능성이 있어 미확정이며 삭제하지 않았다.
- 약3분·3회 이상 대량 왕복/방 재진입1회/마지막15초 방 밖 대기를 사용자에게 요청했다.② 본문 다운로드를 분리하기 위해 확대는 제외했다. 대량 QA 결과 대기 중.

- 사용자 승인 순서: 저장 실패 자동 검증→실기기 취소→대량 반복/대기 시간。
- `ImageFileDownloadSchedulingTests.testDiskWriteFailurePreservesDisplayAndReleasesFileThenRecovers` 추가. 격리 cache 디렉터리 자리에 일반 파일을 두어 실제 disk copy/write 실패를 유도한다. 이미지 반환/메모리 동일 객체 유지, 디스크 miss, 재조회 추가 fetch0, 임시 파일 제거, 모든 gate 사용/대기0, 디렉터리 복구 후 다음 파일 저장을 확인한다. 기기 기존 캐시를 손대지 않는 테스트다.
- iPhone14 대상7개 실패0 통과(`/private/tmp/outpick-download-write-failure.log`). SDK 관찰 계측 포함 빌드에서도 동일7개 실패0(`/private/tmp/outpick-download-cancel-instrumentation.log`). 두 실행을14개 고유 테스트로 합산하지 않는다.
- `FirebaseImageDownload.file`에 opt-in ImageBaseline의 `firebase.file`, `firebase.file.cancelRequested`, `firebase.file.callback` 추가. 경로는 기존 hash 처리, callback 결과는 success/cancelled/failure. 전송/취소/permit 동작 변경 없음.
- QA 시작 전 `tmp/outpick-image-loading` 잔여10개(과거 날짜 포함)를 `/private/tmp/outpick-cancel-files-before.json`으로 기록. 이번 실행 누수로 단정하거나 삭제하지 않는다.
- SDK 계측과 `OUTPICK_MEDIA_QA=1`로 DEV 실행, `/private/tmp/outpick-download-cancel-device.log` 수집 중. 사용자에게 빠른 과거 스크롤→로딩 중 방 이탈→10초 대기 요청. 실제 취소/장시간 QA 결과는 아직 미확정. 끝나면 진단 없는 DEV로 복원한다. 원본 콘솔에는 다른 앱 로그가 포함돼 공유 보고에는 선별한 hash metrics만 사용한다.

2026-09-21 사용자 구현 승인 후 순차 진행. [계획](download-bottleneck-plan.md)의 구조 분리 구현/자동 회귀와 기존 캐시 실기기 계측 완료. 실제 파일 전송 병렬성 확인, 반복 스크롤의 재로딩/재다운로드 문제는 잔여로 확인됐다. 장시간 메모리·동일 cold 조건 비교까지 완료했다는 의미는 아니다.

## 변경

- `ImagePipelineProcessor.downloadFile`에서 SDK 파일 다운로드를 감싸던 `io.withPermit(.write)`를 제거했다. network/files 제한은 유지한다.
- 다운로드6, decode2, 앱 I/O2·쓰기1, files6, byte budget 수치는 변경하지 않았다. resources/limits 주석에 SDK 임시 파일 쓰기와 앱 관리 I/O의 경계를 명시했다.
- files lease는 기존처럼 디코딩·비동기 캐시 저장까지 보유한다. SDK 취소 완료 콜백, 저장 소유권, coordinator의 병합/우선순위/revision, API/DI/서버 계약은 변경하지 않았다.
- 새 `OutPickTests/ImageFileDownloadSchedulingTests.swift`6개: 느린 전송 중 다른 다운로드/캐시 쓰기, 두 pipeline의 공용 files 상한·저장 대기 중 표시, 취소 종료 신호 전 permit 보존, network 대기 취소, 전송 오류/크기 초과/디코드 실패 정리, 파일 디코드 대기 취소.

## 실행 근거

1. 초기 테스트 빌드에서 최소 iOS 호환 오류가 발생했다. 새 테스트의 ContinuousClock/Duration을 systemUptime/기존 sleep API로 바꿨다. 앱 동작 실패와 구분한다. `/private/tmp/outpick-download-separation-before.log`.
2. 기기 잠금 해제 후 기존 제품 코드에서 A를 hold하면 B 다운로드 시작·별도 캐시 쓰기 완료 신호가3초 내 발생하지 않는 재현에 성공했다. cleanup barrier를 열어 모든 작업을 정리했다. `/private/tmp/outpick-download-separation-repro.log`, 예상 assertion 실패1개(미충족 신호2개).
3. 수정 후 `/private/tmp/outpick-download-separation-regression.log`, `/private/tmp/outpick-download-separation-regression.xcresult`: **XCTest24개 + Swift Testing51개/6suite =75개 통과, TEST SUCCEEDED**.
4. XCTest: 신규 scheduling6개 + viewport controller8/policy2/surface3/continuity5. Swift Testing: ImagePipelineResources, ImageLoadCoordinator, ImageCacheRevision, ChatAttachmentImageService, AvatarImageService, LookbookHTTPImageCache.① 누적 수와 중복 합산하지 않는다.
5. fake 전송은 취소 요청 후 barrier가 실제 종료될 때까지 network/files 보유를 확인했다. 실제 Firebase SDK 취소·네트워크 성능 검증을 대신하지 않는다. 저장 실패에 대한 신규 파일 경로 전용 주입 검증은 이번6개에 포함되지 않았으며 기존 정리 코드/기존 회귀와 구분한다.

## 실기기 QA

- 연결된 iPhone14 Development 앱을 `-ImageLoadingBaseline`으로 실행했다. `/private/tmp/outpick-download-separation-device.log`에 기존 hash 기반 계측을 수집한다. 실제 URL/인증값은 보고서에 노출하지 않는다.
- 기존 캐시·로그인·서버 데이터를 유지했다. 초기에는 캐시 hit만 발생했으나 사용자 과거 대량 사진 스크롤 중 실제 파일 전송이 발생했다. 별도6개 검증은 사용자가 기존 캐시 화면 QA만 선택했고 실행하지 않았다. 새 fixture/캐시 삭제/추가 전송 없음.
- 사용자 결과: 이전보다 빨라졌고 기다리면 모두 로딩되지만 여전히 느리며, 위아래로 벗어났다가 돌아오면 다시 로딩된다. 사용자 전체 표시 개선 완료로 처리하지 않는다.
- 최종 집계 `/private/tmp/outpick-download-separation-summary.json`: 완료 file body241건, 고유 hash 경로188개, 반복 경로46개/추가 완료53건, 총408,795,809bytes. 완료 file body의 parent와 network 활성 span을 연결해 실제 파일 전송 동시 최대6 확인. 공용 network 최대6, 파일 입장 최대6도 관찰됐다. 캐시 정리 diskTrim5회.
- 캐시 이벤트: disk1044/local1043/memory241/miss792. disk/local은 같은 로딩의 서로 다른 계층 이벤트일 수 있어 합산해 요청 수로 해석하지 않는다. file body241건은 완료 바이트 기록이며 취소/미완료 전송을 포함한 전체 시도 수가 아니다.
- 최종 network/files/decode/io snapshot 모두 active0/waiting0. 실제 다운로드 직렬화 제거는 입증됐지만 전체 UIImage 메모리나 OS RSS 누수 검증을 뜻하지 않는다.
- 구간별 타이밍 참고: 파일 입장 대기 p95 약3016ms, decode 대기 p95 약216ms, 실제 diskRead p95 약3.7ms. 혼합 스크롤/취소/다른 화면을 포함한 진단 실행 값이며 동일 cold 조건 before/after 비교 또는 화면 표시 지연 수치로 쓰지 않는다.
- 반복 표시 지연에는①의 화면 밖 이미지 해제 이후 메모리/디스크 재조회가 포함된다. 큰 썸네일 보관과 캐시 정리의 영향이 의심되지만, 각 반복 다운로드와 실제 eviction의 개별 대응은 로그가 없어 확정하지 않았다.③에서 표시용 저장 크기/메모리 재사용/원본 분리와 함께 분석할 근거로 남긴다.
- 임시 파일/메모리의 실기기 장시간 누적, SDK 취소 종료 callback 시점, 동일 cold 조건 속도 비교, 캐시 실패 주입은 잔여 검증 한계다. 앱 쓰기/원본/GIF/영상의 저장 정책은 변경하지 않았다.
- QA 후 진단 인자 없는 일반 DEV로 복원했다.③ 캐시/원본 분리는 미착수이며 별도 설계 대상이다.
