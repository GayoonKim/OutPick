# OutPick Test Admin Server

`outpick-test` Firebase project의 테스트 데이터를 로컬/CI에서 seed/reset하기 위한 전용 서버입니다.

이 서버는 앱이 호출하는 production backend가 아니며 Firebase deploy 대상도 아닙니다.

## 목표

- 운영 Firebase project 접근 방지
- Firebase Admin SDK 기반 테스트 데이터 seed/reset
- UITest 실행 전 deterministic test state 준비
- fixture UI test와 실제 Firebase integration UI test 분리

## 현재 단계

현재 제공하는 기능은 다음입니다.

- `GET /health`
- `POST /reset`
- `POST /seed/lookbook-basic`
- `POST /seed/lookbook-comments`
- 환경 변수 기반 config 로딩
- Express 서버 부팅
- Firebase Admin SDK 초기화
- `outpick-test` project guard

실제 Firebase 기반 UITest 호출 경로는 다음 단계에서 추가합니다.

## 환경 변수

필수:

```bash
TEST_FIREBASE_SERVICE_ACCOUNT_PATH=/absolute/path/to/outpick-test-service-account.json
TEST_FIREBASE_TEST_USER_PASSWORD=local-test-password
```

선택:

```bash
TEST_ADMIN_HOST=127.0.0.1
TEST_ADMIN_PORT=45731
TEST_FIREBASE_PROJECT_ID=outpick-test
```

`TEST_FIREBASE_PROJECT_ID`와 service account의 `project_id`가 `outpick-test`가 아니면 서버는 시작하지 않습니다.

## 실행

```bash
cd test-admin-server
npm install
npm run build
TEST_FIREBASE_SERVICE_ACCOUNT_PATH=/absolute/path/to/outpick-test-service-account.json \
TEST_FIREBASE_TEST_USER_PASSWORD=local-test-password \
npm run dev
```

기본 포트는 `45731`입니다.

```bash
curl http://127.0.0.1:45731/health
```

예상 응답:

```json
{
  "status": "ok",
  "firebaseProjectID": "outpick-test",
  "serviceAccountProjectID": "outpick-test",
  "firebaseAdminInitialized": true
}
```

## Reset

`POST /reset`은 allowlist collection의 테스트 문서만 삭제합니다.

현재 allowlist:

- `brands/{uitest-*}`
- `users/{uitest-*}`
- `brands/{*testRunId*}`
- `users/{*testRunId*}`

하위 subcollection 문서도 함께 삭제합니다.

또한 Firebase Auth user 중 `uid`가 `uitest-`로 시작하거나 `testRunId`를 포함하는 계정도 reset 대상에 포함합니다.

실제 삭제 전 dry run:

```bash
curl -X POST http://127.0.0.1:45731/reset \
  -H 'Content-Type: application/json' \
  -d '{"dryRun": true}'
```

특정 testRunId 기준 dry run:

```bash
curl -X POST http://127.0.0.1:45731/reset \
  -H 'Content-Type: application/json' \
  -d '{"testRunId": "run-20260520", "dryRun": true}'
```

실제 삭제:

```bash
curl -X POST http://127.0.0.1:45731/reset \
  -H 'Content-Type: application/json' \
  -d '{}'
```

## Lookbook Basic Seed

`POST /seed/lookbook-basic`은 최소 룩북 진입 데이터를 생성합니다.

생성 대상:

- Firebase Auth user 2명
  - `uitest-user`
  - `uitest-author`
- Firestore user profile 2개
  - `users/uitest-user`
  - `users/uitest-author`
- 브랜드 1개
  - `brands/uitest-brand`
- 시즌 1개
  - `brands/uitest-brand/seasons/uitest-season`
- 포스트 1개
  - `brands/uitest-brand/seasons/uitest-season/posts/uitest-post`

실행:

```bash
curl -X POST http://127.0.0.1:45731/seed/lookbook-basic \
  -H 'Content-Type: application/json' \
  -d '{}'
```

특정 testRunId를 남기고 싶을 때:

```bash
curl -X POST http://127.0.0.1:45731/seed/lookbook-basic \
  -H 'Content-Type: application/json' \
  -d '{"testRunId": "run-20260520"}'
```

## Lookbook Comments Seed

`POST /seed/lookbook-comments`는 기본 룩북 데이터 위에 댓글/답글 테스트 데이터를 생성합니다.

`/seed/lookbook-comments`는 내부에서 `/seed/lookbook-basic`과 같은 기본 데이터 생성을 먼저 보장합니다.

생성 대상:

- root comment 2개
  - `uitest-comment-pinned`
  - `uitest-comment-representative`
- reply 1개
  - `uitest-reply-representative-1`
- 댓글/답글 작성자 user profile 2개
  - `users/uitest-commenter`
  - `users/uitest-replier`
- Firebase Auth user 2명
  - `uitest-commenter`
  - `uitest-replier`
- 현재 사용자 댓글 좋아요 상태 1개
  - `users/uitest-user/commentStates/{brandID}_{seasonID}_{postID}_{commentID}`
- post `metrics.commentCount`
  - `3`

실행:

```bash
curl -X POST http://127.0.0.1:45731/seed/lookbook-comments \
  -H 'Content-Type: application/json' \
  -d '{}'
```

특정 testRunId를 남기고 싶을 때:

```bash
curl -X POST http://127.0.0.1:45731/seed/lookbook-comments \
  -H 'Content-Type: application/json' \
  -d '{"testRunId": "run-20260520"}'
```
