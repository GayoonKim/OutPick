import test from 'node:test';
import assert from 'node:assert/strict';
import {registerMessageHandlers} from '../../src/handlers/messageHandlers.js';
import {createSequenceStore} from '../../src/messages/sequenceStore.js';
import {createMessageDeliverySingleFlight} from '../../src/messages/messageDeliverySingleFlight.js';
import {buildSearchIndexedFields, withMessageSearchProjection} from '../../src/messages/messageSearchIndex.js';
import {createFakeSocket} from '../support/fakeSocket.js';

const keys = ['searchNormalized', 'searchChars', 'searchNgrams2', 'searchIndexVersion'];
function fixture() {
  const documents = new Map([['Rooms/room', {seq: 8, unreadMessageSeq: 5}]]);
  const removed = Symbol('delete');
  const ref = path => ({path, collection: name => ({doc: id => ref(`${path}/${name}/${id}`)})});
  const db = {
    collection: name => ({doc: id => ref(`${name}/${id}`)}),
    runTransaction: async operation => {
      const writes = [];
      const result = await operation({
        get: async r => ({exists: documents.has(r.path), data: () => documents.get(r.path)}),
        set: (r, data) => writes.push(() => {
          const merged = {...documents.get(r.path), ...data};
          for (const key of Object.keys(merged)) if (merged[key] === removed) delete merged[key];
          documents.set(r.path, merged);
        }),
        delete: r => writes.push(() => documents.delete(r.path))
      });
      writes.forEach(write => write());
      return result;
    }
  };
  const store = createSequenceStore({db, admin: {firestore: {FieldValue: {serverTimestamp: () => 'now', delete: () => removed}}}});
  const socket = createFakeSocket({userUID: 'sender'});
  const emitted = [];
  registerMessageHandlers({
    socket: socket.socket, io: {to: () => ({emit: (event, payload) => emitted.push(payload)})},
    isValidRoomID: () => true, authorizeSocketRoom: async () => ({ok: true}), allowRate: () => true,
    generateMessageID: () => 'generated', clock: {nowDate: () => new Date('2026-10-02T00:00:00Z')},
    allocateSeqAndPersist: store.allocateSeqAndPersist, messageDeliverySingleFlight: createMessageDeliverySingleFlight(),
    fanoutChatPush: async () => {}, handleLookbookShare: async () => {}, logger: {log() {}, warn() {}, error() {}}
  });
  const send = async payload => {
    let ack;
    await socket.handlers.get('chat message')({roomID: 'room', ID: 'text', msg: '뭐야 ㅋㅋ', ...payload}, value => { ack = value; });
    return ack;
  };
  return {documents, store, send, emitted};
}

test('실제 텍스트 handler가 본문으로 v2 검색 필드를 저장하고 위조 필드를 무시한다', async () => {
  const f = fixture();
  const ack = await f.send({searchNormalized: 'forged', searchChars: ['x'], searchNgrams2: ['xx'], searchIndexVersion: 999,
    senderUID: 'forged', replyPreview: {messageID: 'reply', text: '인용문 검색 제외'}});
  assert.equal(ack.ok, true);
  const stored = f.documents.get('Rooms/room/Messages/text');
  const expected = buildSearchIndexedFields('뭐야 ㅋㅋ');
  for (const key of keys) assert.deepEqual(stored[key], expected[key]);
  assert.equal(stored.senderUID, 'sender');
  assert.equal(stored.seq, 9);
  assert.equal(stored.unreadMessageSeq, 6);
  assert.equal(stored.searchNormalized.includes('인용문'), false);
});

test('재전송은 seq ACK와 검색 필드의 멱등성을 보존한다', async () => {
  const f = fixture();
  const first = await f.send();
  const before = structuredClone(f.documents.get('Rooms/room/Messages/text'));
  const duplicate = await f.send({msg: '변경된 재전송'});
  assert.equal(first.seq, duplicate.seq);
  assert.equal(duplicate.duplicate, true);
  assert.equal(f.emitted.length, 1);
  assert.deepEqual(f.documents.get('Rooms/room/Messages/text'), before);
  assert.equal(f.documents.get('Rooms/room').seq, 9);
});

test('역할 안내 룩북 빈 미디어 본문은 검색 대상에서 제외된다', async () => {
  const f = fixture();
  for (const [i, body] of [
    {messageType: 'roomRoleEvent', msg: 'ㅋㅋ', serverGenerated: true},
    {messageType: 'lookbookShare', msg: 'ㅋㅋ'},
    {messageType: 'Image', msg: ''}, {messageType: 'Video', msg: ' \n'},
    {messageType: 'Text', msg: 'ㅋㅋ', isDeleted: true}
  ].entries()) {
    const id = `excluded-${i}`;
    const forged = {...body, searchChars: ['ㅋ'], searchNgrams2: ['ㅋㅋ'], searchNormalized: 'ㅋㅋ', searchIndexVersion: 2};
    // seq 없는 기존 문서에서도 merge가 잘못된 projection을 남기지 않아야 한다.
    f.documents.set(`Rooms/room/Messages/${id}`, {searchChars: ['ㅋ']});
    await f.store.allocateSeqAndPersist('room', id, forged);
    for (const key of keys) assert.equal(key in f.documents.get(`Rooms/room/Messages/${id}`), false);
  }
  for (const type of ['Image', 'Video']) {
    await f.store.allocateSeqAndPersist('room', type, {messageType: type, msg: '설명 ㅋㅋ', searchChars: ['fake']});
    assert.deepEqual(f.documents.get(`Rooms/room/Messages/${type}`).searchNgrams2, ['설명','명 ',' ㅋ','ㅋㅋ']);
  }
  assert.equal(withMessageSearchProjection({messageType: 'Text', msg: 'ㅋㅋ'}).searchIndexVersion, 2);
});
