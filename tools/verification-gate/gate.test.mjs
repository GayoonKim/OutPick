import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {mkdtemp, mkdir, readFile, rm, writeFile, access} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {parseJSON, readNodeResults, parseXcodeResults, validateConfig} from "./gate.mjs";

const gate = fileURLToPath(new URL("./gate.mjs", import.meta.url));
const reporter = fileURLToPath(new URL("./node-reporter.mjs", import.meta.url));

async function fixture(t, checks, inputs = ["src", "verification"]) {
  const root = await mkdtemp(join(tmpdir(), "outpick-gate-test-"));
  t.after(() => rm(root, {recursive: true, force: true}));
  await mkdir(join(root, "src"));
  await mkdir(join(root, "verification"));
  await writeFile(join(root, ".gitignore"), "output/\n");
  await writeFile(join(root, "src", "case.test.mjs"), 'import test from "node:test";\ntest("필수 성공", () => {});\n');
  const config = {version: 1, runTimeoutMs: 5000, inputs, checks};
  await writeFile(join(root, "verification", "gate.json"), JSON.stringify(config));
  for (const args of [["init", "-q"], ["add", "."], ["-c", "user.name=Gate", "-c", "user.email=gate@example.invalid", "commit", "-qm", "fixture"]]) {
    const result = spawnSync("git", args, {cwd: root, encoding: "utf8"});
    assert.equal(result.status, 0, result.stderr);
  }
  return {root, config};
}

function command(id, code = "process.exit(0)") {
  return {id, command: process.execPath, args: ["-e", code], cwd: ".", timeoutMs: 3000, kind: "command"};
}

function nodeCheck(name = "필수 성공") {
  return {id: "node", command: process.execPath, args: ["--test", "src/case.test.mjs", "--test-reporter", reporter,
    "--test-reporter-destination", "PLACEHOLDER"], cwd: ".", timeoutMs: 3000, kind: "node",
    requiredTests: [`src/case.test.mjs::${name}`], reportNames: ["main"]};
}

async function run(root) {
  const result = spawnSync(process.execPath, [gate, "--project", root, "--config", "verification/gate.json"], {
    cwd: root, encoding: "utf8", timeout: 15000,
  });
  assert.equal(result.error, undefined);
  const line = result.stdout.trim().split("\n").at(-1);
  const status = JSON.parse(line);
  const summary = JSON.parse(await readFile(status.summary, "utf8"));
  return {result, status, summary};
}

test("정상 명령은 실행 상태와 원본 로그를 기록한다", async (t) => {
  const {root} = await fixture(t, [command("okay", 'console.log("실행됨")')]);
  const {result, status, summary} = await run(root);
  assert.equal(result.status, 0);
  assert.equal(status.verdict, "passed");
  assert.equal(summary.checks.length, 1);
  assert.match(await readFile(join(summary.runDir, "okay", "stdout.log"), "utf8"), /실행됨/);
  assert.equal(summary.source.fileCount > 0, true);
});

test("실패한 독립 검사 이후 검사도 실행하고 실패를 보존한다", async (t) => {
  const {root} = await fixture(t, [command("bad", "process.exit(3)"), command("other", 'console.log("continued")')]);
  const {result, summary} = await run(root);
  assert.equal(result.status, 1);
  assert.equal(summary.checks.length, 2);
  assert.match(summary.failures.join(" "), /bad/);
  assert.match(await readFile(join(summary.runDir, "other", "stdout.log"), "utf8"), /continued/);
});

test("없는 실행 파일과 시간 초과는 차단한다", async (t) => {
  const {root, config} = await fixture(t, [command("missing")]);
  config.checks[0].command = "gate-nonexistent-command-xyz";
  await writeFile(join(root, "verification", "gate.json"), JSON.stringify(config));
  let checked = await run(root);
  assert.equal(checked.result.status, 2);
  assert.match(checked.summary.blockers.join(" "), /검사 실행 불가/);
  config.checks = [command("slow", "setTimeout(() => {}, 5000)")];
  config.checks[0].timeoutMs = 100;
  await writeFile(join(root, "verification", "gate.json"), JSON.stringify(config));
  checked = await run(root);
  assert.equal(checked.result.status, 2);
  assert.match(checked.summary.blockers.join(" "), /검사 시간 초과/);
});

