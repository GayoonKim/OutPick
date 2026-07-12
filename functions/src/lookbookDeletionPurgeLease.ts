export type ManualRetryState = "queued" | "running" | "failed" | null;

/**
 * purge lease가 아직 유효한지 확인한다.
 * @param {number|null} leaseUntilMillis lease 만료 시각
 * @param {number} nowMillis 현재 시각
 * @return {boolean} lease 유효 여부
 */
export function isPurgeLeaseActive(
  leaseUntilMillis: number | null,
  nowMillis: number
): boolean {
  return leaseUntilMillis !== null && leaseUntilMillis > nowMillis;
}

/**
 * Firestore 변경이 수동 purge worker를 시작해야 하는지 확인한다.
 * @param {string|null} beforeToken 변경 전 retry token
 * @param {string|null} afterToken 변경 후 retry token
 * @param {ManualRetryState} afterState 변경 후 retry 상태
 * @return {boolean} trigger 실행 여부
 */
export function shouldStartManualRetryTrigger(
  beforeToken: string | null,
  afterToken: string | null,
  afterState: ManualRetryState
): boolean {
  return afterToken !== null &&
    beforeToken !== afterToken &&
    afterState === "queued";
}

/**
 * purge 결과가 현재 lease owner의 것인지 확인한다.
 * @param {string|null} currentLeaseToken 현재 저장된 lease token
 * @param {string} expectedLeaseToken 실행자가 보유한 lease token
 * @return {boolean} finalize 가능 여부
 */
export function canFinalizePurgeLease(
  currentLeaseToken: string | null,
  expectedLeaseToken: string
): boolean {
  return currentLeaseToken === expectedLeaseToken;
}

/**
 * queued 상태 또는 유효 lease의 retry receipt 재사용 여부를 확인한다.
 * @param {ManualRetryState} state 현재 수동 retry 상태
 * @param {boolean} requestLeaseActive request lease 유효 여부
 * @return {boolean} 중복 retry 여부
 */
export function isManualRetryDuplicate(
  state: ManualRetryState,
  requestLeaseActive: boolean
): boolean {
  return state === "queued" || requestLeaseActive;
}

/**
 * 만료 lease가 남긴 stale running을 화면용 failed 상태로 정규화한다.
 * @param {ManualRetryState} state 저장된 수동 retry 상태
 * @param {boolean} purgeInProgress 현재 purge 실행 여부
 * @return {ManualRetryState} 화면에 전달할 retry 상태
 */
export function visibleManualRetryState(
  state: ManualRetryState,
  purgeInProgress: boolean
): ManualRetryState {
  return state === "running" && !purgeInProgress ? "failed" : state;
}
