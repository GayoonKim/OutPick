# Q7 종료 정산·처음부터 재시도 — 로컬 구현·검증 결과

## K/L 장애 장치·실행기 추가 뒤 현행 필수 검사(2026-10-07)

사용자 K/L새2브랜드·최대8접수 추천 확정 뒤 Development-only exact campaign/batch/job/execution 장애 장치, 실제 종료 메시지 검사,8접수 runner,run 정리 뒤90일 종료 감사 기반 generation 확인을 추가했다. 아래 표가 현재 코드의 결과다. 아래쪽 R1 결과는 이전 코드 이력이다.

|게이트|실제 결과|실행 ID|소스 digest|
|---|---|---|---|
|Worker|361개·lint·fixture·배포계약 passed|1791344828979-e0eac4f5-3f35-42cb-93eb-18ee7d33049e|d08b1647e3ef3be4c00e90c27a8b0d5dc1d5db06c2ef3976f983a9ee8c45b315|
|Functions|324개·lint/build passed|1791345011555-ef617a5a-1bce-46bd-8a4c-33f1009d18e3|87dabe7977ab5190c37eeba65b4a2204ef701336a63b87b543eb158c82db5a54|
|제품큐|build2·Emulator96개 passed|1791345105807-115877a7-ee8a-4e95-9ce6-ece074fc5ee7|4f3cd46c4d92f5cd9c552f9dbd1f623223478e05f7fad5484b31d2f1c847a39b|
|Firestore·Storage|131개 passed|1791345369994-ebdfcfa2-dcbe-40bf-a000-a0c035a18ed8|e068fb5f5d46f246efa8013b45dcf45818e8e0b623ef9c73c84ecb157f6bf55c|
|Q7 verifier|33개 passed|1791344636553-57303d14-4402-4999-9650-6b1b0e4adb01|dfb022f8f65cf2b8673959a5fa68153cfe7da260fd57706c78b49e2f55000261|
|Linux|실제 forceQ7OOM·자원검사2개 passed|1791345015179-cd7c1317-1e9e-4268-8b94-fb383e6e5798|5f9c06717af0d2841b8b9329b2242392b193d0bb4d3218e923a9c152ac77d6ce|

누락/skip/0개 없음. KR15~19/QV09~10 연결과 원본 node-result/stdout/stderr/summary를 보존한다. `1791344404805-9c388622-93e1-476a-90f0-ffdd7cae5b6d`는 실행중 input 변경으로 blocked, `1791344892350-7c484892-5439-45ed-af74-0775ebac702a`는 Firestore typed projectId 빌드 오류로0개/blocked다. 플랫폼 GCLOUD_PROJECT/GOOGLE_CLOUD_PROJECT로 정확 project 증거를 검증하도록 수정하고 소스고정 뒤 재검사했다. 실패를 삭제하거나 기준을 축소하지 않았다.

배포 campaign은 `845dae34-7aac-4108-a613-3944bcf44d6b`. 현재 snapshot/4callable/인덱스2 배포 진행 중이며 실제 K/L 결과는 아직 미검증이다. Development cleanup scheduler2개 미배포 사실을 확인해 이번 실험은 정리예약/보호와24시간 물리삭제 미검증을 구분한다.

2026-10-07. 사용자 D1/D2 추천 확정·구현 승인 뒤 R1/R2 서버 구현과 R3 필수 로컬 검사를 수행했다. 새 계약의 실제 Development 종료/전송·수동 재시도는 아직 미검증이고 Q7 전체 완료·최종 커밋 전이다.

## 구현한 계약

- 실패 목록3개 callable: platformAdmins 인가, 동일 URL별 문서1개, version+executionID CAS, 요청 영수증 멱등, 맨뒤 수동 새 execution/새5회, 안 함은 목록만 제거, 늦은 실패 부활 방지·원본 이력 보호.
- Worker 실패 checkpoint: 재실패 최신화·성공 제거, 최초 포함 총5회·승인 저장 실패도 같은 예산, 소진 후 실패 목록과 다른 시즌/FIFO 진행. 새 추출은 후보·승인·부분 season/posts/assetFailures를 이번 job 소유·활동 없는 범위만 정리한다. 준비된 시도는 restartPreparedAttempt로 중복 정리하지 않는다.
- 종료 정산: task 재전달에서 정확한 head/epoch/run/revision/trace/instance 종료 증거를 확인한다. 이전 root·season·post·실패 쓰기는 같은 transaction 실행권으로 차단한다. 완료/미시작 item와 기존 시도 수 유지, 중간 복원 제외. 시즌 import의 기존 resume는 차단하고 별도 보수 경로는 유지한다.
- 미확정 쓰기: 이전 run 종료 증거·고유 경로·현재 참조를 확인하고 metadata generation을 읽는다. 정리 후24시간 지연 원장을 남기며 누락 generation은 지연 정리 시점에 다시 읽어 정확한 세대만 삭제한다. 종료 미확인·사용자 활동·상한 초과는 차단한다.
- 정상12/14/15 시간·메모리/표본 안전 기준·동시성·128MiB·자원/IAM은 유지한다. 메모리/표본 감독 중단은 플랫폼 비정상 종료 자동 정산과 구분해 복구 확인을 유지한다. 새 iOS/관리자 웹 UI는 추가하지 않았다.

