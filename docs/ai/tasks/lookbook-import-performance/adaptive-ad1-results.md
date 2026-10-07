# 자동 동시성 AD1 — 로컬 제어기 구현·검증

2026-10-04. 사용자가 세부 설계 제시 후 “다음 핵심 작업 진행해”라고 지시해 추천 AD1 범위로 진행했다. [설계와 후속 경계](adaptive-concurrency-design.md)를 따른다. **제어기·가변 슬롯·회귀 테스트 구현 완료, Mac/Linux 각각286개·필수178개 게이트 통과.** 실제 이미지 연결·성능15회·원격 배포/전송은 실행하지 않았다.

## 구현한 동작

- `performance/adaptive-controller.ts`: `AdaptiveController.observe`에 주입한 메모리·정규화 CPU·sharp 대기·완료량/지연·작업 수요·입장 가능 여부로 판단한다. 초깃값 다운로드4/변환1/업로드4/이미지4, 상한16/4/16/24. 제어기는 실제 cgroup 파일을 읽거나 작업을 직접 실행하지 않는다.
- 2초 구간·완료 표본4개 이상에서 한 축을1개 늘리고 최소4초 관찰한다. 처리량5% 이상 증가·실행 지연 중앙값10% 이상 악화 없음·하류 압박 없음일 때 유지한다. 그 외는 복귀, 완료 표본 부족은 미판정으로 보류한다. 재변경 전4초를 기다린다. 업로드→변환→다운로드→이미지 순서를 순환해 한 축이 탐색 기회를 독점하지 않게 했다.
- CPU80% 이상/throttling/sharp 대기 시 변환 증속을 보류하지만 CPU 포화만으로 기존 폭이나 네트워크 폭을 줄이지 않는다. 일시 전송 오류는 해당 축을 절반으로 줄이고 탐색을 중단한다. 단위는 다운로드/업로드 bytes, 변환 출력 pixels, 이미지 완료 개수이며 AD2 수집기가 같은 의미로 전달해야 한다.
- 메모리75%부터 새 이미지·다운로드 허용량0, 변환 목표1로 줄이고 업로드·경로 저장으로 정리할 수 있게 한다.65% 미만1초 뒤 재개한다. 각 단계의 `canAdmit=false`이면 해당 단계의 유효 허용량도0이다. 이는 AD2의 예약 판단을 주입하는 경계이며 실제 메모리 상한 보장이 아니다.
- 기존 `MemoryGuard`로85% 이상1초·표본500ms 초과·한도/출처 변경을 중단한다. CPU 미지원/잘못된 값, 시각 역행/중복, 잘못된 수요/완료값도 중단한다. `checkTime`은 표본 공급이 멈췄을 때 외부 타이머가 호출할 경계다. 중단은 되돌릴 수 없다.
- `pipeline/resources.ts`: 명시적 `adjustableLimits: true`일 때만 `setStageLimit`을 허용한다. `Slots.setLimit(0)`은 신규 시작 보류, 감속은 실행 중 작업을 선점하지 않는다. 종료 시 active를 줄이고 새 상한에 여유가 있을 때만 대기자를 시작한다. 기본 Runtime은 setter를 거부한다.
- `performance/submission-runtime.ts`: 가변 변환 큐에서도 준비된 시즌 순위·동순위 FIFO·AsyncLocalStorage를 유지한다. 기존 기본값은 변환1이며 P/S의 `remotePolicy`와30회 version1 계약은 그대로다. 전체 무한 입력에 대한 공정성을 보장한다고 주장하지 않으며 유한 입력 완료를 검사했다.
- 제한 목표/유효값·입장 변경·CPU/메모리·수요·처리량/지연·증속/유지/복귀/감속/중단 사유의 독립 복사 기록을 제공한다. 결정 기록과 구간 완료 자료는 각각10,000개 한도 초과 시 중단한다. 실제 원격 결과 저장 연결은 AD4다.

`observe`/`snapshot`은 결정 값을 반환한다. AD1 fake 검사에서는 이 값을 가변 슬롯에 적용하지만 실제 Worker의 index/server/remote-runner에 자동 연결하지 않았다. 중단 시 기존 실행을 abort/drain하고, 시작 직전에 메모리를 예약하며, 독립 표본 타이머를 설치하는 책임은 AD2 연결 범위다. 시즌당4 이미지 제한을 실제 R 실행에서 대체하는 변경도 AD2에 남아 있다.

