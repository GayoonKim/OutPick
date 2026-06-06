export type ImportJobLifecycle =
  | "queued"
  | "processing"
  | "succeeded"
  | "partialFailed"
  | "failed"
  | "cancelled";

export type AssetSyncResultStatus = "ready" | "partial" | "failed";

export function completedLifecycle(
  assetStatus: AssetSyncResultStatus,
): ImportJobLifecycle {
  switch (assetStatus) {
  case "ready":
    return "succeeded";
  case "partial":
    return "partialFailed";
  case "failed":
    return "failed";
  }
}

export function isFinalTaskAttempt(
  retryCount: number,
  maxAttempts: number,
): boolean {
  return retryCount >= maxAttempts - 1;
}
