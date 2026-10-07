import assert from "node:assert/strict";
import type {FirebaseClients} from "../firebase.js";
import {fetchPublicHTTP} from "../public-http.js";
import {assertRemoteEnvironment, assertRemoteRoots, REMOTE_BUCKET}
  from "./remote-contract.js";
import type {RemotePorts} from "./remote-io.js";

// GAX 공개 clientConfig를 전달한다. Firestore 상위 stream/transaction 재시도는
// 별도이며 RPC 호출 수를 adapter 호출 수로 오인하지 않는다.
export function configureRemoteFirestore(firebase: FirebaseClients) {
  assertRemoteEnvironment(firebase.app.options.projectId ?? "",
    firebase.storage.bucket().name);
  const methods = Object.fromEntries([
    "GetDocument", "BatchGetDocuments", "BeginTransaction", "Commit",
    "Rollback", "RunQuery",
  ].map((name) => [name, {timeout_millis: 20000,
    retry_codes_name: "remote_none", retry_params_name: "remote_bounded"}]));
  firebase.firestore.settings({clientConfig: {interfaces: {
    "google.firestore.v1.Firestore": {methods,
      retry_codes: {remote_none: []}, retry_params: {remote_bounded: {
        initial_retry_delay_millis: 100, retry_delay_multiplier: 1,
        max_retry_delay_millis: 100, initial_rpc_timeout_millis: 20000,
        rpc_timeout_multiplier: 1, max_rpc_timeout_millis: 20000,
        total_timeout_millis: 20000,
      }}},
  }}});
}

// 실험 전용 서버에서만 생성한다. 제품 route와 같은 프로세스에 연결하지 않는다.
export function remoteFirebasePorts(firebase: FirebaseClients,
  root: string, documents: string): RemotePorts {
  const bucket = firebase.storage.bucket();
  assertRemoteEnvironment(firebase.app.options.projectId ?? "", bucket.name);
  assert.equal(bucket.name, REMOTE_BUCKET);
  assertRemoteRoots(root, documents);
  // SDK의 숨은 업로드 재시도 대신 회차에 기록되는 재시도만 사용한다.
  bucket.storage.retryOptions.autoRetry = false;
  bucket.storage.retryOptions.maxRetries = 0;
  const object = (path: string) => {
    assert.ok(path.startsWith(root) && !path.includes(".."));
    return bucket.file(path);
  };
  const document = (path: string) => {
    assert.ok(path.startsWith(`${documents}/assets/`) &&
      /^[A-Za-z0-9-]+$/.test(path.slice(`${documents}/assets/`.length)));
    return firebase.firestore.doc(path);
  };
  return {
    fetch: fetchPublicHTTP,
    put: async (path, bytes) => {
      assert.ok(bytes.length <= 25 * 2**20);
      await object(path).save(bytes, {resumable: false, timeout: 20000,
        preconditionOpts: {ifGenerationMatch: 0},
        metadata: {contentType: path.endsWith(".json") ?
          "application/json" : "image/jpeg"}});
    },
    get: async (path) => {
      const stream = object(path).createReadStream();
      const timer = setTimeout(() => stream.destroy(
        new Error("실험 객체 읽기 시간 제한")), 20000);
      const chunks: Buffer[] = [];
      let size = 0;
      try {
        for await (const chunk of stream) {
          size += chunk.length;
          assert.ok(size <= 25 * 2**20, "실험 객체 읽기 크기 제한");
          chunks.push(Buffer.from(chunk));
        }
        return Buffer.concat(chunks, size);
      } finally {
        clearTimeout(timer);
        stream.destroy();
      }
    },
    read: async (path) => (await document(path).get()).data(),
    set: async (path, data) => {
      await document(path).set(data, {merge: true});
    },
  };
}
