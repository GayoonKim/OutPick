import {spawn} from "node:child_process";

import {MediaProcessingError} from "./contracts.js";

export interface ProcessResult {
  readonly stdout: string;
  readonly stderr: string;
}

export async function runProcess(
  executable: string,
  args: readonly string[],
  timeoutMilliseconds = 30_000,
): Promise<ProcessResult> {
  return await new Promise((resolve, reject) => {
    const child = spawn(executable, args, {stdio: ["ignore", "pipe", "pipe"]});
    const stdout: Buffer[] = [];
    const stderr: Buffer[] = [];
    let timedOut = false;

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGKILL");
    }, timeoutMilliseconds);

    child.stdout.on("data", (chunk: Buffer) => stdout.push(chunk));
    child.stderr.on("data", (chunk: Buffer) => stderr.push(chunk));
    child.on("error", (error: NodeJS.ErrnoException) => {
      clearTimeout(timer);
      const code = error.code === "ENOENT" ? "runtimeUnavailable" : "processingFailed";
      reject(new MediaProcessingError(code, `${executable} 실행에 실패했습니다.`, {
        retryable: code === "processingFailed",
        cause: error,
      }));
    });
    child.on("close", (exitCode) => {
      clearTimeout(timer);
      const result = {
        stdout: Buffer.concat(stdout).toString("utf8"),
        stderr: Buffer.concat(stderr).toString("utf8"),
      };
      if (timedOut) {
        reject(new MediaProcessingError("resourceLimit", `${executable} 제한 시간을 초과했습니다.`));
        return;
      }
      if (exitCode !== 0) {
        reject(new MediaProcessingError("invalidMedia", `${executable}가 입력을 처리하지 못했습니다.`, {
          details: {exitCode: exitCode ?? -1},
        }));
        return;
      }
      resolve(result);
    });
  });
}
