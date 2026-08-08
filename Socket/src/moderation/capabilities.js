export const MODERATION_CAPABILITIES = Object.freeze({
  active: Object.freeze([
    "readAppContent", "createUGC", "updateUGC", "deleteOwnUGC",
    "createRoom", "joinRoom", "moderateOwnedRoom", "report", "block",
    "unblock", "support", "deleteAccount"
  ]),
  restricted: Object.freeze([
    "readAppContent", "deleteOwnUGC", "report", "block", "unblock",
    "support", "deleteAccount"
  ]),
  suspended: Object.freeze(["support", "deleteAccount"])
});

function timestampMillis(value) {
  if (typeof value?.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return null;
}

export function effectiveModerationStatus(data, nowMillis = Date.now()) {
  const status = data?.moderationStatus;
  if (!Object.hasOwn(MODERATION_CAPABILITIES, status)) return null;
  const restrictedUntil = timestampMillis(data?.restrictedUntil);
  if (status === "restricted" && restrictedUntil !== null &&
      restrictedUntil <= nowMillis) {
    return "active";
  }
  return status;
}

export function moderationSession(data, nowMillis = Date.now()) {
  const moderationStatus = effectiveModerationStatus(data, nowMillis);
  if (!moderationStatus) return null;
  return {
    moderationStatus,
    moderationPrincipalID: typeof data?.moderationPrincipalID === "string"
      ? data.moderationPrincipalID
      : "",
    stateVersion: Number.isInteger(data?.stateVersion) ? data.stateVersion : 0,
    allowedCapabilities: MODERATION_CAPABILITIES[moderationStatus]
  };
}

export function socketHasCapability(socket, capability) {
  return Array.isArray(socket.allowedCapabilities) &&
    socket.allowedCapabilities.includes(capability);
}

export function rejectMissingCapability(socket, capability, callback) {
  if (socketHasCapability(socket, capability)) return false;
  callback?.({
    ok: false,
    message: "moderation_capability_denied",
    error: "moderation_capability_denied",
    requiredCapability: capability
  });
  return true;
}
