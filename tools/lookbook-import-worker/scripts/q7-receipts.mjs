export async function waitQ7Receipt(call, pending, {
  mode = "released", expectedCount, timeoutMs = 15 * 60 * 1000,
  intervalMs = 1_000, now = Date.now,
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
} = {}) {
  if (!["prepared", "released"].includes(mode) || !pending.requestID ||
      !Number.isFinite(timeoutMs) || timeoutMs <= 0 ||
      !Number.isFinite(intervalMs) || intervalMs <= 0) {
    throw new Error("Q7_RECEIPT_WAIT_INVALID");
  }
  const deadline = now() + timeoutMs;
  let receipt = pending.receipt ?? null;
  while (now() < deadline) {
    if (!receipt) receipt = await call("getSeasonImportBatch", {
      requestID: pending.requestID,
    });
    if (receipt.requestID !== pending.requestID ||
        receipt.batchID !== pending.batchID || !Array.isArray(receipt.items)) {
      throw new Error("Q7_RECEIPT_TARGET_CHANGED");
    }
    if (receipt.receiptState === "recoveryRequired") {
      throw new Error("Q7_RECOVERY_REQUIRED");
    }
    if (receipt.failedCount || receipt.skippedCount ||
        receipt.items.some((item) => item.processingStatus === "failed")) {
      throw new Error("Q7_BATCH_HAS_FAILED_ITEMS");
    }
    const prepared = receipt.items.length > 0 &&
      (expectedCount == null || receipt.items.length === expectedCount) &&
      receipt.items.every((item) => typeof item.jobID === "string" && item.jobID);
    if (mode === "prepared" && prepared) return receipt;
    if (mode === "released" && receipt.receiptState === "released") {
      if (!prepared) throw new Error("Q7_IMPORT_ITEM_INCOMPLETE");
      return receipt;
    }
    if (mode === "prepared" && receipt.receiptState !== "preparing") {
      throw new Error("Q7_IMPORT_ITEM_INCOMPLETE");
    }
    await sleep(intervalMs);
    receipt = null;
  }
  throw new Error(mode === "prepared" ? "Q7_PREPARATION_TIMEOUT" :
    "Q7_BATCH_TIMEOUT");
}
