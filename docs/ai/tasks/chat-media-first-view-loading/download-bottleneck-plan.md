# ② 다운로드 병목 해소 — 세부 구현 계획

## 2026-09-22 범위 복귀·설계 재점검

**후속 QA로 판단 변경:** 대량 반복에서 신규 임시 파일3개가 남았고 SDK cancel callback이 내부 완전 종료를 보장하지 않는 구현을 확인했다. 아래 “새 필수 결정 없음”은 QA 전 판단이다. 현재는 취소/파일 소유권 재현·보완 설계가 필요하며② 완료로 처리하지 않는다. [최신 결과](download-bottleneck-results.md).

③ [세부 계획](cache-reuse-implementation-plan.md)은 기록 후 구현 보류. 현재 초점은②다. processor/resources/gate와 기존 결과를 대조했으며 새 필수 제품 결정은 발견하지 못했다.

- 유지 추천: network6/files6/decode2/app IO2/write1.6은 항상 실행될 목표가 아닌 상한이다. 수치는 QA 근거 없이 높이지 않는다.
- files는 저장 완료까지 보유한다. 저장 대기 파일이6개면 새 다운로드도 기다리는 것은 누적 방지 제한이다. 최초 결함인 전송 전체의 write1 직렬화와 구분한다. 기존 files 대기 p95 약3초는 혼합 구간 집계이며 저장 때문이라고 단정하지 않는다. 어느 단계가 files를 오래 보유했는지 확인 후 분리 여부를 재논의한다.
- 대기 visible 우선, 같은 우선순위는 기존 순서. 실행 중 prefetch 강제 선점/전용 슬롯 예약은 추가하지 않는 안을 유지한다. 수요 이탈 취소는① 계약을 따른다.
- SDK 종료 전 permit 조기 반환 금지, 동일 요청 병합, 소비자별 취소, 앱 캐시 I/O 제한은 유지한다.
- 잔여는 검증 한계다: 실제 SDK 취소 완료 시점, 장시간 임시 파일/RSS 누적, 동일 cold 조건 비교, 파일 저장 실패 정리. 이전75개 통과·실제 최대6개는 결과 문서의 기록이며 이번 재실행 결과가 아니다. 이전 임시 로그는 현재 없어 개별 이벤트 재분석 불가. 기존 캐시 보존 제한을 지키며 강제 다운로드/캐시 삭제는 임의 수행하지 않는다.

최신: 사용자 구현 승인 후 Phase1~3 구현·자동75개 통과, Phase4 실기기 QA 진행. [실행 기록](download-bottleneck-results.md)을 우선하며 아래 구현 전 상태는 계획 작성 시점이다.

작성: 2026-09-21. 사용자 요청에 따른 계획 문서이며 **② 제품 코드 구현 전**이다.①은 사용자 QA 수용 상태이고, 검증 범위·한계는 [실행 기록](qa-results.md)을 유지한다. 이 문서의 Phase는①의 [기존 계획](plan.md)과 별개다.

## 1. 목표와 고정 범위

화면에서 필요한 서로 다른 파일 이미지가 다운로드될 때, 네트워크 대기 때문에 공용 디스크 쓰기 슬롯을 점유하지 않도록 한다. 느린 파일 하나가 다른 파일 다운로드 및 캐시 저장을 직렬로 막는 구조를 제거한다.

- 다운로드6·디코딩2·앱 디스크 작업2/쓰기1·decodeBytes/writeBytes 각16MiB를 시작값으로 유지한다. 임시 파일 입장 수는 기존처럼 downloads와 같은6이다. 숫자는 최적값 주장이 아니며 이번 구조 변경과 동시에 조정하지 않는다.
- 중복 요청 병합, visible/prefetch 우선순위 승격, 마지막 소비자 취소, 실패/재시도, revision 기반 오래된 결과 차단을 보존한다.
- 앱 화면/사용자 흐름, Repository protocol, 서버 API/DTO/DB, Container/Coordinator 연결 변경 없음. 기존 Swift/UIKit/MVVM-C 및 공용 pipeline을 사용한다.
- 이미지 실제 크기 대신 maxBytes로 Data/file 경로를 선택하는 정책은 유지한다. 큰 썸네일 바이트량·캐시 용량·축소 저장·GIF/MP4 원본 저장·디코더 크기 정책은③에서 다룬다.
- 업로드 FIFO, raw GIF Data 로더, 동영상 다운로드 서비스, 새 네트워크 라이브러리, 별도 채팅 전용 다운로드 큐를 추가하지 않는다.
- 새 권한·개인정보 항목·외부 전송 목적·서비스 배포는 없다. 서버 쓰기/메시지 전송/전체 캐시 삭제는 검증을 위해 임의 수행하지 않는다.

