export function normalizeEmail(email) {
  return typeof email === "string" ? email.trim().toLowerCase() : "";
}

export function trimString(value, limit = 1000) {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, limit);
}

export function trimPushText(value, limit = 120) {
  if (typeof value !== "string") return "";
  const trimmed = value.trim();
  if (trimmed.length <= limit) return trimmed;
  return `${trimmed.slice(0, limit - 1)}…`;
}

export function normalizeSentAt(value) {
  if (!value) return undefined;
  try {
    if (typeof value === "string") {
      const date = new Date(value);
      return Number.isNaN(date.getTime()) ? undefined : date.toISOString();
    }
    if (typeof value === "number") {
      const date = new Date(value > 3e9 ? value : value * 1000);
      return Number.isNaN(date.getTime()) ? undefined : date.toISOString();
    }
  } catch {}
  return undefined;
}

export function utf8Bytes(value) {
  return Buffer.byteLength(String(value ?? ""), "utf8");
}

export function validatePayloadSize(payload, maxBytes) {
  try {
    return Buffer.byteLength(JSON.stringify(payload ?? {}), "utf8") <= maxBytes;
  } catch {
    return false;
  }
}

export function chunkArray(items, size) {
  const chunks = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}
