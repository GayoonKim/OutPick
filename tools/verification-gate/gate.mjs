import {spawn, spawnSync} from "node:child_process";
import {createHash, randomUUID} from "node:crypto";
import {createWriteStream, realpathSync} from "node:fs";
import {finished} from "node:stream/promises";
import {lstat, mkdir, readFile, writeFile} from "node:fs/promises";
import {dirname, isAbsolute, join, relative, resolve, sep} from "node:path";
import {fileURLToPath} from "node:url";

const ownDirectory = dirname(fileURLToPath(import.meta.url));
const reporterPath = join(ownDirectory, "node-reporter.mjs");
const states = {passed: 0, failed: 1, blocked: 2};

function assert(condition, reason) {
  if (!condition) throw new Error(reason);
}

function strictKeys(object, allowed, where) {
  assert(object && typeof object === "object" && !Array.isArray(object), `${where}: 객체가 필요합니다`);
  for (const key of Object.keys(object)) assert(allowed.includes(key), `${where}: 알 수 없는 필드 ${key}`);
}

// JSON.parse가 중복 키를 덮어쓰기 전에 각 객체의 키를 검사한다.
function rejectDuplicateJSONKeys(source) {
  let cursor = 0;
  const space = () => { while (/\s/.test(source[cursor] ?? "")) cursor++; };
  const string = () => {
    const start = cursor++;
    while (cursor < source.length) {
      if (source[cursor] === "\\") cursor += 2;
      else if (source[cursor++] === "\"") return JSON.parse(source.slice(start, cursor));
    }
    throw new Error("끝나지 않은 JSON 문자열");
  };
  const value = (depth = 0) => {
    assert(depth < 128, "JSON 중첩이 너무 깊습니다");
    space();
    if (source[cursor] === "{") {
      cursor++;
      const seen = new Set();
      space();
      while (source[cursor] !== "}" && cursor < source.length) {
        assert(source[cursor] === "\"", "JSON 키 오류");
        const key = string();
        assert(!seen.has(key), `중복 JSON 키: ${key}`);
        seen.add(key);
        space();
        assert(source[cursor++] === ":", "JSON 구분자 오류");
        value(depth + 1);
        space();
        if (source[cursor] === ",") { cursor++; space(); }
        else break;
      }
      assert(source[cursor++] === "}", "JSON 객체 종료 오류");
    } else if (source[cursor] === "[") {
      cursor++;
      space();
      while (source[cursor] !== "]" && cursor < source.length) {
        value(depth + 1);
        space();
        if (source[cursor] === ",") { cursor++; space(); }
        else break;
      }
      assert(source[cursor++] === "]", "JSON 배열 종료 오류");
    } else if (source[cursor] === "\"") string();
    else {
      const match = /^(?:-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null)/.exec(source.slice(cursor));
      assert(match, "JSON 값 오류");
      cursor += match[0].length;
    }
  };
  value();
  space();
  assert(cursor === source.length, "JSON 뒤에 추가 데이터가 있습니다");
}

function parseJSON(source) {
  rejectDuplicateJSONKeys(source);
  return JSON.parse(source);
}

function positiveNumber(value, where) {
  assert(Number.isSafeInteger(value) && value > 0, `${where}: 양의 정수가 필요합니다`);
}

function safeRelativePath(value, where) {
  assert(typeof value === "string" && value.length > 0 && !isAbsolute(value), `${where}: 상대 경로가 필요합니다`);
  assert(!value.split(/[\\/]/).some((part) => part === ".." || part === ""), `${where}: 허용하지 않는 경로`);
  assert(!value.startsWith(":"), `${where}: Git 경로 지정이 허용되지 않습니다`);
  return value;
}

