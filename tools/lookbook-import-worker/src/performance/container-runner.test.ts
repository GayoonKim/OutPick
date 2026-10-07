import assert from "node:assert/strict";
import {mkdtemp, readFile, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";
import {makeComparisonPlan, runComparison} from "./comparison.js";
import {runContainer, validateContainerPayload} from "./container-runner.js";
import {runOverhead} from "./overhead.js";

const plan = makeComparisonPlan({sourceRevision: "a".repeat(40),
  sourceDigest: "b".repeat(64), inputDigest: "c".repeat(64)})[0];
const imageID = `sha256:${"d".repeat(64)}`;
const containerID = "e".repeat(64);
const result = () => runComparison(plan, async (phase) => ({status:
  phase === "local-extraction" ? "needs-review" : "succeeded"}),
{maxSampleGapMs: 500, readMemory: async () =>
  ({source: "cgroup-v2", usedBytes: 1, limitBytes: 2 * 2**30})});

async function scenario(input: {
  payload?: unknown; exit?: number; oom?: boolean; fail?: string;
  inputVolume?: string; kind?: "comparison" | "overhead";
}) {
  const root = await mkdtemp(join(tmpdir(), "lookbook-container-test-"));
  const commands: string[][] = [];
  try {
    const finished = await runContainer(plan, {imageID, inputDirectory: root,
      outputParent: root, inputVolume: input.inputVolume, kind: input.kind,
      command: async (args) => {
        commands.push(args);
        assert.ok(JSON.parse(await readFile(join(root, plan.id, "started.json"),
          "utf8")).startedAt);
        if (args[0] === input.fail) throw new Error("명령 실패");
        if (args[0] === "image") return `${imageID} arm64 linux`;
        if (args[0] === "volume") return input.inputVolume ?? "";
        if (args[0] === "create") return containerID;
        if (args[0] === "wait") {
          if (input.payload !== undefined) {
            await writeFile(join(root, plan.id, "result.json"),
              JSON.stringify(input.payload));
          }
          return String(input.exit ?? 0);
        }
        if (args[0] === "inspect") {
          return JSON.stringify({Status: "exited",
            Running: false, OOMKilled: input.oom ?? false,
            ExitCode: input.exit ?? 0});
        }
        return "";
      }});
    assert.deepEqual(JSON.parse(await readFile(
      join(root, plan.id, "finished.json"), "utf8")), finished);
    return {finished, commands};
  } finally {
    await rm(root, {recursive: true, force: true});
  }
}

test("외부 감독은 고정 컨테이너 조건과 시작 종료 증거를 기록한다", async () => {
  const {finished, commands} = await scenario({payload: await result()});
  assert.equal(finished.verdict, "succeeded");
  const create = commands.find((args) => args[0] === "create");
  assert.ok(create);
  for (const option of ["--cpus=1", "--memory=2g", "--memory-swap=2g",
    "--network=none"]) assert.ok(create.includes(option));
  assert.ok(create.includes(imageID));
  assert.deepEqual(commands.at(-1), ["rm", containerID]);
});

test("외부 감독은 Linux 입력 volume과 오버헤드 결과를 별도로 확인한다",
  async () => {
    const payload = await runOverhead(plan,
      async () => ({status: "succeeded"}),
      {maxSampleGapMs: 500, readMemory: async () =>
        ({source: "cgroup-v2", usedBytes: 1, limitBytes: 2 * 2**30})});
    const {finished, commands} = await scenario({payload,
      inputVolume: "lookbook-test", kind: "overhead"});
    assert.equal(finished.verdict, "succeeded");
    const create = commands.find((args) => args[0] === "create");
    assert.ok(create?.includes(
      "type=volume,src=lookbook-test,dst=/input,readonly"));
    assert.ok(create?.includes("lib/performance/overhead-entry.js"));
    assert.equal((await scenario({payload})).finished.verdict, "failed");
    assert.equal((await scenario({payload: await result(), kind: "overhead"}))
      .finished.verdict, "failed");
  });

test("외부 감독은 OOM 비정상 종료와 누락 결과를 성공으로 기록하지 않는다",
  async () => {
    const payload = await result();
    assert.equal((await scenario({payload, exit: 137, oom: true}))
      .finished.verdict, "aborted");
    assert.equal((await scenario({payload, exit: 1})).finished.verdict,
      "failed");
    assert.equal((await scenario({})).finished.verdict, "failed");
    const invalid = {...payload, id: "other-run"};
    assert.equal((await scenario({payload: invalid})).finished.verdict,
      "failed");
    assert.equal(validateContainerPayload(plan,
      {...payload, memory: {...payload.memory, limitBytes: 1}}), false);
  });

test("외부 감독은 도구 실패를 보존하고 종료 미확인 컨테이너를 삭제하지 않는다",
  async () => {
    const missing = await scenario({fail: "image"});
    assert.equal(missing.finished.verdict, "unavailable");
    const unknown = await scenario({fail: "wait"});
    assert.equal(unknown.finished.verdict, "failed");
    assert.equal(unknown.finished.stage, "wait");
    assert.equal(unknown.commands.some((args) => args[0] === "rm"), false);
  });

test("외부 감독은 정상 종료 코드여도 감독 중단과 환경 미준비를 보존한다",
  async () => {
    const unavailable = await runComparison(plan,
      async () => assert.fail("실행 불가"),
      {maxSampleGapMs: 500, readMemory: async () => null});
    const before = await scenario({payload: unavailable});
    assert.equal(before.finished.verdict, "unavailable");
    const stopped = {...unavailable, memory: {...unavailable.memory,
      stop: {reason: "memory", detail: "sustained-high", atMs: 1000}},
    results: unavailable.results.map((row) =>
      ({...row, outcome: "aborted", reason: "memory"}))};
    const after = await scenario({payload: stopped});
    assert.equal(after.finished.verdict, "aborted");
    assert.equal(after.finished.reason, "memory");
  });

test("외부 감독은 mutable 이미지 태그와 기존 결과 덮어쓰기를 거절한다",
  async () => {
    const root = await mkdtemp(join(tmpdir(), "lookbook-output-test-"));
    try {
      await assert.rejects(runContainer(plan, {imageID: "latest",
        inputDirectory: root, outputParent: root}));
      await runContainer(plan, {imageID, inputDirectory: root,
        outputParent: root, command: async () => {
          throw new Error("미준비");
        }});
      await assert.rejects(runContainer(plan, {imageID, inputDirectory: root,
        outputParent: root, command: async () => assert.fail("덮어쓰기 불가")}));
    } finally {
      await rm(root, {recursive: true, force: true});
    }
  });
