# Active Task Index

> **채팅 검색·차단 목록 완료(2026-10-02):** 구현·자동 검사·DEV 실기기 QA와 QA 자료 정리까지 완료했다. 공개 기준은 [최종 계약·검증·배포 경계](../architecture/CHAT_MESSAGE_SEARCH.md)다. 로컬 단계별 기록은 chat-message-search/에 보존하며 아래 다른 작업 이력과 구분한다. 운영 배포는 별도다.

> **채팅 미디어 7일 만료: 구현·개발 QA·다섯 게이트·최종 리뷰 완료.** [공개 최종 계약·검증·운영 주의사항](../architecture/CHAT_MEDIA_RETENTION.md)을 기준으로 한다. 작업 단위 커밋을 정리했고 PR/병합 상태는 저장소 기록을 따른다. 로컬 상세 실행 기록은 `chat-media-retention/progress.md`에 보존한다. 운영 배포는 포함하지 않는다. 아래의 “다음 작업/미구현” 표기는 과거 작업의 이력이다.


> **다음 핵심 작업 확정:** [전송 시점+7일 만료 설계·구현 인계](chat-media-first-view-loading/retention-next-handoff.md)를 먼저 읽는다. 이번 완료 미디어 개선 커밋/PR/자체리뷰/머지 진행, [리뷰 기록](chat-media-first-view-loading/review.md). 아래 QA 진행 문구는 당시 이력이다.

> **최신 — 계정 왕복 QA 완료:** B에서 A사진오표시없음 사용자 확인. 동일resource B miss/별도 namespace, A복귀 hit/재다운로드0. A80파일 보존+B1파일 생성/temporary0. 일반실행복원. 전송시점+7일 만료는 확정 정책/별도 미구현 후속. [결과](chat-media-first-view-loading/original-media-results.md).

> **최신 — 같은 계정 재로그인 통과:** 사용자 완료+로그 동일현재/인접2 cache hit, 원본 재다운로드0 확인. 다음 다른 계정 왕복 QA. baseline console70763 유지. [결과](chat-media-first-view-loading/original-media-results.md).

> **최신 — 계정 재사용 QA:** store 자동10개 통과/로그아웃·계정교체 DI 연결 확인. baseline console70763 `/private/tmp/outpick-original-account-console.log`. 사용자 같은 사진 확대→로그아웃→같은 계정 로그인→동일 사진 확대 확인 대기, 이후 다른 계정 왕복. 전송시점+7일 공통 만료는 확정/별도 미구현. [결과](chat-media-first-view-loading/original-media-results.md).

> **최신 — 영상 저장 중 닫기6개 통과:** 실제 UIKit dismiss+지연 fake로 두 화면 준비/제출 후 성공/실패 검증 완료. 늦은 UI 차단·파일/lease 해제·원본 보존 확인, 제품 코드 변경 없음. 다음 계정 전환/재로그인 수동 QA. [결과](chat-media-first-view-loading/original-media-results.md).

> **최신 — 영상 저장 결과 UX:** 사용자 요청으로 두 영상 화면의 중앙 결과 알림/기술 오류를 하단 “저장 완료”/“저장 실패” 토스트로 변경. 기기 build 후 설치·일반 실행/시각 확인. 영상 최종 재생·저장본 화면/소리 및 닫기·계정 QA는 잔여. [결과](chat-media-first-view-loading/original-media-results.md).

> **최신 — 같은 영상 재생 회귀 보완:** 원본 cache hit의 bin 직접 재생 경로에 MP4/MOV 확장자 링크와 수명 lease 적용. 실제 AVURLAsset 재생 가능/Photos 저장/원본 보존 및 resolver 회귀 통과. 기기 수정본 설치 후 같은 영상 재생·저장 재확인 우선. [결과](chat-media-first-view-loading/original-media-results.md).

> **최신 — 영상 저장 보완:** 사용자 재생 시작 짧은 지연/저장 실패. 합성 MP4 bin의 Photos3302 재현 후 MP4/MOV 헤더 식별·확장자 사본 제출 수정. 실제 Photos 통합/형식 회귀 및 기기 build 통과. 수정본 설치 후 같은 영상 저장 사용자 확인 우선, 닫기·계정 QA는 이후. [결과](chat-media-first-view-loading/original-media-results.md).

> **최신 — GIF 실기기 통과:** 사용자 확대 재생·저장·사진 앱 애니메이션 확인 완료. 다음 영상 재생·저장→저장 중 닫기→계정 왕복. [결과](chat-media-first-view-loading/original-media-results.md).

> **최신 — 순차 QA:** 현재 우선 실기기 기록 분석 완료, current miss3건에서 현재 다운로드 종료 뒤 인접2 시작 확인(표시 준비1.06~1.16초, 이전과 다른 사진으로 개선율 미확정). 로딩 문구 변경 사용자 확인 완료. 다음 GIF 재생·Photos 저장→영상→닫기·계정 수명 검증. [결과](chat-media-first-view-loading/original-media-results.md).

> **최신 — 확대 로딩 문구 숨김:** 사용자 승인대로 미리보기 위 “불러오는 중…” 제거, 빈 화면 spinner/실패 retry/저장 안내 유지. 기기 build 성공, 업데이트 설치 후 일반 실행으로 확인. 단순 표시 조건 변경으로 자동 테스트 추가/재실행 없음. 현재 우선 다운로드 정책 실기기 로그는 `/private/tmp/outpick-original-current-first-console.log`에 보존(성공 다운로드20건, 분석 잔여).

> **최신 — 현재 원본 우선 구현 완료:** 사용자 승인 정책 적용, 뷰어7개 테스트·기기 build 성공. 현재 파일 확보 후 인접 시작/현재 decode 병행, 페이지 전환·닫기 회귀 확인. 실기기 순서/체감 QA 대기. [결과](chat-media-first-view-loading/original-media-results.md).

> **최신 — 첫 로딩 실측 완료:** 현재 사진 다운로드1.92초/전체2.02초, 같은 사진 재열기0.10초. gate <1ms. 인접2장 동시 전송의 경합 영향은 미확정. 현재 사진 우선 후 인접 시작 vs 기존 동시 정책 논의 대기, 아직 속도 정책 변경 없음. 측정 종료 후 일반 실행 복원. [결과](chat-media-first-view-loading/original-media-results.md).

> **최신 — 원본 첫 로딩 조사:** 사용자 사진 저장 성공 확인 후 속도 조사 승인. store cache/gate/download/bytes와 viewer acquire/decode를 기존 ImageCacheMetrics에 연결. 기기 build/install 성공, baseline 실행 console96393 `/private/tmp/outpick-original-latency-console.log`. 미확대 사진 실측 대기이며 속도 개선은 아직 미확정. [결과](chat-media-first-view-loading/original-media-results.md).

> **원본 사진 저장 두 번째 보완:** 형식 옵션만 전달한 첫 수정도 실기기3302로 실패. Simulator 실제 Photos에 `.bin` JPEG 제출 시 같은 오류 재현→실제 확장자 임시 사본 제출로 실제 저장 성공. 통합 포함21개·기기 build 통과(`/private/tmp/outpick-original-photos-staged-{tests,device-build}.log`). 수정본 기기 설치 후 같은 사진 저장 사용자 확인 우선, GIF/영상 후속. 최초 로딩만 지연/재열기 즉시·화질 정상은 사용자 확인 완료. [결과](chat-media-first-view-loading/original-media-results.md).

> **원본 실기기 QA 시작:** 사용자 iPhone14 연결 완료. DEV 업데이트 설치/일반 실행/main tab 확인, console96030 `/private/tmp/outpick-original-device-console.log`. 사진 묶음 확대·왕복·재열기·사진 앱 저장 결과 대기. 첫 파일 관찰은 cache4개/18,383,128bytes·temporary0(`/private/tmp/outpick-original-qa-start-files.json`)이며 사용자가 이미 조작한 뒤일 수 있어 빈 캐시 기준선으로 취급하지 않는다. GIF/영상/닫기·계정 QA 후속.

> **2026-09-24 원본 Phase3·4 구현/자동83개 통과:** 계정별 보관/같은 계정 재로그인 재사용 사용자 확정. 원본512MiB store·lease·삭제/세대, 사진±1/GIF 활성·원본 저장/닫기 취소, 영상 스트리밍/저장 연결. [원본 결과·검증 한계](chat-media-first-view-loading/original-media-results.md). Simulator/실기기 build·diff check 성공, iPhone14 disconnected로 연결 요청(설치/실행 전). ③ 전체 QA와 7일 만료는 완료 아님. 아래 정리만/미착수 기록보다 이 기록이 우선한다.

