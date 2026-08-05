import assert from "node:assert/strict";
import test from "node:test";

import {callIssueOperations, formatResult} from "./client.js";

test("token은 Authorization header에만 사용하고 body에 넣지 않는다", async () => {
  let captured;
  const body = await callIssueOperations({
    uri: "https://issue-read.example.run.app",
    token: "secret-token",
    command: {
      environment: "development",
      action: "listClusters",
      payload: {},
    },
  }, async (uri, init) => {
    captured = {uri, init};
    return {
      ok: true,
      async json() {
        return {result: {clusters: [], nextCursor: null}};
      },
    };
  });
  assert.deepEqual(body.result.clusters, []);
  assert.equal(captured.init.headers.authorization, "Bearer secret-token");
  assert.equal(captured.init.body.includes("secret-token"), false);
});

test("기본 출력은 allowlist cluster 요약만 표시한다", () => {
  const output = formatResult({
    result: {
      clusters: [{
        fingerprint: "a".repeat(40),
        stage: "seasonDiscovery",
        adapterScope: "platform",
        adapterKey: "cafe24",
        status: "open",
        occurrenceCount: 2,
      }],
      nextCursor: null,
    },
  }, false);
  assert.match(output, /seasonDiscovery platform cafe24 open occurrences=2/);
});
