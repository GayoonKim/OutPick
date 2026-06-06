export class RetryableImportError extends Error {
  constructor(message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = "RetryableImportError";
  }
}

export function isRetryableImportError(
  error: unknown,
): error is RetryableImportError {
  return error instanceof RetryableImportError;
}

export function isRetryableHTTPStatus(status: number): boolean {
  return status === 429 || status >= 500;
}

export function isRetryableNetworkError(error: unknown): boolean {
  if (error instanceof RetryableImportError) {
    return true;
  }
  if (error instanceof DOMException && error.name === "AbortError") {
    return true;
  }
  const code = (error as {code?: unknown})?.code;
  if (typeof code === "string" && [
    "EAI_AGAIN",
    "ECONNABORTED",
    "ECONNREFUSED",
    "ECONNRESET",
    "ENETDOWN",
    "ENETUNREACH",
    "ETIMEDOUT",
  ].includes(code)) {
    return true;
  }
  const cause = (error as {cause?: unknown})?.cause;
  return cause !== undefined && isRetryableNetworkError(cause);
}
