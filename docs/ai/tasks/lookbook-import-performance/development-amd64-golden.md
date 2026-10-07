# AMD64 전용 golden 생성·검증

2026-10-04. 사용자가 AMD64 기준을 별도로 생성·검증하는 추천안을 승인했다. [이전 실패와 결정 근거](development-amd64-readiness.md)를 보존한다. 배포·유료 실험은 승인 범위가 아니다.

**완료:** 별도 AMD64 기준 생성·두 컨테이너 재현·원격 계약 연결·최종 runtime274개 exact 검사·Mac/AMD64 각각307개 및 emulator5개 필수 검사를 통과했다. 이전 ARM 기준152개 불일치 기록은 그대로 보존하며, 실제 Cloud Run smoke는 아직 실행하지 않았다.

## 구현 범위와 완료 기준

1. 기존 ARM fixture의 SHA `307bdf7d1b90c04fbcc8ed16307aa7e2ed559cc008207eed8fd487cece676a10`와 원본138개를 그대로 유지한다.
2. 검증된 AMD64 runtime 이미지의 실제 `jpegBytes`로274개를 순차 생성한다. JPEG 전수 디코딩, 기존 치수·회전 후 크기·orientation 제거, 원본/정책/개수 불변을 확인한다. 새 컨테이너에서 같은 작업을 다시 실행해 모든 출력 SHA/bytes를 비교한다. 두 실행 모두 network none이며 성능 표본으로 사용하지 않는다.
3. 새 `performance-remote-input-amd64.json`만 추가한다. 원격 로더의 corpus digest·파일·golden profile, 실행 환경 검사, 결과 profile 검증, Docker 복사 경로를 연결한다. 캠페인 version2와 실행 순서는 유지하되 이전 corpus digest는 거부한다.
4. `remote-golden-profile.ts`, `remote-contract.ts`, `remote-runner.ts`, `remote-report.ts`, `index.ts`, Dockerfile, 관련 테스트/게이트/진입점 문서만 변경한다. 제품 변환 함수·크기/품질·SIMD·동시성은 변경하지 않는다.
5. 신규 회귀 검사는 ARM 원본·정책 보존, ARM digest/잘못된 플랫폼·인코더/변조 profile 거부, EXIF 방향 처리다. 필수 Mac/AMD64 Worker 게이트와 emulator를 실행한다. 최종 runtime 이미지에도 같은 golden 검사를 적용한다.

방향 검사는 원본 EXIF에 따른 출력 치수와 orientation 메타데이터 제거를 전수 확인하고, 색상 위치가 알려진 합성 이미지의 방향1~8 변환으로 회전/반전을 별도 검사한다. 실제 모든 사진의 미적 품질이나 육안 방향 검토를 프로그램 검사로 대체했다고 기록하지 않는다. Cloud Run CPU에서의 exact hash 일치는 후속 smoke에 남는다.

## 결과

### 기준값 생성과 보존

두 개의 새 linux/amd64 컨테이너에서 각각 원본138개 SHA/bytes와 JPEG274개 전수 디코딩·치수·orientation 제거를 확인했다. 생성된 두 JSON 파일 전체 bytes가 같으며 새 fixture도 그 파일과 정확히 일치한다. 변환 대상137개의 원본 orientation은 모두1/미지정이었다. 회전/반전은 별도 합성 EXIF1~8 검사 RN15로 확인한다.

- 새 파일: `tools/lookbook-import-worker/fixtures/performance-remote-input-amd64.json`
- 새 SHA: `49671fbcd756f733e034bc079cc6911fa6ef18184e9e6206f3c1d0d475fa8f15`
- 기존 ARM 파일 SHA: `307bdf7d1b90c04fbcc8ed16307aa7e2ed559cc008207eed8fd487cece676a10` 그대로
- profile: `linux-amd64-sharp0345-vips8173-mozjpeg0826579`
- 생성기 SHA: `896f40dd7150437139ecc4074a71971dd9632605f0fc742749830fdba8e19fc2`
- 생성에 사용한 고정 runtime: `sha256:1524ebb2ad5750673280be4bb832737e432603581e56300781e7dd8ad02d1d3d`. 변환 함수는 이후에도 변경하지 않았다.
- 정책·입력·중복·출력 순서는 그대로다. golden의152개 출력 SHA와 해당 bytes·시즌 업로드 합계만 AMD64 값으로 분리했다. 생성 환경 metadata를 추가했으며 RN13이 나머지 필드 전부가 기존 파일과 같은지 대조한다.

[두 실행과 fixture 대조](../../../../output/lookbook-import-performance/amd64-golden/repeat-verification.json), [첫 실행](../../../../output/lookbook-import-performance/amd64-golden/verified-first/generation.json), [새 컨테이너 재실행](../../../../output/lookbook-import-performance/amd64-golden/verified-repeat/generation.json)에 원본을 보존한다. 이 실행들은 로컬 호환성 검사로, 실제 네트워크21회나 성능 표본이 아니다.

최초 준비 스크립트는 `Math.round(원본 크기×비율)`을 sharp의 정확한 크기로 가정해615px 출력을614px로 잘못 예상했다. [실패 로그](../../../../output/lookbook-import-performance/amd64-golden/first/run.log)를 보존한다. 그 계산을 제거하고 **기존 검증된 ARM golden 치수와 정확히 같음 + 최대 크기 준수 + 회전 후 원본보다 확대하지 않음**으로 확인했다. 실제 변환 함수나 기존 golden 치수를 수정하지 않았고, 그 이후의 독립 두 실행이 위 결과다.