function validateConfig(config) {
  strictKeys(config, ["version", "runTimeoutMs", "inputs", "checks"], "설정");
  assert(config.version === 1, "지원하지 않는 설정 버전");
  positiveNumber(config.runTimeoutMs, "전체 시간 한도");
  assert(Array.isArray(config.inputs) && config.inputs.length > 0, "입력 경로가 비어 있습니다");
  for (const input of config.inputs) safeRelativePath(input, "입력 경로");
  assert(new Set(config.inputs).size === config.inputs.length, "중복 입력 경로");
  assert(Array.isArray(config.checks) && config.checks.length > 0, "필수 검사 목록이 비어 있습니다");
  const ids = new Set();
  for (const check of config.checks) {
    strictKeys(check, ["id", "command", "args", "cwd", "timeoutMs", "kind", "requiredTests", "reportNames", "nodeMajor"], "검사");
    assert(typeof check.id === "string" && /^[a-z0-9][a-z0-9_-]*$/.test(check.id), "검사 ID 오류");
    assert(!ids.has(check.id), `중복 검사 ID: ${check.id}`);
    ids.add(check.id);
    assert(typeof check.command === "string" && check.command.length > 0, `${check.id}: 실행 파일 누락`);
    assert(Array.isArray(check.args) && check.args.every((arg) => typeof arg === "string"), `${check.id}: 인자 오류`);
    safeRelativePath(check.cwd, `${check.id}: 작업 경로`);
    positiveNumber(check.timeoutMs, `${check.id}: 시간 한도`);
    if (check.nodeMajor !== undefined) positiveNumber(check.nodeMajor, `${check.id}: Node 주 버전`);
    assert(["command", "node", "xcresult"].includes(check.kind), `${check.id}: 미지원 결과 형식`);
    if (check.kind === "command") {
      assert(check.requiredTests === undefined && check.reportNames === undefined, `${check.id}: 명령 검사는 테스트 결과 항목이 없습니다`);
    } else {
      assert(Array.isArray(check.requiredTests) && check.requiredTests.length > 0 && check.requiredTests.every((id) => typeof id === "string" && id.length > 0), `${check.id}: 필수 테스트 ID 누락`);
      assert(new Set(check.requiredTests).size === check.requiredTests.length, `${check.id}: 중복 필수 테스트 ID`);
      if (check.kind === "node") {
        assert(Array.isArray(check.reportNames) && check.reportNames.length > 0, `${check.id}: 결과 파일 목록 누락`);
        assert(check.reportNames.every((name) => /^[a-z0-9][a-z0-9_-]*$/.test(name)), `${check.id}: 결과 파일 이름 오류`);
        assert(new Set(check.reportNames).size === check.reportNames.length, `${check.id}: 중복 결과 파일 이름`);
      } else assert(check.reportNames === undefined, `${check.id}: Xcode 결과 이름 오류`);
    }
  }
  return config;
}

async function sourceIdentity(project, configPath, inputs) {
  const explicitFiles = [];
  for (const input of inputs) {
    const stat = await lstat(join(project, input));
    if (stat.isFile()) explicitFiles.push(input);
  }
  const listed = spawnSync("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", ...inputs], {
    cwd: project, encoding: "buffer", maxBuffer: 64 * 1024 * 1024, timeout: 30000,
  });
  assert(!listed.error && listed.status === 0, "Git 입력 목록을 읽을 수 없습니다");
  const files = new Set(listed.stdout.toString("utf8").split("\0").filter(Boolean));
  for (const file of explicitFiles) files.add(file);
  files.add(relative(project, configPath));
  assert(files.size > 0, "검사할 입력 파일이 없습니다");
  const hash = createHash("sha256");
  for (const file of [...files].sort()) {
    safeRelativePath(file, "Git 파일");
    const path = join(project, file);
    const stat = await lstat(path).catch((error) => {
      if (error.code === "ENOENT") return null;
      throw error;
    });
    if (!stat) {
      hash.update(file).update("\0deleted\0");
      continue;
    }
    assert(stat.isFile(), `${file}: 일반 파일만 검사 입력으로 지원합니다`);
    hash.update(file).update("\0").update(await readFile(path)).update("\0");
  }
  for (const path of [fileURLToPath(import.meta.url), reporterPath, join(ownDirectory, "gate.test.mjs")]) {
    hash.update(path).update("\0").update(await readFile(path)).update("\0");
  }
  const head = spawnSync("git", ["rev-parse", "HEAD"], {cwd: project, encoding: "utf8", timeout: 30000});
  assert(!head.error && head.status === 0, "Git 기준 버전을 읽을 수 없습니다");
  return {head: head.stdout.trim(), digest: hash.digest("hex"), fileCount: files.size};
}

