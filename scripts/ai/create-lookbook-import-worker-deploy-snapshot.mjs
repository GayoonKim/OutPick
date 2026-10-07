#!/usr/bin/env node
import {createHash} from "node:crypto";
import {execFileSync} from "node:child_process";
import {lstatSync, readFileSync} from "node:fs";
import {lstat, mkdir, readFile, writeFile, chmod} from "node:fs/promises";
import {basename, dirname, join, relative, resolve, sep} from "node:path";
import {fileURLToPath} from "node:url";

const REQUIRED_CHECKS = ["worker-lint", "worker-test", "worker-fixtures",
  "worker-deploy-contract"];
const WORKER_PREFIX = "tools/lookbook-import-worker/";

export async function createWorkerDeploySnapshot({
  projectRoot,
  gateSummaryPath,
  snapshotDirectory,
}) {
  const project = resolve(projectRoot);
  const verificationRoot = resolve(project, "output", "verification") + sep;
  const summaryPath = resolve(gateSummaryPath);
  if (!summaryPath.startsWith(verificationRoot) || basename(summaryPath) !== "summary.json") {
    throw new Error("WORKER_GATE_SUMMARY_PATH_INVALID");
  }

  const expectedConfigPath = resolve(project, "verification/lookbook-import.json");
  const summary = JSON.parse(await readFile(summaryPath, "utf8"));
  if (summary.configPath !== expectedConfigPath || summary.verdict !== "passed" ||
      !summary.source || !Array.isArray(summary.checks) ||
      !/^[a-f0-9]{40}$/.test(summary.source.head ?? "") ||
      !/^[a-f0-9]{64}$/.test(summary.source.digest ?? "") ||
      !Number.isInteger(summary.source.fileCount) || summary.source.fileCount <= 0 ||
      summary.failures?.length !== 0 || summary.blockers?.length !== 0) {
    throw new Error("WORKER_GATE_NOT_PASSED");
  }
  const config = JSON.parse(await readFile(expectedConfigPath, "utf8"));
  if (config.version !== 1 || !Array.isArray(config.inputs) ||
      !Array.isArray(config.checks) ||
      REQUIRED_CHECKS.some((id) => !config.checks.some((check) => check.id === id)) ||
      summary.checks.length !== config.checks.length ||
      new Set(summary.checks.map((check) => check.id)).size !== summary.checks.length ||
      config.checks.some((definition) =>
        summary.checks.filter((check) => check.id === definition.id).length !== 1)) {
    throw new Error("WORKER_GATE_CONFIG_INVALID");
  }
  for (const checkDefinition of config.checks) {
    const checkID = checkDefinition.id;
    const check = summary.checks.find((item) => item.id === checkID);
    if (!check || check.exitCode !== 0 || check.signal || check.timedOut ||
        check.failures?.length !== 0 || check.blockers?.length !== 0 ||
        (checkID === "worker-test" && !(check.executedTests > 0))) {
      throw new Error("WORKER_GATE_CHECK_INCOMPLETE:" + checkID);
    }
  }

  const sourceBefore = computeGateSourceIdentity(project, expectedConfigPath, config.inputs);
  if (sourceBefore.digest !== summary.source.digest ||
      sourceBefore.head !== summary.source.head ||
      sourceBefore.fileCount !== summary.source.fileCount) {
    throw new Error("WORKER_GATE_SOURCE_CHANGED");
  }

  const snapshot = resolve(snapshotDirectory);
  const snapshotRoot = resolve(project, "output/lookbook-import-performance/worker-deploy-snapshots") + sep;
  if (!snapshot.startsWith(snapshotRoot)) throw new Error("WORKER_SNAPSHOT_PATH_INVALID");
  await mkdir(dirname(snapshot), {recursive: true});
  await mkdir(snapshot, {recursive: false});

  const workerFiles = sourceBefore.files.filter((file) => file.startsWith(WORKER_PREFIX));
  if (workerFiles.length === 0) throw new Error("WORKER_SNAPSHOT_EMPTY");
  const fileEntries = [];
  const workerHash = createHash("sha256");
  for (const file of workerFiles) {
    const sourcePath = join(project, file);
    const stat = await lstat(sourcePath);
    if (!stat.isFile()) throw new Error("WORKER_SNAPSHOT_NON_FILE:" + file);
    const bytes = await readFile(sourcePath);
    const snapshotRelativePath = file.slice(WORKER_PREFIX.length);
    const destination = join(snapshot, snapshotRelativePath);
    await mkdir(dirname(destination), {recursive: true});
    await writeFile(destination, bytes, {flag: "wx", mode: stat.mode & 0o777});
    await chmod(destination, stat.mode & 0o777);
    const digest = createHash("sha256").update(bytes).digest("hex");
    workerHash.update(snapshotRelativePath).update("\0").update(bytes).update("\0");
    fileEntries.push({path: snapshotRelativePath, sha256: digest, bytes: bytes.length});
  }

  const sourceAfter = computeGateSourceIdentity(project, expectedConfigPath, config.inputs);
  if (sourceAfter.digest !== summary.source.digest || sourceAfter.head !== summary.source.head) {
    throw new Error("WORKER_GATE_SOURCE_CHANGED_DURING_SNAPSHOT");
  }
  const snapshotDigest = await digestSnapshot(snapshot, fileEntries);
  if (snapshotDigest !== workerHash.digest("hex")) {
    throw new Error("WORKER_SNAPSHOT_DIGEST_MISMATCH");
  }

  const manifest = {
    schemaVersion: 1,
    projectID: "outpick-test",
    sourceRevision: sourceBefore.head,
    verification: {
      config: relative(project, expectedConfigPath).split(sep).join("/"),
      runID: basename(dirname(summaryPath)),
      summaryPath: relative(project, summaryPath).split(sep).join("/"),
      sourceDigest: sourceBefore.digest,
      sourceFileCount: sourceBefore.fileCount,
    },
    workerSnapshot: {
      directory: relative(project, snapshot).split(sep).join("/"),
      digest: snapshotDigest,
      fileCount: fileEntries.length,
      files: fileEntries,
    },
  };
  const manifestPath = snapshot + ".manifest.json";
  await writeFile(manifestPath, JSON.stringify(manifest, null, 2) + "\n", {flag: "wx"});
  process.stdout.write(`source_revision=${sourceBefore.head}\n`);
  process.stdout.write(`verification_digest=${sourceBefore.digest}\n`);
  process.stdout.write(`worker_snapshot_digest=${snapshotDigest}\n`);
  process.stdout.write(`snapshot=${snapshot}\n`);
  process.stdout.write(`manifest=${manifestPath}\n`);
  return manifest;
}

