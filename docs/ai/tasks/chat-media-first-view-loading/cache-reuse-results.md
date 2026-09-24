# ③ 캐시 재사용 개선 — 실행 기록

> 최신: 아래 첫 진입/용량 잔여는 초기 Phase1·2 결과다. 후속 표시 준비 개선과 세 제한 기본 해제 후 사용자 직접 재실행 QA까지 완료했다. 최신 근거는 `display-readiness-plan.md`, 다음 Phase3·4는 [원본 미디어 인계](original-media-handoff.md). 초기 원인 계측부터 재시작하지 않는다.

## 최신 — Phase1·2 구현/검증 완료, 첫 진입·용량 정책 잔여

사용자 확인: 첫 진입에는 로딩 표시가 있지만, 한 번 채워진 뒤 가까운 구간을 위아래로 왕복하면 이미 표시돼 있고 기다려도 안 채워지는 사진은 없음. `/private/tmp/outpick-cache-reuse-phase2-device.log`에서 memoryImmediate140회로 loading 없는 메모리표시 경로의 실제 사용을 확인했다. 고유사진140개나 프레임 깜빡임140회 제거로 과장하지 않는다. 통합 자동89개 통과와 실기기 근접재방문/방재진입 QA를 근거로 Phase1·2 범위를 완료한다.

- disk.lookup hit926/miss498(내부중복조회 포함), 용량퇴거305, 다운로드완료283/고유264/반복19. 반복 중18건은 앞선 용량퇴거와 연결됐고1건 원인 미연결. 기존 정책을 유지한 결과라 원거리/첫진입 모든 대기 해결은 아니다. 이전 QA와 방문량·캐시내용이 달라 총량/시간을 단순 성능비교하지 않는다.
- diskWrite.total/persistence.pending 각282건 모두success. pending.join 실기기표본0이므로 해당경합 개선은 자동테스트 근거다. 이번 QA는 신규송신 검증이 아니며 송신저장 독립수명·준비중삭제도 자동테스트로 확인했다.
- files입장 p95 4073.31ms, decode입장214.92ms, diskRead실행3.20ms, diskWrite전체3.37ms. 첫표시의 파일입장/디코딩 대기는 잔여다. 임의 슬롯확대/캐시증량/재인코딩은 적용하지 않았다.
- SDKsuccess283/cancelled36, 임시파일해제absent319. 관측network/files/decode/io/decodeBytes 종료사용0·대기0. sampler peak138.84MiB/마지막49.69MiB/thermal0. 실제 디스크목록 신규잔존 재검사는 이번에 추가하지 않았으므로 deinit계측과 구분한다.
- 진단종료·일반DEV 복원 성공(`/private/tmp/outpick-cache-reuse-phase2-normal.log`), 캐시삭제/서버변경/커밋 없음. 추가 사용자작업 요청 없음. 다음 원본파일관리 분리(Phase3)와 확대/저장 연결(Phase4), 크기·용량·표시파일 정책 QA(Phase5)는 아직 미완료다.

## Phase2 재사용 구조 구현·통합 검증 중

**최신: 통합89개 통과(XCTest22+SwiftTesting67/7suite), TEST SUCCEEDED. 실기기 BUILD SUCCEEDED/설치/계측 실행 성공.** `/private/tmp/outpick-cache-reuse-phase2-device.log` 수집 중(session25252). 사용자에게 사진을 채운 뒤 가까운 구간2왕복/방재진입 및 체감·잔류빈사진 확인 요청. 기존 캐시 유지, 개선 실기기 결과는 답변 대기다. 아래 진행 중은 이전 상태다.

