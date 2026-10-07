# 실행 내 원본 재사용과 실제 저장 함수 회귀

2026-10-03. 사용자 ‘진행해도 문제 없으면 진행’에 따라 승인된 같은 실행의 Buffer 재사용을 구현하고 저장/재시도 검증을 보강했다. 영구 캐시·관리자 검토 우회·기본 정책 변경·배포는 포함하지 않는다.

## 변경과 연결

`tools/lookbook-import-worker/src/pipeline/source-buffer-store.ts`의 `SourceBufferStore`는 인스턴스 공용 보관 예산을 관리한다. `PipelineRuntime` 생성 시 `sourceBufferBudgetBytes`를 명시하면 생성하며, 미설정은 off, 0은 모든 보관 거절, null은 유한 실행 자료 전체 보관이다. 128/256/512MiB를 같은 API로 비교할 수 있고 이번 연결 회귀는 합의한 초기 후보 256MiB를 사용했다. 제품 기본 활성화나 최적값 선택은 아니다.

`processor.ts`의 `processJob`은 매 실제 호출에 독립 scope를 생성하고 finally에서 닫는다. `/wake`가 여러 job을 처리해도 각 scope는 별도이며 예산만 공용이다. claim 거절·성공·검토 대기·실패·예외 모두 같은 종료 경로를 사용한다. 새 HTTP 실행/수동 재시도/검토 승인 후 재개는 이전 scope를 복구하지 않는다.

`extraction/dedupe.ts`는 해시 계산에 성공한 바이트만 `onHashedBytes`로 전달한다. processor가 canonical URL과 실제 sourcePageURL 요청 맥락을 키로 보관한다. 현재 이미지 GET의 가변 요청 맥락은 Referer용 sourcePageURL이며, HTTP 보안/DNS/redirect 검증은 기존 함수가 담당한다. 이후 중복 제거에서 제외된 URL은 `retainOnly`로 정리한다. 다른 요청 맥락이나 다른 job 사이에서 이미지를 공유하지 않는다.

저장 시 `usingSourceBytes`가 같은 키를 대여하고, miss면 기존 `withImmediateRetry`→공용 다운로드 슬롯→`fetchRemoteImageBytes`로 읽는다. 보관 용량이 부족해도 슬롯/예산 대기를 만들지 않는다. 실패 응답과 저장 단계의 miss 결과를 새 원본 캐시로 게시하지 않는다. 이미 해시한 키의 값을 늦게 받은 다른 바이트로 덮어쓰지 않는다.

Buffer는 복사하지 않고 읽기 전용 사용 계약으로 대여한다. 이것은 JavaScript Buffer 자체의 변조를 런타임으로 막는 보안 장치가 아니다. 제품의 소비자는 실제 sharp 변환이며 원본을 수정하지 않는지를 고정 자료 검사로 대조한다. 두 출력 변환·복수 대상이 같은 원본을 써도 대여 참조를 각각 관리한다.

scope를 닫거나 중복을 제거하면 새 대여/보관은 막되, 진행 중 소비자의 마지막 반환까지 예산에 계속 포함한다. 반환은 멱등이고 반납한 lease를 다시 읽으면 오류다. 원본 보관 예산은 payload 길이 합이며, Buffer allocator 여유·디코딩·출력·대기 JPEG·Chromium·전체 RSS 한도가 아니다. 마지막 소비 직후 보관 항목을 축출하는 정책은 추가하지 않았으며 필요한 원본은 job 종료까지 보관한다.

재사용은 형제 작업 종료를 기다리는 `PipelineRuntime` 경로에서만 허용한다. 기본 A의 선행 Promise 실패 반환 경로에 단독으로 끼워 넣으면 바이트 반환 시점과 실제 사용 종료가 어긋날 수 있으므로 `runSyncTargets`가 이 조합을 거절한다. 재사용 off/on 비교는 같은 실험 runtime 설정에서 수행해야 한다. 서버 index/환경변수/HTTP 요청으로 이 runtime을 활성화하는 새 경로는 만들지 않았다.

## 테스트와 실제 호출 범위