## 2. 현재 구조와 변경 계약

### 현재

`ChatMediaViewportController → ChatAttachmentImageService → ImageCachePipeline → ImageLoadCoordinator → ImagePipelineProcessor`

1. 메모리/디스크 캐시 조회 및 동일 요청 합류.
2. maxBytes가 min(decodeBytes, writeBytes)를 초과하면 `downloadFile` 진입.
3. files 입장 → 임시 파일 생성 → io(write) 획득 → network 획득 → SDK 파일 다운로드 완료 대기.
4. network/io 반환 → 파일 크기 검사 → decode + io(read)로 이미지 준비.
5. coordinator가 메모리에 반영하고 persistence에 저장을 접수한 뒤 소비자에게 이미지 반환. 디스크 저장 완료까지 화면을 기다리게 하지는 않는다.
6. persistence가 io(write)로 캐시에 복사/교체. 저장 완료 뒤 files lease 반환, payload 마지막 참조 해제 뒤 임시 파일 삭제.

diskWrites=1인3번 때문에 파일 전송 자체가 직렬화된다. 같은 슬롯을 사용하는6번의 캐시 저장도 경쟁한다.

### 변경 후

| 단계 | 소유할 제한 | 해제 시점 |
| --- | --- | --- |
| 파일 경로 입장 | files | 성공 시 저장/소비 처리 완료, 실패·취소 시 정리 완료 |
| SDK 다운로드와 임시 파일 기록 | network + 기존 files | network는 SDK 완료 콜백으로 전송 종료가 확인된 후 |
| 파일 디코딩 | decode + io(read), 기존 files | 디코딩 완료/실패 후 decode/read 반환 |
| 앱 캐시 복사·교체 | io(write), 기존 files | 쓰기 종료 후 lease 반환·payload 해제 |

- `downloadFile`의 network를 감싸는 `io.withPermit(kind: .write)`만 제거하는 구조를 기본안으로 한다. 새 gate나 공개 API를 만들 필요가 없다.
- SDK의 파일 쓰기는 실제로 발생한다. 이를 무제한으로 풀지 않고 network/files 제한으로 제어한다. **io.maxWrites=1은 앱이 관리하는 캐시/로컬 쓰기의 제한이며 SDK 다운로드를 포함한 장치 전체 쓰기 개수 제한은 아니다.** SDK 다운로드 최대6개와 캐시 쓰기1개가 겹칠 수 있다.
- `stored(Data)`의 실제 파일 쓰기, 디스크 캐시 복사/교체, 파일 디코딩 read는 기존 io gate를 유지한다. io gate 전체를 없애지 않는다.
- 네트워크 작업 종료 직후 network를 반환하고 디코딩·저장 대기는 network 밖에서 수행한다. 반대로 files lease를 다운로드 종료 직후 반환하면 저장 대기 임시 파일이 무제한 늘 수 있으므로 기존 긴 수명을 유지한다.
- files6개가 저장 대기로 모두 차면 새 파일 다운로드 입장은 기다린다. 이는 자원 누적을 막는 의도된 제한이며, 모든 저장 지연을 무조건 제거하는 것이 목표는 아니다.
- Data 경로의 바이트 예약은 별도 메모리 보호 계약이므로 그대로 둔다. 다른 공용 network 사용자가 있으면 파일 다운로드6개가 항상 동시에 실행되는 것은 아니다.

## 3. 변경 파일과 영향 지도

경로는 저장소 루트 기준이다. 구현 시작 전 실제 diff와 참조를 다시 대조한다.