test("설정 오류는 외부 명령 실행 전에 거절한다", async (t) => {
  const {root, config} = await fixture(t, [command("touch", 'process.stdout.write("should not run")')]);
  config.checks[0].timeoutMs = 0;
  await writeFile(join(root, "verification", "gate.json"), JSON.stringify(config));
  const result = spawnSync(process.execPath, [gate, "--project", root, "--config", "verification/gate.json"], {encoding: "utf8"});
  assert.equal(result.status, 2);
  assert.match(result.stderr, /양의 정수/);
  assert.equal(result.stdout, "");
  assert.throws(() => parseJSON('{"x":1,"x":2}'), /중복 JSON 키/);
  assert.throws(() => validateConfig({...config, extra: 1}), /알 수 없는 필드/);
});

test("검사 중 입력이 변하면 결과를 차단한다", async (t) => {
  const {root} = await fixture(t, [command("mutate", 'require("node:fs").writeFileSync("src/case.test.mjs", "changed")')]);
  const {result, summary} = await run(root);
  assert.equal(result.status, 2);
  assert.match(summary.blockers.join(" "), /입력\/설정\/실행기 변경/);
});

test("Node 구조화 결과에서 필수 실행을 검증한다", async (t) => {
  const {root, config} = await fixture(t, [nodeCheck()]);
  // 일반 CLI에는 검사별 결과 경로가 실행 시 결정되므로 테스트용 runner가 환경 변수를 사용한다.
  config.checks[0].args = ["-e", `const {spawnSync}=require('node:child_process'); const r=spawnSync(process.execPath,['--test','--test-reporter',process.env.OUTPICK_GATE_REPORTER_PATH,'--test-reporter-destination',process.env.OUTPICK_GATE_RESULT_PATH,'src/case.test.mjs'],{stdio:'inherit'});process.exit(r.status??1)`];
  await writeFile(join(root, "verification", "gate.json"), JSON.stringify(config));
  let checked = await run(root);
  assert.equal(checked.result.status, 0, checked.result.stderr + checked.result.stdout + await readFile(join(checked.summary.runDir, "node", "stderr.log"), "utf8") + await readFile(join(checked.summary.runDir, "node", "node-result.jsonl"), "utf8"));
  config.checks[0].requiredTests = ["src/case.test.mjs::없는 테스트"];
  await writeFile(join(root, "verification", "gate.json"), JSON.stringify(config));
  checked = await run(root);
  assert.equal(checked.result.status, 2);
  assert.match(checked.summary.blockers.join(" "), /필수 테스트 누락/);
});

test("실제 Node assertion 실패를 게이트 실패로 반환한다", async (t) => {
  const {root, config} = await fixture(t, [nodeCheck()]);
  await writeFile(join(root, "src", "case.test.mjs"), 'import test from "node:test";\nimport assert from "node:assert/strict";\ntest("필수 성공", () => assert.equal(1, 2));\n');
  config.checks[0].args = ["-e", `const {spawnSync}=require('node:child_process'); const r=spawnSync(process.execPath,['--test','--test-reporter',process.env.OUTPICK_GATE_REPORTER_PATH,'--test-reporter-destination',process.env.OUTPICK_GATE_RESULT_PATH,'src/case.test.mjs'],{stdio:'inherit'});process.exit(r.status??1)`];
  await writeFile(join(root, "verification", "gate.json"), JSON.stringify(config));
  const {result, summary} = await run(root);
  assert.equal(result.status, 1);
  assert.match(summary.failures.join(" "), /테스트 실패/);
  assert.equal(summary.checks[0].executedTests, 1);
  const raw = await readFile(join(summary.runDir, "node", "node-result.jsonl"), "utf8");
  assert.match(raw, /ERR_ASSERTION/);
  assert.match(raw, /expected: 2/);
});

test("검사 전 정상적으로 삭제한 추적 파일도 입력으로 식별한다", async (t) => {
  const {root} = await fixture(t, [command("okay")]);
  await rm(join(root, "src", "case.test.mjs"));
  const {result} = await run(root);
  assert.equal(result.status, 0);
});

