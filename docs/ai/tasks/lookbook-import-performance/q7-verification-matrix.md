# Q7 입력·계측·필수 게이트 행렬

## 최종 서버 판정(2026-10-07)

[전체결과·커밋기록](product-queue-q7-final-results.md). QL01/02:새26후보0%/base100%·같은Googleadmin/기존자원확인. QL03:정상A/B기능완료,active중B신규접수시간조건미관측보존. QL04:A~J대기/FIFO완료(실제서버100ms간격보장아님). QL05:원본계측/960정상JPEG의각run검증·현재참조결과보존,최적수치/장기실패율/정확청구는단정하지않음. QL06:Koldrun실제종료→같은execattempt2새파싱/재검토/저장·L총5회소진/실패목록/맨뒤수동새exec새5회/성공제거·옛쓰기미참조/정리예약·idle종료를확인했다. 승인범위 완료·필수7종 모두passed·서버/Worker/앱/검증커밋4개 생성·설계/결과67개문서 포함 승인. 실제장시간/24h물리삭제는후속미검증이다. 아래잔여·미배포·실행전은과거시점이다.

2026-10-07 실패 목록 최종 확정: 동일 시즌의 실패 목록 문서는 하나로 유지·재시도 실패 시 최신화·성공 또는 명시적 ‘재시도 안 함’ 선택 시 제거·무선택 유지다. 원본 실행 기록의 기존 보관 정책과 완료 시즌은 보호한다. 갱신/제거 인가·멱등·이전 실행의 늦은 응답 차단을 로컬 필수 검사에 연결해야 하며 아직 새 코드·테스트 통과를 의미하지 않는다. 정식 관리자 웹 UI는 별도 작업이다.

2026-10-07 최신 정정: [시즌 실패 기록·처음부터 재시도](season-failure-retry-decision.md). 중간 복원·미완료 저장 재연결은 제외한다. QL06은 실제 비정상 종료 정산·옛 쓰기 차단·새 시도 성공/총5회 소진·실패 목록/이력·맨뒤 새 수동 재시도·다음 브랜드 진행의 증거를 요구한다. 정리 범위/시도 계약과 새 실험 입력·요청량/비용은 후속 상세 설계다. 기존 저장 이어 실행 제안과4접수 산술은 실행 근거로 사용하지 않는다. 현재 Q7 미완료이며 원격 삭제·새 실험을 수행하지 않았다.

2026-10-07 사용자 확정: [Q7 집중 계획](product-queue-current-operations-plan.md). 정상 A/B·A~J 증거를 유지하고 짧은 실제 종료·복구 검증으로 Q7을 마무리한다. 실제12/14/15분 장시간 플랫폼 경계 실측은 후속 미검증으로 이관하며 기존 안전장치·로컬 시간 검사는 유지한다. 목록10개/더보기·최근 운영 지침은 관리자 웹 별도 작업이며 Q7 선행 조건이 아니다. 범위 변경은 과거 미검증의 통과를 뜻하지 않는다. 새 실제 종료 방법·요청량·비용은 상세 실행안에서 확정하며 아직 실행하지 않는다. 아래 미확정 장시간 제안은 과거 이력이다.

2026-10-07 잔여 검증 실행안 작성: [장시간·복구 최소 실행안](product-queue-q7-boundary-validation-plan.md). L/T/O각1회·11접수·90분·추가 관리예산3USD/기존누적10USD안이다. 정상6설정에서미시작항목을남기기위해2023SS를추가한7시즌안을준비했다(로컬30후보/HEAD6,704,829B). 강제종료시active/draining을조건부복구상태로정산하는경로와미완료execution/continuation재연결이현재없음을확인했다. 실제종료증거·완료/시도이력보존·전용Development고의지연/종료기능을추가하는방향은사용자확인전미확정이다. 원격변경/새접수/고의장애0,기존Q7미완료·커밋0. 승인순서대로실행안준비는진행했으며추가기술결정대기중이다.

## 최신 판정 — 2026-10-07

[A~J 결과](product-queue-q7-ten-brands-results.md): run d691aaa5는36접수/16성공/710JPEG·공개 원장 대조로 완료했다. 두wave의 브랜드 대기 및 서버sequence 비중첩을 확인했다. 서버 첫run 전에10건이접수됐으므로 active중신규도착은 미관측이다. 아래‘실행 중’은 과거 기록이다.

