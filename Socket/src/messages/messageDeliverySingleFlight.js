const MESSAGE_KINDS = new Set(["text", "lookbook", "images", "video"]);

function requireNonEmptyString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`${fieldName} must be a non-empty string`);
  }
  return value;
}

export function buildMessageDeliveryKey({ kind, roomID, messageID }) {
  if (!MESSAGE_KINDS.has(kind)) {
    throw new TypeError("unsupported message kind");
  }

  return JSON.stringify([
    kind,
    requireNonEmptyString(roomID, "roomID"),
    requireNonEmptyString(messageID, "messageID")
  ]);
}

export function createMessageDeliverySingleFlight() {
  const inFlight = new Map();

  async function run(identity, operation) {
    if (typeof operation !== "function") {
      throw new TypeError("operation must be a function");
    }

    const key = buildMessageDeliveryKey(identity);
    const existing = inFlight.get(key);
    if (existing) {
      return {
        value: await existing,
        duplicate: true
      };
    }

    const ownerPromise = Promise.resolve().then(operation);
    inFlight.set(key, ownerPromise);

    try {
      return {
        value: await ownerPromise,
        duplicate: false
      };
    } finally {
      if (inFlight.get(key) === ownerPromise) {
        inFlight.delete(key);
      }
    }
  }

  return { run };
}
