# 진행 상태

## 최신 — 빠른스크롤 선로딩 구현·자동30통과·기기QA 대기

directdisk만으로사용자매우빠른스크롤loading개선불충분. direct재다운로드0/링크378정리/압축byte대기제거됐으나decode입장p95 474ms잔여. 속도최대4화면+예상도착구간/24경로상한·빠른수요밖즉시취소구현. 자동30개통과/기기설치launch성공, `/private/tmp/outpick-predictive-prefetch-device.log` session40665. 이동중loading와정지위치표시를나눠사용자QA답변대기. [근거](display-readiness-plan.md).

## 최신 — direct disk 자동47개 통과·기기QA 대기

기기캐시보존설치/재실행/계측성공. `/private/tmp/outpick-direct-disk-device.log` session13182. 사용자같은과거구간빠른스크롤/1왕복후체감답변대기, 실제direct/fallback/링크해제·decode대기검토필요. 그후3단계속도/도착선로딩구현(승인됨). [진행](display-readiness-plan.md).

## 최신 — direct disk URL 구현/회귀, 속도선로딩 다음

사용자두추천안확정. 채팅remote만direct disk file URL opt-in,hardlink로교체/삭제보호·decode2/IO상한유지·실패legacy복구. 테스트/기기빌드진행(기기build성공). 먼저실기기재실행후direct경로효과확인,그다음속도/도착구간선로딩순차구현. [계획/계측](display-readiness-plan.md).

## 최신 — 예산확대·재실행QA 완료, 디스크 표시준비대기 다음

재실행후network완료0/diskhit358/miss0/용량퇴거·압박0, memoryImmediate1734. 사용자빠른스크롤시짧은로딩후표시. diskRead p95 3.56ms 대비decode입장232.56/decodeBytes입장395.47ms로 다음2단계원인범위좁힘. 일반DEV복원요청. [근거](display-readiness-plan.md). 1GiB예산단계완료, 파일규격·선로딩정책변경없음.

## 최신 — 1GiB 장거리 QA 사용자수용, 앱재실행 검증 중

사용자반복로딩0/버벅임·발열·빈사진없음. 계측memoryImmediate2043/캐시339개929MiB계산비용/다운로드85개전부고유/용량퇴거0/압박0, 앱phys_footprint peak126.35MiB(캐시비용과다름). 앱재실행진단 `/private/tmp/outpick-display-budget-relaunch-device.log` session53004 실행성공, 같은과거구간왕복답변대기. [근거](display-readiness-plan.md).

## 최신 — 1GiB 캐시 자동검증통과·기기QA 대기

고유자동58개 통과(공용57+최종LRU5중신규1). 실기기build/install/진단launch 완료, `/private/tmp/outpick-display-budget-device.log` session42614. 사용자전체채움/장거리3왕복/방재진입 체감답변대기. 이후앱재실행디스크재사용별도측정. 정책은디스크1GiB/900MiB,채팅메모리1GiB LRU+압박warning256MiB·critical0·normal복귀. 다른캐시/파일규격유지. [기록](display-readiness-plan.md).

## 최신 — 사용자1GiB/LRU/압박축소 확정, 예산확대 구현·회귀 중

채팅 remote 메모리1GiB LRU/디스크1GiB 정리900MiB 구현. warning해제후256MiB/critical0/normal1GiB복귀. 기존파일/화질/서버/계정정책유지, 다른캐시기존예산유지. 자동LRU·압박·공용회귀/기기빌드 진행. [세부](display-readiness-plan.md). 아래추천답변대기는해소됐으며첫단계실기기QA후표시대기/선로딩순진행.

## 최신 — 표시파일/예산→표시대기→선로딩 순으로 우선순위 변경 승인

사용자 새순서대로진행 지시. 고유다운로드275개398.29MiB 및 기기채팅캐시254개314.12MiB 확인. 현행파일유지+공용채팅디스크1GiB/정리900MiB QA안을 제시했고 답변대기. 정책코드미변경. [세부계획](display-readiness-plan.md). 원본분리는뒤로미룸.

## 최신 — ③ Phase1·2 완료, 후속 Phase3~5 미착수

