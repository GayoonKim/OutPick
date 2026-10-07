import assert from "node:assert/strict";
import test from "node:test";
import {
  SourceBufferStore, usingSourceBytes, withSourceBufferScope,
} from "./source-buffer-store.js";
import {
  canonicalCandidateURL, resolveContentHashDedupe,
} from "../extraction/dedupe.js";

test("원본 보관 예산은 여러 실행을 합산하고 초과분은 기다리지 않는다", () => {
  const store = new SourceBufferStore(6);
  const a = store.openScope();
  const b = store.openScope();
  assert.equal(a.retain("url", "page", Buffer.alloc(4)), true);
  assert.equal(b.retain("url", "page", Buffer.alloc(3)), false);
  assert.equal(b.retain("url", "page", Buffer.alloc(2)), true);
  assert.equal(store.snapshot().retainedBytes, 6);
  a.close();
  assert.equal(b.retain("another", "page", Buffer.alloc(4)), true);
  assert.equal(store.snapshot().peakRetainedBytes, 6);
  b.close();
  assert.equal(store.snapshot().retainedBytes, 0);
  assert.equal(store.snapshot().openScopes, 0);
});

test("동일 원본도 실행과 요청 맥락이 다르면 재사용하지 않는다", () => {
  const store = new SourceBufferStore(null);
  const a = store.openScope();
  const b = store.openScope();
  const original = Buffer.from("hashed bytes");
  a.retain("url", "page-a", original);
  assert.equal(a.acquire("url", "page-b"), null);
  assert.equal(b.acquire("url", "page-a"), null);
  const lease = a.acquire("url", "page-a");
  assert.ok(lease);
  assert.equal(lease.bytes, original);
  lease.release();
  assert.throws(() => lease.bytes);
  lease.release();
  a.close(); b.close();
});

test("실행 종료 후에도 마지막 소비자까지 보관 예산을 유지한다", () => {
  const store = new SourceBufferStore(4);
  const scope = store.openScope();
  scope.retain("url", "page", Buffer.from("data"));
  const a = scope.acquire("url", "page");
  const b = scope.acquire("url", "page");
  assert.ok(a); assert.ok(b);
  scope.close(); scope.close();
  assert.equal(store.snapshot().openScopes, 0);
  assert.equal(store.snapshot().retainedBytes, 4);
  assert.equal(scope.acquire("url", "page"), null);
  const next = store.openScope();
  assert.equal(next.retain("next", "page", Buffer.alloc(1)), false);
  a.release();
  assert.equal(store.snapshot().retainedBytes, 4);
  assert.equal(b.bytes.toString(), "data");
  b.release();
  assert.equal(store.snapshot().retainedBytes, 0);
  assert.equal(next.retain("next", "page", Buffer.alloc(1)), true);
  next.close();
});

test("검토 대기 실패와 취소 종료는 보관을 닫고 늦은 게시를 거절한다",
  async () => {
    const store = new SourceBufferStore(100);
    for (const outcome of ["review", "failure", "cancelled"]) {
      const error = new Error(outcome);
      let late!: () => boolean;
      const operation = withSourceBufferScope(store, async (scope) => {
        assert.ok(scope);
        scope.retain("url", "page", Buffer.from("source"));
        late = () => scope.retain("late", "page", Buffer.from("late"));
        if (outcome !== "review") throw error;
        return "awaitingReview";
      });
      if (outcome === "review") assert.equal(await operation, "awaitingReview");
      else await assert.rejects(operation, (e) => e === error);
      assert.equal(late(), false);
      assert.equal(store.snapshot().retainedBytes, 0);
      assert.equal(store.snapshot().openScopes, 0);
    }
  });

test("중복 후보 제거는 불필요한 보관을 해제하되 대여 바이트를 유지한다",
  () => {
    const store = new SourceBufferStore(20);
    const scope = store.openScope();
    scope.retain("first", "page", Buffer.alloc(4));
    scope.retain("duplicate", "page", Buffer.alloc(4));
    const lease = scope.acquire("duplicate", "page");
    assert.ok(lease);
    scope.retainOnly(new Set(["first"]), "page");
    assert.equal(scope.acquire("duplicate", "page"), null);
    assert.equal(store.snapshot().retainedBytes, 8);
    lease.release();
    assert.equal(store.snapshot().retainedBytes, 4);
    scope.close();
  });

