# A~J Development version5 연결 검증

2026-10-05. [승인한 실행안](ten-brand-execution-proposal.md)의 원격 연결 구현과 로컬 필수 검증을 완료했다. Mac/Linux 각각316개·필수208개, emulator5개, 이미지 대조 모두 통과했다. 이번에는 클라우드 배포·유료 실험·제품 분산 큐 구현을 실행하지 않았다.

## 구현과 검사 진입점

- `remote-contract.ts`: version5, smoke/S6/Sall/P6/Pall/D8/T2/U8 고정8회, 시즌6/null과4/1/4·8/1/4·4/2/4·4/1/8. 입력 매핑·100ms 간격·시즌/단계 정책을 plan digest에 포함한다. version4 및 임의 회차는 거부한다.
- `remote-input.ts`: 원본6시즌을3번씩 배정하는18개 가상 시즌. 각 시즌 입력·golden·커버를 복사해 ID를 분리한다. source URL·이미지 해시·golden JPEG는 유지한다. 동일 URL도 다른 실행 scope의 원본 Buffer를 공유하지 않는다.
- `remote-runner.ts`→`arrival-runner.ts`: 메타데이터 준비 후 A0~J900ms 접수. 접수 전 후보 다운로드를 시작하지 않는다. 예약/실제 접수/시즌 사건을 기록하고 취소 시 타이머와 작업을 정리한다. 이미지 재시도와 접수 타이머를 분리한다.
- `submission-runtime.ts`: 고정 우선순위 변환 큐의 초기 한도를1뿐 아니라 승인된2로 설정할 수 있다. 동적 변경은 기존처럼 명시적 가변 모드에서만 가능하다. TB08이 실제 슬롯과 고정 모드 변경 거부를 검사한다.
- `remote-arrivals.ts`/`remote-report.ts`: 도착 전 시작·시즌 상한·정책/슬롯 불일치·입력/출력 변조를 거부한다. 브랜드별 예약/접수/시작/정리, 접수 후 대기/완료 시간을 독립 재계산한다. SP/PP만으로 묶지 않고7개 variant를 분리하며 S6를 기준으로 비교한다. 각1관측이므로 채택/반복 악화/실패율 개선은 미판정이다.
- `remote-campaign.ts`, `remote-campaign-cli.ts`, `remote-fixture.ts`: version5 실행/집계와18시즌 비용 산술을 연결한다. 실패·종료 미확인·비용/시간 중단 후 다음 회차를 자동 요청하지 않는다.

실제 타이머 집중 검사에서 소수점 예약 시각보다 조금 일찍 깨어나는 경우를 발견했다. 남은 시간을 올림해 다시 기다리도록 수정했고 TB09로 회귀 검증한다. 이전 A~J 로컬313개 결과는 변경 전 기록이며 새 코드의 통과로 재사용하지 않는다.

## 필수 검사

`verification/lookbook-import.json`: 전체316개·필수208개. 신규 TB07(18시즌 매핑/복사 격리), TB08(고정 증량 공용 슬롯), TB09(타이머 조기 기상)를 추가했다. RN01/03·RC01은8회 계약으로 갱신했고 RN04는 입력/정책/도착/대기 지표 위조, RC05는18시즌의54개 원본 GET·72개 독립 JPEG 저장을 tiny fixture에서 검사한다. 이 수치는 실제 UNAFFECTED 이미지 수가 아니다.

`verification/lookbook-remote.json`: 실제 로컬 Firestore/Storage emulator5개. RD05를8회 고정 순서·구버전/초과 요청 거부로 변경했다. 보안 규칙을 수정하지 않고 실험 문서/객체의 클라이언트 직접 접근 차단을 유지한다.

Linux 게이트와 이미지 대조 실행기: `output/lookbook-import-performance/ten-brand-remote-v5/`. 기존 실행기 재사용이며 테스트 이미지·runtime 이미지·호스트 컴파일 결과·Node/Sharp/libvips/mozjpeg·원격 golden 해시를 대조한다. Linux 전체 검사 조건은 AMD64/1CPU/2GiB/추가 swap 없음/network none이다.