- `src/pipeline/source-buffer-store.test.ts`: 인스턴스 합산 예산·정확한 경계·즉시 miss, 실행/요청 맥락 격리, 다중 소비자·종료 후 예산 유지, 검토/실패/취소 정리, 중복 pruning, 늦은 실제 해시 다운로드 게시 거절, 원본 변경, off/all/예산 입력 검사.
- `src/pipeline/processor-storage.test.ts`: 제품 `runSyncTargets`→`syncSingleTarget`→실제 JPEG 인코더/업로드 함수/경로 저장 함수를 호출한다. Firestore와 Storage는 제어 가능한 fake다. cover/post 저장 경로, 기존 media 속성 유지, 두 업로드 전 ready 금지, 한 파일 실패 후 형제 종료, 이미 완료된 대상 제외, DB 실패 후 재시도와 슬롯 반환을 확인한다.
- `runSyncTargets`의 모듈 export는 로컬 검증용 진입점이며 HTTP API 추가가 아니다. Firebase 문서 필드/Storage 경로는 변경하지 않았다.

검증 완료 범위는 위 실제 함수+fake 통합이다. 실제 Firestore emulator/클라우드 transaction, Cloud Tasks 전달, 완전한 job lifecycle 통합과 관리자 화면은 아직 미검증이다. 최초 포함 총 5회의 job 시도 계약은 Phase 4이며 이 저장 함수 재시도 검사가 대신하지 않는다.

## 필수 게이트

Node 24.19.0에서 `node tools/verification-gate/gate.mjs --project . --config verification/lookbook-import.json` 실행. `output/verification/1791002010312-5a7618bc-59a3-4da4-965b-a82a30b1a593/summary.json`: **passed**.

lint·build·전체 Node 테스트 **166개**, 필수 ID **58개**, 추출 fixture corpus 통과. 기존 152개에 재사용 10개와 실제 저장 함수 회귀 4개를 추가했다. HEAD `1d67d61faa04984783083971688a7c628df74748` + 작업 트리, source digest `d5d3d350ace885d40a17498958813f884a78dd170e22520da7c5d7e0a8b3cbea`, 117파일. 이 게이트 이후 코드/검사 설정은 변경하지 않았다.

## 다음 범위

고정 입력의 로컬 연결 회귀도 완료했다. 원본은 `output/lookbook-import-performance/unaffected-2026-10-03/reuse-validation-6bc00247-cb93-42a4-b730-3f5cb90c6569/{plan.json,result.json}`, 실행기는 `verify-source-reuse.mjs`다. 코드는 위 게이트와 같으며 plan에 실행기 digest/설정을 따로 기록했다. 각 조건에서 6개 시즌을 순차 검사한 12개 결과가 모두 정상·정합성 검사를 통과했다.

| 로컬 자료 읽기/출력 | 재사용 off | 같은 실행 재사용 256MiB |
| --- | ---: | ---: |
| 원본 읽기 횟수 | 269 | 138 |
| 원본 읽기 bytes | 223800086 | 112771684 |
| JPEG 파일 수 | 274 | 274 |
| JPEG bytes | 42259800 | 42259800 |
| 경로 spy 호출 | 137 | 137 |

모든 JPEG가 앞서 고정한 SHA-256과 일치했고 sharp 사용 전후 원본 SHA-256도 일치했다. 재사용 hit 131, 커버 miss 6, 예산 거절 0이다. 이 순차 검사에서 최대 보관량은 51079588 bytes(약 48.713MiB)였으며 매 실행 종료 후 retainedBytes/openScopes는 모두 0이다. 서로 다른 예산의 최적성이나 여러 시즌 병렬 실행의 최대 메모리를 측정한 것은 아니다.

이 검사는 로컬 파일·메모리 Storage/경로 spy를 사용하는 통제된 연결 검사다. 외부 GET/실제 업로드 횟수가 아니며 처리 시간 개선을 판정하지 않았다. 실제 UNAFFECTED의 `needsReview` 분기를 우회하지 않았다. 실제 추출→검토 종료→승인 후 저장은 scope가 달라 이 절감을 얻지 못한다는 기존 합의를 유지한다.

시즌 비교 실행기, 중간 바이트 관측/해제, 메모리 85%/1초 감독 및 누락 표본 처리, 실험 manifest·초기 조합과 A~F 연결을 준비한다. 현재 6개 시즌 자료만으로는 128/256/512MiB의 성능 차이를 충분히 구분할 수 없어 예산 초과는 작은 fake 자료의 필수 테스트로 검증했다. 추가 재사용 성능 대조 회차는 실행 전에 제시한다. 54회 구조 비교, 클라우드 실행/배포, 최종 채택은 아직 하지 않았다.
