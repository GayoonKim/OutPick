import assert from "node:assert/strict";
import { after, before, beforeEach, describe, test } from "node:test";
import { readFileSync } from "node:fs";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc,
  deleteField,
  getDoc,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";

const projectId = "outpick-rules-test";
const ownerUID = "owner-uid";
const rules = readFileSync(new URL("../firestore.rules", import.meta.url), "utf8");

let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules,
    },
  });
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
});

after(async () => {
  await testEnvironment.cleanup();
});

function roomData(creatorUID = ownerUID) {
  return {
    roomName: "Rules Test Room",
    roomDescription: "Room creation contract",
    creatorUID,
    createdAt: serverTimestamp(),
    lastMessageAt: serverTimestamp(),
    memberCount: 1,
    seq: 0,
    isClosed: false,
    updatedAt: serverTimestamp(),
  };
}

function memberData(role = "owner") {
  return {
    userID: ownerUID,
    role,
    joinedAt: serverTimestamp(),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

function joinedRoomData(roomID, role = "owner") {
  return {
    roomID,
    role,
    joinedAt: serverTimestamp(),
    isClosed: false,
    updatedAt: serverTimestamp(),
  };
}

async function createRoomTransaction(
  firestore,
  roomID,
  {
    creatorUID = ownerUID,
    memberRole = "owner",
    joinedRole = "owner",
    joinedRoomID = roomID,
    extraRoomData = {},
  } = {},
) {
  const roomRef = doc(firestore, "Rooms", roomID);
  const memberRef = doc(roomRef, "members", ownerUID);
  const joinedRoomRef = doc(firestore, "users", ownerUID, "joinedRooms", roomID);

  return runTransaction(firestore, async (transaction) => {
    transaction.set(roomRef, { ...roomData(creatorUID), ...extraRoomData });
    transaction.set(memberRef, memberData(memberRole));
    transaction.set(joinedRoomRef, joinedRoomData(joinedRoomID, joinedRole));
  });
}

async function assertRoomCreationWasAtomic(roomID) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    const snapshots = await Promise.all([
      getDoc(doc(firestore, "Rooms", roomID)),
      getDoc(doc(firestore, "Rooms", roomID, "members", ownerUID)),
      getDoc(doc(firestore, "users", ownerUID, "joinedRooms", roomID)),
    ]);
    assert.deepEqual(snapshots.map((snapshot) => snapshot.exists()), [false, false, false]);
  });
}

async function seedRoom(roomID, data = {}) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "Rooms", roomID), {
      ...roomData(),
      ...data,
    });
  });
}

describe("Rooms document ID boundary", () => {
  test("authenticated owner can atomically create room, member, and joined projection", async () => {
    const firestore = testEnvironment.authenticatedContext(ownerUID).firestore();

    await assertSucceeds(createRoomTransaction(firestore, "room-valid"));

    const room = await getDoc(doc(firestore, "Rooms", "room-valid"));
    assert.equal(room.exists(), true);
    assert.equal(room.data().ID, undefined);
    assert.equal(room.data().id, undefined);
    assert.equal(room.data().participantUIDs, undefined);
  });

  test("unauthenticated room transaction fails atomically", async () => {
    const firestore = testEnvironment.unauthenticatedContext().firestore();

    await assertFails(createRoomTransaction(firestore, "room-unauthenticated"));
    await assertRoomCreationWasAtomic("room-unauthenticated");
  });

  test("creator mismatch fails atomically", async () => {
    const firestore = testEnvironment.authenticatedContext(ownerUID).firestore();

    await assertFails(createRoomTransaction(firestore, "room-bad-creator", {
      creatorUID: "different-user",
    }));
    await assertRoomCreationWasAtomic("room-bad-creator");
  });

  test("member role mismatch fails atomically", async () => {
    const firestore = testEnvironment.authenticatedContext(ownerUID).firestore();

    await assertFails(createRoomTransaction(firestore, "room-bad-member", {
      memberRole: "member",
    }));
    await assertRoomCreationWasAtomic("room-bad-member");
  });

  test("joined projection mismatch fails atomically", async () => {
    const firestore = testEnvironment.authenticatedContext(ownerUID).firestore();

    await assertFails(createRoomTransaction(firestore, "room-bad-projection", {
      joinedRoomID: "different-room",
    }));
    await assertRoomCreationWasAtomic("room-bad-projection");
  });

  for (const field of ["ID", "id"]) {
    test(`room create containing ${field} fails atomically`, async () => {
      const roomID = `room-create-${field}`;
      const firestore = testEnvironment.authenticatedContext(ownerUID).firestore();

      await assertFails(createRoomTransaction(firestore, roomID, {
        extraRoomData: { [field]: roomID },
      }));
      await assertRoomCreationWasAtomic(roomID);
    });
  }

  for (const field of ["ID", "id"]) {
    test(`adding ${field} to an existing room is denied`, async () => {
      const roomID = `room-update-${field}`;
      await seedRoom(roomID);
      const firestore = testEnvironment.authenticatedContext(ownerUID).firestore();

      await assertFails(updateDoc(doc(firestore, "Rooms", roomID), {
        [field]: roomID,
      }));
    });
  }

  test("changing or deleting a legacy document ID field is denied", async () => {
    const roomID = "room-legacy-protected";
    await seedRoom(roomID, { ID: roomID, id: roomID });
    const firestore = testEnvironment.authenticatedContext(ownerUID).firestore();

    await assertFails(updateDoc(doc(firestore, "Rooms", roomID), { ID: "changed" }));
    await assertFails(updateDoc(doc(firestore, "Rooms", roomID), { id: "changed" }));
    await assertFails(updateDoc(doc(firestore, "Rooms", roomID), { ID: deleteField() }));
    await assertFails(updateDoc(doc(firestore, "Rooms", roomID), { id: deleteField() }));
  });

  test("metadata update succeeds while legacy ID fields remain unchanged", async () => {
    const roomID = "room-legacy-metadata";
    await seedRoom(roomID, { ID: roomID, id: roomID });
    const firestore = testEnvironment.authenticatedContext(ownerUID).firestore();

    await assertSucceeds(updateDoc(doc(firestore, "Rooms", roomID), {
      roomName: "Updated Room Name",
      roomDescription: "Updated description",
      updatedAt: serverTimestamp(),
    }));

    const room = await getDoc(doc(firestore, "Rooms", roomID));
    assert.equal(room.data().ID, roomID);
    assert.equal(room.data().id, roomID);
    assert.equal(room.data().roomName, "Updated Room Name");
  });
});
