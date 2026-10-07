# Q7 A~J 실제 제품 검증 결과 — 2026-10-07 KST

## 완료 범위

Development `outpick-test`, candidate `lookbook-import-worker-development-00024-car`, run `d691aaa5-64c2-413c-a3d4-115450a1df5c`에서 A 6시즌, B 2시즌, C~J 각 1시즌의 생성·목록 탐색·추출·정상 검토 승인·변환·업로드·경로 공개를 완료했다. 접수 36건 모두 accepted, batch 36개 모두 released, run 36개 모두 종료 확인, job 16개 모두 succeeded다. 마지막 대기열은 idle/head null이고 한 instanceKey가 관측됐다. Production 변경, 새 권한, 자원 증설, 데이터 삭제, 커밋은 하지 않았다.

JPEG 710개/106,930,391B의 SHA-256·크기·방향·golden 총량·Storage generation 검사가 통과했다. 커버 32객체와 게시물 이미지 339개/678객체의 현재 공개 원장·execution/epoch/write·경로/generation도 일치했다. 추가 게시물 원장 대조는 Storage GET을 추가하지 않았다.

이번은 FIFO 제품 연결의 정상 검증 1회다. 브랜드 병렬 대조군과의 성능 우월성, 최적 동시성, 장기 실패율 개선으로 해석하지 않는다. 이전 구조 비교와 입력·검토 절차가 다르므로 직접 시간 비율을 비교하지 않는다.

## 100ms wave와 실제 대기

생성·탐색 10건과 import 10건을 별도 wave로 시작했다. 앞 요청의 응답을 기다리지 않았으며 900ms 예약 구간에서 시작 지연은 각각 최대 3ms/2ms였다. HTTP 직전 기록 구간은 791ms/861ms였다. 첫 인증 토큰 취득·기록·전송 지연이 끼므로 예정 시각, 실행기 시작, HTTP 직전 기록, 실제 서버 접수를 구분한다.

| 항목 | 생성/탐색 | import |
|---|---|---|
| 실제 서버 접수 순서 | A→I→E→F→J→D→H→G→B→C | F→E→A→H→G→C→I→B→D→J |
| 서버 접수 전체 구간 | 3,785ms | 617ms |
| 앞 브랜드 종료 전 접수된 뒤 브랜드 쌍 | 45 | 45 |
| 앞 브랜드 실행 시작 이후의 신규 접수 쌍 | 0 | 0 |

두 wave 모두 10건이 첫 run 시작 전에 접수됐다. 따라서 여러 브랜드가 이미 대기하는 상태에서 서버 sequence 순으로 차례를 진행하고, 앞 run이 종료·drain된 뒤 다음 run이 시작함을 확인했다. A/B smoke에서 놓친 ‘이미 실행 중인 A에 B가 새로 도착’과 정확히 동일한 시간 조건을 재현한 것은 아니다. 클라이언트 A~J 호출 순서와 서버 접수 순번은 달랐고, 제품 FIFO는 서버가 부여한 sequence 기준이다. 실제 서버 도착이 100ms 간격이었다고 표시하지 않는다.

## 시간·자원·전송

| 항목 | 관측값 |
|---|---:|
| 실행기 시작부터 결과 검사 완료 | 628.343초 |
| 첫 서버 run 시작~마지막 run 종료 | 504.727초 |
|36HTTP 처리 측정 합계 | 442.455초 |
| Node process CPU user/system | 277.11초 / 11.70초 |
| 컨테이너 메모리 최고 |84.0496% |
| 메모리 표본 최대 공백 |380.689ms |
| 원본 이미지 다운로드 |697회 /563,984,210B |
| JPEG 업로드 |710회 /106,930,391B |
| 검증 metadata / content GET |710회 /710회 |

실행기 시간에는 로그인·사전검사·폴링·산출물 검증이 포함된다. HTTP 합계에 시즌별 병렬 작업 누적 시간을 다시 더하지 않는다. Node CPU는 Chromium 자식 CPU 전체나 실제 과금 vCPU 시간이 아니다. HTML·브라우저 하위 자원·SDK 재전송·Firestore transaction retry 등을 이미지 바이트와 동일시하지 않는다. 원본 GET 초기 산술 713회와의 16회 차이는 추출 해시 단계에서 다운로드하지 않은 커버다.

정상 이미지 단계 실패 0건, 시즌 실행 재시도 0회, 메모리 중단 0회, 복구 0회다. batch 항목 42개가 모두 최초 시도 1회로 끝났다. 관측된 메모리 최고치는 2GiB 중 약 1,721.3MiB이고 85% 기준까지 약 19.5MiB만 남았다. 해당 B 저장 run의 RSS 최고는 1,612,808,192B, JS heap 최고는 약 115MB였다. 원본 재사용 128MiB 예산이나 JS heap만으로 전체 메모리를 설명하지 않으며, native 메모리·할당 유지의 기여 원인은 이번 증거만으로 확정하지 않는다. 이 결과는 동시성 확대 근거가 아니다.

