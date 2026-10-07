import {execFile} from "node:child_process";
import {readFile, writeFile, mkdir} from "node:fs/promises";
import {isAbsolute, join} from "node:path";
import {promisify} from "node:util";
import {type ComparisonPlan, phasePlans, validateComparisonPlan}
  from "./comparison.js";
import {validateResultSet} from "./result.js";
import {assessOverhead, validMemoryEvidence} from "./overhead.js";
import {validateReusePlan, validateReusePayload, type ReusePlan}
  from "./reuse-comparison.js";

type Command = (args: string[]) => Promise<string>;
const exec = promisify(execFile);
const docker: Command = async (args) => (await exec("docker", args,
  {maxBuffer: 1024 * 1024})).stdout;
type ObjectValue = Record<string, unknown>;
function object(value: unknown): value is ObjectValue {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function validateContainerPayload(plan: ComparisonPlan, value: unknown) {
  if (!object(value) || value.id !== plan.id ||
    value.measurementEnabled !== true || !Array.isArray(value.results)) {
    return false;
  }
  const validation = validateResultSet(phasePlans(plan), value.results);
  return validation.valid && validation.eligibleIDs.length === 2 &&
    validMemoryEvidence(value.memory);
}

// 회차 디렉터리는 새로 만든다. 기존 결과 덮어쓰기나 자동 재실행은 허용하지 않는다.
export async function runContainer(plan: ComparisonPlan | ReusePlan, options: {
  imageID: string; inputDirectory: string; outputParent: string;
  inputVolume?: string;
  kind?: "comparison" | "overhead" | "reuse";
  command?: Command;
}) {
  const reuse = plan.experiment === "reuse-comparison-v1";
  if (reuse !== (options.kind === "reuse")) {
    throw new Error("계획과 컨테이너 실행 종류 불일치");
  }
  if (reuse) validateReusePlan(plan as ReusePlan);
  else validateComparisonPlan(plan as ComparisonPlan);
  const expected = reuse ? [plan as ReusePlan] :
    phasePlans(plan as ComparisonPlan);
  if ((options.kind && !["comparison", "overhead", "reuse"]
    .includes(options.kind)) ||
    (options.inputVolume &&
      !/^[a-z0-9][a-z0-9_.-]+$/.test(options.inputVolume))) {
    throw new Error("실험 종류 또는 입력 volume이 유효하지 않습니다.");
  }
  if (!/^[A-Za-z0-9_-]+$/.test(plan.id) ||
    !/^sha256:[a-f0-9]{64}$/.test(options.imageID) ||
    [options.inputDirectory, options.outputParent].some((path) =>
      !isAbsolute(path) || /[,\n\r]/.test(path))) {
    throw new Error("고정 이미지 ID와 절대 입출력 경로가 필요합니다.");
  }
  const command = options.command ?? docker;
  const directory = join(options.outputParent, plan.id);
  await mkdir(directory);
  await writeFile(join(directory, "plan.json"), JSON.stringify(plan),
    {flag: "wx"});
  const startedAt = new Date().toISOString();
  await writeFile(join(directory, "started.json"), JSON.stringify({
    id: plan.id, imageID: options.imageID, startedAt,
    inputVolume: options.inputVolume ?? null,
    kind: options.kind ?? "comparison",
  }), {flag: "wx"});
  let stage = "image-inspect";
  let containerID: string | null = null;
  let evidence: unknown = null;
  let payload: unknown = null;
  let verdict: "succeeded" | "failed" | "aborted" | "unavailable" =
    "unavailable";
  let reason = "environment";
  try {
    const image = (await command(["image", "inspect", options.imageID,
      "--format", "{{.Id}} {{.Architecture}} {{.Os}}"])).trim();
    if (image !== `${options.imageID} arm64 linux`) {
      throw new Error("비교 이미지 플랫폼 불일치");
    }
    if (options.inputVolume && (await command(["volume", "inspect",
      options.inputVolume, "--format", "{{.Name}}"])).trim() !==
      options.inputVolume) throw new Error("입력 volume 확인 실패");
    stage = "create";
    const created = (await command(["create", "--cpus=1", "--memory=2g",
      "--memory-swap=2g", "--network=none",
      "--mount", options.inputVolume ?
        `type=volume,src=${options.inputVolume},dst=/input,readonly` :
        `type=bind,src=${options.inputDirectory},dst=/input,readonly`,
      "--mount", `type=bind,src=${directory},dst=/output`,
      options.imageID, "node", reuse ? "lib/performance/reuse-entry.js" :
        options.kind === "overhead" ? "lib/performance/overhead-entry.js" :
          "lib/performance/local-entry.js",
      "/input", "/output/plan.json", "/output/result.json"])).trim();
    if (!/^[a-f0-9]{64}$/.test(created)) throw new Error("컨테이너 ID 불일치");
    containerID = created;
    await writeFile(join(directory, "container.json"),
      JSON.stringify({containerID}), {flag: "wx"});
    stage = "start";
    await command(["start", containerID]);
    stage = "wait";
    const exitText = (await command(["wait", containerID])).trim();
    if (!/^\d+$/.test(exitText)) throw new Error("종료 코드 누락");
    const exitCode = Number(exitText);
    stage = "inspect";
    evidence = JSON.parse(await command(["inspect", containerID,
      "--format", "{{json .State}}"]));
    if (!object(evidence) || evidence.Running !== false ||
      evidence.Status !== "exited" || typeof evidence.OOMKilled !== "boolean" ||
      !Number.isSafeInteger(exitCode) || exitCode < 0 ||
      evidence.ExitCode !== exitCode) throw new Error("종료 증거 불일치");
    stage = "result";
    try {
      payload = JSON.parse(await readFile(join(directory, "result.json"),
        "utf8"));
    } catch {
      // OOM 등으로 결과가 없어도 외부 종료 증거를 남긴다.
    }
    if (evidence.OOMKilled) {
      verdict = "aborted";
      reason = "memory";
    } else if (object(payload) && payload.id === plan.id &&
      ["evidence-limit", "evidence-write"]
        .includes(String(payload.evidenceError))) {
      verdict = "failed";
      reason = String(payload.evidenceError);
    } else if (exitCode !== 0) {
      verdict = "failed";
      reason = "operation";
    } else if (object(payload) && payload.id === plan.id &&
      Array.isArray(payload.results) &&
      validateResultSet(expected, payload.results).valid &&
      object(payload.memory) && object(payload.memory.stop) &&
      ["memory", "environment"].includes(String(payload.memory.stop.reason))) {
      verdict = payload.results.every((row) =>
        object(row) && row.outcome === "unavailable") ? "unavailable" :
        "aborted";
      reason = String(payload.memory.stop.reason);
    } else if (reuse ? validateReusePayload(plan as ReusePlan, payload) :
      options.kind === "overhead" ?
        assessOverhead(plan as ComparisonPlan, payload).valid :
        validateContainerPayload(plan as ComparisonPlan, payload)) {
      verdict = "succeeded";
      reason = "none";
    } else {
      verdict = "failed";
      reason = "incomplete-or-invalid-result";
    }
  } catch {
    // 도구 stderr에 인증/환경 정보가 섞일 수 있어 단계와 원본 결과만 저장한다.
    verdict = containerID ? "failed" : "unavailable";
    reason = "environment";
  }
  const finished = {id: plan.id, startedAt, endedAt: new Date().toISOString(),
    imageID: options.imageID, containerID, stage, verdict, reason, evidence,
    payload};
  await writeFile(join(directory, "finished.json"),
    JSON.stringify(finished, null, 2), {flag: "wx"});
  // 종료/inspect 실패에서는 아직 실행 중일 수 있으므로 자동 삭제하지 않는다.
  if (containerID && object(evidence) && evidence.Status === "exited") {
    try {
      await command(["rm", containerID]);
    } catch {
      await writeFile(join(directory, "cleanup-pending.json"),
        JSON.stringify({containerID}), {flag: "wx"});
    }
  }
  return finished;
}