| 분류 | 파일 | 작업/영향 |
| --- | --- | --- |
| 필수 제품 변경 | `OutPick/Infra/Cache/ImageCache/ImagePipelineProcessor.swift` | downloadFile의 io/network 중첩 제거, 단계별 lease 수명 보존 |
| 계약 주석 | `OutPick/Infra/Cache/ImageCache/ImagePipelineResources.swift`, `ImagePipelineLimits.swift` | SDK 임시 파일 쓰기와 앱 io 제한의 의미 명시, 수치 유지 |
| 신규 집중 테스트 | `OutPickTests/ImageFileDownloadSchedulingTests.swift` | 실제 processor/pipeline + 제어 가능한 파일 transport로 병렬성·분리·자원 경계 검증 |
| 기존 회귀 | `OutPickTests/ImagePipelineResourcesTests.swift`, `ImageLoadCoordinatorTests.swift`, `ImageCacheRevisionTests.swift` | 기존 계약 유지 확인, 중복되는 테스트는 새로 만들지 않음 |
| 필요 시에만 | `OutPick/Infra/Cache/ImageCache/ImageCacheMetrics.swift` | 기존 network/diskIO/files span으로 구분 불가한 경우 최소 계측 추가 |
| 하네스 | `docs/ai/ENTRYPOINTS.md`, `entrypoints/CHAT.md`, `entrypoints/TESTS.md`, `tasks/active.md`, 본 task 문서 | 코드 위치·새 제한 의미·실행 근거·검증 한계 갱신 |

직접 변경하지 않고 계약을 확인할 경계:

- `ImageCachePipeline.swift`, `ImageLoadCoordinator.swift`, `ImageCachePersistence.swift`, `ImageCacheDiskStore.swift`, `ImageCachePayload.swift`, `ImageStageGate.swift`: 저장 접수/소유권/임시 파일 삭제/취소/우선순위.
- `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseImageDownload.swift`: `ImageStorageTaskHandle`은 cancel 요청만으로 continuation을 조기 완료하지 않는다. SDK 완료 콜백 이후 반환 계약을 보존한다. progress 크기 초과 취소와 완료 후 크기 검증도 유지한다.
- 같은 fileFetcher를 사용하는 `ChatAttachmentImageService`, `RoomImageService`, `AvatarImageService`: 실제 요청의 maxBytes에 따라 영향이 달라지며 모든 아바타가 파일 경로라고 가정하지 않는다.
- `LookbookHTTPImageCache`: 별도 HTTP Data 경로지만 같은 resources의 network/io를 공유하므로 경쟁 회귀 확인. 완료한 룩북 URL 기능을 재설계하지 않는다.

공용 processor와 resource 경계를 공유하므로 Phase는 메인 작업에서 순차 진행한다. DI·Container·Coordinator·서버 계약을 변경할 필요가 생기면 계획 범위를 다시 확인한다.

## 4. 순차 구현 Phase

### Phase 1 — 병목 재현과 계약 고정

- 목표: 현재 직렬화와 쓰기 경쟁을 제어 가능한 테스트로 재현하고 실패 지점을 고정한다.
- 변경 범위: 신규 `ImageFileDownloadSchedulingTests.swift`; 기존 resource/coordinator 테스트는 참조한다.
- 구현: actor 기반 transport spy·명시적 시작/완료 barrier·실제 임시 파일·독립 cache 폴더를 사용한다. 작은 PNG라도 maxBytes를 주입한 byte budget보다 크게 해 file 경로를 강제한다. 실제 대용량 파일이나 Firebase는 필요 없다.
- 완료 기준: 서로 다른2개 파일 중 A를 hold한 상태에서 B의 transport 시작을 요구하는 검사가 현재 코드에서 실패한다. 전송 hold 중 실제 disk.write 완료를 요구하는 검사도 직렬화 경계를 드러낸다. 테스트 종료/실패 시 barrier와 lease를 항상 정리한다.
- 검증 방법: 기존 코드의 실패 결과 저장. 고정 sleep/Task.yield 횟수를 성공 조건으로 쓰지 않고 명시 신호·gate snapshot·유한 timeout을 사용한다.
- 논의 필요: 없음. 실패가 다른 원인일 경우 수정 전에 조사 결과를 기록한다.

### Phase 2 — 다운로드와 앱 쓰기 제한 분리