### 원격 연결과 검사

`remote-contract.ts`는 새 파일의 SHA와 profile을 확인한다. 이전 ARM corpus digest로 된 캠페인은 거부한다. 캠페인 version2·plan digest·21회 순서는 유지하며, 기준 파일 변경은 corpus digest로 구분한다. `remote-golden-profile.ts`는 플랫폼/linux·arch/x64·sharp/libvips/mozjpeg 버전을 고정한다. `index.ts`가 실험 프로세스의 실행 환경을 Firebase 초기화 전에 확인하고, `remote-runner.ts`가 실제 인코더 버전과 profile을 결과에 남기며, `remote-report.ts`가 성공 결과의 환경을 재검사한다. Mac CLI에서 기준 파일을 읽고 계획을 작성하는 것은 허용하되 실제 실험 Worker 시작과 구분한다.

RN13~15를 Worker 필수 게이트에 추가했고 RN04에는 잘못된 profile/인코더 결과 거부를 추가했다. 새 코드 검증에 이전304개 결과를 재사용하지 않는다.

### 최종 이미지와 게이트

HEAD `1d67d61faa04984783083971688a7c628df74748`와 작업 트리 기준이다. 서로 다른 게이트 입력 범위 때문에 아래 source digest는 서로 다르다. 검사별 stdout/stderr와 Node 원본 결과는 각 summary 옆에 보존한다.

| 검사 | 실제 결과 | source digest / 원본 |
| --- | --- | --- |
| Mac Worker | passed. lint 오류0/경고58, 전체307개·필수199개·fixture 통과 | `6382733298f751c97c4dc4abf981fda4140ca40a1e5ce212b2aca92796f38b9e`,193파일 / [summary](../../../../output/verification/1791112735515-6bd383ac-84db-4f72-a87b-bcf8fd1266a1/summary.json) |
| Linux/amd64 Worker | passed. lint 오류0/경고58, 전체307개·필수199개·fixture 통과 | `6ed72a0671f5b355934e3f0f80ed2eaaabcdfc8050acb5bb401060475d4c7716`,196파일 / [summary](../../../../output/verification/1791112786671-adc240cf-03cb-41ef-806e-49d552cb01d9/summary.json) |
| 로컬 emulator | passed. build·RD01~05 총5개 | `11e0b29be160fb4d0a30d7b1e02d90b2085f99d037ec4366e91fde1726aa83b9`,197파일 / [summary](../../../../output/verification/1791112926347-90e89c9d-2dda-462f-b9f4-b18638ea3f6f/summary.json) |
| 최종 runtime 실제274개 golden | passed. 원본138개·JPEG274개·profile·전체 fixture bytes exact 일치 | `d9fa07680cb2318cc3e2cf6dc3fadbede7895c5185be20f16b3f4e56de926612`,195파일 / [summary](../../../../output/verification/1791112788155-16b7e888-d7a2-4b8d-ab33-c92db4013146/summary.json) |

최종 runtime 이미지 `sha256:2c331c525d116c67970e9b3e196ffdb50006d9b7ead102af2c2f0dccac86924d`, 검증 이미지 `sha256:9a0647bae7dc3b2db49e30d13eb60d3d6160e5d9a3aef70be7ecd6b12433f32e`. Node24.21.0/sharp0.34.5/libvips8.17.3/mozjpeg0826579,linux/x64다. [284개 파일 대조](../../../../output/lookbook-import-performance/amd64-golden/image-binding.json)에서 두 이미지와 호스트의 compiled/package SHA 일치를 확인했다. runtime golden [원본 보고](../../../../output/lookbook-import-performance/amd64-golden/runtime-verification-4afed718-a393-474e-8694-b282add4acb0/runtime-verification.json)를 보존한다.

재실행 명령은 프로젝트 루트에서 Node24 PATH를 사용한다. Docker 권한이 필요하며 각 명령은 성능 측정이 아니다.

```sh
node tools/verification-gate/gate.mjs --project . --config verification/lookbook-import.json
node tools/verification-gate/gate.mjs --project . --config output/lookbook-import-performance/amd64-golden/gate.json
node tools/verification-gate/gate.mjs --project . --config verification/lookbook-remote.json
node tools/verification-gate/gate.mjs --project . --config output/lookbook-import-performance/amd64-golden/golden-gate.json
```

### 요청량 갱신

[독립 산술 결과](../../../../output/lookbook-import-performance/amd64-golden/request-volume.json): 6시즌 JPEG42,259,618bytes, 2026SS smoke2,353,608bytes, 본20+smoke1 합계847,545,968bytes/5,542객체다. 기존 ARM 계산보다3,633bytes 줄었으며 속도 개선을 뜻하지 않는다. 원본 GET·경로·Firestore 문서 수는 변경 없다. 동일 bytes의 검증 GET과 결과 JSON21개·최대168MiB는 별도다. 기존 단가 가정의 JPEG30일 보관 추정은 무료 차감 전 약US$0.017906이다.

배포 전제: 새 최종 이미지·코드 digest를 실행안에 반영하고 승인된 배포/실험 범위를 확인해야 한다. 실제 Cloud Run CPU의 exact JPEG, cgroup 계측, ADC의 새 result.json 수집은 원격 smoke에 남는다. 원 사이트 최신 확인·레지스트리 push·배포·실제21회·IAM 변경은 이번에 하지 않는다.