- 즉시 메모리표시 viewport/service/surface16개 통과(`/private/tmp/outpick-cache-reuse-immediate-tests.log`).
- `ImageCachePersistence.wait(forKey:revision:)` 및 coordinator 세대검사로 cache miss 전 같은 키/같은 세대의 pending 쓰기만 합류한다. 대기 전에 files/decode/IO 슬롯을 얻지 않으므로 저장 슬롯과 교착하지 않는다. caller 취소는 공유 쓰기를 취소하지 않는다. 전역 flush는 조회에 추가하지 않았다.
- pending 단계 자동46개 통과(`/private/tmp/outpick-cache-reuse-pending-tests.log`: XCTest8+SwiftTesting38). 메모리퇴거/저장보류 재조회 다운로드1회 및 다른키 조회, 공용아바타/룩북/revision/coordinator 포함. 후속 로컬저장 변경 전 결과다.
- 송신 `storeImageData`: 변환 전 `beginPreparedStore`에서 세대 확보→준비 후 `storePrepared`에서 세대 확인/메모리 반영→persistence가 payload와 lease 소유. 호출자에게 쓰기 완료 전에 반환한다. 준비 중 삭제/새 세대면 거절하고 예약 해제한다. API의 완료는 표시 준비/저장 인계이며 디스크 성공 보장이 아니다.
- 로컬 저장이 write hold 중에도 반환/메모리 유지, 호출자 종료 뒤 디스크 저장, 디코드 대기 중 삭제하면 늦은 저장 거절 테스트 추가.
- 통합 회귀 `/private/tmp/outpick-cache-reuse-phase2-regression.log`, 기기 빌드 `/private/tmp/outpick-cache-reuse-phase2-device-build.log` 진행 중. 최종 개선 빌드 실기기 비교 전, 원본 store/뷰어(Phase3~4) 미착수. 이미지 크기·용량·계정 보존 정책 변경 없음.

## 앱 재실행 기준선 완료

사용자: 기다리면 사진은 채워지며 스크롤할 때 로딩 표시. 지속 빈사진 문제는 아님. 로그 `/private/tmp/outpick-cache-reuse-relaunch-device.log`에서 disk.lookup hit509/miss162, memory.lookup hit148/miss2356(각각 내부 다중조회 포함), 완료다운로드115/저장성공115/용량퇴거110. files대기 p95 4273.07ms, decode대기187.26ms, diskRead실행3.37ms. 디스크파일 존재만으로 화면준비까지 즉시 완료되지는 않으며, 용량퇴거로 실제 재다운로드도 발생한다. 수집 종료 후 일반DEV 복원 성공. 계측 전용빌드 기준선이며 개선 효과로 표현하지 않는다.

## 반복 스크롤·방 재진입 기준선

사용자 완료 후 `/private/tmp/outpick-cache-reuse-baseline-device.log` 수집 종료, 일반DEV 복원 성공. 총166808개 계측 이벤트이며 begin/end를 중복 합산하지 않았다.

- 완료 body160건/고유resource132개/299010873bytes. 반복28건 중27건은 **앞선 disk.eviction(capacity)** 기록과 동일 resource로 연결됐다. 나머지1건은 관측 퇴거로 연결되지 않아 원인 미확정이다. 완료160건 중114건에서 이전 용량퇴거가 연결됐지만 기존파일의 첫 관측 다운로드도 포함하므로114건을 반복다운로드로 표현하지 않는다.
- disk.eviction174건, diskWrite.total/persistence.pending 각159건 전부success. 다운로드160과 저장159의 차이는 취소·전달 경계가 포함될 수 있어 저장실패1건으로 취급하지 않는다. 이 표본에서는 pending 중 disk miss0.
- memory.lookup hit169/miss5271, disk.lookup hit1124/miss387은 내부 다중조회 포함 횟수이며 사진별 hit율이 아니다. loading 후100ms 이내 memory hit130회 관측. 동일 사진의 반복 상태 알림/여러소비자가 섞일 수 있어130개의 고유 깜빡임을 입증하는 값은 아니다.
- 성공 chatPreview.load p95 2655.94ms, files입장3617.59ms, decode입장199.33ms, IO입장19.79ms, diskRead실행3.28ms, diskWrite전체4.93ms. 단계별 표본/성공·취소 포함 범위가 다르므로 합산하지 않는다. 디버그 로깅 비용 포함, 실제프레임 완료 지연 아님.
- 종료 network/files/decode/io/decodeBytes 사용0·대기0. sampler peak139.59MiB/마지막45.45MiB/thermal0. 용량퇴거가 이번 재다운로드의 주된 관측 원인이다. 용량증가/재인코딩을 임의 적용하지 않고 계획대로 즉시hit/pending 재사용 먼저 진행한다.

## 앱 재실행 기준선 / Phase2 첫 개선