| 단계 | 설정 상한 | 실제 관측 최고 |
|---|---:|---:|
| 시즌 작업 본체 |6 |3 |
| 이미지 다운로드 |4 |4 |
| JPEG 변환 |1 |1 |
| JPEG 업로드 |4 |4 |
| 경로 공개 |없음 |4 |

A 6시즌 추출 HTTP는 9.196초이며 job peak는 3이었다. 6개가 실제로 동시에 무거운 처리를 했다는 뜻은 아니다. 모든 추출이 검토 대기를 필요로 했고 승인은 각 시즌의 새 FIFO 요청이므로, 저장 16건은 각 1job으로 처리했다. 6시즌 동시 자동 저장 부하를 이번 검토 승인 흐름이 검증하지는 않는다. 큰 시즌 저장 HTTP는 A2026FW 39.779초/E2026FW 36.456초였으며, 1회차 차이를 우월성으로 판정하지 않는다.

## 기록 문제와 원본 보존

추가 공개 원장 검사에서 원래 manifest.jobs가 빈 배열인 도구 기록 누락을 발견했다. 최초 대조는 32≠710으로 실패했고 로그·도구 원본을 보존했다. 원래 report/manifest를 수정하지 않고 16개 reviews+brands와 실제 job·승인 batch를 대조한 `verified-job-index.json`을 추가했다. 게시물 339개/678객체의 최종 대조는 통과했다. 실행기는 이후 manifest.jobs를 실제 importJobs 배열에 연결하도록 수정했으며 기존 36요청을 재접수하지 않았다.

## 원본과 필수 검사

원본기준폴더:`output/lookbook-import-performance/product-queue-q7/d691aaa5-64c2-413c-a3d4-115450a1df5c/`.

- `report.json`, `manifest.json`, 동일runID journal, `execution.log`.
- `evidence/development-preflight.json`, `batches/`, `reviews/`, `waves.json`.
- `evidence/post-publication-reference-check.json`, `verified-job-index.json`, `publication-diagnostic/{original-tool,original-failure,final-tool,final-result}`.
- `metrics/worker-measurements.json`, `rollup.json`, `rollup-tool.mjs`, `evidence/cost-status.json`.
- 실제배포snapshotgate:359tests/lint/fixtures/deploy, digest `69f5fb7455ee93224ec3f629b3c78bf8fc74461e5122ab9bb8a046537731355b`.candidate024/image5559dffd…4ec/1CPU·2GiB/concurrency2/900s/revisionmax1,tag0%/base00012-fih100%.실제run은이snapshot소스다.
- 최종 job 기록 수정 후 client gate `1791304119351-dfc3ff52-ef3a-44a8-b3fa-4836832e5c6f` passed31, digest `b0f1d7de912c642c751e516367324fdfb232038af45663e865433b8e1d1604bd`/29files.
- 최신 로컬 Worker gate `1791304151340-e812c186-cb7d-4f71-b278-8f2e3dcd3fee` passed359/lint/fixtures/deploy, digest `05762147a8c2fc4d4c9fc6236524d671ccd2b2b1f7d9d3335db99e01738b4b37`/257files.
- 최신 Linux gate `1791304150201-27099b7b-f27e-4d8e-b639-eb6c135451e7` passed2/skip0, digest `15c0dace19510bcfa46b4abddb1a390ba6f91e24696e3519da8f2d604946dd12`/251files. 1CPU·2GiB Chromium·공유 자원·표본 경계와 별도 192MiB 컨테이너의 실제 OOMKilled/137을 확인했다. 실제 Cloud Run 고의 OOM 검사가 아니다.

## 남은 완료 조건

정상 제품 저장·여러 브랜드 대기·FIFO 검증은 완료했다. 실제 12/14/15분 장시간 이어 실행·플랫폼 timeout·재전달·종료 불명확 차단은 별도 잔여 필수 항목이며 이번 짧은 run으로 통과시키지 않는다. 고의 장애나 장시간 입력은 정상 43건과 별도 실행 대상·추가 요청량·비용을 확정해야 한다. 실제 청구액, 공유 free tier 잔여, Firestore·Functions 전체 과금량은 미확정이다. 비용 ledger는 관측 사용량과 미수집 항목을 구분하며 정확한 총액이나 US$10 결제 상한을 보장하지 않는다. 전체 작업 완료 전 커밋하지 않는다.