> **현재 인계/정리만 완료:** 새 스레드는 [③ 확대 원본·저장·파일 수명 인계](chat-media-first-view-loading/original-media-handoff.md)부터 읽고 기존 계획 Phase3→4→통합 QA를 진행한다. 현 스레드는 구현 중단 상태이며 사용자 새 진행 요청 후 재개. 아래 오래된 QA 대기/최대2개/옵션 전용 문구는 역사 기록이다.

> **최신 최종 QA 완료:** 채팅 디스크 준비·직접 decode/IO 세 동시 제한을 환경변수 없이 기본 해제. 자동26개·기기 빌드/설치/일반 실행 통과. 사용자 직접 앱 재실행 후 빠른 스크롤도 이미 로딩된 것처럼 표시됨 확인. 표시 준비 개선 완료, ③ 원본/저장 후속 범위는 별도. [최종 기록](chat-media-first-view-loading/display-readiness-plan.md).

> **최신 예측선로딩QA:** direct-only 빠른스크롤loading잔여→속도/도착구간선로딩·빠른이탈즉시취소구현,자동30개통과. `/private/tmp/outpick-predictive-prefetch-device.log` session40665실행,사용자이동중loading/정지화면즉시표시QA답변대기. [기록](chat-media-first-view-loading/display-readiness-plan.md).

> **최신 direct disk QA:** 사용자파일URL준비+속도/도착선로딩확정. direct disk만먼저구현·자동47개통과·기기실행성공. `/private/tmp/outpick-direct-disk-device.log` session13182에서사용자과거사진빠른스크롤/왕복답변대기. 선로딩변경아직전이며다음순차진행. [기록](chat-media-first-view-loading/display-readiness-plan.md).

> **최신:** 1GiB예산대량왕복·재실행QA 완료. 재실행network완료0/diskhit358/miss0, 짧은표시대기는decode/압축data입장후보. 다음승인순서2단계디스크표시대기→3단계선로딩, 원본분리는그뒤. [실측](chat-media-first-view-loading/display-readiness-plan.md).

> **1GiB 장거리QA 완료/재실행검증중:** 사용자반복로딩·버벅임·발열·빈사진없음. 메모리즉시표시2043,고유다운로드85/반복완료0,용량퇴거·압박0. 캐시339개계산929MiB/앱footprint최고126.35MiB 별도지표. 재실행진단session53004 `/private/tmp/outpick-display-budget-relaunch-device.log`에서사용자QA답변대기. [기록](chat-media-first-view-loading/display-readiness-plan.md).

> **최신 1GiB QA:** 사용자확정에따라채팅메모리1GiB LRU/압박축소·디스크1GiB/정리900MiB 구현, 고유자동58개통과·기기실행성공. `/private/tmp/outpick-display-budget-device.log` 계측, 사용자장거리왕복/방재진입답변대기. 앱재실행QA후속. [계획/근거](chat-media-first-view-loading/display-readiness-plan.md).

> **최신 순서 변경:** 사용자 표시파일·예산→디스크표시대기→스크롤선로딩 순서승인. 원본분리보다앞당김. 고유275개398.29MiB 근거로 파일유지/채팅공용디스크1GiB·정리900MiB QA제안 답변대기, 아직 정책코드변경없음. [계획](chat-media-first-view-loading/display-readiness-plan.md).

> **③ Phase1·2 최종:** 자동89개+기기QA완료, 사용자 가까운왕복이미지유지/미표시잔류없음 확인. memoryImmediate140회/저장282success, 일반DEV복원성공. 첫진입대기·용량퇴거는 잔여, Phase3~5 미완료. [기록](chat-media-first-view-loading/cache-reuse-results.md).

> **③ 최신:** Phase1 반복/재실행 기준선 완료, 반복다운로드28중27건 용량퇴거 연결. Phase2 즉시메모리표시·pending합류·독립저장/삭제세대차단 구현, 통합89개 통과. 개선DEV실행/사용자 비교QA 답변 대기(`/private/tmp/outpick-cache-reuse-phase2-device.log`). 크기/용량/계정정책 유지,③전체완료아님. [기록](chat-media-first-view-loading/cache-reuse-results.md).

> **2026-09-23 최신:**③ 원인 계측→캐시 재사용 개선 사용자 승인. Phase1 hash 연결/저장·퇴거·표시 계측 구현, 자동 회귀/기기 빌드 진행. 기존 정책 유지하고 기준선 QA 후 Phase2. [진행](chat-media-first-view-loading/cache-reuse-results.md).

> **2026-09-22 최종:**② 취소·파일 수명 필수 회귀 완료. Firebase12.17.0 공식수정, 구SDK 재현실패/신SDK 통과·공용87개통과, 기기 취소87·파일90개정리·신규잔여0. 사용자 지속빈화면아닌 빠른스크롤직전 로딩으로 확인. 일반DEV복원 요청. 다음③은 [캐시 재사용 계획](chat-media-first-view-loading/cache-reuse-implementation-plan.md), 아직 구현 전. [검증 근거·한계](chat-media-first-view-loading/download-bottleneck-results.md).

> **2026-09-22 취소 수정 진행:** Firebase Storage 공식 취소 경합 수정이 포함된12.17.0 적용, 공용 회귀87개 통과. 구12.3.0 비교 재현 진행 중. 기존 DerivedData의 Firestore bridge 컴파일 실패는 새 DerivedData 실기기 빌드에서 해소(BUILD SUCCEEDED). 최종 기기 반복 QA 전이므로② 완료/③ 착수는 보류. [근거](chat-media-first-view-loading/download-bottleneck-results.md).

> **2026-09-22 최신:** 다운로드② 잔여 검증에서 저장 실패 자동7개 통과, 실기기 취소/대량 반복 수행. 신규 임시 파일3개 잔존으로 완료 보류, SDK 취소 callback/실제 파일 수명 경계 추가 조사 필요. 일반 DEV 복원 완료(18:03). [판정](chat-media-first-view-loading/download-bottleneck-results.md).③ 구현 보류.

> **2026-09-22:** [③ 세부 구현 계획](chat-media-first-view-loading/cache-reuse-implementation-plan.md) 작성·구현 보류. 크기·용량·표시 파일 정책은 QA 결정. 현재 [② 병렬 다운로드 재점검](chat-media-first-view-loading/download-bottleneck-plan.md)으로 복귀, 제품 변경 없음.

> **2026-09-21 ③ 핵심 정책 확정:** 앱 표시 캐시/원본 분리 우선. 확대 사진 원본 현재+앞뒤1장, GIF·영상은 열 때만, 원본 파일 저장·실패 재시도 확정. [설계 초안](chat-media-first-view-loading/display-original-cache-design.md)에 반영했고 크기/메모리/migration 세부 점검 중. 코드 구현 전이다.

> **2026-09-21 ③ 설계 진행:** 앱 캐시 분리 우선 확정, [설계 초안](chat-media-first-view-loading/display-original-cache-design.md) 작성. 작은 preview 저장/원본 경쟁 분리와 재등장 관측 설계. 원본 선로딩·저장 UX 답변 대기. 제품 코드 변경·세부 구현 계획 확정 없음.

> **2026-09-21 다운로드② 검증 결과:** 자동75개 통과, 기존 캐시 실기기 QA에서 파일 최대6개 병렬 전송 확인. 사용자 체감 개선 있으나 반복 로딩 잔여. 완료241건/고유188경로/추가53건, 캐시 정리5회 관찰. 일반 DEV 복원.③ 표시 캐시/원본 분리 미착수. [근거·한계](chat-media-first-view-loading/download-bottleneck-results.md).

> **2026-09-21 다운로드② 구현·자동75개 통과:** 파일 전송의 io(write) 점유 제거, network/files·수치 유지. 기존 직렬화 실패 재현 및 공용 회귀 통과. 기기 baseline을 켜고 사용자 과거 미디어 왕복 QA 진행 중. 실제 overlap/체감 확인 전이며③ 미착수. [현재 결과](chat-media-first-view-loading/download-bottleneck-results.md).

> **2026-09-21 다운로드② 세부 계획 완료·구현 전:** [계획](chat-media-first-view-loading/download-bottleneck-plan.md)의4개 Phase(병목 재현→분리→회귀→실기기 검증) 순차 진행 예정. 기본 수치 유지, SDK 파일 쓰기는 network/files로 제한, 앱 캐시 쓰기는 기존 io로 제한한다. 이번 작업은 문서만 변경했으며 코드/테스트 실행/기기 조작 없음.