- 목표: file transport가 io(write)를 점유하지 않게 하되 network/files 상한을 유지한다.
- 변경 범위: processor의 downloadFile, resources/limits의 관련 주석. 불필요한 service/DI 변경 없음.
- 구현 순서: 중첩 io wrapper 제거 → network 완료/크기 검사/prepare 순서 유지 → 성공 payload 소유권 전달 및 실패 catch lease 반환 검토 → SDK 완료 전 permit 조기 반환이 없는지 대조.
- 완료 기준: Phase1 재현 테스트 통과. 실제 파일 전송2개 이상이 겹치고 network/files 상한 초과0. 앱 diskWrites는 여전히1이며 디스크 쓰기 gate 단위 테스트가 유지된다. 전송 중 캐시 쓰기 진행, 쓰기 대기 중 이미지 반환 계약 유지.
- 검증 방법: 신규 집중 테스트와 기존 ImagePipelineResourcesTests 실행. 제한 숫자를 높여 테스트만 통과시키지 않는다.
- 논의 필요: 없음. 실제 SDK 쓰기를 청크별 io gate로 제어하는 별도 transport 재작성은 이번 범위에 포함하지 않는다.

### Phase 3 — 취소·저장·공용 소비자 회귀

- 목표: 병렬화로 드러날 수 있는 lease 누수·중복 전송·저장 전 임시 파일 삭제·늦은 결과를 차단한다.
- 변경 범위: 신규 집중 테스트 보강. 실패가 재현된 경우에만 해당 공용 코드의 최소 수정; API/소유권 계약 변경이 필요하면 먼저 재검토한다.
- 완료 기준: 아래 자동 검증 행렬 통과, 테스트 전용 files/network/decode/io 사용량·대기0, 테스트 임시 파일 잔여0. 기존 저장/revision·서비스 회귀 통과.
- 검증 방법: fake 파일 transport가 취소 요청과 실제 종료 신호를 분리하도록 구성한다. 공유 resources를 두 pipeline에 주입해 전역 상한을 검증한다. 서비스 fake의 호출 결과만으로 실제 Firebase 완료 콜백 계약을 검증했다고 주장하지 않는다.
- 논의 필요: 없음. 원본 캐시 정책·전역 우선순위 선점·서비스별 슬롯 예약 요구가 발견되면② 최소 수정과 구분해 논의한다.

### Phase 4 — 실기기 비교·정리

- 목표: 실제 캐시 미스 파일 요청의 병렬 실행과 사용자 표시 개선을 확인하고① 회귀가 없는지 검증한다.
- 변경 범위: 기존 진단 계측/QA 기록, 필요한 경우 DEBUG 한정 관찰 지점, 하네스.
- 방법: 같은 기기/방/네트워크 조건에서 캐시 상태와 표본 수를 기록한다. 메모리 hit·디스크 hit·파일 다운로드를 구분하고 요청 시작/완료·활성 수·바이트·첫 visible 표시/전체 visible 준비·취소 결과를 비교한다. 전체 캐시를 임의 삭제하지 않는다. 기존 데이터로 미스 표본이 부족하면 독립 진단 캐시 또는 정확히 지정한 QA 캐시 범위를 먼저 정리해 사용자와 확인한다.
- 수동 흐름: 미디어 QA방 진입→과거 사진 묶음→빠른 왕복→확대/닫기→재진입. 사진/GIF/영상은 본문 정적 thumbnail 경로 확인이며 원본 병렬화 성능으로 해석하지 않는다. 아바타/방 이미지/룩북 대표 경로의 표시도 확인한다.
- 완료 기준: fake 검증과 실SDK 증거를 분리 기록. 실제 cache-miss 파일 전송이 겹치는지 확인하고 제한 초과/지속적 메모리 증가/임시 파일 누적/표시 회귀가 없어야 한다. UI 검사만으로 동시 전송을 입증하지 않는다. 속도 배수나 최적 개수는 단정하지 않는다.
- 정리: 임시 계측·QA 파일만 정리, 일반 DEV 실행 복원, 관련 진입점 갱신. 변경 파일·실행 로그·미검증·③ 잔여를 보고. 임의 커밋/운영 배포 없음.
- 논의 필요: 실제 QA에 캐시 상태 변경/새 fixture가 필요할 때 정확 범위만 확인한다. 다운로드6으로 실기기 자원 문제가 관찰되면 수치 조정 근거를 제시한다.

## 5. 자동 검증 행렬

