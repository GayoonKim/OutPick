export function createRoomRegistry({ db, isValidRoomID }) {
  const rooms = {};

  async function fetchRoomsFromFirebase() {
    const roomsCollection = db.collection("Rooms");
    const snapshot = await roomsCollection.get();

    snapshot.forEach((doc) => {
      const roomID = doc.id;
      if (!rooms[roomID]) {
        rooms[roomID] = [];
      }
    });

    console.log("Rooms initialized from Firebase:", Object.keys(rooms));
  }

  async function ensureRoomLoaded(roomID) {
    if (!roomID || !isValidRoomID(roomID)) {
      return false;
    }

    if (rooms[roomID]) {
      return true;
    }

    try {
      const roomSnapshot = await db.collection("Rooms").doc(roomID).get();
      if (!roomSnapshot.exists) {
        return false;
      }

      rooms[roomID] = rooms[roomID] || [];
      console.log(`[room-bootstrap] loaded room from Firestore: ${roomID}`);
      return true;
    } catch (error) {
      console.error(`[room-bootstrap] failed to load ${roomID}:`, error);
      return false;
    }
  }

  return {
    rooms,
    fetchRoomsFromFirebase,
    ensureRoomLoaded
  };
}
