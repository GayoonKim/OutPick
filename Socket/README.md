# OutPick Socket Server

OutPick 채팅과 룩북 공유의 Socket.IO 런타임 서버다. 로컬 개발은 Application Default Credentials를 사용하고, 운영 배포는 Cloud Run service account / ADC를 사용한다.

## Source Structure

- `index.js`: Firebase/runtime bootstrap, room preload, listen과 signal 연결만 담당한다.
- `src/app/`: Express/HTTP/Socket.IO application과 production dependency graph를 조립한다.
- `src/auth/`, `src/handlers/`: handshake 인증과 기능별 Socket event 등록을 담당한다.
- `src/rooms/`, `src/messages/`, `src/media/`: 기능별 validation, payload, persistence orchestration을 담당한다.
- `src/lifecycle/`, `src/runtime/`: health/shutdown과 clock/ID 같은 runtime capability를 담당한다.
- `test/`: application, 계약, handler/service/state의 `node:test` 검증이다.

## Verification

```bash
npm run check
npm test
```

테스트 runner는 `test/` 아래의 모든 `*.test.js`를 재귀적으로 실행하며 테스트가 하나도 없으면 실패한다.

## Local Firebase Admin Auth

The local Socket server uses Firebase Admin through Application Default Credentials (ADC).

One-time setup:

```bash
gcloud config set project outpick-664ae
gcloud auth application-default login --project=outpick-664ae
gcloud auth application-default set-quota-project outpick-664ae
```

Check:

```bash
npm run check:adc
```

Run:

```bash
npm start
```

Health check:

```bash
curl http://localhost:3000/readyz
```

## Cloud Run Runtime

Initial production target:

```text
service: outpick-socket
project: outpick-664ae
region: asia-northeast3
min instances: 0
max instances: 1
```

The container listens on the `PORT` environment variable supplied by Cloud Run. Firebase Admin should use the attached Cloud Run service account through Application Default Credentials.

Local Docker build candidate:

```bash
docker build -t outpick-socket:local Socket
```

Local Docker run candidate:

```bash
docker run --rm -p 8080:8080 -e PORT=8080 outpick-socket:local
```

## Cloud Run Deploy Candidate

Run these commands only after confirming the deployment window.

Least-privilege runtime role and service account:

```bash
gcloud iam roles create outpickSocketRuntime \
  --project=outpick-664ae \
  --title="OutPick Socket Runtime" \
  --permissions="firebaseauth.users.get,datastore.databases.get,datastore.entities.allocateIds,datastore.entities.create,datastore.entities.delete,datastore.entities.get,datastore.entities.list,datastore.entities.update,storage.objects.delete,storage.objects.list,cloudmessaging.messages.create" \
  --stage=GA

gcloud iam service-accounts create outpick-socket-runtime-v2 \
  --project=outpick-664ae \
  --display-name="OutPick Socket Runtime v2"

gcloud projects add-iam-policy-binding outpick-664ae \
  --member="serviceAccount:outpick-socket-runtime-v2@outpick-664ae.iam.gserviceaccount.com" \
  --role="projects/outpick-664ae/roles/outpickSocketRuntime"
```

`outpickSocketRuntime` is the single runtime role for Firebase Auth revoked/disabled
checks, Firestore chat state, room Storage prefix cleanup, and FCM message delivery.
Do not replace it with broad Firebase Auth Viewer, Datastore User, Storage Object
Admin, or Firebase Cloud Messaging Admin roles. Validate a new identity on a
no-traffic candidate before changing the live revision identity.

The socket server initializes Firebase Admin with `OUTPICK_FIREBASE_STORAGE_BUCKET`
or `FIREBASE_STORAGE_BUCKET` when provided. The production default is
`outpick-664ae.appspot.com`, which is required for room close cleanup to delete
the `rooms/{roomID}/` Storage prefix.

Build and deploy candidate:

```bash
gcloud builds submit Socket \
  --project=outpick-664ae \
  --tag=asia-northeast3-docker.pkg.dev/outpick-664ae/cloud-run-source-deploy/outpick-socket:manual

gcloud run deploy outpick-socket \
  --project=outpick-664ae \
  --region=asia-northeast3 \
  --image=asia-northeast3-docker.pkg.dev/outpick-664ae/cloud-run-source-deploy/outpick-socket:manual \
  --service-account=outpick-socket-runtime-v2@outpick-664ae.iam.gserviceaccount.com \
  --allow-unauthenticated \
  --min-instances=0 \
  --max-instances=1 \
  --timeout=3600 \
  --concurrency=80 \
  --port=8080
```

`--allow-unauthenticated` is required so iOS clients can reach the Socket.IO endpoint. The server still requires Firebase ID Token authentication at the Socket.IO handshake layer.

External readiness check:

```bash
curl https://outpick-socket-2w7zhxurhq-du.a.run.app/readyz
```

Rollback candidate:

```bash
gcloud run revisions list \
  --project=outpick-664ae \
  --region=asia-northeast3 \
  --service=outpick-socket

gcloud run services update-traffic outpick-socket \
  --project=outpick-664ae \
  --region=asia-northeast3 \
  --to-revisions=REVISION_NAME=100
```

Do not commit Firebase Admin JSON keys. The server still supports `FIREBASE_SERVICE_ACCOUNT_JSON` for controlled environments, but local development should prefer ADC.