| 게이트 | 최신 상태 |
|---|---|
| QL01/02 | candidate024/digest·설정·정상 관리자 로그인/인가 확인 |
| QL03 | A/B 기능 저장 완료. active 중 B 신규 접수는 미검증으로 보존 |
| QL04 | A~J36건/16시즌/두100ms예약/실제서버도착기록·대기·FIFO비중첩 확인. 서버100ms도착 보장 없음 |
| QL05 |36계측/710산출물/원본바이트·CPU·메모리·시간 기록. 실제청구·전체Functions/Firestore과금은 미확정 |
| QL06 | 기존 종료 정산/IAM/audit 증거 보존. 실제 비정상 종료 뒤 처음부터 재시도·총5회 소진·실패 결과/이력·새 수동 재시도·FIFO 진행은 잔여. 중간 복원 제외, 실제12/14/15분 경계 실측은 후속 미검증 |

정상접수43건의범위는완료했지만 QL03의원래시간조건과QL06잔여를 임의로통과시키지않는다. 추가유료/고의장애검증의입력·방법·회차·비용은 별도확정한다. 최종커밋은 전체완료 뒤다.

A/B 기능 저장 smoke는7접수/3시즌/126JPEG·현재 공개 원장 검사로 완료했다. 기존 복구 실패는 보존했으며 active 중 B접수는 관측하지 못해 통과로 표시하지 않는다. 사용자 승인에 따라 이 조건은 A~J100ms wave의 실제 브랜드 대기로 확인한다. 상세는 [smoke 결과](product-queue-q7-smoke-results.md)다. 아래 최초 smoke 중단은 과거 이력이다.

A~J 실행기 QV08은 예정100ms시각과HTTP직전기록/서버접수createdAt·sequence를 구분한다. 두wave각10건/다른브랜드대기/실행비중첩을 모두 판정하고 기록 누락·중첩·대기 미관측은 통과하지 않는다. 클라이언트100ms예약이실제서버100ms도착을보장하지않는다. verifier gate1791303321801-54c50236-ead4-40c3-ad2d-f126a1131cbc passed31. 원격 run d691aaa5-64c2-413c-a3d4-115450a1df5c 진행 중이다.

QL06의 실제 장시간 이어 실행은 후속 미검증으로 이관했으며 정상 사례 완료로 대체하지 않는다. 짧은 종료·복구 검증의 증거가 확보되기 전 QL06을 완료 처리하지 않는다. 새 고의 장애는 기존36건에 포함하지 않는다.

2026-10-06 최신 상태. [통합 계획](product-queue-q7-server-validation-plan.md)과 [P2 구현안](q7-verifier-p2-plan.md)의 판정 기준이다. smoke에서 A 생성·최초 탐색과 후보 29개 확인까지 수행했으나 discovery는 `correctionRequired`, queue head는 `recoveryRequired`가 되어 시즌 이미지 import 전에 멈췄다. 수정 Worker gate 354 tests, product queue emulator gate 70 tests는 통과했으며 Q7 product E2E·A~J는 미완료다. 이 행렬의 비용 산술은 최대 예상 요청량이며 청구서 상한이 아니다.

## 실제 smoke 관측 — 진행 가능 상태가 아님

run `e9049126-5161-48ee-ad67-fc6966a7b8ca`의 A 브랜드 생성·탐색은 성공적으로 접수됐다. 고정 시즌 target 2026SS/534, 2025FW/469, 2025SS/128은 모두 후보 29개 안에 `newSeason`으로 존재하고 목록 커버 29개가 확인됐다. discovery 결과는 `load_more_detected`·`dynamic_rendering_detected`로 `correctionRequired`다. 클릭/스크롤 확장 진단은 저장되지 않아 아직 전체 목록이 완전히 소비됐다고 입증되지 않았다. 구 Worker의 결과 매핑 오류로 batch/head가 `recoveryRequired`이며, 실제 실행 기록은 `terminalConfirmed=true`, `inFlight=0`이다. 현재 `resume` 경로는 terminal outcome을 item checkpoint에 반영하지 않으므로 자동 재시도/복구 실행은 보류한다.

Worker gate `1791278437747-2969911b-2f9f-45ad-b9ef-244f9b03f212` passed (354 tests, lint, fixtures); product queue gate `1791278627925-2abd9823-7307-47e9-85e5-2bffc9c3a8f0` passed (70 emulator tests and both builds). Candidate is not updated with this source yet. Memory data had a 594.949ms sample gap and 553.648ms max event-loop delay, so Q7 run does not validate the 500ms sampling-gap or 85%/1s memory guard; images/Storage stage is untested.