사용자 근접왕복이미지유지/기다리면모두표시 확인. 자동89개통과, 기기memoryImmediate140회, 저장282건success/종료gate0 확인. 첫진입로딩·용량퇴거·files/decode대기는 잔여. pending합류/송신저장경합은 자동근거이며 이번실기기표본없음. 일반DEV복원성공. [근거·한계](cache-reuse-results.md).③전체완료아님.

## 최신 — ③ Phase2 자동89개 통과, 개선 기기 QA 대기

즉시메모리표시/같은key pending합류/송신준비후독립저장/삭제중늦은저장차단 통합89개 통과 및 기기build/install/진단launch 성공. `/private/tmp/outpick-cache-reuse-phase2-device.log` session25252 수집 중. 사용자 같은구간2왕복/방재진입 체감 답변 대기. 용량퇴거 재다운로드는 정책유지로 남으며③ 전체완료아님. Phase3원본/Phase4뷰어 미착수. [기록](cache-reuse-results.md).

## 최신 — ③ Phase1 기준선 완료, Phase2 통합 회귀 진행

반복28개 다운로드 중27개 용량퇴거 연결, 앱재실행 후에도 디스크hit와 실제재다운로드 혼재. 사용자 기다리면 모두표시/스크롤시로딩 확인. 기준선계측 종료·일반DEV복원. 즉시메모리표시16개 및 pending합류46개 단계검증 통과(중복합산금지). 로컬준비→독립쓰기·삭제세대차단까지 수정해 최종통합회귀/기기빌드 진행. Phase3~4 미착수, 크기/용량/계정정책 유지. [근거](cache-reuse-results.md).

## 2026-09-23 최신 — ③ Phase1 계측→Phase2 개선 승인·착수

계측 자동25개 통과·실기기빌드/설치/진단실행 성공. `/private/tmp/outpick-cache-reuse-baseline-device.log` 수집 중. 사용자 반복 스크롤/10초정지/방재진입 완료 답변 대기, 앱 재실행 기준선은 다음 순서. Phase2 행동 변경 전이다.

리소스/디스크 hash 연결, 메모리·디스크 hit/miss/쓰기 결과/pending/용량 퇴거/표시 상태 계측 추가. 기존 캐시/크기/용량/계정 정책 유지. 자동 회귀·기기 계측 빌드 진행, 기준선 실기기 QA 후 Phase2. [실행 기록](cache-reuse-results.md). 아래③ 미착수는 과거 기록이다.

## 최종 — ② 필수 잔여 종료, 다음③

공식 SDK12.17.0 취소 수정 적용. 구SDK 동일 테스트에서 취소 후 HTTP 재시작·success 전환·파일 생성3개 실패를 재현했고 수정SDK 단독 통과/공용87개 통과. 새 DerivedData 실기기 빌드 및 취소QA 통과: callback취소87, 파일90개 생성/해제, 기존13→13 신규0, 관측gate 전부종료0. 사용자 앱 멈춤없음, 빈이미지는 빠른스크롤/방이탈 직전으로 명확화해 지속실패아님. 일반DEV복원 요청. 이전3개파일 개별원인 입증/신규SDK 성공대량속도 비교까지 완료한 의미는 아니다. 다음③ 구현은 `cache-reuse-implementation-plan.md` 기준이며 아직 착수 전.

## 최신 — 공식 SDK 취소 수정 적용, 최종 기기 QA 준비

Firebase12.17.0으로 공식 Storage 취소 경합 수정 적용. Simulator 공용87개 통과. 구12.3.0의 같은 테스트 비교 진행 중이며 테스트 상태 조회는 두 버전 공통 task.state로 맞췄다. 기존 DerivedData 실기기 빌드의 Firestore bridge 오류는 새 DerivedData에서 해소되어 BUILD SUCCEEDED. 기기 설치/최종 반복 QA가 남았으므로② 완료 및③ 착수 아님. 이전 임시 파일3개의 개별 발생 원인까지 증명한 것은 아니다.

## 최신 — 파일 수명 재현 QA 완료, 이번에는 잔존 미재현

