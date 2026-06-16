# OutPick Socket Local Server

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

Do not commit Firebase Admin JSON keys. The server still supports `FIREBASE_SERVICE_ACCOUNT_JSON` for controlled environments, but local development should prefer ADC.