test("미보관분은 재다운로드하고 실패 응답과 저장 실패는 바이트를 남기지 않는다",
  async () => {
    for (const budget of [0, 100]) {
      const store = new SourceBufferStore(budget);
      let downloads = 0;
      const failure = new Error("저장 실패");
      await assert.rejects(withSourceBufferScope(store, async (scope) => {
        scope?.retain("url", "page", Buffer.from("source"));
        return usingSourceBytes(scope, "url", "page", async () => {
          downloads++;
          return Buffer.from("downloaded");
        }, async () => {
          throw failure;
        });
      }), (e) => e === failure);
      assert.equal(downloads, budget === 0 ? 1 : 0);
      assert.equal(store.snapshot().retainedBytes, 0);
      await assert.rejects(withSourceBufferScope(store, (scope) =>
        usingSourceBytes(scope, "missing", "page", async () => {
          throw new Error("HTTP 실패");
        }, async () => assert.fail("실패 응답 사용 금지"))));
      assert.equal(store.snapshot().retainedBytes, 0);
    }
  });

test("같은 실행은 해시 원본을 유지하고 새 실행은 변경된 원본을 받는다",
  async () => {
    const store = new SourceBufferStore(null);
    await withSourceBufferScope(store, async (scope) => {
      assert.ok(scope);
      scope.retain("url", "page", Buffer.from("old"));
      assert.equal(scope.retain("url", "page", Buffer.from("new")), false);
      const result = await usingSourceBytes(scope, "url", "page",
        async () => Buffer.from("new"), async (bytes) => bytes.toString());
      assert.equal(result, "old");
    });
    await withSourceBufferScope(store, async (scope) => {
      const result = await usingSourceBytes(scope, "url", "page",
        async () => Buffer.from("new"), async (bytes) => bytes.toString());
      assert.equal(result, "new");
    });
  });

test("해시 성공 원본만 게시하고 중복 제거 후 첫 후보 바이트를 재사용한다",
  async () => {
    const store = new SourceBufferStore(100);
    await withSourceBufferScope(store, async (scope) => {
      assert.ok(scope);
      const candidates = [0, 1, 2].map((n) => ({sourceURL: `https://x.test/${n}`}));
      const original = Buffer.from("same bytes");
      const result = await resolveContentHashDedupe({
        candidates,
        loadBytes: async (candidate) => {
          if (candidate === candidates[2]) throw new Error("HTTP 오류");
          return original;
        },
        onHashedBytes: (candidate, bytes) => {
          if (Buffer.isBuffer(bytes)) {
            scope.retain(canonicalCandidateURL(candidate.sourceURL),
              "page", bytes);
          }
        },
      });
      scope.retainOnly(new Set(result.candidates.map((c) =>
        canonicalCandidateURL(c.sourceURL))), "page");
      assert.equal(store.snapshot().retainedBytes, original.length);
      const lease = scope.acquire(candidates[0].sourceURL, "page");
      assert.ok(lease);
      assert.equal(lease.bytes, original);
      lease.release();
      assert.equal(scope.acquire(candidates[2].sourceURL, "page"), null);
    });
  });

test("보관 예산 off 전체 보관과 잘못된 수치를 구분한다", () => {
  for (const value of [-1, 0.5, NaN, Infinity]) {
    assert.throws(() => new SourceBufferStore(value));
  }
  for (const limit of [128, 256, 512, null]) {
    const store = new SourceBufferStore(limit === null ? null : limit * 2**20);
    const scope = store.openScope();
    assert.equal(scope.retain("empty", "page", Buffer.alloc(0)), false);
    assert.equal(scope.retain("one", "page", Buffer.alloc(1)), true);
    scope.close();
  }
});

test("종료 뒤 완료된 실제 해시 다운로드는 보관을 다시 만들지 않는다",
  async () => {
    const store = new SourceBufferStore(100);
    const scope = store.openScope();
    let complete!: (bytes: Buffer) => void;
    const downloaded = new Promise<Buffer>((resolve) => {
      complete = resolve;
    });
    const work = resolveContentHashDedupe({
      candidates: [{sourceURL: "https://x.test/late"}],
      loadBytes: () => downloaded,
      onHashedBytes: (candidate, bytes) => {
        if (Buffer.isBuffer(bytes)) {
          scope.retain(candidate.sourceURL, "page", bytes);
        }
      },
    });
    scope.close();
    complete(Buffer.from("late bytes"));
    assert.equal((await work).complete, true);
    assert.equal(store.snapshot().retainedBytes, 0);
    assert.equal(store.snapshot().openScopes, 0);
  });