사용자 완료 후350개 생성/해제 전부 확인, 실제 취소330건, 미해제 key0, 임시 폴더13→13 신규0. 상세는 [실행 결과](download-bottleneck-results.md). 앞선3개 잔존 원인과 SDK 종료 경계는 미해결,③ 착수하지 않음. 계측 종료·일반DEV복원. 다음은 SDK 파일 전송 수명 보완 대안의 기술 영향 검토다.

## 2026-09-22 — ② 취소·파일 수명 원인 추적 진행

- 사용자 수정·회귀 후③ 진입 승인. 아직 원인 수정 완료/③ 착수 아님.
- `ImageTemporaryFile` 생성/해제(absent/removeFailed), Firebase file target 및 callback 후 progress 계측 추가. target과 파일 생명 주기를 같은 URL path hash로 연결한다. `ImageStorageTaskHandle.hasFinished`는 진단 판별용이다.
- iPhone14 scheduling7개 회귀 통과(`/private/tmp/outpick-file-lifetime-trace-build.log`). 진단 실행은 자동 잠금으로 한 번 실패했고 사용자 잠금 해제 후 재실행 성공. `/private/tmp/outpick-file-lifetime-device.log` 수집 중, devicectl console session91783. 시작 전 파일 목록 `/private/tmp/outpick-lifetime-before.json`.
- 사용자의 빠른 과거 스크롤→로딩 중 이탈3회→15초 대기 완료 답변을 기다리는 상태. 아직 이번 진단에서 실제 file 전송/생명 주기 표본이 없어 원인을 추가 확정하지 않았다. 완료 후 사후 파일 목록과 생성/해제 hash를 대조하고 일반 DEV로 복원해야 한다.
- SDK 소스 확인: enqueue의 actor await 중 취소/완료 callback이 먼저 발생할 수 있으며 이후 enqueue 진행을 막는 검사가 보이지 않는다. 원격 SDK의 늦은 쓰기와 앱의 참조 잔존을 구분해야 한다. 단순 지연 삭제/강제 전체 캐시 삭제/승인 없는 transport 교체는 하지 않았다.

## 2026-09-22 — ② 잔여 QA에서 임시 파일3개 잔존 발견

저장 실패 자동 suite7개 통과. 실제 취소 callback과 대량 반복 QA 수행, 사용자 멈춤/점진적 느려짐 없음. 작업 슬롯은 정리됐으나 신규 임시 파일3개가 남아② 완료 판정 보류. SDK cancel callback은 내부 전송 완전 종료 보장이 아니므로 기존 가정을 재검토해야 한다. [근거·수치·미확정 원인](download-bottleneck-results.md).③ 구현 미착수 유지.

## 2026-09-22 — ③ 계획 기록 후② 재점검 복귀

- [③ 세부 계획](cache-reuse-implementation-plan.md): 계측→표시 재사용/독립 저장→원본 lease→뷰어/영상 수명→280장 QA. 각 Phase 파일·의존성·완료 기준·검증·미결 명시. 닫기 저장 취소/안내 없음과 영상 즉시 재생 반영. 크기·용량·표시 파일 정책은 QA 후 결정, 구현 미착수.
- [② 재점검](download-bottleneck-plan.md): 기존 상한·files 저장까지 보유·대기 visible 우선/실행 중 비선점 유지 추천. 새 필수 사용자 결정은 없으며 SDK 취소/장시간 자원/저장 실패/동일 cold 비교는 검증 잔여다.
- 문서 작성과 코드 대조만 수행. 제품 변경·테스트 실행·기기/서버 조작 없음.

## 2026-09-21 — ③ 핵심 정책 확정

- 앱 캐시 분리 우선, 현재 사진+앞뒤1장 원본 선로딩/범위 밖 취소, GIF·영상은 열 때만, 원본 파일 저장/실패 재시도를 사용자 확정했다. 앞선 질문 대기 기록은 해소됐다.
- [설계 초안](display-original-cache-design.md)에 반영. 크기·인코딩·메모리 보존·구버전 migration·원본 파일 예산/lease는 추가 기술 점검 대상이다. 구현 계획/제품 코드 수정 없음.