test("명시한 ignored 입력 파일도 변경을 감지하고 내용은 요약에 노출하지 않는다", async (t) => {
  const {root} = await fixture(t, [command("mutate", 'require("node:fs").writeFileSync("local.txt","changed")')], ["src", "verification", "local.txt"]);
  await writeFile(join(root, ".gitignore"), "output/\nlocal.txt\n");
  await writeFile(join(root, "local.txt"), "private-fixture-value");
  const {result, summary} = await run(root);
  assert.equal(result.status, 2);
  assert.match(summary.blockers.join(" "), /입력\/설정\/실행기 변경/);
  assert.equal(JSON.stringify(summary).includes("private-fixture-value"), false);
});

test("시간 초과 시 SIGTERM을 무시하는 자손도 정리한다", async (t) => {
  const descendant = 'process.on("SIGTERM",()=>{});setTimeout(()=>require("node:fs").writeFileSync("escaped.txt","escaped"),2000)';
  const parent = `const cp=require('node:child_process');cp.spawn(process.execPath,['-e',${JSON.stringify(descendant)}],{stdio:'ignore'});setTimeout(()=>{},5000)`;
  const check = command("slow", parent);
  check.timeoutMs = 500;
  const {root} = await fixture(t, [check]);
  const {result, summary} = await run(root);
  assert.equal(result.status, 2);
  assert.match(summary.blockers.join(" "), /시간 초과/);
  await new Promise((done) => setTimeout(done, 1100));
  await assert.rejects(access(join(root, "escaped.txt")), {code: "ENOENT"});
});

test("Node 주 버전이 다르면 실행하지 않고 차단한다", async (t) => {
  const {root, config} = await fixture(t, [command("version")]);
  config.checks[0].nodeMajor = 999;
  await writeFile(join(root, "verification", "gate.json"), JSON.stringify(config));
  const {result, summary} = await run(root);
  assert.equal(result.status, 2);
  assert.match(summary.blockers.join(" "), /Node 999 환경/);
  assert.equal(summary.checks[0].endedAt, undefined);
});

test("skip, 0개, 손상, 중복 결과를 차단하고 실제 실패를 기록한다", async (t) => {
  const {root} = await fixture(t, [command("noop")]);
  const path = join(root, "events.jsonl");
  const id = "src/case.test.mjs::필수 성공";
  const event = (type, name, skip = null) => JSON.stringify({type, name, file: join(root, "src/case.test.mjs"), suite: false, skip, todo: null});
  const summary = JSON.stringify({type: "test:summary", counts: {tests: 1, failed: 0, skipped: 0, todo: 0, cancelled: 0}});
  const parse = async (data) => { await writeFile(path, data); return readNodeResults(root, [path], [id]); };
  assert.match((await parse(event("test:pass", "필수 성공", "보류") + "\n" + summary)).blockers.join(" "), /skipped/);
  assert.match((await parse(JSON.stringify({type: "test:summary", counts: {tests: 0}}))).blockers.join(" "), /0개/);
  assert.match((await parse("broken")).blockers.join(" "), /손상/);
  assert.match((await parse(event("test:pass", "필수 성공") + "\n" + event("test:pass", "필수 성공") + "\n" + summary)).blockers.join(" "), /중복/);
  const failed = await parse(event("test:fail", "필수 성공") + "\n" + JSON.stringify({type: "test:summary", counts: {tests: 1, failed: 1}}));
  assert.match(failed.failures.join(" "), /테스트 실패/);
  const brokenCounts = await parse(event("test:pass", "필수 성공") + "\n" + JSON.stringify({type: "test:summary", counts: {tests: 1, passed: 1, failed: "invalid"}}));
  assert.match(brokenCounts.blockers.join(" "), /잘못된 요약 수치/);
});

test("Xcode 필수 테스트의 assertion 실패와 누락·skip을 구분한다", () => {
  const data = (result) => ({testNodes: [{nodeType: "Test Case", nodeIdentifier: "Suite/example()", result}]});
  const ids = ["Suite/example()"];
  const failed = parseXcodeResults(data("Failed"), ids);
  assert.equal(failed.failures.length, 1);
  assert.equal(failed.blockers.length, 0);
  const passed = parseXcodeResults(data("Passed"), ids);
  assert.equal(passed.failures.length + passed.blockers.length, 0);
  assert.match(parseXcodeResults(data("Skipped"), ids).blockers.join(" "), /미실행/);
  assert.match(parseXcodeResults({testNodes: []}, ids).blockers.join(" "), /누락/);
  assert.match(parseXcodeResults({testNodes: []}, []).blockers.join(" "), /0개/);
});
