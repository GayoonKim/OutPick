/* eslint-disable require-jsdoc, max-len */
export const ROOM_SUCCESSION_WINDOW_MILLIS = 50_000;
export const ROOM_SUCCESSION_MAX_ATTEMPTS = 4;
const RETRY_DELAYS = [0, 5_000, 15_000, 20_000] as const;

export function successionRetryDelayMillis(attempt: number): number | null {
  return RETRY_DELAYS[attempt] ?? null;
}

export function roomSuccessionExpired(deadlineMillis: number, nowMillis: number): boolean {
  return !Number.isFinite(deadlineMillis) || nowMillis >= deadlineMillis;
}

export function nextRoomSuccessionAttempt(attempt: number, deadlineMillis: number, nowMillis: number): number | null {
  const delay = successionRetryDelayMillis(attempt);
  if (delay === null || roomSuccessionExpired(deadlineMillis, nowMillis + delay)) return null;
  return nowMillis + delay;
}

export function retryableSuccessionError(error: unknown): boolean {
  const code = (error as {code?: unknown})?.code;
  if ([4, 8, 10, 13, 14].includes(typeof code === "number" ? code : -1)) return true;
  if (typeof code === "string" && [
    "aborted", "deadline-exceeded", "resource-exhausted", "internal", "unavailable",
  ].includes(code)) return true;
  return error instanceof Error && error.message === "room_successor_changed";
}
