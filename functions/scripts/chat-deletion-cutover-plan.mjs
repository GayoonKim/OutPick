import {createHash} from "node:crypto";

export const DEVELOPMENT_PROJECT_ID = "outpick-test";
export const APPLY_CONFIRMATION = "APPLY_CHAT_DELETION_CUTOVER_TO_OUTPICK_TEST";

export function opaqueRoomID(roomID) {
  return createHash("sha256").update(roomID).digest("hex").slice(0, 16);
}

function requiredNonNegativeInteger(value, name) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`${name}은 0 이상의 안전한 정수여야 합니다.`);
  }
  return value;
}

export function validateApplyGate(options, actual) {
  if (options.projectID !== DEVELOPMENT_PROJECT_ID) {
    throw new Error("이 보정 도구는 outpick-test Development에서만 실행할 수 있습니다.");
  }
  if (actual.roomHash !== options.expectedRoomHash) {
    throw new Error("영향 방 hash가 --expected-room-hash와 다릅니다.");
  }
  if (actual.count !== options.expectedCount) {
    throw new Error("누락 tombstone 수가 --expected-count와 다릅니다.");
  }
  if (actual.head !== options.expectedHead) {
    throw new Error("Room deletion head가 --expected-head와 다릅니다.");
  }
  if (options.apply && options.confirmation !== APPLY_CONFIRMATION) {
    throw new Error(`apply에는 --confirm ${APPLY_CONFIRMATION}가 필요합니다.`);
  }
}

export function buildRevisionAssignments(messages, currentHead) {
  requiredNonNegativeInteger(currentHead, "currentHead");
  const seenSequences = new Set();
  const ordered = messages.map((message) => {
    if (typeof message.id !== "string" || message.id.length === 0 || message.id.includes("/")) {
      throw new Error("유효하지 않은 message ID입니다.");
    }
    const seq = requiredNonNegativeInteger(message.seq, "message seq");
    if (seenSequences.has(seq)) throw new Error("누락 tombstone seq가 중복됩니다.");
    seenSequences.add(seq);
    return {id: message.id, seq};
  }).sort((lhs, rhs) => lhs.seq - rhs.seq || lhs.id.localeCompare(rhs.id));

  return ordered.map((message, index) => ({
    ...message,
    deletionRevision: currentHead + index + 1,
  }));
}