const pendingStops = new WeakMap();
function stopProcess(child) {
  if (!child?.pid) return Promise.resolve();
  if (pendingStops.has(child)) return pendingStops.get(child);
  try { process.kill(-child.pid, "SIGTERM"); }
  catch { try { child.kill("SIGTERM"); } catch {} }
  const stopped = new Promise((done) => setTimeout(() => {
    try { process.kill(-child.pid, "SIGKILL"); }
    catch { try { child.kill("SIGKILL"); } catch {} }
    done();
  }, 1000));
  pendingStops.set(child, stopped);
  return stopped;
}

async function execute(command, args, options) {
  const {cwd, env, timeoutMs, stdoutPath, stderrPath, onSpawn} = options;
  const out = createWriteStream(stdoutPath, {flags: "wx"});
  const err = createWriteStream(stderrPath, {flags: "wx"});
  const child = spawn(command, args, {cwd, env, shell: false, detached: true, stdio: ["ignore", "pipe", "pipe"]});
  onSpawn?.(child);
  const streamsDone = Promise.all([finished(out), finished(err)]).catch((error) => {
    stopProcess(child);
    return error;
  });
  child.stdout.pipe(out);
  child.stderr.pipe(err);
  let timedOut = false;
  const timer = setTimeout(() => { timedOut = true; stopProcess(child); }, timeoutMs);
  const result = await new Promise((resolveResult) => {
    child.once("error", (error) => resolveResult({error: error.message}));
    child.once("close", (code, signal) => resolveResult({code, signal}));
  });
  clearTimeout(timer);
  const streamError = await streamsDone;
  await pendingStops.get(child);
  if (streamError instanceof Error) throw streamError;
  return {...result, timedOut};
}

function nodeTestID(project, file, name) {
  assert(typeof file === "string" && typeof name === "string", "테스트 식별 정보 누락");
  const rel = relative(realpathSync(project), realpathSync(file)).split(sep).join("/");
  safeRelativePath(rel, "테스트 파일");
  return `${rel}::${name}`;
}

async function readNodeResults(project, paths, requiredTests) {
  const observed = new Map();
  const failures = [];
  const blockers = [];
  let executed = 0;
  for (const path of paths) {
    let raw;
    try { raw = await readFile(path, "utf8"); }
    catch { blockers.push(`원본 결과 누락: ${path}`); continue; }
    const lines = raw.trim().split("\n");
    let summary = null;
    let individualTests = 0;
    const counts = {passed: 0, failed: 0, skipped: 0, todo: 0};
    for (const line of lines) {
      let event;
      try { event = parseJSON(line); }
      catch { blockers.push(`원본 결과 손상: ${path}`); break; }
      if (event.type === "test:summary") { summary = event.counts; continue; }
      if (!["test:pass", "test:fail"].includes(event.type) || event.suite) continue;
      individualTests++;
      let id;
      try { id = nodeTestID(project, event.file, event.name); }
      catch { blockers.push(`테스트 ID 해석 불가: ${path}`); continue; }
      if (observed.has(id)) blockers.push(`중복 테스트 ID: ${id}`);
      const state = event.skip != null ? "skipped" : event.todo != null ? "todo" : event.type === "test:fail" ? "failed" : "passed";
      counts[state]++;
      observed.set(id, state);
      if (state === "failed") failures.push(`테스트 실패: ${id}`);
      if (state === "skipped" || state === "todo") blockers.push(`미실행 테스트 ${state}: ${id}`);
      if (state === "passed" || state === "failed") executed++;
    }
    if (!summary || !Number.isInteger(summary.tests) || summary.tests < 1) blockers.push(`테스트 요약 누락/0개: ${path}`);
    else if (summary.tests !== individualTests) blockers.push(`요약과 개별 테스트 수 불일치: ${path}`);
    for (const name of ["passed", "failed", "skipped", "todo", "cancelled"]) {
      if (!Number.isSafeInteger(summary?.[name]) || summary[name] < 0) blockers.push(`잘못된 요약 수치 ${name}: ${path}`);
      else if (name !== "cancelled" && summary[name] !== counts[name]) blockers.push(`요약과 개별 상태 불일치 ${name}: ${path}`);
    }
    if (summary?.skipped > 0 || summary?.todo > 0) blockers.push(`건너뛴 테스트: ${path}`);
    if (summary?.cancelled > 0) blockers.push(`중단된 테스트: ${path}`);
  }
  if (executed === 0) blockers.push("실행된 테스트 0개");
  for (const id of requiredTests) {
    const state = observed.get(id);
    if (!state) blockers.push(`필수 테스트 누락: ${id}`);
    else if (state === "skipped" || state === "todo") blockers.push(`필수 테스트 ${state}: ${id}`);
  }
  return {failures, blockers, executed, observed: [...observed]};
}

