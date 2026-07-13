const DEFAULT_MAX_KEYS = 50_000;

export function createMediaDeliveryState({ maxKeys = DEFAULT_MAX_KEYS } = {}) {
  const keysByKind = {
    images: new Set(),
    video: new Set()
  };

  function keys(kind) {
    const value = keysByKind[kind];
    if (!value) throw new Error(`unsupported_media_kind:${kind}`);
    return value;
  }

  function has(kind, key) {
    return keys(kind).has(key);
  }

  function add(kind, key) {
    const values = keys(kind);
    values.add(key);
    if (values.size > maxKeys) values.clear();
  }

  function remove(kind, key) {
    keys(kind).delete(key);
  }

  function size(kind) {
    return keys(kind).size;
  }

  return { add, has, remove, size };
}
