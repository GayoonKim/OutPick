# Q7 K/L 기존 접수 보존 — 수정 후 이어 실행 제안

2026-10-07. **사용자 ‘이어서 다음 핵심 작업 진행’으로 확정했다.** K·L의 각 흐름을 한 번 확인하며 전달·접수 상한을 반복 테스트 횟수로 해석하지 않는다. 원래 실험은 K의 3접수·실제 OOM 1회 뒤 종료 로그 필터 결함으로 멈췄다. 기존 K를 삭제하거나 재접수하지 않는다. [실제 결과](q7-retry-development-results.md).

## 이번 실행 전 확인

- 기존 K는 queue/batch/execution active·attempt1/5, 이전 run epoch49와 동일하다. task는 만료되어 0개이며 이전 revision의 요청 로그에서 총18전달을 관찰했다. 읽기 전용 원본 `845dae34.../continuation-latest-readback.json`을 보존했다.
- 남은 정상 흐름 약6전달을 위한 여유는 누적30/추가10 안에 있다. task전달 상한은 관찰과 신규 투입 중지 기준이며 서버의 정확한 강제취소 상한이 아니다. 고의 OOM은 추가0회다.
- 변경 파일은 `q7-retry-contract.mjs`, `q7-retry-runner.mjs`, `q7-journal.mjs`, 기존 계약 테스트/필수 verifier 설정이다. 공개 제품 API·DB schema·IAM·Swift·관리자 웹 변경은 없다.
- QV13은 동일3accepted·UID/head/oldrevision·원본 소비·미공개 원장·남은5접수만을 검사한다. QV14는 같은 계약의 조건부 task1개와 배타적 intent·불확정 재전송 금지·누적 전달 상한을 검사한다. 실제 Worker 정산과 Storage 산출물은 원격 검증에서만 통과를 판정한다.

## 추천 계약

- 기존K brand/job/execution·3requestID와최초attempt1·원본OOMrun25/epoch49를유지한다. 새K브랜드/추가OOM/이미지중간복원은없다. 종료확인뒤기존제품코드가처음부터attempt2로추출한다.
- 수정된passed snapshot을Development0%후보1회에배포한다. base100%/1CPU2GiB/min0/revisionmax1/concurrency2/900초·기존계정/IAM·Storage·기존QA보호는유지한다. 새실행창은preflight통과후최대20분1회, 추가관리USD1/누적10한도는기존전체K/L예산을공유한다.
- 기존3접수+남은최대5접수=전체최대8을유지한다. 남은것은K새검토승인1, L브랜드생성/목록1·시즌접수1·소진뒤수동새요청1·정상검토승인1이다. L2026SS입력/제어실패5회/최종124JPEG/실패목록제거/총5회조건은변경하지않는다.
- K증거는old25의trace/instance/insertID를검사한다. 다음run은새candidate가정확같은head/epoch/generation을transaction재검사한뒤새epoch에서처리한다. 증거revision이해당oldrun과다르면계속거절한다. 단순히currentrevision으로증거를바꾸지않는다. 성능원본은25/수정후revision별로분리하며단일revision실험으로표시하지않는다.
- 고의장치는새20분창전용campaign UUID에재고정하되새target은L의원래execution뿐이다. 기존K의소비된OOMtarget·캠페인은증거로보존하고새Ktarget을만들지않는다. 새후보에서K에다시고의장치가적용되지않도록한다.
- 공유queue/head/Kbatch/3영수증·원본소비1회·새published쓰기없음·sameUID·큐간섭없음·이미지원본fixture를읽기전용확인해야기존3건을복원한다. 승인전`--resume=true`의2건복원조건을일반화하지않는다.
- 기존K task가있으면새후보/readback이끝난뒤동일task를최대1회즉시전달하도록실행하는안이다. 이미task가없으면같은Kbatch·현재dispatchGeneration·동일계약body/endpoint/기존task SA·canonical OIDC audience로새고정이름의task최대1개를만들어재전달하는안이다. 원장head/epoch/실행권은직접수정하지않고제품의exact종료증거/CAS로정산한다. 원래task이름은삭제후보존기간때문에재사용하지않고intent/새이름을전송전원자기록해불확정응답재전송을막는다. 이는새제품접수나시즌시도예산재설정이아니다. 기존실험중지뒤에도CloudTasks자동503재전달이계속돼2026-10-07T04:37조회에서KtaskdispatchCount9였다. 기존discovery/import2와구분해모든원본전달을합산한다. 이어실행은**추가최대10전달·기존전달포함누적30전달**로제안하며기존20상한변경을명시적으로확인한다. 새투입전현재횟수+남은6정상전달여유를확인하고한도초과예상시중지한다. 기존queue설정maxAttempts3/maxRetryDuration3600s와시즌총5회는별개다. 전역queue설정은변경하지않는다.

기존배포Google계정의`iam.serviceAccounts.actAs`(기존task SA)·`cloudtasks.tasks.create/run/fullView`(Development import queue)를공식testIamPermissions로읽기전용확인했다. 원본은`continuation-existing-permissions.json`. 권한추가/서비스계정key/실제task생성·실행은없다. task가없을때의조건부재전달1회도이번제안확인에포함한다.

## 최소 구현·변경 후보와 필수 검사

이미구현한exact로그필터/KR20·QV11/12는별도로검증한다. 이어실행변경은 `scripts/q7-retry-{contract,runner}.mjs`, `q7-journal.mjs`, `verification/lookbook-q7-verifier.json`의좁은3건복원·원본digest보존·별도faultcampaign·old/currentrevision별증거대조다. 공개제품API/DB스키마/IAM/Swift/관리자웹은추가하지않는다.

필수: 같은3accepted만복원, uncertain/더많은접수/다른UID·head·oldrevision·extrafault소비/이미완료·예산초과거절; Kcreate/import/첫approval재전송0; 새window준비실패면추가접수0; old플랫폼증거를유지하고새run불완전종료는통과하지않음;5남은접수·총8·같은L실패목록·수동새execution;missingasset부모문서의원장보호;최종공개124JPEG/generation/hash·old파일미참조와cleanup예약. 제품큐/Worker/실행기·필요한설정의Rules필수gate원본을source와함께보존한다.

## 요청량·비용

정상완료K/L이미지124JPEG는기존계획과같다. 이미관찰한K중단12JPEG384,872B와최초해시30GET2,499,444B는새다운로드합계에서숨기지않는다. 남은K재추출·K/L저장·L추출은최초보수183GET/186JPEG한도안에서검토한다. 원본HTML/브라우저·metadata/Storage검증GET·Firestore·Logging·task·SDK재전송은따로기록한다.

실제기존배포량보정관리추정약0.22USD에수정후보build5분0.03USD·image동일크기추가1개월0.054USD·새20분compute/조회여유약0.10USD를더하면약0.40USD다. 신규builder/machine/보관량/무료잔여·정확청구는미확정,상한보장은아니다. 새배포량·이미지가확인되면다시계산하고전체추정이기존추가관리1USD를넘으면시작하지않는다.

확정 범위는 ‘기존K3건유지·남은5접수·수정후보1회·새20분창1회·기존K조건부재전달최대1회(기존task실행또는없을때새task1개)·추가task최대10/누적30전달·기존전체비용한도유지’다. 그밖의입력·고의종료횟수·최종산출물·보호범위는유지한다. 추가task전달은제품추출접수30회나30번비교를의미하지않으며같은원장의재전달이다.