## 2026-09-21 — ③ 설계 시작

- 후속 사용자 선택: 주변 원본 선로딩 일부 유지. 방문한 원본만 요청하는 최초 추천 대신 현재+앞뒤1장 사진/범위 밖 취소·GIF/영상은 열 때만 받는 안을 질문했다. 원본 파일 저장 실패 시 재시도 정책도 별도 질문 중. 제품 코드는 수정하지 않는다.

- 사용자 앱 내부 표시용 캐시/원본 분리부터 진행 선택. 서버 썸네일 재생성은 이번 우선 범위에서 제외했다. [설계 초안](display-original-cache-design.md) 작성, 제품/테스트 코드 변경·기기/서버 조작 없음.
- 원문 payload 저장과1024px 화면 디코딩의 불일치, 확대에서 가까운8개+나머지 원본 선로딩, 같은 remote cache 공유, displayed UIImage 우선 저장을 확인했다. 앞선 재다운로드53건에 원본이 섞일 수 있어 thumbnail-only 증거로 해석하지 않는다.
- 원본 방문 기반 저장/전체 선로딩 제거/원본 파일 저장과 실패 재시도 방향을 사용자에게 질문한 상태다. rendition/변환/메모리/원본/영상·마이그레이션 계약 확정 전이며 세부 구현 계획은 아직 작성하지 않는다.

## 2026-09-21 — ② 실기기 병렬 전송 확인·반복 로딩 잔여

- 구조 수정/자동75개 통과 후 기존 캐시 유지 QA에서 실제 파일 전송 최대6개 overlap 확인. 다운로드 완료241건/경로188개, 추가 완료53건과 캐시 정리5회도 관찰됐다. 사용자 보고는 이전보다 빠르지만 재등장 재로딩과 느림이 남는다는 것이다.
- 별도6개 다운로드·캐시 삭제는 수행하지 않았으며 사용자 기존 캐시 화면 QA만 진행 의사를 준수했다. 일반 DEV 실행 복원. [정확한 집계/검증 한계](download-bottleneck-results.md).
- ②의 직렬화 제거 구현과 실기기 병렬성은 확인됐다. 반복 다운로드 원인의 개별 eviction 대응/장시간 RSS/동일 cold 비교는 미검증.③ 표시 캐시·원본 분리 작업을 임의 착수하지 않는다.

## 2026-09-21 — ② 구현·자동 회귀 완료, 실기기 QA 진행

- 사용자 구현 승인 후 file 다운로드의 앱 io(write) 점유를 제거했다. network/files와 기존 수치·저장/취소 계약 유지. 기존 코드에서 A hold 시 B 전송과 캐시 저장이 막히는 실패를 재현했고 수정 후75개 통과.
- 실기기 기존 캐시를 유지한 계측 실행으로 사용자 과거 사진 왕복 QA 진행 중. 실제 파일 다운로드 overlap/체감은 아직 확인 중이다. [변경·실행 근거·한계](download-bottleneck-results.md).

## 2026-09-21 — ② 세부 구현 계획 작성 완료

- 사용자 계획 작성 요청에 따라 [② 계획](download-bottleneck-plan.md)을 작성했다. 공용 processor·files/network/io 소유권과 SDK 완료 콜백·persistence·캐시 파일 정리, 채팅/방 이미지/아바타/HTTP 룩북 영향을 대조했다.
- Phase1 병목 재현→Phase2 io/network 분리→Phase3 취소/저장/공용 회귀→Phase4 실제 기기 비교. 각 목표/파일/완료 기준/검증/논의 조건과 자동 검증 행렬을 포함했다.
- 구조 변경과 수치 튜닝을 분리한다. SDK 임시 파일 쓰기는 network/files에 제한되며 앱 diskWrites1이 장치 전체 쓰기1개를 의미하지 않음을 명시했다. files는 저장 완료까지 유지해 저장 대기 누적을 제한한다.
- 이번 턴은 문서만 변경. 제품 코드·테스트 코드·빌드·테스트 실행·기기/서버 변경 없음. 기존 사용자/① 변경은 보존한다.② 구현은 아직 시작하지 않았다.

