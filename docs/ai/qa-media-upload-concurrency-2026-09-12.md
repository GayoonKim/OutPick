# iPhone 14 업로드 동시성 비교 — 2026-09-12

## 2026-09-14 최종 적용·Development 결합 QA 완료

- 확정 정책: FIFO1/원본확보4/연속사진 전체준비/PUT4, 계약3 서버metadata·URL서명·취소정리 각각 대상전체 실행. 아래9월12일 후보·복원·미검증 문구는 당시 이력이다.
- 원본 확보 추가 비교4/all/4/all:1.630/0.411/0.505/0.437초. 첫 실행 이후 차이는 약0.07~0.09초이며 사용자 결정으로4 유지. 캐시 영향은 추측으로 원인을 확정하지 않았다.
- 최종 코드 iPhone14 Development41개/4 suites, Socket 문법검사/124개 통과. 실패/취소·원본소유권·멱등성·전체작업 종료대기 회귀 포함.
- Development 배포: `outpick-socket-development-concurrency-all-0914`100%, digest `sha256:dda2c4eb9540a28643061d8cd4f153189e504ea5072edb1e76fadb95c20a6d37`. 기존env/runtime 유지, candidate/live readiness 정상, rollback `photo300-0911`.
- 실제3장 smoke 후70장: 서버30/30/10·seq58/59/60·계약3ready와 앱FIFO 순서 대조. 원본0.534초/준비3.950초/전체27.623초, metadata60/60/20 합663ms. 개별 실험보다 항상 빠르다는 근거는 아니다.
- 200ms 누적 표본peak1415.32MiB,1초출력시점 관측최대1160.36MiB,thermal0. 순간최대값 보장이 아니며 사용자 전송중스크롤/입력·완료후재입장 확인과 구분한다.
- 사용자 네트워크 차단→실패버블 재시도/삭제 버튼 확인→재시도성공. 서버후속2장/seq61·metadata4/all/33ms 대조. 삭제버튼 실제삭제 조작까지 확인한 것은 아니다. 이때 앱콘솔 연결이 끊겨 재시도 전후 앱로그는 확보하지 못했으며 사용자확인/서버기록이 근거다.
- QA 종료 후계측off로 재실행했고 최종기본정책은 유지했다. 커밋/PR은 이 결과를 기준으로 진행하며 Production은 [기존대기작업에통합](runbooks/CHAT_MEDIA_PRODUCTION_ROLLOUT.md)해 별도로 진행한다.
- 증거: `/private/tmp/outpick-concurrency-final-ios-tests.xcresult`, `/private/tmp/outpick-concurrency-final-socket-tests.log`, `/private/tmp/outpick-concurrency-combined-70-{summary,messages}.json`, `/private/tmp/outpick-concurrency-combined-server-final.json`, `/private/tmp/outpick-concurrency-recovery-{messages,server}.json`. 원시콘솔·인증자료는 커밋하지 않는다.

## 2026-09-14 적용 방향 확정

- 사용자 확정: 묶음 FIFO1·원본 확보4·이미지 준비 연속 사진 전체·파일 업로드4·서버 metadata 요청 내 전체 파일 조회. 영상 정책 유지.
- 이미지 준비 `all`은 `Int.max`로 연속 사진 구간의 작업을 모두 등록하며, 30장 묶음 분할 전에 실행한다. 사진70장이 연속이면70개 작업이 대상이다. 실제 CPU 동시 실행 개수를 의미하지 않는다.
- 아래 서버 비교는 명시적 상한60 설정의 실측이다. 확정 정책은 고정60 대신 요청 대상 전체 조회이며, 현재 최대30장/60파일 계약에서는 동일한 조회 폭이다. 정책 변경 코드와 최종 결합 조합은 아직 검증하지 않았다.
- 향후 묶음 크기 확대 후 지연·실패율이 증가하면 측정에 따라 제한 도입을 재검토한다. 이번에는 방향과 상태만 기록했으며 코드·배포 변경은 없다.

## 조건

- Development `outpick-test`, 다른 참여자 없는 `미디어 QA`, 사용자 확인 여유 공간 약 50GB.
- 묶음 FIFO 1, 원본 확보 4, 이미지 준비 4, 서버 metadata 4 유지. 파일 업로드만 4 / all 교대로 변경.
- all은 묶음의 전체 PUT 작업을 시작한다. 30장 묶음은 본 이미지·썸네일 합계 60파일이다. 실제 네트워크 연결 60개가 동시에 활성화됐다는 의미는 아니다.
- DEBUG Development 실행 환경 변수로만 적용. 정식 기본값은 4 유지.

## 실측

| 실행 순서 | 업로드 제한 | 전체 완료 초 | 원본 확보 초 | 업로드 구간 합계 초 | 첫 30장 업로드 초 | 관측 최고 메모리 MiB |
|---|---|---:|---:|---:|---:|---:|
| 1 | 4 | 49.993 | 26.619 | 11.334 | 7.442 | 1034.75 |
| 2 | all | 32.021 | 0.524 | 19.330 | 16.645 | 1033.22 |
| 3 | 4 | 24.391 | 0.542 | 12.058 | 7.896 | 950.72 |
| 4 | all | 82.266 | 0.540 | 70.150 | 66.319 | 1069.31 |

