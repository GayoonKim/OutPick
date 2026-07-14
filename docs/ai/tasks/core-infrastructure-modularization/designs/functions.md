# Firebase Functions Module Design

## 목표

functions/src/index.ts에서 기능 구현을 제거하고 기존 이름의 flat export만 제공한다.

## 목표 흐름

~~~text
functions/src/index.ts
  → 기존 이름의 flat re-export
  → 기능별 handler
  → 기능별 service / mapper / validator
  → 공통 Firebase Admin / runtime
~~~

## 모듈 후보

- core/firebaseAdmin.ts
- core/callableValidation.ts
- auth/
- brand/admin/
- brand/requests/
- lookbook/engagement/
- lookbook/comments/
- lookbook/import/
- lookbook/deletion/
- chat/cleanup/

실제 디렉터리 깊이와 파일명은 Phase 1 export/helper dependency inventory 후 확정한다.

## index.ts 책임

- 기존 callable/trigger/scheduler 이름의 flat export.
- 필요한 bootstrap import.
- 구현 로직, payload parsing, Firestore query, mapping은 소유하지 않는다.

namespace export로 Function 이름을 바꾸지 않는다.

## 공통 runtime 책임

- admin.initializeApp.
- getFirestore 등 공통 Firebase Admin client.
- setGlobalOptions.
- 공통 runtime environment 접근.

초기화가 여러 기능 모듈에서 중복되지 않게 owner를 한 곳에 둔다. handler가 다른 handler를 직접 호출하지 않고 공통 service/helper를 호출한다.

## 보존 계약

- export된 callable/trigger 이름.
- Functions region과 runtime option.
- callable payload와 response.
- HttpsError code.
- Firestore trigger path.
- scheduler와 timezone.
- Cloud Tasks queue와 endpoint.

계약 오류나 dead Function이 발견되면 구조 리팩터링과 분리해 별도 결정한다.

## 테스트 배치

- 기능별 순수 helper/service test는 같은 기능 디렉터리에 둔다.
- Phase 1에서 기존 npm test의 `lib/*.test.js` glob이 하위 디렉터리 test를 찾지 못함을 확인했다. Phase 4에서 feature 폴더로 test를 옮길 경우 test discovery 명령도 함께 조정한다.
- export inventory와 runtime option 비교를 구조 변경 전후 검증에 포함한다.

## 완료 기준

- index.ts는 flat export 중심이다.
- feature handler/service/validator/mapper 책임이 분리된다.
- admin/runtime 초기화가 한 곳이다.
- circular import가 없다.
- 기존 export와 runtime contract가 유지된다.
- npm test, lint, build가 통과한다.