async function readXcodeResults(project, bundlePath, requiredTests, runDir, timeoutMs, onSpawn) {
  const outPath = join(runDir, "xcresult-tests.json");
  const errPath = join(runDir, "xcresult-tests.stderr.log");
  const result = await execute("xcrun", ["xcresulttool", "get", "test-results", "tests", "--path", bundlePath], {
    cwd: project, env: process.env, timeoutMs, stdoutPath: outPath, stderrPath: errPath, onSpawn,
  });
  const failures = [];
  const blockers = [];
  if (result.error || result.timedOut || result.code !== 0) return {failures, blockers: ["xcresult 원본 해석 실패"], executed: 0};
  let data;
  try { data = parseJSON(await readFile(outPath, "utf8")); }
  catch { return {failures, blockers: ["xcresult JSON 손상"], executed: 0}; }
  const observed = new Map();
  const visit = (nodes) => {
    for (const node of nodes ?? []) {
      if (node.nodeType === "Test Case") {
        const id = node.nodeIdentifier ?? node.name;
        if (typeof id !== "string" || !id) { blockers.push("Xcode 테스트 ID 없음"); continue; }
        if (observed.has(id)) blockers.push(`중복 Xcode 테스트 ID: ${id}`);
        observed.set(id, node.result);
        if (node.result === "Failed") failures.push(`테스트 실패: ${id}`);
        else if (node.result !== "Passed") blockers.push(`미실행/미지원 Xcode 상태: ${id}: ${node.result}`);
      }
      visit(node.children);
    }
  };
  visit(data.testNodes);
  if (observed.size === 0) blockers.push("Xcode 테스트 0개");
  for (const id of requiredTests) if (observed.get(id) !== "Passed") blockers.push(`필수 Xcode 테스트 미통과: ${id}`);
  return {failures, blockers, executed: observed.size, observed: [...observed]};
}