export function computeGateSourceIdentity(project, configPath, inputs) {
  const explicitFiles = [];
  for (const input of inputs) {
    const stat = lstatSync(join(project, input));
    if (stat.isFile()) explicitFiles.push(input);
  }
  const listed = execFileSync("git", ["ls-files", "-z", "--cached", "--others",
    "--exclude-standard", "--", ...inputs], {cwd: project, encoding: "buffer",
    maxBuffer: 64 * 1024 * 1024, timeout: 30_000});
  const files = new Set(listed.toString("utf8").split("\0").filter(Boolean));
  for (const file of explicitFiles) files.add(file);
  files.add(relative(project, configPath).split(sep).join("/"));
  const hash = createHash("sha256");
  for (const file of [...files].sort()) {
    if (!file || file.startsWith("/") || file.split(/[\\/]/).includes("..")) {
      throw new Error("WORKER_GATE_INPUT_PATH_INVALID");
    }
    const path = join(project, file);
    let stat;
    try { stat = lstatSync(path); } catch (error) {
      if (error.code === "ENOENT") {
        hash.update(file).update("\0deleted\0");
        continue;
      }
      throw error;
    }
    if (!stat.isFile()) throw new Error("WORKER_GATE_INPUT_NOT_FILE:" + file);
    hash.update(file).update("\0").update(readFileSync(path)).update("\0");
  }
  const gateDirectory = resolve(project, "tools/verification-gate");
  for (const path of [join(gateDirectory, "gate.mjs"), join(gateDirectory, "node-reporter.mjs"),
    join(gateDirectory, "gate.test.mjs")]) {
    hash.update(path).update("\0").update(readFileSync(path)).update("\0");
  }
  const head = execFileSync("git", ["rev-parse", "HEAD"], {cwd: project,
    encoding: "utf8", timeout: 30_000}).trim();
  return {digest: hash.digest("hex"), head, fileCount: files.size,
    files: [...files].sort()};
}

async function digestSnapshot(snapshot, entries) {
  const hash = createHash("sha256");
  for (const entry of entries) {
    const bytes = await readFile(join(snapshot, entry.path));
    const digest = createHash("sha256").update(bytes).digest("hex");
    if (digest !== entry.sha256 || bytes.length !== entry.bytes) {
      throw new Error("WORKER_SNAPSHOT_FILE_MISMATCH:" + entry.path);
    }
    hash.update(entry.path).update("\0").update(bytes).update("\0");
  }
  return hash.digest("hex");
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const args = parseArguments(process.argv.slice(2));
    await createWorkerDeploySnapshot(args);
  } catch (error) {
    console.error(error instanceof Error ? error.message : "WORKER_SNAPSHOT_FAILED");
    process.exitCode = 1;
  }
}

function parseArguments(args) {
  if (args.length !== 6) {
    throw new Error("사용법: snapshot --project <경로> --gate-summary <summary.json> --snapshot <경로>");
  }
  const parsed = {};
  for (let index = 0; index < args.length; index += 2) {
    const value = args[index];
    if (!value.startsWith("--") || !args[index + 1]) {
      throw new Error("사용법: snapshot --project <경로> --gate-summary <summary.json> --snapshot <경로>");
    }
    parsed[value.slice(2)] = args[index + 1];
  }
  if (Object.keys(parsed).sort().join(",") !== "gate-summary,project,snapshot") {
    throw new Error("사용법: snapshot --project <경로> --gate-summary <summary.json> --snapshot <경로>");
  }
  return {projectRoot: parsed.project, gateSummaryPath: parsed["gate-summary"],
    snapshotDirectory: parsed.snapshot};
}