## 고정 입력과 요청량

기존 queue-development-contract.mjs의 makePlan 산술을 로컬에서 재확인했다. 원격 요청은 실행하지 않았다.

| 항목 | smoke1회 | A~J1회 |
|---|---:|---:|
| 시즌 | A2026SS/2025FW, B2025SS:3 | A6/B2/C~J각1:16 |
| 생성+탐색 / import / 승인 | 2 / 2 / 3 | 10 / 10 / 16 |
| 논리 mutation 합계 | 7 | 36 |
| 추출 이미지 GET / bytes | 64 / 28,241,613 | 358 / 284,478,036 |
| 별도 승인 저장 원본 GET / bytes | 63 / 27,445,876 | 355 / 282,090,825 |
| JPEG writes / bytes | 126 / 15,614,243 | 710 / 106,930,391 |
| 결과 검증 GET 최대 / bytes | 126 / 15,614,243 | 710 / 106,930,391 |

합계43 논리 mutation, 원본 GET840/622,256,350bytes, JPEG836개/122,544,634bytes, 검증GET최대836이다. HTML·브라우저·SDK 재시도·캐시 miss·상태 조회는 별도이며 위 값은 청구 상한이 아니다. 검토 대기를 넘는 영구 원본 캐시는 없으므로 승인 단계 원본 다운로드를 포함했다.

A는 2026FW/SS·2025FW/SS·2024FW/SS, B는2025FW/SS. C2024FW,D2024SS,E2026FW,F2026SS,G2025FW,H2025SS,I2024FW,J2024SS.
A~J create/import 각각100ms wave, smoke는 실행 상태를 관측하며 접수한다.

## 계측 범위

| 지표 | 수집·판정 | 한계 |
|---|---|---|
| 종단간 시간 | 클라이언트 전송→접수→실행→검토→승인→최종공개; 대기/처리/검토대기를 분리 | 검토 대기는 사람/도구 지연이므로 순수 처리 시간과 구분 |
| FIFO | sequence·실행권epoch·run/continuation·drain·다음시작 | 브랜드 전체 완료 순서와 다름 |
| CPU | 기존 process user/system 및 필요 시 cgroup/Cloud Monitoring 보완 | Node process CPU에 Chromium 자식 CPU가 모두 포함되지 않음 |
| 메모리 | cgroup100ms, peak/limit/표본 공백; RSS/external/ArrayBuffer 보조 | 공유 process/container 값, 시즌별 메모리로 표시하지 않음 |
| 단계 동시성 | download/transform/upload/paths 각 active/peak/duration/성공실패 | 설정값과 실제 최고값 구분 |
| 전송량 | origin GET·image bytes·Storage 제출/완료 bytes·객체 metadata | HTML 하위자원/SDK 재전송을 놓치면 미수집 표시, 청구량과 동일시 금지 |
| 안정성 | 시즌/이미지 실패·재시도·중단·복구 및 분모 | 1회0실패로 장기 실패율 개선 주장 금지 |
| 비용 | 아래 비용 ledger | 추정·실측 사용량·실제 청구를 분리 |

경로 저장은 업로드된 객체 경로/generation을 Firestore에 기록하고 현재 실행권을 검사해 공개하는 단계다. 파일 전송이 아니다. 한도 없음은 실제 Firestore 병목이 없다는 뜻이 아니며 대기/transaction retry/실패를 관측한다.

## 필수 로컬 게이트

| ID | 내용·합격 |
|---|---|
| QV01 | 정상 인증과 잘못된 프로젝트/UID/origin/nonce/만료 토큰 거절, 비밀 로그0 |
| QV02 | 전송 전 기록·동시 실행 잠금·크래시 복원·동일ID 멱등, 기록 실패 시 mutation0 |
| QV03 | callable 오류/응답유실/권한회수·사이트변경·입력/요청량 상한 시 차단 |
| QV04 | fixture 시즌·순서·hash·cover·JPEG count/size 검증 및 잘못된 증거 실패 |
| QV05 | 서버 sequence/epoch/drain/continuation/조건부공개·객체generation 증거 검사 |
| QV06 | metrics 상관관계·누락/표본공백/비용 항목 미수집 표시, 판정 조작 방지 |
| QV07 | 실제 gate 필수ID·0개/skip/timeout/환경미준비 실패, 원본 로그/source digest 연결 |