- 전체 완료: selection_started → 마지막 image_pending_cleared.
- 업로드 구간: batch_reserved → batch_finalize_started의 묶음별 시간 합계. 파일 전송과 클라이언트 내부 대기 시간을 포함하며 순수 회선 전송 시간은 아니다.
- 네 번 모두 Firestore 메시지 첨부 30·30·10장 확인. 순번은 각각 21–23, 24–26, 27–29, 30–32. 앱 성공 반영 이후 다음 묶음 예약 시작 로그 확인.
- 사용자는 매 실행 후 완료 및 스크롤·입력 확인 완료를 보고했다. 별도 프레임 시간 계측은 수행하지 않았다.
- 200ms 메모리 표본, 1초 출력의 누적 peak 관측값. 정확한 순간 최대값이 아니며 준비·채팅 화면 메모리까지 포함한다. 기록된 thermal rawValue는 모두 0.

## 해석과 제한

- 이번 조건에서는 업로드 4를 유지한다. 두 번 모두 업로드 11–12초였고 all은 19초와 70초였다. 전 기기·네트워크에서의 최적값을 입증한 것은 아니다.
- 첫 실행의 원본 확보가 길어 전체 시간만 비교하면 잘못된 결론이 난다. 캐시 등 원본 제공 조건의 영향은 추측이며 별도 원인 확정은 하지 않았다.
- 첫 30장 업로드 바이트는 네 번 모두 150,250,712로 같다. 두 번째 실행의 뒤 두 묶음은 다른 실행과 바이트가 조금 다르므로 완전히 동일한 입력이라고 단정하지 않는다. 바이트 일치도 내용 해시 일치를 증명하지 않는다.
- 66.319초 지연은 예약 완료 후 finalize 시작 전이다. URLSession 세부 전송 지표가 없어 연결 경쟁, 회선 변동, 내부 재시도 등 구체 원인은 미확정.
- 이 표는 파일 업로드 제한 비교다. 이후 수행한 준비·metadata 비교는 아래 추가 결과를 참조한다.

## 추가: 이미지 준비 비교

- 준비 all / 업로드4 / metadata4 두 실행 모두70장 정상 저장, seq33–35 및36–38. 사용자 두 번 모두 완료·스크롤·입력 이상 없음 확인.
- 원본 확보 완료 → 마지막 chunk_prepared: 3.818초 / 3.979초. 기존 준비4는 약6초. 전체 완료24.714초 /22.038초.
- 관측 최고 메모리1592.19 /1337.61MiB, thermal0. 메모리 증가만으로 실패 판정하지 않으며, 준비 시간 이득과 사용자 조작 결과를 함께 평가한다. 장시간·다른 사진/기기 일반화는 불가.
- 증거 `/private/tmp/outpick-concurrency-pall-{r1,r2}-{summary,messages}.json`.
- metadata60 비교용 Socket 테스트116개 통과, 이미지 digest `sha256:70f9a39f2ce415dbf2d30c15e78718601e3cb0f1bac748a43f88c742f0fe5a74`. Development `outpick-socket-development-metadata60-0912` no-traffic 배포 후 readyz 성공. 기존 롤백 리비전 `outpick-socket-development-photo300-0911`.

## 추가: 서버 metadata 비교 및 종합 판단

- 준비4 / PUT4 / metadata60 두 실행 모두70장 정상 저장, seq39–41 및42–44. 전체23.637초 /23.813초. 사용자 두 번 모두 완료·스크롤·입력 이상 없음 확인.
- metadata 조회 시간 합계: 60개는0.475초(369/69/37ms), 재측정0.200초(102/68/30ms). 이전4개 여섯 실행은0.621–0.673초.
- 서버 조회60은30장 묶음의60파일 전체를 시작하며, 실제 연결/CPU가60개로 병렬 실행된다는 의미는 아니다. 다중 사용자 서버부하·서버 메모리 피크는 별도 계측하지 않았다.
- 개별 단계 후보: 업로드4 유지, 준비 전체 동시 실행은 약2초 단축·사용자 조작 이상 없음으로 채택 후보, metadata60은 조회 시간 단축으로 채택 후보. 준비 전체 동시 실행과 metadata60을 결합한 최종 조합은 아직 미검증. 지원 기기 전체의 최적값 확정 아님.
- 총8회/560장/24묶음 메시지 저장 확인. 증거 메시지 seq21–44. 메모리만으로 조작 성능을 판정하지 않았고 사용자 확인과 분리 기록했다.
- 실험 종료 후 앱QA 환경 비활성, 준비4/PUT4 복원. Development 트래픽은 기존 `photo300-0911`(metadata4)로 복원하며 배포 템플릿도 기존 이미지/metadata4로 복원한다. Production 변경 없음.
- metadata60 증거 `/private/tmp/outpick-concurrency-m60-{r1,r2}-{summary,messages}.json`, `/private/tmp/outpick-metadata60-r2-server.json`, `/private/tmp/outpick-metadata4-baseline-server.json`.

## 증거 위치

- `/private/tmp/outpick-concurrency-{u4,uall}-{r1,r2}-summary.json`: 단계별 시간·메모리 및 메시지 ID.
- 같은 접두사의 `-messages.json`: Firestore 첨부 개수·순번.
- 같은 접두사의 `-console.log`: 원시 기기 기록. 외부 게시 전 인증·개인정보 제거 필요.
- `OutPickTests/ChatMediaUploadUseCaseTests.swift`: 4 / Int.max에서 모든 파일 업로드 후 finalize하는 매개변수 테스트 포함. Development iPhone 테스트 성공, 실패 0. 측정 빌드 성공.
