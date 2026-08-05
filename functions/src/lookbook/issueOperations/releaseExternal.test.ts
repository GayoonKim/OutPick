import assert from "node:assert/strict";
import test from "node:test";

import {activeTrafficStatuses} from "./releaseExternal.js";
import {sourceJob} from "./releaseService.js";

test("Cloud Run traffic에서 tag만 남은 0% revision은 제외한다", () => {
  assert.deepEqual(activeTrafficStatuses([
    {revision: "worker-00001-old", tag: "old"},
    {revision: "worker-00002-old", percent: 0, tag: "candidate"},
    {revision: "worker-00003-new", percent: 100},
  ]), [
    {revision: "worker-00003-new", percent: 100},
  ]);
});

test("유효하지 않은 traffic 응답은 활성 revision으로 인정하지 않는다", () => {
  assert.deepEqual(activeTrafficStatuses(null), []);
  assert.deepEqual(activeTrafficStatuses([
    null,
    {revision: "", percent: 100},
    {revision: "worker-00003-new", percent: "100"},
  ]), []);
});

test("대표 job이 삭제됐으면 같은 fingerprint의 현존 job을 검증 입력으로 사용한다", async () => {
  const fallbackPath = "brands/current/seasonDiscoveryJobs/current-job";
  const firestore = {
    doc: () => ({get: async () => ({exists: false, data: () => undefined})}),
    collectionGroup: () => ({
      where: () => ({
        limit: () => ({
          get: async () => ({docs: [{
            ref: {path: fallbackPath},
            data: () => ({
              extractionIssueFingerprint: "a".repeat(40),
              sourceArchiveURL: "https://brand.example/archive",
            }),
          }]}),
        }),
      }),
    }),
  };

  assert.deepEqual(await sourceJob(firestore as never, {
    fingerprint: "a".repeat(40),
    representativeJobPath: "brands/deleted/seasonDiscoveryJobs/deleted-job",
  }, "seasonDiscovery"), {
    jobPath: fallbackPath,
    sourceURL: "https://brand.example/archive",
  });
});
