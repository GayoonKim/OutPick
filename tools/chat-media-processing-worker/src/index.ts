import {resolve} from "node:path";

import {cloudJobEnvironment, runCloudMediaJob} from "./cloudJob.js";
import {classifyUnexpectedProcessingError} from "./contracts.js";
import {processImage} from "./imageProcessor.js";
import {processVideo} from "./videoProcessor.js";
import {startImageProcessingService} from "./httpService.js";

async function main(): Promise<void> {
  if (process.env.PORT && !process.env.CHAT_MEDIA_UPLOAD_PATH) {
    startImageProcessingService();
    return;
  }
  const environment = cloudJobEnvironment();
  if (environment !== null) {
    await runCloudMediaJob(environment);
    return;
  }
  const [kind, inputPath, outputDirectory, declaredMimeType] = process.argv.slice(2);
  if ((kind !== "image" && kind !== "video") || inputPath === undefined || outputDirectory === undefined) {
    throw new Error("사용법: node lib/index.js <image|video> <inputPath> <outputDirectory> [declaredMimeType]");
  }

  const result = kind === "image" ?
    await processImage(resolve(inputPath), resolve(outputDirectory), declaredMimeType) :
    await processVideo(resolve(inputPath), resolve(outputDirectory));
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

main().catch((error: unknown) => {
  const classified = classifyUnexpectedProcessingError(error);
  process.stderr.write(`${JSON.stringify({
    code: classified.code,
    retryable: classified.retryable,
    message: classified.message,
    details: classified.details,
  })}\n`);
  process.exitCode = 1;
});