## 2026-09-21 — ① 사용자 수용·② 상세 설계 착수

- 사용자가 회전 복귀 체감 개선을 확인하고 다음 단계 진행에 동의했다.① 집중 회귀95개/UI3개 및 사진·영상·GIF 사용자 QA 결과 수용. 상세 미검증 한계는 qa-results에 유지한다.
- ② 사전 조사: `ImagePipelineProcessor.downloadFile`이 `io.withPermit(.write)` 안에서 전체 network 전송을 기다린다. 기본 network6/file6이어도 diskWrites1 때문에 파일 다운로드가 직렬화된다. SDK 파일 전송 입장과 캐시 디스크 쓰기 예산 분리 설계가 필요하다. 공용 경로라 채팅/방 이미지/아바타와 디스크 저장·취소·임시 파일 정리 영향 확인 후 세부 계획을 확정한다.② 제품 코드는 아직 수정하지 않았다.

## 2026-09-21 — 사용자 회전 지연 보고 후 수정

- 가로→세로에서 크기 복원이 느리다는 사용자 보고를 조사했다. 미디어 폭/높이가 configure 시 고정돼1장/30장 모두 폭 변경을 반영하지 않는 실패를 자동 테스트로 재현했다.
- `ChatMessageCell.configureWithImage`의 크기를 부모 폭70%와 배열 높이 비율 제약으로 연결. 재설정·이미지 재로딩 없이 크기 변경을 반영한다. 관련8개와 실기기 회전 UI1개 재실행 통과, 누적 단위/컴포넌트95개·UI3개. 일반 DEV 복원, 사용자 체감 재확인 대기. [수치/로그/한계](qa-results.md).

## 2026-09-21 — 화면 수명 후속 QA

- 단위/컴포넌트 누적94개, 실기기 UI 누적3개 통과. 키보드·검색 모드 종료·설정 패널·사진 선택 취소·짧은 뒤로가기 제스처 후 채팅 유지·세로 복귀 확인. 회전 시 XCTest hit point 오류는 viewport 교차 기준으로 검사 보정 후 재실행했다.
- 가로의 좌표/로딩 상태 검사는 통과했지만 캡처가 잘려 보여 사용자 실제 화면 대조 대기. 제품 코드 변경 없이 테스트와 문서만 보완했고 일반 DEV 실행 복원. [로그·한계·잔여](qa-results.md). 아래 수명 QA 미검증 기록은 이전 이력이다.

## 2026-09-21 — ① 자동 테스트·실기기 QA 진행

- 사용자의 검증 승인 후 iPhone14에서 중복을 제외한 단위/컴포넌트89개와 실제 미디어 QA방 UI1개 통과. 실행별 수치·로그·한계는 [실행 기록](qa-results.md)을 따른다.
- 테스트 probe 중복 fulfill 수정, 공유 카드 SF Symbol alignment inset으로56pt 영역이53pt가 되던 문제 수정 및 재검증 완료.
- 과거 사진 스크롤·확대/닫기·왕복·백그라운드 복귀·방 재진입을 자동 조작하고 캡처를 확인했다. 현재 캐시가 있는 기존 방 검증이며 cold 다운로드 성능 또는 모든 미디어의 서버 E2E 통과는 아니다.
- 일반 DEV 실행으로 복원. 사용자가 신규 사진 여러 장·짧은 영상에 이어 GIF도 전송→스크롤 복귀→방 재진입→확대·재생까지 정상 확인했다. 세 미디어의 해당 실기기 흐름 모두 통과. 키보드/설정 등 잔여 범위는 실행 기록에 구분했으며① 전체 완료·② 진입은 보류한다. 아래 미실시 기록은 이번 검증 전 이력이다.

## 2026-09-21 — ① 로컬 구현·검증

