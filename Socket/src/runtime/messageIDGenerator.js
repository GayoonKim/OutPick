export function createMessageIDGenerator({ clock, random = Math.random }) {
  return function generateMessageID() {
    return `${clock.nowMillis()}-${random().toString(16).slice(2)}`;
  };
}
