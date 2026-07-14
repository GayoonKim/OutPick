# Phase 4 Firebase Functions Decisions

## 상태

2026-07-14 사용자 승인으로 N7~N13을 D20~D26으로 확정했다. 이후 필요한 파일만 분리하고, 복잡한 service에만 dependency seam을 두며, dependency 없는 Node clean/test script를 사용하는 추천안 3개도 확정했다. D19 후속 구현은 완료됐고 Functions 코드·package script·배포 설정은 아직 변경하지 않았다.

## D20. 기능 하위 도메인별 module과 역할별 파일을 사용한다

- 함수 1개당 파일 1개나 `brand.ts`/`lookbook.ts` 같은 새 대형 파일을 만들지 않는다.
- `auth`, `brand/admin`, `brand/requests`, `lookbook/deletion`, `lookbook/engagement`, `lookbook/comments`, `lookbook/safety`, `lookbook/import`, `chat/cleanup`을 기능 경계로 사용한다.
- 각 기능 안에서 변경 이유가 다른 `functions`, `service`, `validator`, `mapper`, query/storage helper를 필요한 만큼 분리한다.
- 파일 줄 수가 아니라 외부 trigger 등록, 작업 단위 부작용, validation/mapping이라는 책임 차이로 분리한다.
- 기존 deletion purge drain/lease와 season candidate discovery/parser는 해당 기능 폴더로 이동하되 동작은 변경하지 않는다.

목표 구조:

```text
functions/src/
├── core/
├── shared/
├── auth/
├── brand/
│   ├── admin/
│   └── requests/
├── lookbook/
│   ├── deletion/
│   ├── engagement/
│   ├── comments/
│   ├── safety/
│   └── import/
├── chat/
│   └── cleanup/
└── index.ts
```

## D21. Firebase 초기화와 global runtime option은 core가 한 번 소유한다

- `core/firebase.ts`가 Admin app 초기화와 Firestore/Auth/Storage 접근을 소유한다.
- 중복 import와 test import에 안전하도록 Firebase Admin app 존재 여부를 확인한 뒤 초기화한다.
- `core/runtime.ts`가 `setGlobalOptions({maxInstances: 10})`, 공통 region과 공통 runtime 상수를 소유한다.
- 기능 module은 직접 `initializeApp` 또는 `setGlobalOptions`를 호출하지 않는다.
- `setGlobalOptions`가 function definition보다 먼저 평가되도록 각 function registration module은 core runtime에 명시적으로 의존한다.
- `onInit`은 function definition/global option 초기화 수단으로 사용하지 않는다.

## D22. 얇은 Functions wrapper와 작업 단위 service를 분리한다

- wrapper는 trigger/onCall 등록, auth UID와 payload 검증, service 호출, response와 `HttpsError` 변환을 담당한다.
- service는 Firestore transaction/batch, Cloud Tasks enqueue/idempotency, Storage 삭제, purge claim/finalize와 import job 상태 전이를 담당한다.
- 모든 함수에 class/interface/factory를 강제하지 않는다.
- 외부 부작용이 복잡하거나 실패 분기 자동 테스트가 필요한 service에만 dependency parameter 또는 좁은 dependency object를 도입한다.
- 단순 validator/mapper까지 generic repository 계층으로 감싸지 않는다.
- 기존 transaction, batch, delete, enqueue와 finalize 순서를 파일 이동 과정에서 변경하지 않는다.

## D23. infrastructure core와 공유 도메인 정책을 구분한다

- `core/`에는 Firebase SDK 초기화, runtime option, callable primitive validation과 공통 오류 변환만 둔다.
- 서로 다른 feature가 동일한 의미로 사용하는 브랜드 권한 같은 도메인 정책은 `shared/`에 둔다.
- 한 feature 내부에서만 재사용하는 validator/mapper/query는 해당 feature에 유지한다.
- `utils.ts`, `helpers.ts` 같은 무제한 공통 수납 파일은 만들지 않는다.
- 재사용 횟수만으로 core에 올리지 않고 의미와 소유권이 실제로 동일한지 확인한다.

## D24. index.ts는 49개 이름을 명시적으로 flat export한다

- wildcard export를 사용하지 않는다.
- `index.ts`에는 Firestore query, handler body, validator, mapper와 service 구현을 두지 않는다.
- callable 43개, Firestore trigger 3개, scheduler 3개의 기존 export 이름을 명시적으로 re-export한다.
- 내부 helper가 Firebase 배포 export로 노출되지 않게 한다.
- default codebase와 기존 function 이름을 유지한다.