async function runGate({project, configPath}) {
  const startedAt = new Date().toISOString();
  const startedTime = Date.now();
  const config = validateConfig(parseJSON(await readFile(configPath, "utf8")));
  const runDir = join(project, "output", "verification", `${Date.now()}-${randomUUID()}`);
  await mkdir(runDir, {recursive: true});
  const report = {startedAt, runDir, project, configPath, source: null, checks: [], failures: [], blockers: [], verdict: "blocked"};
  let active = null;
  const cancel = () => { if (!report.blockers.includes("사용자 취소")) report.blockers.push("사용자 취소"); stopProcess(active); };
  process.once("SIGINT", cancel);
  process.once("SIGTERM", cancel);
  try {
    report.source = await sourceIdentity(project, configPath, config.inputs);
    for (const check of config.checks) {
      if (report.blockers.includes("사용자 취소")) break;
      const remaining = config.runTimeoutMs - (Date.now() - startedTime);
      if (remaining <= 0) { report.blockers.push("전체 시간 초과"); break; }
      const checkDir = join(runDir, check.id);
      await mkdir(checkDir);
      const details = {id: check.id, kind: check.kind, command: check.command, args: check.args, cwd: check.cwd, startedAt: new Date().toISOString(), failures: [], blockers: []};
      report.checks.push(details);
      const env = {...process.env};
      // 상위 프로세스가 Node 테스트인 경우 하위 테스트가 재귀 실행으로 오인되지 않게 한다.
      delete env.NODE_TEST_CONTEXT;
      if (check.nodeMajor !== undefined) {
        const version = spawnSync("node", ["--version"], {cwd: project, env, encoding: "utf8", timeout: 10000});
        if (version.error || version.status !== 0 || Number(/^v(\d+)/.exec(version.stdout)?.[1]) !== check.nodeMajor) {
          report.blockers.push(`${check.id}: Node ${check.nodeMajor} 환경이 필요합니다`);
          break;
        }
      }
      if (check.kind === "node") {
        env.OUTPICK_GATE_REPORTER_PATH = reporterPath;
        env.OUTPICK_GATE_RESULT_PATH = join(checkDir, "node-result.jsonl");
        env.OUTPICK_GATE_RESULT_BASE = checkDir;
      }
      let args = [...check.args];
      let bundlePath;
      if (check.kind === "xcresult") {
        bundlePath = join(checkDir, "tests.xcresult");
        args = [...args, "-resultBundlePath", bundlePath];
      }
      const run = await execute(check.command, args, {
        cwd: join(project, check.cwd), env,
        timeoutMs: Math.min(remaining, check.timeoutMs),
        stdoutPath: join(checkDir, "stdout.log"), stderrPath: join(checkDir, "stderr.log"),
        onSpawn: (child) => { active = child; },
      });
      active = null;
      details.endedAt = new Date().toISOString();
      details.exitCode = run.code ?? null;
      details.signal = run.signal ?? null;
      if (run.error) details.blockers.push(`검사 실행 불가: ${run.error}`);
      if (run.timedOut) details.blockers.push("검사 시간 초과");
      if (run.signal && !run.timedOut) details.blockers.push(`검사 중단: ${run.signal}`);
      if (check.kind === "node") {
        const paths = check.reportNames.map((name) => name === "main" ? env.OUTPICK_GATE_RESULT_PATH : join(checkDir, `node-result-${name}.jsonl`));
        const parsed = await readNodeResults(project, paths, check.requiredTests);
        details.failures.push(...parsed.failures);
        details.blockers.push(...parsed.blockers);
        details.executedTests = parsed.executed;
      }
      if (check.kind === "xcresult") {
        const parsed = await readXcodeResults(project, bundlePath, check.requiredTests, checkDir, Math.max(1, Math.min(config.runTimeoutMs - (Date.now() - startedTime), check.timeoutMs)), (child) => { active = child; });
        active = null;
        details.failures.push(...parsed.failures);
        details.blockers.push(...parsed.blockers);
        details.executedTests = parsed.executed;
      }
      if (run.code !== 0 && !run.error && !run.timedOut && !run.signal) {
        if (check.kind === "command") details.failures.push(`명령 실패: 종료 코드 ${run.code}`);
        else if (details.failures.length === 0 && details.blockers.length === 0) details.failures.push(`테스트 실행 실패: 종료 코드 ${run.code}`);
      }
      if (run.code === 0 && details.failures.length > 0) details.blockers.push("종료 코드와 실패 결과 불일치");
      report.failures.push(...details.failures.map((reason) => `${check.id}: ${reason}`));
      report.blockers.push(...details.blockers.map((reason) => `${check.id}: ${reason}`));
      const currentSource = await sourceIdentity(project, configPath, config.inputs);
      if (currentSource.digest !== report.source.digest || currentSource.head !== report.source.head) {
        report.blockers.push("검사 중 입력/설정/실행기 변경");
        break;
      }
      if (run.timedOut && Date.now() - startedTime >= config.runTimeoutMs) {
        report.blockers.push("전체 시간 초과");
        break;
      }
      if (report.blockers.includes("사용자 취소")) break;
    }
    if (report.checks.length !== config.checks.length) report.blockers.push("필수 검사 미실행");
    if (Date.now() - startedTime > config.runTimeoutMs) report.blockers.push("전체 시간 초과");
  } catch (error) {
    report.blockers.push(`게이트 준비/실행 오류: ${error.message}`);
  } finally {
    process.off("SIGINT", cancel);
    process.off("SIGTERM", cancel);
    report.endedAt = new Date().toISOString();
    report.verdict = report.blockers.length ? "blocked" : report.failures.length ? "failed" : "passed";
    await writeFile(join(runDir, "summary.json"), JSON.stringify(report, null, 2) + "\n");
  }
  return report;
}

function parseArguments(args) {
  assert(args.length === 4 && args[0] === "--project" && args[2] === "--config", "사용법: gate.mjs --project <경로> --config <상대 경로>");
  const project = resolve(args[1]);
  const config = safeRelativePath(args[3], "설정 경로");
  return {project, configPath: join(project, config)};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const report = await runGate(parseArguments(process.argv.slice(2)));
    console.log(JSON.stringify({verdict: report.verdict, summary: join(report.runDir, "summary.json"), failures: report.failures, blockers: report.blockers}));
    process.exitCode = states[report.verdict];
  } catch (error) {
    console.error(`게이트 차단: ${error.message}`);
    process.exitCode = states.blocked;
  }
}

export {parseJSON, readNodeResults, validateConfig};
