import {inStage, type PipelineRuntime} from "./resources.js";
import {drainAll} from "./scheduling.js";
import {observeBuffer} from "../performance/buffer-inventory.js";

export type ImageVariant = "thumb" | "detail";

export async function storeImageVariants(
  input: Buffer, runtime: PipelineRuntime | undefined,
  operations: {
    transform: (input: Buffer, variant: ImageVariant) => Promise<Buffer>;
    upload: (bytes: Buffer, variant: ImageVariant) => Promise<void>;
    savePaths: () => Promise<unknown>;
  },
): Promise<void> {
  const variants: ImageVariant[] = ["thumb", "detail"];
  const releaseInput = observeBuffer("source", input);
  const outputReleases: Array<() => void> = [];
  let closed = false;
  try {
    const transforms = variants.map((variant) => async () => {
      const release = observeBuffer("source", input);
      try {
        const output = await inStage(runtime, "transform", () =>
          operations.transform(input, variant));
        const releaseOutput = observeBuffer("jpeg", output);
        if (closed) releaseOutput();
        else outputReleases.push(releaseOutput);
        return output;
      } finally {
        release();
      }
    });
    const outputs = await together(runtime, transforms);
    const uploads = variants.map((variant, index) => async () => {
      const release = observeBuffer("jpeg", outputs[index]);
      try {
        await inStage(runtime, "upload", () =>
          operations.upload(outputs[index], variant));
      } finally {
        release();
      }
    });
    await together(runtime, uploads);
    await inStage(runtime, "paths", operations.savePaths);
  } finally {
    // 기본 Promise.all의 조기 실패 후에도 실행 중 소비자의 보유량은 남긴다.
    closed = true;
    releaseInput();
    outputReleases.forEach((release) => release());
  }
}

function together<T>(
  runtime: PipelineRuntime | undefined, operations: Array<() => Promise<T>>,
): Promise<T[]> {
  return runtime ? drainAll(operations) :
    Promise.all(operations.map((op) => op()));
}