## 필수 검사와 원본

검사 상태는 HEAD `1d67d61faa04984783083971688a7c628df74748` + 작업 트리다. `verification/lookbook-import.json`에 AP01~08을 추가했고 기존 필수170개를 유지했다. 문서만 갱신한 결과를 코드 검사 통과로 대신하지 않는다.

| 검사 | 원본 | 결과 |
| --- | --- | --- |
| Mac | [1791100381972-6f49c297-bdc7-4dc4-9c45-d03e0a48e900](../../../../output/verification/1791100381972-6f49c297-bdc7-4dc4-9c45-d03e0a48e900/summary.json) | passed. 전체286개/필수178개, lint/build/추출 fixture. digest `24e2a16a918bd01f31e12e91fa46d7bfc24a8791de6a8e490fe8c34d87b1a054`,175파일 |
| Linux | [1791100569560-46e57743-c7f7-4d07-94b1-ad86d154a1f3](../../../../output/verification/1791100569560-46e57743-c7f7-4d07-94b1-ad86d154a1f3/summary.json) | passed. 전체286개/필수178개, lint/build/추출 fixture. digest `50576042f22b73fd08b52bbf75823efce92baa57844ce95b61d7417b700290b3`,179파일 |

Linux 검사 이미지는 `sha256:8d3cd307aaf035f951d2f348e826b276f9b9b4d54782bbe9723a65c2ded3dd1e`. 이전 로컬 이미지 `sha256:9da9eda38eaeea0a9664c4aa370f87e394b409eb7fc91f78e952f9604bc88705`에서 외부 네트워크 없이 빌드했다. 새 검사 wrapper/config/image ID는 `output/lookbook-import-performance/adaptive-ad1-*`에 보존하며 이전 remote 검사 파일을 덮어쓰지 않았다. 컨테이너1CPU/2GiB·추가swap 없음·네트워크 없음. 성능 측정과 구별한다.

```sh
node tools/verification-gate/gate.mjs --project . --config verification/lookbook-import.json
node tools/verification-gate/gate.mjs --project . --config output/lookbook-import-performance/adaptive-ad1-linux-gate.json
```

AP01 초기 범위/미지원/지연/역행, AP02 감속/정지/재개, AP03 한 축 증속/표본 부족/되돌림/각 축 상한, AP04 CPU와 전송 오류 분리, AP05 메모리 제동/하류 정리/예약 거절/안전 중단, AP06 취소/실패/늦은 완료와 슬롯 반환, AP07 가변 우선순위/맥락/유한 입력 완료, AP08 결정 증거 불변성과 P/S 계약 불변을 검사한다. 기존 저장·캐시·원격 fake·실제 JPEG 회귀도 전체 Worker 게이트에 포함된다.

이번에 원격 계약·Firestore transaction·rules를 변경하지 않아 emulator 게이트는 재실행하지 않았다. 이전 emulator4개 결과는 [당시 D0~D3 기록](development-connection-results.md)에 보존하며 이번 전체 코드 digest의 emulator 통과로 재사용하지 않는다. 실제 자원 사용량/변동 네트워크에서의 속도·실패율 개선은 아직 미검증이다.

## 준비 과정과 남은 작업

- 초기 개발 중 TypeScript의 optional snapshot 접근5곳과 lint의 블록/들여쓰기/줄 길이 오류를 수정했다. AP 단독 검사는8개 통과했고 최종 판정은 위 전체 게이트 결과를 사용한다. 처음부터 모든 개발 명령이 통과했다고 기록하지 않는다.
- Linux 준비 시 Docker daemon이 종료돼 있었다. 로컬 Docker Desktop을 시작하고 기반 이미지 ID를 확인한 뒤 빌드했다. 배포·원격 이미지 요청·Firebase 쓰기는 없었다.
- 다음 AD2는 원본 해상도/채널/포맷·변환 증분 메모리 조사 → 미반영 예약/여유/해제 계약과 준비 규모 제시 → 실제 로컬 연결 구현 순서다. 원본 크기를 출력 JPEG 크기로 대체하지 않는다.
- 성능15회, 대용량 압박 회차, Development version2/실행 비용·중단 manifest는 아직 실행하지 않는다. 현재 수치가 최적값이라는 결론을 내리지 않는다.
