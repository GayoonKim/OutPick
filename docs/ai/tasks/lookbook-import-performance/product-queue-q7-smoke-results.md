# Q7 A/B 기능 저장 smoke 결과 — 2026-10-07 KST

## 완료 범위

run `92ad4778-f90e-408a-b062-8afc46383952`, Development `outpick-test`, candidate `00024-car`에서 A2026SS/2025FW와 B2025SS를 생성·탐색·추출·검토 승인·변환·Storage 업로드·경로 공개했다. 확정 mutation7개 모두 accepted,7batch released,3job succeeded,queue idle/head null. 이전 A 실패 이력1회 포함 누적 접수8회. Production/자원증설/데이터삭제/커밋 없음.

기능 완료이며 A active 중 B 접수 조건은 미검증이다. 실제 A import run 약3.240초를 조회가 놓쳤고 사용자 승인에 따라 기존 결과를 유지해 저장만 이어갔다. report는 `functionalStorageSmoke`, `overlapObserved=false`, `historicalFailurePreserved`, 대기 검증 후속은 `tenBrands100msWave`다. 최초 접수부터 완료까지5,636,078ms에는 진단·배포·인증·중단 시간이 포함되므로 연속 처리 성능으로 사용하지 않는다.

## 실제 검사

- JPEG126개/15,614,243B, metadata126회/GET126회. SHA-256·JPEG 크기/방향·golden 총량·Storage generation 통과.
- 커버6객체는 현재 published 원장에서 경로/generation을 확인했다. 게시물60이미지/120객체도 현재 공개 원장·review batch epoch·execution/write 식별자·Storage generation과 일치했다. 게시물 추가 원장 검사는 Storage를 다시 다운로드하지 않았다.
- 서버sequence/FIFO·실행종료/inFlight0·다음차례 비중첩을 검사했다. 현재revision7run은 기존 자원 기준을 충족했다. 이전2recovery run은 durableDrain/쓰기불확정0/실제recoveryDecisions와 시간순서를 대조해 별도 실패 이력으로 유지했다.
- 실제 후보 원본 순서/hash/cover URL 대조와 정상 검토 API 승인3회를 수행했다. B의 원본17개는 중복 제거 후16개 게시물로 저장됐다.

## 실제 자원/전송

현재revision7reports의 HTTP 처리 측정 합계71,532.469ms, process CPU user47.05s/system1.94s. Chromium 자식 CPU가 모두 포함된 전체 컨테이너 CPU라는 뜻은 아니다. 메모리는 cgroup1/2GiB·100ms표본, 최고63.1504%, 최대표본간격394.535ms, memoryStop0. 현재 정상 추출/저장 이미지 단계 실패0/재시도0이다. 1회 결과로 장기 실패율이나 통계적 우월성을 판정하지 않는다.

실제 원본 이미지 GET124회/55,089,793B, JPEG upload126회/15,614,243B. 초기 산술127회/55,687,489B와 차이는 추출 단계에서 다운로드하지 않은 커버3개다. 승인 저장 단계는63GET이다. HTML/브라우저 하위 자원·SDK재전송·과금량은 이 이미지 바이트와 구분한다. 실제 청구액은 미확정이며 비용 상한 보장이 아니다.

| 단계 | 실제 최고 동시성 | 실제 처리 |
|---|---:|---:|
| 이미지 다운로드 | 4 | 124 |
| JPEG 변환 | 1 | 126 |
| JPEG 업로드 | 4 | 126 |
| 경로 공개 | 2 | 63 |

시즌 설정은6이지만 A2 추출 job peak는1이었다. 실제6시즌/10브랜드 부하에서의 최고 동시성·대기는 아직 검사하지 않았다. A2026SS 저장 HTTP8.753s, A2025FW28.714s, B2025SS13.147s다. 변환 누적은각7.394/26.435/11.561s, 업로드누적6.161/2.424/2.814s이며 병렬 작업의 합계라 전체벽시각에 더하지 않는다.

## 실패 이력과 수정

1. candidate022 첫모듈 지연: samplegap922ms→Ready 전에 Playwright JS 준비. local Linux 실제 index/supervisor maxgap103.647ms, browser0. actual Cloud 성공은 이번 정상runs의394.535ms로 확인했다.922ms의 단일 원인 확정은 아니다.
2. candidate023 복구: 이미succeeded item을 다시begin하여 NOTQUEUED. terminal item 재실행을 막고 release transaction의 실제execution/continuation 종료검사를 유지했다. 불일치 차단 Emulator2건 통과.
3. 복구 해제 후 준비: 같은preparationSequence라5분점검을 기다렸다. recoveryRequired 해제 이벤트도 같은prepareNextQueueBatch를 호출하도록 변경, 중복1회 준비 Emulator 통과. Development handler1개 갱신/ACTIVE readback.
4. 짧은active 관측 실패: 사용자 승인으로 기능 저장과 대기 검증을 분리. 중단원본은 overlap-observer-stop에 유지했다.
5. 최종cover 집계: 별도coverThumbPath를 요구한 검증 도구 오류. 현재공개원장의 실제thumb/detail경로·generation으로 확인하도록 수정했다. 이미완료된7요청은 `--verify-only=true`로 읽기전용 재검사했다.

## 필수 검사와 원본

- 배포 Worker snapshot: gate `1791300288876-5012c6a9-e515-4f94-bb0e-087c9dd6bf66` passed359/lint/fixture/deploy, digest `69f5fb7455ee93224ec3f629b3c78bf8fc74461e5122ab9bb8a046537731355b`/255files. image `sha256:5559dffde8569818cba9ddc6907056e75323265cdcd33ae414c566514affa4ec`, Q7tag0%/base00012-fih100%,1CPU/2GiB/concurrency2/900s/revisionmax1.
- Functions gate `1791300998982-1da417ca-ba0f-4e74-907a-f967302e64f9` passed321/lint/build, digest f713621f…c450/274files. 제품큐 `1791301003465-cdbacef3-0013-4b35-89b4-1da2adf3afed` passed75/build, digest7cf1b44f…acd4/292files.
- 최종client gate `1791302208309-5377eb9c-99f6-458d-a650-352c1b84f956` passed26, digest `7ff34fab416baaaa4555207da533b498de26feebf7ccb9eda957a80a168e5ad1`/27files. 이전Worker snapshot을 변경된client 소스 전체의 통과로 재사용하지 않는다.
- 원본: `output/lookbook-import-performance/product-queue-q7/92ad4778-f90e-408a-b062-8afc46383952/{report,manifest,92ad4778-f90e-408a-b062-8afc46383952}.json`, `evidence/{batches,reviews,resume-original,overlap-observer-stop,finalization-stop-*}`, `evidence/{storage-count-readback,post-publication-reference-check,extracted-source-fixture-check,preparation-function-readback}.json`, `metrics/worker-measurements.json`.

## 다음

A~J는 아직미실행. 승인된 생성10/import10의100ms wave를 실제로 응답대기 없이 보내도록 도구를 보완하고, journal/manifest 동시기록과 실패시 시작한요청정리를 local gate로 확인한 뒤에만36접수/16시즌 검증을 시작한다. 설정/입력/회차/비용상한은 유지한다. 장시간 경계·고의장애·관리자웹 UI는 이 정상smoke의 완료로 대신하지 않는다.