> **2026-09-21 ① 사용자 수용·② 설계 착수:** 회전 체감 개선 확인 및 다음 단계 동의. 누적95개/UI3개·사진/영상/GIF 실기기 QA 수용.②는 공용 파일 다운로드가 network 전송 중 diskWrites1을 점유하는 경계 분리부터 설계한다. 구현 전 영향/취소/저장 계약 검토. [현재 진행](chat-media-first-view-loading/progress.md). 아래 체감 확인 대기와② 보류는 이전 기록이다.

> **2026-09-21 회전 지연 수정:** 사용자 가로/세로 크기 복원 지연 보고→미디어 셀 고정 제약 재현→부모 폭70%·배열 비율 제약으로 수정. 관련8개＋기기 회전 UI1개 재검증 통과, 누적95개/UI3개. 일반 DEV 복원·사용자 체감 확인 대기,② 미착수. [최신 기록](chat-media-first-view-loading/qa-results.md).

> **2026-09-21 화면 수명 후속:** 키보드/검색 종료/설정 패널/사진 선택 취소/세로 복귀 확인. 단위·컴포넌트94개/UI3개 통과. 가로는 좌표·loaded 검사 통과하나 캡처가 잘려 보여 사용자 육안 대조 대기. 일반 DEV 복원,② 미착수. [최신 근거](chat-media-first-view-loading/qa-results.md). 아래 수명 미검증 표기는 이전 기록이다.

> **2026-09-21 채팅 미디어① QA 진행:** iPhone14 단위/컴포넌트89개와 기존 미디어 방 UI1개 통과. 공유 카드 좌표 오류 수정·재검증, 일반 DEV 실행 복원. 신규 사진·영상·GIF 전송 후 스크롤 복귀/방 재진입 표시·확대/재생 사용자 QA 통과. 키보드/설정 등 잔여 검증으로① 전체 완료 전이며②다운로드 병목 미착수. [검증 근거·한계](chat-media-first-view-loading/qa-results.md). 아래 자동 테스트 미실시 상태는 이전 기록이다.

> **2026-09-21 현재 우선순위 변경 — 채팅 미디어 첫 표시:** 사용자와①화면 주변 로딩·이탈 취소→②다운로드 병목→③표시 캐시/원본 분리를 먼저 진행하기로 합의.①요청 조정자·개별 좌표/화면 수명·일괄 로딩 제거 로컬 구현 및 Development Simulator 앱/테스트 빌드 완료. 자동 테스트 실행·실기기 QA 미실시. [설계](chat-media-first-view-loading/design.md)·[계획](chat-media-first-view-loading/plan.md)·[현재 상태](chat-media-first-view-loading/progress.md). 아래 '다음 채팅방 대표 이미지'는 이전 순서다. 실패는 방 재진입/실제 화면 재등장 때 재시도하며 단순 네트워크/앱 복귀 자동 반복을 추가하지 않는다.

> **2026-09-21 아바타 Phase0~5 최종완료:** 잔여4개QA 포함 확인, VoiceOver명시제외. 기존112개회귀와별도iPhone14 16개통과(중복포함), QA자료·진단코드·테스트전용캐시정리, 일반DEV메인탭복구완료. [검증방법·한계](avatar-image-loading/progress/phase-5.md). 다음채팅방대표이미지설계미착수, 커밋/배포없음. 아래아바타미완료상태는과거기록.

> **2026-09-21 아바타 Phase5 후속 QA·정리:** 위임후보/미참여방·스크롤/새메시지재시도·타계정왕복 확인, 정상소스102+10 자동회귀통과. 서버183문서20이미지·기기174행3이미지·임시코드/파일정리 및 정상DEV홈복구완료. 전체Phase5완료아님: route spy·원본only자동계약, 중첩viewport요청계측, 캐시재사용/승격연속기기증거 항목이 남음. VoiceOver는 사용자 요청으로 이번 QA에서 제외. [최신 체크리스트](avatar-image-loading/qa-checklist.md), [검증기록](avatar-image-loading/progress/phase-5.md).

> **2026-09-18 아바타 Phase4 완료:** UIKit/SwiftUI 화면 주변 선로딩·300ms 해제·새 표시/참여 계기 재시도·수동 실패 해제 연결. 통합69개 통과 후 마지막 정책 집중8개 통과(중복 실행 포함). [실제 범위와 검증](avatar-image-loading/progress/phase-4.md). 다음은 Phase5 실기기 스크롤/중첩 참여자/줌/메모리 QA. 기기 설치·서버·커밋 변경 없음. 아래 Phase4 미착수는 과거 기록이다.

> **2026-09-18 아바타 Phase3:** 표시 상태·전체 아바타 화면 수명·확대 종료 구현, 빌드와 Swift Testing54개＋viewer XCTest10개 회귀 통과. [실제 범위](avatar-image-loading/progress/phase-3.md). 다음 Phase4 viewport/추가 표시 계기, Phase5 실기기QA. 기기/서버/커밋 변경 없음.

> **2026-09-18 아바타 Phase2 완료:** 단일 서비스·사용처별 정책/DI·사진/세션 무효화·썸네일3MiB·원본 transient 연결. 실제 DEV 본인 사진 비교 후 JPEG0.8 승격 encoder 적용. 최종48개/10suite 통과, 앱/전체 테스트 target 컴파일·diff check 통과. [구현/표본/검증](avatar-image-loading/progress/phase-2.md). 다음 Phase3 화면 수명, Phase4 viewport/retry, Phase5 기기QA는 미완료. 기기 사진 read-only 외 설치/서버/커밋 변경 없음. 아래 Phase2 미착수/형식 대기보다 우선한다.

> **2026-09-18 아바타 Phase1 공용 구현·회귀 완료:** transient 비저장 원본·옵트인 메모리→디스크 비동기 재인코딩·단일화·무효화 세대 구현, Development Simulator50개/6suite 통과. [실제 범위](avatar-image-loading/progress/phase-1.md). 서비스/화면/세션 연결·실기기 QA는 미착수, PNG/JPEG 실제 비교와3MiB 호출 적용은 다음 단계다. 아래 코드 미착수 상태보다 이 기록을 우선한다.

> **2026-09-18 아바타 착수:** 사용자 구현 승인 후 Phase0 조사 진행. [호출 지도·기술 결정 대기](avatar-image-loading/progress/phase-0.md). 공용 코드 변경 전 디스크 승격 방식·한도 정합성·원본-only 표시 선택을 논의한다. 코드·테스트·기기 변경 없음. 아래 구현 승인 전 기록보다 우선한다.

> **현재 작업 — 아바타 이미지 로딩 설계·계획 작성 완료:** 사용자와 프로필·마이페이지·채팅·룩북 댓글/답글 전체 범위를 합의하고 [설계](avatar-image-loading/design.md)·[세부 계획](avatar-image-loading/plan.md)·[결정](avatar-image-loading/decisions.md)·[QA](avatar-image-loading/qa-checklist.md)를 작성했다. 구현 Phase0~5는 전부 미착수. 일반 썸네일/확대 원본 무캐시, 사용처별 memory-only·disk100/75MiB, viewport1.5/0.5·고유24·300ms, 새 표시 계기 retry(5초 억제 없음), 사진·세션 무효화를 확정했다. 다음은 구현 착수 요청 후 Phase0 기술 계약 확인이다. [현재 상태](avatar-image-loading/progress.md). 아래 이미지 작업 진행/관리자 웹 다음 순서 기록보다 이 현재 상태를 우선한다.

> **작업 순서 갱신:** 완료한 룩북 공용 기반 다음은 아바타 → 방 대표 이미지 → 채팅 사진/공유 카드/영상 썸네일 → GIF → 관리자 preview → 남은 외부 URL → 로컬 미디어 → 확대·저장 잔여 경로 순서로 설계·계획·구현한다. 관리자 웹 전환·iOS 관리자 제거와 Production 미디어 배포는 별도 대기다. 채팅 과거 미디어 첫 표시 task는 첨부 이미지 단계에서 연결한다. 룩북 기반은 PR #31/main `3c162f30` 머지 완료로 남은 구현에서 제외한다.