## 현행 소스 필수 검사

HEAD `1d67d61faa04984783083971688a7c628df74748` 위 미커밋 변경을 검증했다. 아래 각 gate의 summary.json/source digest·명령 stdout/stderr·node-result.jsonl을 원본으로 보존한다. 문서 변경과 제품 코드 변경을 구분하며 이후 제품 코드가 바뀌면 이 통과를 재사용하지 않는다.

| 게이트 | 결과 | 실행 ID | 소스 digest |
|---|---|---|---|
| G-E 제품 큐 |build2 + Emulator93개 통과 |1791343299106-f53558d8-4c34-4521-9104-f97d9d37b6f8 |ad062a4b35b3894e36cc14d1725cb0281761e792c22fe1d7195f02035a0cec89 |
| G-F Functions |lint/build·324개 통과 |1791343381053-0048969a-1d8e-43ed-8af6-385c2748d76e |a3ba7544f4621fe8e2738cb4f809c0a7ed42ec9a916ebc1c04c598ec9c89e5a2 |
| G-W Worker |lint/build·359개·fixture/deploy 계약 통과 |1791343383478-07eb0f4c-5967-4ab7-b534-011468949020 |1ae65cdf5941064ddec6dade0c4d1805d3a1a74f5c24e2db3a5730ef846e6528 |
| G-R Firestore·Storage |131개 통과 |1791343423341-a7bdba32-53d2-4403-8b94-7ccda3432d8b |691264f5fb38a4517ad84d9c895bbfed55e3e9a936c696bf67dae9f698bb2d0e |
| Q7 verifier |31개 기존 실행기 회귀 통과 |1791343381053-3f9deaef-5f0f-43ad-88c1-6376d9b2140d |860d96cd5e031252a0fbd6d94938ee7939b3e1c52bef5f724154242a281d2527 |
| G-L Linux |실제 Docker Chromium/1CPU·2GiB·표본/자원 감독, 제한 container 실제 OOM2개 통과 |1791343574268-bf27686e-b897-4865-b920-abd70b7a0cde |f518445dca55a374624b7f608a9c3faf627f89be6a022b0b8ff7d4901cd90027 |

원본 경로: `output/verification/{실행ID}/summary.json`. 필수 누락/skip/0개는 없다. lint는 기존 warnings가 남고 errors0이다. Q7 verifier31개는 기존 실행기 회귀이며 새 고의 종료 장치·새 원격 실행기의 검사로 표시하지 않는다. Linux 실제 OOM은 Cloud Run 시스템 로그/실제 task 재전달 검증이 아니다.

## 실패·이전 검사 이력

- `1791343211869-8eceb2bc-ac8d-4364-9ab8-1a67e3575127`:93개 중 기존 보수 resume1건 실패. import의 중간 재개 금지에 맞춰 보수용 fixture로 구분했으나 기존 scan이 importSeasons만 읽어 보수의 미확정 쓰기를 놓쳤다. 이미지 처리 kind의 원장을 조사하도록 수정 후 G-E93 통과. 실패 원본 보존·기준/테스트 수 축소 없음.
- `1791343522316-46b9bf7d-74af-4c38-8fe0-c6e975eec043`: Docker 엔진 미실행으로 before hook 실패2건. 엔진 시작 후 같은 G-L2 검사 통과. 미준비 실행을 통과로 변경하지 않는다.
- 초기 Worker sandbox 브라우저/HTTP 권한 실패와 lint indent/curly 실패, 이전 중간 단계 통과는 각 gate와 /tmp 로그에 보존했다. 현행 소스의 성공 ID는 위 표다.

## 변경 진입점·남은 작업

Functions `lookbook/import/queue/{failure-service,failure-functions,record-retention,asset-retention}.ts`, shared queue projection/index export·contract tests·expiry indexes; Worker `queue/{failure-record,restart,job-write,termination-retry,checkpoint,batch-runner,asset-publication,recovery}.ts` 및 processor/server; Emulator KR01~14와 verification required IDs. DATA_SCHEMA/ENTRYPOINTS 및 FIREBASE/LOOKBOOK/DATA/TESTS에 데이터/API/검사 위치를 반영했다.

다음은 [짧은 Development 실행안](q7-retry-development-execution-plan.md)의 고의 종료 방법과8회 규모를 확정한 뒤 최소 장치/실행기·필수 검사→Development 배포/readback→실제 검증이다. 새 플랫폼 로그·Storage 전송·부분 데이터 원격 정리는 아직 실행하지 않았다. 실제24시간 파일 삭제·12/14/15 장시간 경계·관리자 웹 화면은 별도 미검증이다.

최종 커밋은 전체 Q7 완료 뒤만 한다. task 문서 ignore 포함 범위와 작업 외 dirty files를 점검하고 서버/앱/테스트/문서 작업 단위로 나눈다. HANDOFF/.codex/로컬 설정은 기본 제외한다.