- 진단 앱 재실행 성공, `/private/tmp/outpick-cache-reuse-relaunch-device.log` 수집 중(session35837). 사용자에게 같은 과거 사진 구간10~15초 정지와 빈사진 잔류 여부 확인 요청. 설치된 앱은 **계측 전용** 기준선이다.
- 로컬 Phase2 첫 개선: `ChatAttachmentImageLoading.cachedMemoryImageImmediately`→service 원격 메모리만 조회→Container에서 viewport에 주입. viewport는 진행요청이 없고 memory hit이면 loading 없이 image를 동기 반영한다. 로컬 파일 읽기/디코딩을 동기 API에 넣지 않는다. 기존 실패 재시도·진행요청 병합/취소는 유지한다.
- 재진입에서 loading/비동기 요청0·동일UIImage 확인 테스트 추가. `/private/tmp/outpick-cache-reuse-immediate-tests.log`에서 viewport/service/surface 회귀 진행. pending 합류·송신 저장 수명 개선은 아직 미구현이다.

## 2026-09-23 Phase1 계측 구현

사용자가 원인 계측→캐시 재사용 개선을 승인했다. swift-app-workflow/test-design-workflow 적용. 기존 크기·용량·업로드 규격·계정 보존 정책 유지. Phase2 행동 변경 전 기존 캐시 실기기 기준선을 확보한다.

- `ImageCacheMetrics.linkCacheKey`: resource path, imageCache prefix key, SHA256 디스크 파일명을 하나의 parent span으로 연결한다. 모두 기존 hash로 출력하며 원문·토큰·사진 내용은 출력하지 않는다. 비활성 상태에서는 변환/시계 접근 없이 반환한다.
- `ImageCacheMemoryStore`: 조회 hit/miss·저장·명시 제거 계측. NSCache의 자동 퇴거 사유(메모리 압박/자체 정책)는 API만으로 확정하지 않는다. store 뒤 miss만 보고 압박으로 단정하지 않는다.
- `ImageCacheDiskStore`: 조회 hit/miss, 용량 퇴거 파일/제거 실패, 쓰기 전체 대기 포함 결과 success/failure/cancelled/stale를 계측한다. 반환 결과를 추가했으나 캐시 용량·파일 형식·쓰기 순서는 변경하지 않았다.
- `ImageCachePersistence`: pending 저장 시작~해제 완료, superseded/stale 기록. 기존 독립 Task 소유권은 유지했다. 아직 pending 합류 동작을 추가하지 않았다.
- `ChatMediaViewportController`: loading/image/failed/released 및 load span. 이는 렌더 요청 시각이며 실제 프레임 렌더 완료 시각은 아니다.
- `ChatAttachmentImageService`: 송신 로컬 preview 보존 준비·반환 계측. `returned`는 디스크 성공 보장이 아니며 diskWrite.total 결과와 연결한다.

## 검증

- **자동25개 통과:** XCTest15(viewport8/file scheduling7) + Swift Testing10(metrics5/revision5), TEST SUCCEEDED. 실제 계측은 opt-in이며 자동 테스트는 key 연결/기존 동작을 확인한다.
- 기기 BUILD SUCCEEDED, 기존 앱 업데이트 설치 및 진단 실행 성공. `/private/tmp/outpick-cache-reuse-baseline-device.log` 수집 중(실행 session87103). 사용자에게 과거 사진10초 정지→동일 구간2왕복→방 재진입→밖에서15초 요청. 앱 재실행 측정은 후속으로 분리했다. 완료/체감 답변 대기.
- Phase2 전 코드 확인: viewport.start는 메모리 hit 전 loading을 전달한다. 원격 persistence는 이미 독립 Task지만 memory miss 시 pending 저장에 합류하지 않는다. 송신 `storeImageData`→coordinator.store는 disk.write 완료를 기다린다. 이것이 실기기 재로딩에서 차지하는 비중은 아직 미확정이다.

- `ImageCacheMetricsTests`에 resource/storage/file 연결과 비밀 값 비노출 검증 추가, disabled 검증에 연결 API 포함.
- metrics/file scheduling/revision/viewport 회귀 로그: `/private/tmp/outpick-cache-reuse-instrumentation-tests.log`.
- 실기기 빌드: `/private/tmp/outpick-cache-reuse-instrumentation-device-build.log`.
- 아직 기준선 QA 전이며 반복 로딩 원인별 비중/개선 효과를 수치로 확정하지 않는다. 기존 캐시 삭제·새 메시지 생성 없음.

## 다음

기존 QA 방 왕복·재진입·재실행 기준선에서 memory/disk/pending/network와 퇴거를 연결한다. Phase2는 즉시 메모리 hit·저장 중 재조회 합류·로컬 저장 수명 독립을 순차 검증한다. 삭제/세대 변경 부활·교착·공용 아바타/룩북 영향 자동 회귀가 필요하다.