> **2026-09-16 완료:** `image-loading-stage-concurrency` Phase0~5 구현·자동90개/UI1개·실기기 기능QA·성능 비교 완료. 사용자가 실측 한계를 수용하고 현재 제한값 채택/Phase5 완료를 승인했다. 최적값 탐색 완료 주장은 하지 않는다. 최신 DEV 일반 실행으로 복원했다. [최종 결과](image-loading-stage-concurrency/phase-5-validation.md). 채팅 첫 과거 사진 지연은 [별도 작업](chat-media-first-view-loading/README.md), 커밋/PR/배포는 미수행. 아래 진행/보류 문구는 과거 이력이다.

> 2026-09-16 Phase 5 반복 cold 후속: 두 번째 현재 DEV 아모멘토 로그에서 목록 공개 약 28/92/43ms(홈/브랜드/시즌), 브랜드·시즌 이미지 본문 42건·1,152,606B, 단계 최대 network6/decode2/diskIO2. Activity Monitor는 스크롤 전에 종료됐고 대응 Phase0 앱 콘솔 실행은 CoreDeviceService 오류로 실패해 유효 반복 비교가 아니다. 최신 DEV 재설치 후 사용자 룩북 홈 정상 진입 확인. D07 현재 제한값 유지, D08 반복 쌍·동조건 프레임 비교/허용 기준은 대기. [상세](image-loading-stage-concurrency/phase-5-validation.md).

> 2026-09-16 Phase 5 프레임 최신: iPhone14 현재 앱 시즌 스크롤의 `Animation Hitches --all-processes` 18.8초에서 OutPick frame lifetime178행·hitch0행. 단일 표본이며 Phase0 동조건 프레임 비교는 남는다. 재설치로 바뀐 App Check debug token을 기존 승인된 outpick-test Development QA 범위에 등록해 `앱 데이터를 준비하지 못했습니다` 오류 복구. 이후 cold QA는 등록된 토큰을 `AppCheckDebugToken` 프로세스 환경 변수로 재사용해 추가 등록을 피한다. D08 반복/허용 기준을 거쳐 현 D07 값 조정 여부 판정. [상세](image-loading-stage-concurrency/phase-5-validation.md). 채팅 미디어 지연은 별도 작업.

> 2026-09-16 Phase 5 USB 비교 최신: Phase0/현재 Phase5 iPhone14 아모멘토 1회씩 이미지 콘솔·Activity Monitor CPU/메모리 정상 수집. 목록 metadata 공개 홈912→48ms·브랜드612→89ms·시즌97→69ms, 사용자 Phase0 첫 이미지 조금 느림 관찰. 요청 이미지 수 44/42 및 단일 실행·무선 변동 때문에 CPU/메모리/바이트 우열을 확정하지 않는다. Animation Hitches 시간 초과, 반복·스크롤 구간 정렬 남음. D07 현 값 유지, D08 최종 판정 대기. 최신 Phase5 DEV 앱 복원 완료. [결과](image-loading-stage-concurrency/phase-5-validation.md) 우선. 채팅 첫 사진 지연은 별도 후속 작업이다.

> 2026-09-16 범위 분리: `미디어 QA`방의 과거 사진 첫 표시 지연은 [chat-media-first-view-loading](chat-media-first-view-loading/README.md) 후속 작업으로 기록만 한다. 화면 근처 썸네일 선로딩·방문한 원본/영상 제한 디스크 캐시 방향은 사용자 선택이며 세부 설계·구현은 미착수다. 현재 우선 작업은 `image-loading-stage-concurrency` Phase 5의 정량 비교/자원 검증으로 유지한다. 아래 Phase 5 기록 속 채팅 관찰은 발견 경위이지 이번 구현 범위가 아니다.

> 2026-09-16 최신 이미지 로딩: `image-loading-stage-concurrency` Phase 5 자동 회귀 64+26개 및 실패 재시도 UI 1개 통과, iPhone14 DEV cold 아모멘토 수동 QA 정상. Phase0 수동 비교는 체감 비슷했으나 계측 연결 오류로 시즌 수치·CPU/RSS/hitch 미확보. 현 D07 시작값 유지, D08 최종 정량 판정 대기. 최신 Phase5 DEV 앱 복원 완료. 미디어 QA방 첫 과거 사진 지연은 chat thumb의 300MB 파일 경로가 I/O write1을 전송 중 점유하는 구조와 관련 가능성이 있으며, 사용자는 화면 근처 선로딩·방문 원본/영상 제한 캐시 방향 선택. 채팅 후속 설계·구현 대기. [실행 기록](image-loading-stage-concurrency/phase-5-validation.md)과 [진행](image-loading-stage-concurrency/progress.md) 우선. 아래 이미지 Phase2/1/0 상태는 과거 이력이다.

> 이미지 Phase2 cold QA: 아모멘토 비교 후 decode/write 예약각16MiB, 나머지한도유지. 사용자체감비슷, network최대6/예약회수확인. Instruments전체송수신량/RSS미확보. 상세 image-loading-stage-concurrency/phase-2-qa.md. Phase3/4미착수.

> 2026-09-16 이미지 로딩 Phase 2: 초기값 구현 후 QA 조정 방식 승인·구현. 네트워크6/디코딩2/I/O2(쓰기1), decode/write 각8MiB, 비동기 저장·큰 파일 처리·SDK 취소. [구현·한계](image-loading-stage-concurrency/phase-2-implementation.md), [검증 상태](image-loading-stage-concurrency/progress.md). 실제 테스트/기기 QA 미수행, Phase3/4 미착수.

## 현재 상태

- 2026-09-14 다음 최우선 핵심 작업: **이미지 로딩 단계별 자원 사용 분석과 동시성 정책 설계**(`image-loading-stage-concurrency`). 사용자 요청으로 아래 현재 핵심 작업에 기록했다. 다음 착수 시 이 작업의 설계 논의부터 진행한다. 이번 요청은 기록까지이며 단계별 수치·구현 계획·코드 변경은 아직 확정하거나 승인하지 않았다. 이전 이력의 이미지 깜빡임·관리자 웹 우선 문구보다 이 순서를 우선한다.