- 사용자 “세부 구현 계획 따라서 순서대로 … 구현 진행하자” 승인에 따라 Phase 1~3을 순차 통합했다. Phase 4는 테스트 작성/컴파일 검증이며 자동 테스트 실행·실기기 QA는 미실시다.
- Phase 1: ChatMediaViewportPolicy/Controller 신규. 실제 표시 회차와300ms 해제 유예 분리, 실패 회차당1회·재등장/방 세션 재시도, suspend 시 회차 보존, 경로/요청 세대 검사. 서비스 priority 명시 전달. 동일 파일 합류/최종 소비자 취소는 기존 ImageLoadCoordinator가 담당한다.
- Phase 2: Container factory→Coordinator→VC로 방별 controller 주입. 별도 VC extension의 frame 수집과 화면 수명 연결. 사진 묶음은 공유 layout 함수와 실제 중첩 layout attributes, 카드는 thumbnail 영역을 사용한다. 셀/카드 자체 Task 제거, 로컬→서버 표시 유지, 일반 원격 경로 교체 시 기존 표시 초기화.
- Phase 3: initial warmMedia 이벤트와 미사용 concurrency, 수신 전체첨부 대기, 메시지±60 prefetch/cleanup, 최신 메시지 이동 warmup, 본문 원본/MP4/poster fallback 제거. 미사용 ChatVideoAssetLoading/Service 및 전용 테스트 제거. 초기 조회 크기·저장 queue·전송 FIFO·서버 DTO/DB·뷰어 원본 API 유지.
- 세부 구현 선택: item별 소비자 상태를 두고 resource 중복 다운로드는 공용 pipeline에서 합류한다. 승격 시 기존 prefetch 소비자를 완료까지 유지하고 visible 소비자를 합류시켜 등록/취소 경합과 다운로드 재시작을 피한다. 추가 방 전체 UIImage 캐시는 없다.
- 테스트 작성: ChatMediaViewportPolicyTests, ChatMediaViewportControllerTests, ChatImagePreviewContinuityTests 갱신. ImageViewerPagePolicyTests의 본문 경로 정책과 upload fake 계약 갱신. 기존 ImageLoadCoordinatorTests의 최종 소비자/transport 계약은 유지한다.
- 초기/수신 VC 전체를 fake로 구동하는 별도 통합 테스트는 추가하지 않았다. 해당 변경은 기존 미디어 await 제거와 타입/참조 대조로 확인했으며 실제 표시·저장 접수/읽음/페이지 회귀는 QA 잔여다. 수동 QA를 자동 테스트 통과로 대체하지 않는다.
- 첫 빌드는 실행 중 파일 삭제에 따른 입력 목록 오류, 다음 빌드는 최신 메시지 이동의 잔여 warmup 호출로 실패했다. 해당 경로까지 교체 후 Development Simulator 앱/테스트 target build-for-testing 통과. 마지막 보완을 포함한 최종 빌드도 통과했다.
- 최종 검증: `xcodebuild -project OutPick.xcodeproj -scheme OutPick-Development -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/outpick-media-viewport-build build-for-testing` → **TEST BUILD SUCCEEDED**. 로그 `/private/tmp/outpick-media-viewport-build-final.log`. 앱과 전체 테스트 타깃 arm64/x86_64 컴파일이며 XCTest 실행 결과가 아니다.
- 마지막 셀 reconfigure의 viewport 갱신 보완까지 포함해 빌드 통과. `git diff --check`와 task 문서11개 내부 링크/공백 검사 통과. 기존 HANDOFF.md·docs/portfolio/·firestore-debug.log 변경은 건드리지 않았다.
- 테스트 실행은 프로젝트 지침(명시 요청 시 실행)에 따라 보류. 서버/기기 데이터 변경·앱 설치·캐시 삭제·커밋 없음. ②다운로드 직렬화와③큰 썸네일/원본 캐시는 아직 개선 범위 밖이다.


## 2026-09-21 — 분석·정책 합의·설계/계획 작성 완료

- 후속 사용자 요청에 따라 [세부 계획](plan.md)을4개 phase 문서로 구체화했다. 파일/메서드 변경, 입력·출력과 상태 소유, UI/DI 연결, 초기·수신 우회 제거, 테스트/QA 및 통합 경계를 명시했다. 추가 제품 결정 사항은 현재 없다.
- 이번 후속 작업도 문서만 변경했으며 제품 코드·빌드·테스트 실행·기기/서버 조작은 하지 않았다.
- 세부 계획 추가 후 task 문서11개의 내부 링크·trailing whitespace 검사와 `git diff --check` 통과. 기존 사용자 변경은 보존했다.