| 시나리오 | 핵심 확인 |
| --- | --- |
| A hold, B 요청 | A 완료 전 B transport 시작; 둘 모두 network 상한 내 |
| 다운로드 중 캐시 쓰기 | 파일 A hold 중 실제 독립 disk.write 완료, A는 계속 실행 중 |
| 쓰기 gate hold | 파일 다운로드 및 read/decode 완료·화면 반환 가능; 캐시 저장만 대기 |
| network/files 포화 | N개 실행 시 N+1번째 대기, 완료/취소 후 입장; 두 pipeline 합계도 상한 준수 |
| 파일 입장/network 대기 취소 | transport 미시작, waiter 제거, 선취한 files 반환 |
| 진행 중 전송 취소 | 실제 종료 신호 전 network/files 조기 반환 금지, 종료 후 모두 정리 |
| transport 실패/크기 초과/디코딩 실패 | 오류 전달, 캐시 미저장, 부분 임시 파일 제거·lease 반환 |
| 디코딩 대기 취소 | network는 이미 반환, decode waiter와 files 정리 |
| 저장 지연 | 이미지 먼저 반환, payload/파일은 저장 완료까지 유지; 포화 시 새 files 입장만 대기 |
| 저장 완료/실패 | 정상 반환 후에도 persistence 종료 시 files/임시 파일 정리 |
| 같은 경로 소비자2명 | 실제 전송1회, 한 명 취소 시 유지, 마지막 취소 시 transport 취소 |
| visible 승격 | files/network 대기 우선순위 반영, 실행 중 전송 재시작 없음; 활성 작업 강제 선점은 요구하지 않음 |
| 삭제/revision/세션 종료 경합 | 늦은 결과가 캐시/화면으로 부활하지 않음; 기존 coordinator/revision 회귀 활용 |
| Data 경로·HTTP 경로 | byte budget와 저장 분리 계약 유지, 공용 network 상한 경쟁 정상 |

테스트 파일은 행렬 항목 수와1:1로 늘리지 않는다. 기존 suite가 충분히 검증하는 계약은 재실행으로 대체하며 새 file 경계만 보강한다. 저장 실패 재현에 별도 제품 추상화를 추가하지 않고 기존 disk API/격리 파일 조건으로 가능한 범위를 사용한다.

회귀 순서: 신규 파일 scheduling + ImagePipelineResources → ImageLoadCoordinator/ImageCacheRevision → ChatAttachmentImageService/AvatarImageService/LookbookHTTPImageCache →① viewport policy/controller/surface/continuity. RoomImageService 전용 테스트 유무를 확인하고 없으면 공용 계약+대표 실기기 표시로 검증한다. 새 UI happy-path 테스트를 대량 추가하지 않는다.

## 6. 실행·판정과 인계

- 이번 요청은 계획 작성이므로 코드 수정·빌드·테스트·기기 조작은 실행하지 않는다. 구현 승인 후 기존 사용자 지시인 자동 테스트→실기기 QA 순서를 적용한다.
- 구현 전 `git status --short`로① 미커밋 변경 및 사용자 변경을 확인한다. HANDOFF.md·docs/portfolio/·firestore-debug.log를 되돌리지 않는다.
- 단위 테스트는 테스트별 독립 resources/cache를 사용한다. 연결된 기기와 실행 목적을 확인한 후 Development scheme의 대상 suite만 실행한다. 예시:

```bash
xcodebuild -project OutPick.xcodeproj -scheme OutPick-Development \
  -destination 'platform=iOS,id=00008110-000168693E91401E' \
  -derivedDataPath /private/tmp/outpick-avatar-device \
  -parallel-testing-enabled NO \
  -only-testing:OutPickTests/ImageFileDownloadSchedulingTests \
  -only-testing:OutPickTests/ImagePipelineResourcesTests test
```

- 로그/결과는② 전용 이름으로 남기고,①의 기존 통과 수에 재실행을 중복 가산하지 않는다.
- 최종 보고는 구조적 직렬화 제거, 실제 동시 전송 증거, 자원/취소 회귀, 미검증 한계를 분리한다. 다운로드 바이트 축소나 캐시 수용량 문제가 남아도②에서 해결됐다고 보고하지 않는다.
- 신규 ADR 후보: SDK 파일 전송은 network/files로, 앱 캐시/로컬 I/O는 io gate로 제어한다. 구현과 검증 후 ADR 반영 여부를 정리한다.
