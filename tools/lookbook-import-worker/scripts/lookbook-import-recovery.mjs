#!/usr/bin/env node
import {parseRecoveryCLICommand} from "../lib/queue/recovery-cli.js";
import {recoveryIdentityToken} from "../lib/queue/recovery-auth.js";

const help = `룩북 import 복구: inspect | resume | settle-correction

필수 옵션 (형식: --이름=값):
  --project=<project ID> --service=<Cloud Run service>
  --revision=<revision> --batch=<64자리 batch ID> --epoch=<epoch>

resume 추가 확인:
  --report-digest=<inspect 결과> --state-revision=<inspect 결과>
  --decision-id=<고정 UUID; 응답 유실 재시도에 같은 값을 재사용>

환경 변수:
  OUTPICK_IMPORT_RECOVERY_URL
  OUTPICK_IMPORT_RECOVERY_AUDIENCE
  OUTPICK_IMPORT_RECOVERY_SERVICE_ACCOUNT_EMAIL

--revision은 현재 배포본이 아니라 대상 run 기록의 revision이어야 합니다.
복구는 inspect 결과와 동일한 run revision/epoch/state에서만 허용됩니다.
settle-correction은 종료 증거가 있는 단일 시즌 목록 탐색의 correctionRequired 결과만 정산합니다.
force·삭제·성공 전환 기능은 없습니다.`;

if (process.argv[2] === "--help" || process.argv[2] === "-h") {
  process.stdout.write(`${help}\n`);
} else {
  try {
    const command = parseRecoveryCLICommand(process.argv.slice(2), process.env);
    const token = await recoveryIdentityToken(command,
      new AbortController().signal);
    const endpoint = command.mode === "inspect" ? "/recovery/inspect" :
      command.mode === "resume" ? "/recovery/resume" :
        "/recovery/settle-correction";
    const body = command.mode === "inspect" ? {target: command.target} : {
      target: command.target, reportDigest: command.reportDigest,
      expectedStateRevision: command.expectedStateRevision,
      decisionID: command.decisionID,
    };
    const response = await fetch(new URL(endpoint, command.baseURL), {
      method: "POST",
      headers: {authorization: `Bearer ${token}`,
        "content-type": "application/json"},
      body: JSON.stringify(body), signal: AbortSignal.timeout(15000),
    });
    const text = await response.text();
    let result;
    try {
      result = JSON.parse(text);
    } catch {
      result = {accepted: false, errorMessage: "Worker 응답 JSON을 확인하지 못했습니다."};
    }
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    if (!response.ok) process.exitCode = 1;
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown";
    process.stderr.write(`${message}\n\n${help}\n`);
    process.exitCode = 1;
  }
}