- 2026-09-14 최종완료: 동시성 적용4개 커밋→[PR#30](https://github.com/GayoonKim/OutPick/pull/30) 자체리뷰(COMMENT)→main `71e1376c74fef490efd1c901f34c2b79a35ba33c` 머지. iPhone41/Socket124 및 Development3장/70장/실패재전송 QA 완료. Production은 기존 배포대기에 이번 변경까지 통합 기록했고 미배포. 아래 커밋/PR대기 문구는 과거 이력이다.

- 2026-09-14 `chat-media-concurrency-qa-rollout`: 구현·iPhone41개/Socket124개·Development 배포·3장/70장 정상 전송/재입장·네트워크 실패 후 재시도 실기기 QA 완료. QA 계측 해제, 최종 정책 유지. [완료 근거](chat-media-concurrency-qa-rollout/progress.md). 남은 것은 커밋·PR·리뷰·머지, Production은 별도 대기. 아래 QA 대기 문구는 해소됐다.

- 2026-09-14 최종 조합3장+70장 Development 정상 QA 통과. 서버70장30/30/10·seq58~60·계약3 ready 및전체조회 확인, 사용자 전송/스크롤/입력/재입장 확인. 실기기 실패버블 복구 항목만 확인 중. [진행](chat-media-concurrency-qa-rollout/progress.md). 커밋/PR/Production 미수행.

- 2026-09-14 승인된 Development Socket `concurrency-all-0914`100% 반영 및 최신DEV 앱 설치·실행 완료. 원본4/준비전체/PUT4 기본값 확인, 서버 조회·서명·취소 정리 전체 실행 이미지 배포. `미디어 QA`3장 smoke 사용자 응답 대기,70장 결합 QA 미완료. [현재 진행](chat-media-concurrency-qa-rollout/progress.md). Production 미변경.

- 2026-09-14 구현 승인 후 `chat-media-concurrency-qa-rollout` Phase1~2 로컬 구현 완료. 원본4/준비전체/PUT4, 계약3 서버 조회·서명·취소 정리 전체 실행. iPhone41개/4 suites·Socket check/124개 통과. [진행](chat-media-concurrency-qa-rollout/progress.md). Development 서버 배포·실제 결합 QA·커밋/PR 미수행. 아래 구현 승인 전 문구는 이전 이력이다.

- 2026-09-14 최종 방향과 [세부 구현 계획](chat-media-concurrency-qa-rollout/plan.md) 작성 완료. 원본 확보4 유지, 계약3 서버 metadata 조회·URL 서명·취소 정리 모두 요청 대상 전체 실행으로 사용자 확정. FIFO1·준비전체·PUT4 유지. 남은 설계 선택 없음, 코드 구현 승인 전이며 배포 미착수.

- 2026-09-14 원본 확보4/전체 실기기 비교 완료: 4→all→4→all, 원본 확보1.630/0.411/0.505/0.437초. 매회70장·3묶음 앱 성공 및 사용자 조작 확인, 서버 문서 별도 감사 미수행. 반복4 대비 차이는 약0.07~0.09초로 체감 개선 입증 아님. 원본 확보 최종값은 추가 논의 대기, 실험 설정 해제·기본4 복원. [결과](chat-media-preview-continuity/acquisition-diagnosis.md). 정식 적용 구현 계획은 아직 미확정.

- 2026-09-14 `chat-media-concurrency-qa-rollout`: 사용자와 적용 방향 확정. 묶음 FIFO1·원본 확보4·이미지 준비 연속 사진 전체·파일 업로드4·서버 metadata 요청 내 전체 파일 조회, 영상 정책 유지. 방향 확정과 기록까지 완료했으며 정식 코드 반영·최종 결합 QA는 아직 미수행이다.

- 2026-09-12 미디어 동시성 개별 비교 완료. 사용자 요청으로 결과 적용·Development 검증·커밋/PR/리뷰/머지는 아래 핵심 대기 작업으로 **기록만** 한다. 이번 기록 요청으로 추가 구현·배포·커밋·PR·머지를 실행하지 않는다.

- 2026-09-11 현재 대화: `chat-message-cache-sync` — 완료. 합의된 QA·최종48개 회귀·iPhone14 개발 앱 설치/실행·3개 커밋·PR #29 자체 리뷰 및 main 머지 완료(`143544e5`). VoiceOver 제외·실기기 장시간 보류 유지. [진행](chat-message-cache-sync/progress.md).

- `shared-image-viewer-editorial` — 구현·빌드·자동 회귀12개·렌더링 및 이번 범위 실기기 QA 완료. 사용자 나머지 항목 모두 확인, 큰 글씨·VoiceOver는 명시적으로 QA 제외(미검증). [최종 기록](shared-image-viewer-editorial/implementation-plan.md). 커밋/PR 미수행. 기존 이미지 깜빡임/300MB 작업은 완료 상태 유지.

- 2026-09-11 최종: `chat-media-preview-continuity` 및 후속 사진300MB/실패 복구 작업 완료. 구현·Development 배포·사용자 실기기 QA 완료, Swift29회/Socket115개 통과. [최종 검증 범위](chat-media-preview-continuity/photo-size-failure-recovery.md).300MB 정확한 경계는 자동 테스트로 검증했고 실파일 경계 시험은 완료 조건에서 제외. 커밋/PR/머지 및 Production 배포는 미수행. 아래 깜빡임 착수/QA 대기 상태는 과거 이력이며 다음 핵심 대기는 관리자 웹 설계 논의다.

- 2026-09-10 최종: 사용자 요청으로 이번 미디어 구현·Development 배포·사진 QA·PR #27 머지 작업을 **완료** 처리했다(main `34831dfc`). Production 배포는 아래 별도 핵심 대기 작업으로 분리하며 아직 미승인·미수행이다. 다음 최우선은 이미지 깜빡임 개선이다.

- 2026-09-10 최신 결정: 현재 미디어 변경을 커밋·PR·리뷰·머지한 뒤 **미디어 버블 이미지 깜빡임 제거**를 다음 최우선 핵심 작업으로 진행한다. 사용자는 저장 공간 확보 후 70장 전송·전송 중 조작·완료 후 재입장까지 확인하고 QA 방을 삭제했다. 아래 관리자 웹 작업은 그다음 순서다.
- 미디어 신규 계약 3은 Development 배포 및 3장/70장 실제 전송 확인 완료. Production 배포·영상 실제 QA·병렬 4 대 30 비교는 미수행. 과거 아래 queued 반환/병렬 묶음 기록은 최종 공용 FIFO 1·성공 UI 반영 또는 실패 후 다음 묶음 정책으로 대체된다.

### 완료 작업의 이전 이력: 미디어 버블 이미지 깜빡임 제거

- 2026-09-11 후속 로컬 구현 완료: 사진 본/썸네일 각각300,000,000bytes, 묶음 본파일 합계300,000,000bytes/30장, 실패 사진은 별도 실패 버블(재시도/삭제)로 보존. Swift28개 정의/29회 실행·Socket7개 통과. [현재 구현·검증](chat-media-preview-continuity/photo-size-failure-recovery.md)을 따른다. 서버 배포·새 정책 실기기 QA는 미수행.

- 2026-09-11 QA 후속: 31장 원본 확보 중 무반응 보고. index 0~17 복사 뒤 취소됐으며 사용자는 기다리다 앱·방을 이동했다고 확인했다. 최초 지연 원인은 미확정이다. 사용자 승인으로 [파일 제공/복사/대기·동시성 세부 계측](chat-media-preview-continuity/acquisition-diagnosis.md)을 진행하며 원인 확인 전 31장 깜빡임 QA는 통과 처리하지 않는다.

- 2026-09-11: 사용자 세부 계획·구현 승인 후 이미지 표시 보존 로컬 구현 완료. Development 앱 및 최종 테스트 코드 빌드 성공, 자동 테스트 실행·실기기 QA 미실시. 최신 상태는 [구현·검증 기록](chat-media-preview-continuity/implementation.md)을 따른다. 아래 기록만 완료 상태는 착수 전 이력이다.

- 현상: 이미 표시된 사진이 플레이스홀더로 바뀌었다 돌아온다.
- 근거: `ChatMessageCell.previewItemID`가 hash와 로컬/원격 경로를 포함해 확정 시 identity가 바뀐다. `ChatImagePreviewCollectionView`는 이전 ID 이미지를 제거하고 갱신마다 layout을 재생성한다. `ChatImagePreviewCell.configure`는 이미지가 nil이면 기존 이미지를 지운 뒤 비동기 재로딩한다.
- 방향: 동일 첨부의 안정적 식별자, 로컬→서버 전환 중 기존 이미지 유지, 진행률 갱신과 사진 목록 갱신 분리. 다른 사진으로 셀이 재사용될 때 잘못된 이전 이미지는 표시하지 않는다.
- 검증: 대기/진행/확정, 스크롤 재사용, 방 재입장 수동 QA 및 동일 첨부 재설정·늦은 응답 경합 회귀.
- 상태: 기록만 완료. 현재 PR에 깜빡임 수정은 포함하지 않는다.

- 2026-09-10 이번 대화 최종 승인: `chat-media-bounded-parallel-upload` 상세 설계를 확정하고 로컬 구현·검증을 진행했다. 상세 상태는 해당 [progress](chat-media-bounded-parallel-upload/progress.md)를 우선한다. 아래 관리자 웹 우선순위는 다른 대기 작업 간 순서로 유지한다.

- 2026-09-10 사용자 결정: 핵심 작업 순서는 관리자 웹 전환 → iOS 관리자 콘솔 제거다. 고객지원 페이지와 Apple 로그인은 후순위로 보류한다.
- 관리자 웹 전환은 이미지 로딩 단계별 동시성 작업 다음 대기 작업이며, 상세 구현 계획과 구현은 아직 승인되지 않았다.
- `chat-room-moderator-delegation`은 완료되어 직전 완료 작업으로 이동했다.
- `lookbook-discovery-learning-loop`의 후속 구현·Production rollout 완료 기록을 확인해 대기 목록에서 제외했다. 상세 연결은 해당 task의 `progress.md` 최상단을 따른다.

## 현재 핵심 작업

- `image-loading-stage-concurrency` — Phase0~5 구현·QA 완료, 현재값 채택 승인. PR 정리 리뷰에서 HTTP 디스크 바이트 예약 순서를 보완했고 최종91개/14 suite 통과(2026-09-16). [공개 검증 요약](../qa-image-loading-concurrency-2026-09-16.md). 아래 하위 항목은 최초 조사·구현 단계의 이력이다.
  - 최신 Phase 1: 사용자 D01/공용 자원 기준 확정 후 요청 통합·소비자 취소·캐시 세대 보호 구현. [실제 계약](image-loading-stage-concurrency/phase-1-implementation.md), [진행](image-loading-stage-concurrency/progress.md). 테스트14개 시나리오 작성·컴파일 성공/실행 보류. Phase 0 소스 별도 보존, 아모멘토 실측은 아직 미수행. Phase 2 D02 디스크 배분/D03 바이트 예산·실험 수치 결정이 다음 선행 조건이다. 아래 Phase 0 당시 Phase1 미착수 표기보다 이 기록 우선.
  - 최신: 사용자 순차 진행 요청으로 Phase 0 계측 구현, 기존 정책 유지. 테스트4개 작성/실행 보류, 앱 Simulator build 통과. [계측 사용법](image-loading-stage-concurrency/baseline-instrumentation.md)·[진행](image-loading-stage-concurrency/progress.md). OutPick-DEV 아모멘토 선택, 시즌/캐시 준비 방식 미정. Phase 1~5·기기 측정·배포·커밋 미수행. 아래 계획 작성 당시 미착수 기록보다 이 상태를 우선한다.
  - 최신 기준: [설계](image-loading-stage-concurrency/design.md), [구현 계획](image-loading-stage-concurrency/implementation-plan.md), [QA](image-loading-stage-concurrency/qa-checklist.md), [진행](image-loading-stage-concurrency/progress.md). 공용 기반 + 룩북 세 화면 + 다른 소비자 회귀 확인으로 범위를 확정했다. Phase 0~5는 전부 미착수이며 성능 측정도 미수행이다.
  - 승인 상태: 사용자 `세부 구현 계획 작성 진행` 요청으로 task/phase 문서를 작성했다. 코드 구현·테스트 실행·기기 설치·배포 승인은 별도이며 수행하지 않았다. 미정 수치/기술 선택은 설계 D01~D08에서 해당 phase 선행 조건으로 관리한다. 아래 항목은 최초 조사 배경이며 현재 결정은 새 설계를 우선한다.
  - 문제: 현재 공용 `ImageCachePipeline`은 메모리·디스크 캐시를 먼저 확인한 뒤, 캐시 미적중 시 다운로드 → 디코딩 → 메모리 등록·디스크 저장 전체를 공용 6개 제한으로 묶는다. CPU·메모리·디스크 I/O·네트워크 특성에 맞춘 단계별 동시성 정책은 분리되어 있지 않다.
  - 현재 대화에서 코드로 확인한 사항: 기본 파이프라인들은 기능별 6개가 아닌 같은 정적 limiter의 합산 6개를 공유한다. prefetch에는 캐시 조회를 포함하는 별도 작업 수 제한이 있다. `ChatAttachmentImageService.loadImageData`는 로컬 파일·별도 메모리 데이터 캐시 확인 후 Storage를 직접 호출하며 공용 제한과 디스크 데이터 캐시를 거치지 않는다. 디스크 캐시 스토어는 actor이므로 네트워크 제한 밖이라는 사실을 디스크 I/O 무제한 병렬 실행으로 해석하지 않는다.
  - 다음 첫 작업: 룩북·프로필/아바타·채팅방 대표 이미지·첨부 썸네일·확대 화면의 실제 호출 경로를 확인하고, 캐시 조회·네트워크·디코딩/다운샘플링·캐시 저장 단계 및 공용 제한 우회 경로를 정리한다. 기존 미디어 전송 작업의 단계별 정책 결정 방식은 참고하되 업로드의 수치를 다운로드에 그대로 적용하지 않는다.
  - 설계 논의 대상: 메모리 캐시 적중의 즉시 반환, 디스크 읽기·디코딩의 CPU/메모리 부담, 다운로드와 후속 처리의 제한 분리 여부, 공용/기능별 제한 범위, visible/prefetch 우선순위, 동일 요청 병합·취소·실패 복구, 직접 다운로드 경로의 포함 범위. 캐시라는 이유만으로 무제한을 확정하거나 모든 단계에 제한이 필요하다고 단정하지 않는다.
  - 측정·검증 후보: 메모리 적중/디스크 적중/캐시 미적중을 구분한 첫 이미지·전체 표시 시간, 스크롤 응답성, CPU·최고 메모리·동시 네트워크 요청 수, 중복 요청과 취소/재사용 경합. 비교 조건·허용 기준·실기기 범위는 사용자와 논의한 뒤 확정한다. 현재 성능 측정은 미수행이며 단계별 분리의 개선 효과와 최적 수치는 미확정이다.
  - 코드 진입점: `OutPick/Infra/Cache/ImageCache/ImageCachePipeline.swift`, `OutPick/Features/Chat/Services/ImageLoading/{AvatarImageService,RoomImageService,ChatAttachmentImageService}.swift`, `OutPick/Features/Lookbook/Repositories/LookbookRepositoryProvider.swift`, `OutPick/Features/Lookbook/Services/ImageLoading/`, `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseImageStorageRepository.swift`, `OutPick/Infra/Media/ImageViewer/SimpleImageViewerVC.swift`.
  - 최초 기록 당시 승인 상태(2026-09-14): 우선순위 기록만 승인됐다. 이후 설계 합의·계획 작성 승인은 위 2026-09-16 기록으로 갱신됐다. 구현·검증·배포는 여전히 미수행이다.

### 직전 미디어 동시성 작업의 설계 이력

- `chat-media-concurrency-qa-rollout` — 완료(PR #30 머지). 아래 세부 내용은 적용 전 설계 이력이며 현재 완료 상태는 이 문서 최상단과 progress를 따른다.
  - 세부 계획: [Phase1~4 구현·검증 계획](chat-media-concurrency-qa-rollout/plan.md). 서버 전체 실행은 계약3 metadata 조회뿐 아니라 URL 서명·취소 정리에도 적용한다. 원본 확보4 최종 확정. 기존 계약2 동시성 설정은 유지한다.
  - 근거: [iPhone 14 동시성 비교 결과](../qa-media-upload-concurrency-2026-09-12.md). 8회·560장·24묶음 정상 저장, 사용자 매회 완료·스크롤·입력 이상 없음 확인.
  - 확정 방향: 묶음 FIFO1 유지 + 원본 확보4 + 이미지 준비 연속 사진 전체 동시 실행 + 파일 업로드4 + 서버 metadata 요청 내 전체 파일 동시 조회. 영상 정책은 유지한다. 이미지 준비는 30장으로 분할하기 전 연속 사진 구간 전체가 대상이며 30개 제한이 아니다. metadata도 고정60 제한 대신 요청 대상 전체를 조회한다. 현재 계약은 최대30장×본파일/썸네일=60파일이다. 향후 묶음 확대 후 지연·실패율 증가가 관측되면 제한 도입을 재검토한다.
  - 근거 수치: 업로드4는11.33/12.06초, 전체 동시 실행은19.33/70.15초. 준비 전체 동시 실행은3.82/3.98초(기존약6초), 관측 최고 메모리1338–1592MiB. 서버60 조회 합계0.475/0.200초(기존4는0.621–0.673초).
  - 다음 진행 순서: 확정 정책의 변경 파일·구현/검증 범위 정리 → 코드·관련 하네스 반영 및 필요한 회귀 → Development 앱/서버 반영 → 최종 결합 조합으로70장 실제 전송·메시지 순서/누락/중복·조작·메모리 확인 → 작업별 커밋 정리 → PR 생성 → 리뷰·지적사항 보완 → 검증한 head 머지. 적용 방향 확정을 배포·커밋·PR·머지 실행 승인으로 간주하지 않는다.
  - 완료 기준: 개별 측정 결과를 최종 조합 검증과 구분해 기록하고, Development 적용 상태·검증 결과·커밋·PR·리뷰·머지 근거를 남긴다. 여러 사용자 동시 부하는 미검증이므로 이번 결과를 전체 지원 기기의 최적값으로 단정하지 않는다.
  - 현재 상태: 앱 준비/업로드 기본4 및 Development 기존metadata4로 복원 완료. 서버 실험 트래픽은 `outpick-socket-development-photo300-0911`100%, 템플릿은 기존 이미지/metadata4의 `qa-restored-0912`. 비교용 코드·테스트·문서는 로컬 미커밋 상태로 보존한다.
  - 커밋 정리 시 이번 Swift 계측·설정·테스트, Socket 상한60/테스트, QA·진입점 문서를 구분한다. 기존 HANDOFF·포트폴리오·로컬 로그 등 무관 변경은 포함하지 않는다. Production 배포는 별도 대기 작업을 유지하며 이번 후속 범위에 포함하지 않는다.

- `chat-message-cache-sync` — 완료: 실기기 개발 앱 설치·PR #29 머지까지 완료. progress 참조.

- 미디어 버블 이미지 깜빡임 제거 및 사진300MB/실패 복구 — 완료. [최종 상태](chat-media-preview-continuity/photo-size-failure-recovery.md).

- `admin-web-operations-migration` — 이미지 로딩 단계별 동시성 작업 이후 설계 논의 대기
  - [기존 결정](admin-web-operations-migration/decisions.md)
  - 웹 기술 스택·화면/API 범위·권한 전환·검증 기준을 논의한 뒤 구현 계획을 작성한다.

## 직전 완료 핵심 작업

- `chat-media-bounded-parallel-upload` — 완료
  - [진행·검증](chat-media-bounded-parallel-upload/progress.md), [직접 업로드 구현·QA](chat-media-bounded-parallel-upload/qa/direct-upload-implementation.md)
  - 구현·Development 배포·3장/70장 실제 전송·사용자 조작/재입장 확인·5개 커밋·[PR #27](https://github.com/GayoonKim/OutPick/pull/27) 자체 리뷰/머지 완료, main `34831dfc`.
  - 최종 검증: Swift62/62, Socket113/113, Functions262/262, worker22/22, Storage5/5.
  - Production 배포·영상 실제 QA·병렬4대30 비교·최종 iOS 취소 경합 보완의 실기기 재설치는 완료 범위에서 제외하고 후속으로 유지한다.

- `chat-room-moderator-delegation`
  - [설계](chat-room-moderator-delegation/design.md)
  - [결정](chat-room-moderator-delegation/decisions.md)
  - [Phase 계획](chat-room-moderator-delegation/plan.md)
  - [현재 상태](chat-room-moderator-delegation/progress.md)
  - [QA 기준](chat-room-moderator-delegation/qa-checklist.md)
  - 상태: 완료 — Production 반영·기능 활성화·최신 앱 QA·부모 장애 격리 수정·재검증·PR #26 자체 리뷰/머지 완료, main `a3911e32`
  - 후속: 관리자 웹 전환 설계 논의. 최소 지원 버전 상향·creatorUID 제거·외부 출시 준비는 별도 범위다.

## 구현·운영 승인 경계

- 구현 승인은 Phase 1 코드 변경 시작 권한이며 외부 배포 권한을 포함하지 않는다.
- Functions/Rules/Socket 배포는 구현·검증 후 별도 승인한다.
- Production read-only audit, ownerUID/counter backfill, 최소 지원 버전 상향, 기능 활성화, creatorUID 제거는 단계별로 각각 승인한다.
- 2026-09-02 사용자 확인상 앱 미출시·미운영이므로 최소 지원 버전 상향 없이 관리자 위임 서버·앱 flag를 활성화했고 최신 Production 빌드 임명/회수 QA를 통과했다. 부모 장애 격리 수정·재검증 후 최종 배포·커밋·PR 리뷰/머지 진행을 승인받았다.
- 고객지원 URL과 자동 의미 필터 관련 기존 App Review 1.2 외부 출시 gate는 moderator delegation이 해제하지 않는다.

## 핵심 작업 진행 순서

1. `image-loading-stage-concurrency`: 구현·QA 완료. 현재값 채택 승인 후 커밋·PR·머지 정리 중이다.
2. `admin-web-operations-migration`: 플랫폼 총관리자 운영 기능을 localhost 관리자 웹으로 전환한다. 기존 iOS가 사용하는 권한·API의 호환과 최종 제거 시점을 먼저 설계한다.
3. `ios-admin-console-removal`: 관리자 웹의 필수 운영 기능 동등성 검증과 운영 경로 전환 후 iOS 관리자 콘솔·전용 연결을 제거한다. 일반 사용자 브랜드 요청과 채팅방 운영 기능은 유지한다.

- 문의 접수 방식·처리 이력의 구체 설계는 고객지원 작업과 함께 논의한다. 이를 관리자 웹의 다른 기능 착수 조건으로 두지 않는다.

## 추가 핵심 대기 작업

- `chat-media-production-rollout`: 이번 미디어 전송 변경의 Production 배포
  - 최종 소스 연결: [PR#30](https://github.com/GayoonKim/OutPick/pull/30), main `71e1376c74fef490efd1c901f34c2b79a35ba33c`. 기존 PR#27/#28과 함께 운영 상태 차이를 확인할 대상이며 이번에는 기록만 수행했다.
  - 2026-09-14 추가 기록: 기존 PR#27/#28 범위에 이번 최종 동시성 적용도 통합한다. iOS 원본4/준비전체/PUT4/FIFO1, 계약3 Socket 조회·서명·취소정리전체. 계약2 수치 설정은 유지하며 계약3은 metadata 환경 변수를 소비하지 않는다. [Development 최종 근거](../qa-media-upload-concurrency-2026-09-12.md), [운영 배포 대기 범위](../runbooks/CHAT_MEDIA_PRODUCTION_ROLLOUT.md). 실제 Production 배포는 이번 커밋/PR/머지 요청에 포함되지 않는다.
  - 상태: 사용자 요청으로 대기 목록에 기록. 실제 Production 배포 승인은 아직 없으며 배포하지 않았다. 다른 대기 작업과의 착수 순서는 추후 결정한다.
  - 기준: PR #27/main `34831dfc`와 PR #28/main `8e7d3c31`까지 포함. 2026-09-11 사용자 요청으로 이번 완료 변경의 Production 반영도 기존 대기 항목에 통합 기록했다. 실제 배포 승인은 아님. [FIREBASE 진입점](../entrypoints/FIREBASE.md)과 [Development QA 기록](chat-media-bounded-parallel-upload/qa/direct-upload-implementation.md)을 따른다.
  - PR #28 추가 범위: Socket 계약3 사진 본 파일·썸네일 각각300,000,000바이트 및 묶음 본 파일 합계300,000,000바이트/30장 정책. iOS 이미지 깜빡임 개선·실패 사진 원본 보존/재시도/삭제·다운로드 한도 정합성·공용 확대 화면 리팩토링도 Production 앱 반영 대상에 포함한다. 공용 확대 화면 자체는 서버 배포가 필요 없고, 이번 PR의 Functions/Firestore/Storage rules 변경은 없다.
  - 추가 순서/검증: Production Socket의300MB 정책 준비·검증 후 새 앱 반영. Development `outpick-socket-development-photo300-0911` 배포와 문제 사진/31장 전송·실패 복구·공용 뷰어 사용자 QA 결과를 참고하되 Production 통합 검증을 별도로 수행한다. 큰 글씨·VoiceOver는 사용자 요청으로 QA 제외,300MB 정확한 경계는 자동 테스트 검증(실파일 기기 경계 시험 미실시).
  - 사전 확인: 운영 Socket·관련 Functions·worker·규칙·인덱스의 실제 상태와 코드 차이를 확인하고 정확한 배포 목록 및 기존 revision/digest 롤백 기준을 작성한다. 기존 계약2 진행 자료 호환 경로는 임의 삭제하지 않는다.
  - 범위: Socket 계약3, 최종 버킷 환경 변수/메타데이터 병렬 설정, 최종 버킷 객체 접근·서명 IAM, ready Storage Rules, cleanup 복합 인덱스/receipt TTL, `reconcileChatMediaObjectCleanup` 및 변경된 기존 media 함수/worker의 배포 필요 여부 확인.
  - 순서: 규칙·인덱스·필요 IAM 및 서버 준비 → 후보 검증 → 트래픽 전환 → 계약3 iOS 반영 → 실제 통합 확인. 신규 앱을 계약3 미지원 서버보다 먼저 배포하지 않는다. IAM과 운영 변경은 구체 범위를 확인한 후 승인받는다.
  - 검증: 승인된 QA 방에서 본/썸네일 signed PUT·확정 전 읽기 차단·확정 후 접근, 메시지/seq/Socket 멱등성, 취소/성공 경합, 늦은 PUT 정리, 기존 정상 미디어 및 재시도를 확인한다. 미완료 영상 실전 QA의 운영 전 검증 범위도 결정한다.
  - 완료 기준: 승인 범위 배포·인덱스 READY·함수 ACTIVE·Socket readiness/오류 확인·실제 QA 결과·롤백 기준·하네스 갱신. 현재 병렬4를 최적값으로 간주하지 않는다.

### 완료 작업의 이전 설계 이력 (대기 작업 아님)

- `chat-media-bounded-parallel-upload`: 미디어 묶음의 제한된 병렬 전송 리팩토링
  - 2026-09-10 상세 논의 후 사용자가 구현을 승인해 현재 작업으로 승격했다. 이 항목의 이전 사용자별 슬롯/terminal 대기안은 최종 설계로 대체한다.
  - 목표: 현재 미디어 종류별 한 묶음 실행을 서버 예약 기반의 제한된 병렬 실행으로 확장해 대량 선택 시 전송 시간을 개선한다. 속도·안정성·대규모 사용자 적합성은 검증 대상으로 두며, 최적 구조로 검증됐다고 간주하지 않는다.
  - 확정 분할 정책: 선택 순서를 유지하면서 묶음당 150MiB를 넘기지 않는 범위에서 최대 30장으로 나눈다. 다음 사진을 넣으면 용량 또는 장수 제한을 넘는 시점에 분할하며, 용량을 채우기 위한 재정렬은 하지 않는다. 기존 `ChatMediaSelectionChunker`가 이미 이 정책을 구현한다.
  - 확정 실행 방향: 기기의 원본 확보·준비·업로드를 제한 병렬로 실행하고 queued 접수 직후 업로드 차례를 반환한다. 서버 사용자별 2/1 제한을 제거하고 전체 execution 제한은 유지한다. 구버전 서버의 슬롯 부족은 제한 빈도 대기로 호환한다.
  - 확정 공개 정책: 묶음 내부 사진 선택 순서는 유지하지만 묶음 간 선택 순서는 보장하지 않는다. 먼저 성공한 묶음부터 공개하며, 앞 묶음의 처리·실패 때문에 성공한 뒤 묶음을 대기시키지 않는다. 실패는 해당 묶음에만 적용하고 수동 재시도 성공 시 최신 메시지로 공개한다.
  - 선택 이유·대안: 현재 1개씩 처리하는 방식은 단순하지만 업로드와 서버 처리를 겹치지 못한다. 병렬 처리 후 선택 순서대로 공개하는 대안은 사용자 결정으로 채택하지 않는다. 완료 순서 공개를 선택해 기존 서버의 처리 완료 시 메시지 생성·seq 부여 계약을 유지하고 별도 공개 대기 상태를 추가하지 않는다.
  - 최종 기술·복구 정책: async/await+제한 TaskGroup, actor FIFO, GRDB 원본/outbox 소유권, Socket/status 성공 수렴. 전체 원본 확보 전 무표시, 정상 최종 묶음만 표시, 중단 후 미분할 원본만 대표 실패 복원, 수동 retry는 뒤에 접수한다. 미확정 서버 결과와 local 실패 UI를 분리한다.
  - 검증 후보: 동시 1개/2개의 전체·첫 묶음 표시 시간, 용량·장수 분할, 완료 역전, 일부 실패·재시도, 슬롯 부족·취소 경합, 중복·누락, 여러 사용자 동시 전송 시 대기·서버 부하.
  - 코드 진입점: `ChatMediaSelectionChunker.swift`, `ChatMediaUploadTurnQueue.swift`, `ChatMediaUploadUseCase.swift`, `ChatViewControllerExtension.swift`, `Socket/src/media/mediaUploadService.js`, `functions/src/chat/media/readyService.ts`. 기존 계약은 `chat-ugc-safety-room-moderation/decisions.md`의 Phase 7 미디어 정책을 참고한다.
  - 문서화: 실제 대안 비교·선택 이유·단점·재검토 조건을 설계 결정에 남긴다. 당시 actor 대안 비교 근거가 없는 부분은 현재 분석과 구분한다.

## 후순위·보류 작업

- `customer-support-https-page`: 공개 문의·제한 이의제기·신고 처리·개인정보·계정 삭제 경로 준비
  - 2026-09-10 사용자 결정: 관리자 웹 관련 작업보다 후순위로 미룬다. 외부 운영·출시 준비 전에 재검토한다.
  - 고객지원 경로 준비 전 실제 계정 제한·정지 운영과 외부 배포를 보류하는 기존 결정은 유지한다. 관리자 웹 구현·내부 QA는 진행할 수 있다.
- `sign-in-with-apple-account-lifecycle`: Apple 로그인·재인증·계정 삭제·재가입 principal 복원 설계
  - 2026-09-10 사용자 결정: 아직 App Store 출시 계획이 없어 후순위로 보류한다. 출시 준비 시점에 재검토한다.

## 별도 후속 범위

- 최소 지원 버전 상향과 `creatorUID` 제거: 관리자 위임 완료 범위와 분리해 진행한다.
- App Review 외부 출시 준비: 고객지원 URL과 자동 의미 필터 관련 기존 출시 gate를 확인한다. 관리자 위임 완료로 해제되지 않는다.

## 문서 관리 규칙

1. 이 문서에는 현재 핵심 작업 한 건과 직전 완료 작업만 상세 링크로 유지한다.
2. 오래된 완료 이력은 각 task의 `progress.md`와 `docs/ai/ADR.md`에서 확인한다.
3. 코드 진입점이 바뀌면 `docs/ai/ENTRYPOINTS.md`와 관련 `entrypoints/*.md`를 함께 갱신한다.
4. 외부 배포·운영 데이터 변경·파괴 작업은 사용자 명시 승인 없이 진행하지 않는다.
# 최신: 채팅 전체 디스크 준비 QA

현재 불러온 메시지 전체를 거리순으로 한 장씩 준비하되 메모리 여유까지만 처리. cache-only/최저 우선순위/무퇴거 삽입/화면 이탈 취소 구현, 자동45개 및 기기 빌드·설치 통과. 서버 만료 별도. [최신 진행](chat-media-first-view-loading/display-readiness-plan.md).
# 최신: 진입 초기 디스크 준비 QA

현재 메시지 확보 직후 snapshot/layout 전 준비 시작으로 앞당김. 최신/unread 순서 유지 후 실제 화면 거리순 전환, 화면 이탈 조기취소. 자동29개 및 최종 기기 빌드 통과. 진입 직후 스크롤 QA는 [최신 계획](chat-media-first-view-loading/display-readiness-plan.md)과 `/private/tmp/outpick-early-disk-preparation-device.log` 참조.
# 최신: 초기 준비 동시성 QA

초기 시작 앞당김 후에도 즉시 스크롤에는 준비 전 loading이 남아, 기존 decode2 한도 내에서 먼 디스크 준비 작업을1→2로 조정. 자동28개/기기빌드 통과. 기존 캐시 유지, `/private/tmp/outpick-dual-disk-preparation-device.log`로 실기기 효과 확인 전. [최신 계획](chat-media-first-view-loading/display-readiness-plan.md).
# 최신: 세 동시 실행 제한 해제 QA

사용자 명시 승인으로 DEBUG 옵션 OUTPICK_UNLIMITED_DISK_PREPARATION=1에서 준비 요청/decode/IO 상한을 함께 우회. 일반실행은 기존제한 유지, 메모리보관/취소/파일보호 유지. 실제decode active 및CPU(getrusage)/phys_footprint/thermal 계측 추가. 검증 최종로그 `/private/tmp/outpick-unlimited-disk-preparation-tests-final.log`, 기기빌드 `/private/tmp/outpick-unlimited-disk-preparation-device-build-final.log`. [계약/결과](chat-media-first-view-loading/display-readiness-plan.md).
# 최신: 로컬 단계 준비/셀 최초 표시 QA

온라인 로컬창 확보 후 서버창 조회 전 prepareLocalMedia 힌트로 준비 시작. 실제 메시지 표시는 서버/삭제 확인 이후 유지. 사진/GIF/영상썸네일 셀 첫구성 및loading 이벤트에서 공용메모리 즉시조회 연결. 자동44개/기기빌드 통과. 기존 캐시 및 제한해제 QA 옵션 유지, `/private/tmp/outpick-local-early-media-device.log` 예정. [최신 기록](chat-media-first-view-loading/display-readiness-plan.md).
# 최신: 전환 중 표시와 이탈 픽셀 유지 QA

직전계측은cellCache540모두hit/로딩시작0. viewport활성을willAppear로앞당기고snapshot완료즉시초기위치조정,셀idle에서표시이미지유지(reuse/경로교체제거유지). 자동25개/기기빌드통과. `/private/tmp/outpick-media-entry-transition-device.log`에서체감검증예정. [최신계획](chat-media-first-view-loading/display-readiness-plan.md).
# 최신: 실제 회전 표시 원인 추적

사용자 분석지시. 전체캐시hit로표시문제를단정하지않고ChatImagePreviewCell 실제스피너span/캐시결과/셀할당/종료이유계측추가. 다른회전표시도분리. 자동16개/기기빌드통과, `/private/tmp/outpick-spinner-trace-device.log`로재현대기. 기존캐시와제한해제QA조건유지. [진단계획](chat-media-first-view-loading/display-readiness-plan.md).
