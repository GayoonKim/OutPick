export function createFakeSocket(overrides = {}) {
  const handlers = new Map();
  const emitted = [];
  const joined = [];
  const left = [];
  const socket = {
    id: "socket-1",
    handshake: { auth: {}, headers: {}, query: {}, address: "127.0.0.1" },
    rooms: new Set(),
    on(event, handler) {
      handlers.set(event, handler);
    },
    emit(event, payload) {
      emitted.push({ event, payload });
    },
    join(roomID) {
      joined.push(roomID);
      socket.rooms.add(roomID);
    },
    leave(roomID) {
      left.push(roomID);
      socket.rooms.delete(roomID);
    },
    ...overrides
  };
  return { socket, handlers, emitted, joined, left };
}

export function createFakeIO() {
  const roomEmits = [];
  return {
    roomEmits,
    io: {
      to(roomID) {
        return {
          emit(event, payload) {
            roomEmits.push({ roomID, event, payload });
          }
        };
      }
    }
  };
}