검사 기준 HEAD는 `1d67d61faa04984783083971688a7c628df74748`+작업 트리다. summary와 같은 폴더에 stdout/stderr/개별 테스트 JSONL을 보존한다.

- Mac [passed](../../../../output/verification/1791173155162-b14d4c4d-95c3-4c54-b469-c04214faef07/summary.json): 전체316개·필수208개, 실패/차단/취소/skip0, lint0오류/기존70경고, build·추출 fixture 통과. source digest `5eed8079e2b60cacbe0ea871e90623c2abac393f0e6856b9483eec7ea778be01`(199파일).
- Emulator [passed](../../../../output/verification/1791173317158-fc205dcf-7e63-4197-a189-111e185e1c75/summary.json): RD01~05 모두 통과, source digest `8a71c65018e11973907ef319dd7510cbfcccf420be78411f46643f7a2d246757`(203파일). 로컬 demo 프로젝트만 실행했다.
- 이미지 대조 [passed](../../../../output/verification/1791173374323-a62834c1-ba47-4c57-a5c6-790747d6ebe1/summary.json): 호스트/테스트/runtime 컴파일 결과·고정8회 계획·AMD64 인코더·runtime 원격 golden 확인. [대조 원본](../../../../output/lookbook-import-performance/ten-brand-remote-v5/image-binding.json), [소스 대조](../../../../output/lookbook-import-performance/ten-brand-remote-v5/image-source-evidence.json).
- Linux [passed](../../../../output/verification/1791173196101-3f58329e-024b-4bcc-90d1-be4ccf4c8e72/summary.json): 전체316개·필수208개, 실패/차단/취소/skip0, lint0오류/기존70경고, build·추출 fixture 통과. source digest `3fb9fb88590fb1f29e15dc7631d08cbd78148ec6c127fdc05feffd8c0be608c4`(202파일)는 Mac 입력에 Linux 실행기/게이트/이미지 ID3개가 추가된 범위다.

테스트 이미지 `sha256:eed2418314eb9e84f5d7d38455d09c849d4bdded3c955abccffd39a12a9fe799`, 실행 이미지 `sha256:dfc4f4793b49e0081db1ed22b271446d78eaec3dda212d50ca151cb3472eb723`. 소스/설정 대조와 컴파일 결과296개 대조 모두 통과했다. 이미지 registry push와 Cloud Run 배포는 미실행이다.

준비 검사에서 구계약 테스트 참조의 TypeScript 오류, 새 파일 lint 형식 오류, 조기 타이머 기상 및 기존 변환1 고정 제약을 발견해 수정했다. 신규 입력에서 원본 변동 시 첫 브랜드의 실행 가능 시즌이2개에서6개로 바뀌므로 RC13의 후보 GET 상한은6×2로 변경했고, 다른 브랜드 미시작/정리 검사는 유지했다. 최종 게이트는 이 변경을 모두 포함한 코드로 실행했다.

고정 plan digest는 `9cca98384c439d242a1af55f7ac6d54c2f557cbf7a48dcc41227838ba79aad16`이다. [회차별 입력·정책·요청량 산술](../../../../output/lookbook-import-performance/ten-brand-remote-v5/request-estimate.json)을 보존했다. 실제 네트워크 실행 결과가 아니다.

## 실행 규모와 남은 경계

고정8회 원본 산술은 JPEG5,816개/889,805,586B로 기존 제안과 일치한다. 후보 해시 읽기와 저장 단계 모두 재다운로드하는 산술은5,710GET이며, 재사용 모두 hit·재시도 없음 가정의2,929GET과 다르다. 실제 캐시 miss/재시도는 계측값으로 보고한다. 원본 변동·메모리 중단·실패 발생 시 보충 회차는 자동 실행하지 않는다.

다음은 검증 완료 이미지에 대해 배포 시점의 Development 자원/기본 트래픽·입력·요청량·비용·실행 manifest를 대조하고 승인된8회를 수행하는 단계다. 이미지가 로컬에서 검증됐다는 사실을 실제 네트워크 성능이나 무료 실행 보장으로 해석하지 않는다.
