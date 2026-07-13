/* eslint-disable require-jsdoc */
export function messageFromError(
  error: unknown,
  fallback = "시즌 가져오기 작업을 준비하지 못했습니다."
): string {
  if (error instanceof Error && error.message.trim().length > 0) {
    return error.message;
  }
  return fallback;
}

export function isAlreadyExistsError(error: unknown): boolean {
  const code = (error as {code?: unknown})?.code;
  return code === 6 || code === "ALREADY_EXISTS";
}