기존 verification/lookbook-queue-development-preparation.json을 유지한다. 새 verifier gate는 준비 gate와 QV01~07을 필수 검사로 연결한다. 제품 코드 변경 범위에 맞춰 Functions/Worker/Emulator/Linux 기존 gate를 추가한다. 변경 전 결과를 변경 후 소스의 통과로 재사용하지 않는다.

## 실제 게이트와 잔여 필수 항목

| ID | 증거·완료 조건 |
|---|---|
| QL01 | 정확한 Development project/revision/digest·CPU/메모리/min/max/HTTP concurrency/timeout·IAM/큐 상태 snapshot |
| QL02 | 실제 Google 로그인과 exact UID 인가; 자동 privilege grant 없음 |
| QL03 | smoke7건 영수증,3시즌 hash/검토/최종JPEG/공개generation, 실제 대기·drain |
| QL04 | A~J36건,16시즌,100ms 실제 도착 기록·서버sequence·비중첩 |
| QL05 | 요청-실행-계측 연결, 누락/오류0, 자원/시간/전송/비용 보고 |
| QL06 | 실제 종료 증거·옛 쓰기 차단·처음부터 재시도·총5회 소진/최종 실패·시즌별 결과/이력·맨뒤 새 수동 재시도·완료 시즌 보호·다음 브랜드 진행·원본/audit. 장시간 플랫폼 경계 실측은 후속 미검증 |

QL06은 정상 smoke로 자동 충족되지 않는다. 기존 Q6 로컬 실패/재시도/lease/12·14·15분 검사를 유지하며 실제 플랫폼 미검증은 별도 표시한다. 고의 OOM·장시간 작업·권한 변경·강제 종료를 이번 정상43건에 몰래 추가하지 않는다. 실제 fault 시나리오가 필요하면 대상·방법·추가 비용을 먼저 실행안으로 구체화한다. 전체 Q7 완료는 필수 항목 전부의 증거가 있어야 한다.

2026-10-07 공식 문서 확인: [Cloud Run request timeout](https://docs.cloud.google.com/run/docs/configuring/request-timeout)은 timeout 시504/연결종료와 container종료를구분하며 코드가계속실행될수있다고명시한다. 따라서 정상짧은run종료나외부15분설정만으로플랫폼장시간종료를입증하지않는다. [Cloud Tasks API](https://docs.cloud.google.com/tasks/docs/reference/rpc/google.cloud.tasks.v2#task)의dispatch deadline/재전달과제품의drain·진행보존은별도조건으로검증해야한다. 이번정상43건의추가고의장애실행승인으로해석하지않는다.

## 중단·복원·비용

- 기존 기준 유지: cgroup85% 이상 표본상1초,100ms측정·500ms초과 공백이면 중단. 새 접수 차단 후 실행 중 작업 drain과 진행 기록을 확보한다. 종료 불명확이면 자동 다음 브랜드 금지.
- 12분 신규 작업 투입 중단/14분 정리·응답/외부15분, 시즌 최초 포함 총5회 즉시 재시도. 정상 이어 실행은 재시도 소진 아님.
- 실행 창 최대2시간·누적 추정US$10 중단은 기존 외곽 상한이다. 자원 증설 금지. 과거 max3 허용을 이유로 현재1인스턴스를 늘리지 않는다.
- 실행 전 현재1CPU/2GiB/min0/revisionmax1/concurrency2/timeout900 후보와 서비스 전체 max·traffic·태그 경로를 대조한다. 과거 값만으로 실제 최대 인스턴스를 단정하지 않는다.
- 비용 ledger: Worker vCPU/메모리/과금시간, Functions 호출·컴퓨팅, Cloud Tasks, Firestore reads/writes/deletes/transaction retry, Storage operation·보관·다운로드/egress·검증GET, source 네트워크, Build/Registry/Logging 및 soft-delete 보관 조건.
- 실행 직전 공식 단가/리전/무료구간·프로젝트 공유 사용량을 확인하고 계산 가정·조회 시각·예상 요청량을 기록한다. 과거$0.4~1을 이번 청구 보장으로 재사용하지 않는다. 청구 지연으로 정확한 결제 상한은 보장되지 않는다.
- 기준 초과 시 새 접수 중단, 서버 작업 종료/복구 상태 관측, 원본 보존. 자동 QA 삭제·Production 변경 없음.
- 오류·누락·skip·0개·환경미준비는 pass 아님. 실제 사용량과 추정 비용을 남기고 청구가 미확정이면 미확정으로 표시한다.
