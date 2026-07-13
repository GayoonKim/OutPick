export function isValidRoomID(roomID) {
  return typeof roomID === "string" && /^[A-Za-z0-9_-]{1,64}$/.test(roomID);
}
