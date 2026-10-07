# Q7 제품 룩북 대기열 — 최종 검증 정리

2026-10-07. **합의한 Development 서버 검증을 완료했고, 설계·결과 문서 67개를 포함하는 최종 커밋 범위도 사용자 승인으로 확정했다.** 관리자 웹·최근 목록 운영 지침, 실제 장시간 경계와 24시간 물리 삭제는 후속 미검증으로 남긴다. 아래 완료는 이 항목들의 통과를 뜻하지 않는다.

## 완료한 흐름과 실제 근거

| 범위 | 결과 | 원본과 판정 문서 |
|---|---|---|
| A/B 정상 기능 | 7접수·3시즌·126JPEG/15,614,243B, 현재 참조·generation·hash 일치 | [smoke 결과](product-queue-q7-smoke-results.md), run `92ad4778-f90e-408a-b062-8afc46383952` |
| A~J 요청 집중 | 36접수·16시즌·710JPEG/106,930,391B, 두100ms예약 wave·서버sequence FIFO·종료 후 다음 차례 확인 | [A~J 결과](product-queue-q7-ten-brands-results.md), run `d691aaa5-64c2-413c-a3d4-115450a1df5c` |
| K 실제 비정상 종료 | firstattempt의 실제OOM·signal9 확인→같은execution의 attempt2/5 새파싱→새검토→저장 성공 | [K/L 결과](q7-retry-development-results.md), run `845dae34-7aac-4108-a613-3944bcf44d6b` |
| L 자동소진·수동재시도 | 원래execution 총5회 제어실패→실패목록1개→맨뒤 새execution/새5회→attempt1 성공→목록 제거·원래5회 이력 유지 | 같은 run의 `L-original-failure.json`, `L-retry-evidence.json`, `batches.json` |
| 최종 K/L 산출물 | 124JPEG/4,707,216B, SHA-256·크기·generation·현재 공개 원장 일치, queue idle/head null | 같은 run의 `manifest.json`, `report.json`, `final-{K,L}.json`, `final-queue.json` |
| 중단 산출물 보호 | oldepoch49 원장6건 unpublished/cleanup pending, 새 공개 파일과 경로 비중첩, 기존12객체384,872B 보존 | `K-unreferenced-writes.json`, 원래 interruption assets readback |

정상 검증43접수와 이번8접수는 목적·입력을 구분한다. 초기 진단/실패 이력은 별도 보존하며 전체 실험 누적량을51접수로 단정하지 않는다. A/B의 active 중 B 신규도착은 놓쳤고 A~J도 첫run 전에10건이 접수됐다. 사용자 승인대로 실제 여러 브랜드의 대기/FIFO를 확인했으며 원래 시간 조건을 통과로 바꾸지 않는다.

## K/L 이어 실행과 성능 기록

- 기존K3영수증/brand/job/execution과OOM 소비1회 보존, 남은5접수만 실행해 전체8accepted다. 추가OOM0, 새task6전달/기존18포함총24전달로 추가10·누적30관찰 상한 안이었다. 모든 새task HTTP 응답은200이다. task 상한은 신규 투입 중지 기준이며 정확한 서버 강제취소 상한은 아니다.
- 이어 실행창은108.957초. 실제 종료 뒤 parsing/review 요청4.198초, K승인 저장8.635초, L탐색14.050초, L5회제어실패3.080초, L수동추출1.966초, L승인 저장7.793초다. 대기/관리자검토/검증GET 시간은 Worker 요청 시간과 구분한다.
- 새6요청의 Node CPU 합계18.01초, 컨테이너 메모리 최고47.1109%, 최대 표본 간격238.070ms. 추가 원본 이미지GET122/10,225,638B, 정상업로드124/4,707,216B, 결과검증GET124/4,707,216B다. HTML/브라우저/Firestore/Storage metadata/Logging/SDK 요청은 이미지 바이트와 별개다.
- 관측 최고 download4/transform1/upload4/path2. 제품 설정 season6/download4/transform1/upload4/cache128MiB를 유지했다. K/L은 단일시즌2개이므로 season6의 성능 근거로 쓰지 않는다.
- old25와 수정후26 revision을 구분한다. 강제 종료 요청은 마지막 CPU/바이트 계측을 남기지 못했으며 원래CLI의 실제조회수도불명확(null)이다. old12객체384,872B는 metadata로만 확인했고 미검증 hash를 통과로 표시하지 않는다. 원래503 재전달도 정상 처리 시간·실패율에서 숨기지 않는다.
- 이는 각기능흐름1회검증이다. 통계적 성능 우월성·최적 동시성·장기 실패율·실제 청구 확정으로 해석하지 않는다. 원본 `continuation-metrics-summary.json`, `worker-measurements.json`, `runtime-logs-final.json`.

