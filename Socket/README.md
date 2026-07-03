# OutPick Socket Server

OutPick 채팅과 룩북 공유의 Socket.IO 런타임 서버다. 로컬 개발은 Application Default Credentials를 사용하고, 운영 배포는 Cloud Run service account / ADC를 사용한다.

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

Service account:

```bash
gcloud iam service-accounts create outpick-socket \
  --project=outpick-664ae \
  --display-name="OutPick Socket Cloud Run"
```

Minimum runtime IAM candidates:

```bash
gcloud projects add-iam-policy-binding outpick-664ae \
  --member="serviceAccount:outpick-socket@outpick-664ae.iam.gserviceaccount.com" \
  --role="roles/datastore.user"

gcloud projects add-iam-policy-binding outpick-664ae \
  --member="serviceAccount:outpick-socket@outpick-664ae.iam.gserviceaccount.com" \
  --role="roles/firebasecloudmessaging.admin"

gcloud projects add-iam-policy-binding outpick-664ae \
  --member="serviceAccount:outpick-socket@outpick-664ae.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"
```

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
  --service-account=outpick-socket@outpick-664ae.iam.gserviceaccount.com \
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