- 현재 우선순위: 채팅방 대표 이미지보다 먼저 과거 미디어 재로딩을①수요/취소→②다운로드→③캐시/원본으로 개선하기로 사용자 합의.
- ① 정책은 [결정](decisions.md)·[설계](design.md)에 확정. 사용자가 스크롤 재등장/방 재진입 재시도로 수정했으며, 네트워크 복구·앱 복귀 자동 재시도를 추가하지 않는다.
- [구현 계획](plan.md) Phase1~4 전부 미착수. 코드·테스트·기기·서버 변경 없음. 다음 액션은 구현 계획에 대한 사용자 구현 착수 지시 후 Phase1부터 순차 진행.

## 분석 근거

Development 미디어 QA방과 연결된 iPhone14의 읽기 전용 대조: 서버/로컬64메시지·313사진 첨부 경로/순서 일치, 실패0·잘못된 로컬 파일 경로0·DB quick_check ok. 서버 원본/썸네일626개 존재, 원본 크기/generation/MIME 일치. 썸네일394.93MiB 중 기기279개340.32MiB 보유,34개 디스크 부재. 보유 파일279개의 크기는 서버 썸네일과 모두 일치하나 본문 해시 검증은 아님. 현재 이 방에는 남아 있는 GIF/영상0개라 해당 결함은 코드 분석에 한정.

34개 각각이 퇴거됐는지 미다운로드인지 역사 로그로 확정하지 못했다. Storage 관리자 metadata 조회는 앱 SDK의 인증/권한 성공이나 파일본문 무결성 검증을 대신하지 않는다. 요청별 실제 지연은 새 계측 필요.

기존 코드: ChatViewController 초기전체 warmup·수신전체 다운로드 대기·message±60 prefetch; ChatAttachmentImageService 표시1024px/원문 disk350/280MiB; ImagePipelineProcessor maxBytes 기반 파일 경로와 I/O write1 점유. 이 상호작용이①~③의 출발점이다.

임시 상세 보고서는 `/private/tmp/outpick-media-analysis-20260921.md`. 분석 DB 사본은 삭제했고 서버 미디어 본문 다운로드·데이터 변조는 없었다. 임시 파일의 장기 존재를 보장하지 않으며 핵심 근거는 본 문서에 보존한다.

## 문서 변경과 검증

- task README 갱신; design/decisions/decisions 상세/plan/QA/progress 작성; ENTRYPOINTS·CHAT·active의 새 작업 링크 추가.
- 앱 구현이 없어 빌드/자동 테스트 미실행. task 문서7개 내부 링크·trailing whitespace 검사와 `git diff --check` 통과.
- 기존 사용자 변경 `HANDOFF.md`, `docs/portfolio/`, `firestore-debug.log`는 보존한다. 기존 task 폴더는 ignore 대상이며 force-add/커밋하지 않는다.
# 최신: 현재 불러온 메시지 전체 디스크 준비

사용자 승인 범위대로 거리순 한 장씩 cache-only 준비, prefetch보다 낮은 우선순위, 메모리 여유/압박 검사 및 무퇴거 삽입 구현. 서버 미디어 만료는 별도. 자동45개와 기기 빌드 통과, 기존 캐시 유지 설치. 실기기 QA는 [표시 준비 계획 최신 항목](display-readiness-plan.md) 및 `/private/tmp/outpick-room-disk-preparation-device.log`에서 이어간다.
# 최신: 제한 해제 실험

사용자가 세 동시성 제한 해제 QA 승인. DEBUG 전용 옵션으로 요청/decode/IO gate를 함께 우회하고 CPU·실제decode active 계측 추가. 초기 컴파일 반환문 누락 수정 후 최종검증 실행 중. 자세한 계약과 후속 QA는 [표시 준비 개선](display-readiness-plan.md)의 최신 절을 따른다. 일반실행/Release 정책 확정은 QA 결과 이후다.