## 현재 서버 소스의 필수 게이트

| 검사 | 실제 실행ID | 결과 |
|---|---|---|
| Q7 verifier | `1791350705468-a622bcfb-7122-4c77-83d2-b5f4cbfcc93a` | 40 passed |
| Worker/lint/fixture/deploy | `1791350924548-fb884600-16d2-4ce6-a7d1-6a6584747dcf` | 362 passed |
| Functions/lint/build | `1791350768254-4fb5aafc-8c63-4052-9c91-52d3dde93644` | 324 passed |
| Firestore·Storage | `1791350834823-04879ad1-a8c9-4b27-bf8c-7cab285725ea` | 131 passed |
| Linux 자원·실제OOM | `1791350929505-833392b6-f2b8-4f63-9d72-2e6c01116b90` | 2 passed |
| 제품 대기열/빌드2 | `1791351062534-a659aa8e-fd95-46ea-8615-b03ed12fee38` | 96 passed |
| 앱·GRDB 요청 계약 | `1791351931354-77dba3f2-cbfd-48ca-b01e-503e3c4db6e8` | 28 passed |

source digest·필수검사·원본 summary 연결은 `continuation-local-gates.json`. 초기sandbox W9실패(MachPort/listen EPERM) 원본을 보존했으며 같은소스/기준을 실행 가능한 환경에서 통과했다. 기존 Rules 동시신고33검사는 freshEmulator에서 실행해 전체131항목을 유지했다. 실패 원인/환경 보완은 [상세 결과](q7-retry-development-results.md)에 기록한다. 앱·GRDB 변경도 현재파일 기준28개를 새로 통과했다. 새관리자웹UI/실기기수동QA를 이검사로 대체하지 않는다.

## 배포·비용·보호 범위

Development `00026-zip`, 이미지 `sha256:0b1ddb5c88919fcd7d9c612a5f0aa3133085592d6a06648b1e3766b69ea022cf`, Wdigest `87c232ee179117b8fd1efcd94a0b8c3ffe9eb487570f1a2e07c1852aa52fda91`. Q7태그0%/base`00012-fih`100%,1CPU2GiB/min0/revisionmax1/service max5/concurrency2/900초를 실제 확인했다. 추가IAM/자원증설/Production변경/기존QA삭제0. 새L전용faultcampaign은completed이며 기존Kfault는 원본으로 보존한다.

실제새build239.420초/이미지574,343,286B. 공식SKU 기존입력·무료차감0·추가image1개월·새20분compute/operations여유로 전체K/L관리추정약USD0.396이다. 기존추가관리1USD/누적10USD한도유지, 정확청구/하드결제상한은아니다. 원본 `continuation-deployment-{readback,cost-inputs}.json`.

## 후속 미검증·커밋 경계

- 실제12/14/15분 장시간 플랫폼 경계와24시간후물리삭제는 후속이며 로컬시간/보호검사는 유지한다. Development asset/recordcleanup scheduler2개는 미배포다. 전역정리 활성화로 기존QA를 임의삭제하지 않았다.
- 관리자 웹 UI·최초10개/더보기10개·원본사이트순서·최근1~2년 운영은 [별도 작업](../admin-web-operations-migration/lookbook-list-operations-followup.md). 정식관리자웹 없는현재Q7은 로그인+기존제품API·실제서버증거로검증했다.
- 최종 커밋은 서버, Worker, 앱, 테스트·검증, 설계·결과 문서로 나눈다. 별도 chat-search/Xcode 프로젝트 변경·portfolio·로컬 설정·생성 로그·HANDOFF/.codex는 제외한다. 사용자가 승인한 task 문서67개만 파일명을 지정해 force-add한다.

## 작업별 커밋 기록

| 작업 | 커밋 | 파일 수 |
|---|---|---:|
| 서버 계약·실패 목록 | `f633028c` | 36 |
| Worker FIFO·처음부터 재시도 | `0116c133` | 120 |
| 앱 요청 기록·상태 복원 | `db02b801` | 33 |
| 테스트·필수 게이트 | `b272a940` | 96 |
| 설계·결과·후속 운영 지침 | 이 문서를 포함하는 마지막 커밋 | 79 |

앞 네 커밋은 생성 결과를 확인했고 문서 커밋에는 기존 공유 하네스12개와 승인된 문서67개를 포함한다. 자체 커밋 해시는 문서 내용에 순환 참조하지 않으며 `git log`와 로컬 실행 기록 `final-commits.json`에서 확인한다. 커밋 과정에서 검증한 제품 코드의 내용은 변경하지 않았다.