## D25. clean build와 재귀 test 발견을 하나의 계약으로 고정한다

- 현재 `tsc`가 stale `lib/` 산출물을 남기는 문제를 제거한다.
- build 전에 dependency 추가 없는 Node script로 `lib/`를 삭제한다.
- build 후 Node test runner가 `lib/` 하위 `*.test.js`를 재귀적으로 발견하도록 test script를 바꾼다.
- 기존 deletion drain/lease test를 기능 폴더로 이동해도 `npm test`에서 실제 실행되어야 한다.
- 신규 contract test는 49개 export 이름과 `__endpoint` metadata의 region, maxInstances, timeout, memory, trigger path, schedule/timezone을 비교한다.
- Admin 초기화와 `setGlobalOptions` owner가 각각 한 곳인지 정적으로 검증한다.
- 신규 Firebase Emulator 환경 구축은 구조 이동보다 범위가 크므로 Phase 4 필수 완료 기준에 포함하지 않는다.

## D26. 위험이 낮은 module부터 순차 이전하고 전체 배포만 별도 승인한다

구현 순서:

1. clean/test discovery와 export/runtime contract snapshot
2. core Firebase/runtime/validation
3. Auth와 Chat cleanup
4. Brand admin/request
5. Lookbook engagement/comment/safety
6. Lookbook import
7. Lookbook deletion lifecycle
8. `index.ts` 명시적 flat export 축소
9. 전체 test/lint/build와 문서 갱신

- phase 내부에서는 컴파일 가능한 중간 `index.ts`를 허용하지만 완료 시 구현이 남아 있으면 안 된다.
- 구현 중 운영 배포는 하지 않는다.
- `firebase.json`의 `default` codebase를 유지한다.
- 구현 완료 후 `npm test`, `npm run lint`, `npm run build`를 모두 통과한다.
- 운영 배포는 사용자 별도 승인 후 `firebase deploy --only functions --project outpick-664ae` 전체 배포를 기본으로 한다.
- 공통 module packaging이 모든 함수에 영향을 주므로 선택 배포로 서로 다른 source revision을 섞지 않는다.

## 구현 계획 추가 확정

- feature마다 `functions/service/validator/mapper` 파일을 강제하지 않고 변경 이유가 있는 책임만 분리한다.
- Auth, Chat cleanup, Lookbook import/deletion처럼 외부 부작용과 실패 순서가 복잡한 service에만 dependency object seam을 둔다.
- `functions/scripts/clean-lib.mjs`, `run-tests.mjs`로 stale build 정리와 재귀 test 발견을 구현하며 shell glob과 새 dependency는 사용하지 않는다.
- 구체적인 변경 파일과 Step 4A~4I는 [Phase 4 구현 계획](../phases/phase-4-firebase-functions.md), 테스트는 [Phase 4 테스트 계획](../phases/phase-4-firebase-functions-tests.md)을 따른다.

## 선택하지 않은 대안

- 함수 1개당 파일: 탐색 파일과 반복 wrapper가 과도하게 늘어난다.
- feature당 단일 파일: 기존 giant entrypoint 문제를 기능별 giant file로 옮긴다.
- 모든 service의 interface/factory화: 동작 보존 리팩터링 범위를 불필요하게 확장한다.
- wildcard export: helper의 우발적 배포와 함수 이름 변경을 놓치기 쉽다.
- `lib/*.test.js` 유지: 하위 feature test가 실행되지 않는다.
- clean 없이 재귀 test만 적용: stale build test가 중복 또는 잘못 실행될 수 있다.
- Phase 4 중 선택 배포: 공통 module을 사용하는 함수가 서로 다른 source revision으로 운영될 수 있다.

## 재검토 조건

- 서로 다른 팀이 독립 배포를 실제로 요구하면 Firebase codebase 분리를 별도 ADR로 검토한다.
- heavy dependency나 장시간 초기화가 일부 함수의 cold start를 유의미하게 악화시키면 별도 source package/codebase를 검토한다.
- Firestore service의 실패 분기를 unit test로 제어하기 어려워 회귀가 반복되면 Emulator 기반 integration test를 별도 phase로 도입한다.
- feature 간 shared 정책이 늘어나 순환 의존 가능성이 생기면 package/target 수준 경계를 재검토한다.
