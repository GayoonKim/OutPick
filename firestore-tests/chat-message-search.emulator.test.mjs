import assert from 'node:assert/strict';
import {before, after, test} from 'node:test';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment, assertFails} from '@firebase/rules-unit-testing';
import {collection, query, where, orderBy, documentId, limit, startAfter, getDocsFromServer} from 'firebase/firestore';
import {db} from '../functions/lib/core/firebase.js';
import {deleteChatMessageService} from '../functions/lib/chat/moderation/service.js';
import {scrubMessagePage} from '../functions/lib/accountDeletion/cleanup.js';
import {withMessageSearchProjection} from '../Socket/src/messages/messageSearchIndex.js';

const roomID = 'search-phase2-room';
const author = 'search-phase2-author';
const admin = 'search-phase2-admin';
const deletedAuthor = 'search-phase2-deleted-author';
const now = new Date('2026-10-02T00:00:00Z');
const room = db.collection('Rooms').doc(roomID);
let environment;
before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, '에뮬레이터에서만 실행한다');
  environment = await initializeTestEnvironment({projectId: 'outpick-rules-test', firestore: {host: '127.0.0.1', port: 8080,
    rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8')}});
  await db.recursiveDelete(room);
  await room.set({seq: 20, isClosed: false, lifecycleStatus: 'active', creatorUID: author});
  for (const uid of [author, admin, deletedAuthor]) {
    await db.collection('users').doc(uid).set({accountStatus: 'active'});
    await db.collection('moderationAccounts').doc(uid).set({accountStatus: 'active', moderationStatus: 'active', moderationPrincipalID: uid, stateVersion: 1});
  }
});
after(async () => {
  await environment?.cleanup();
  await db.recursiveDelete(room);
  for (const uid of [author, admin, deletedAuthor]) {
    await db.recursiveDelete(db.collection('users').doc(uid));
    await db.recursiveDelete(db.collection('moderationAccounts').doc(uid));
  }
  await db.collection('platformAdmins').doc(admin).delete();
});

function message(id, seq, msg, senderUID = author) {
  return withMessageSearchProjection({ID: id, roomID, seq, msg, senderUID, senderNickname: '작성자', messageType: 'Text', sentAt: now, isDeleted: false});
}

test('고정 상한과 값 cursor가 빈 일치 페이지 삭제 경계 동률에서도 누락 중복을 만들지 않는다', async () => {
  const client = environment.authenticatedContext(author).firestore();
  for (const [id, seq, text] of [['z',10,'ㅋㅋ불일치'],['a',10,'ㅋㅋ다른후보'],['old',1,'ㅋㅋ정답'],['too-new',11,'ㅋㅋ정답']]) {
    await room.collection('Messages').doc(id).set(message(id, seq, text));
  }
  const base = collection(client, 'Rooms', roomID, 'Messages');
  const page = cursor => getDocsFromServer(query(base, where('searchNgrams2','array-contains','ㅋㅋ'), where('seq','<=',10),
    orderBy('seq','desc'), orderBy(documentId(),'desc'), ...(cursor ? [startAfter(...cursor)] : []), limit(2)));
  const first = await page();
  assert.equal(first.metadata.fromCache, false);
  assert.deepEqual(first.docs.map(d => d.id), ['z','a']);
  assert.equal(first.docs.filter(d => d.data().searchNormalized.includes('ㅋㅋ정답')).length, 0);
  await room.collection('Messages').doc('a').delete();
  const second = await page([10,'a']);
  assert.deepEqual(second.docs.map(d => d.id), ['old']);
  assert.equal((await page([1,'old'])).empty, true);
  const one = await getDocsFromServer(query(base, where('searchChars','array-contains','ㅋ'), where('seq','<=',10), orderBy('seq','desc'), orderBy(documentId(),'desc'), limit(100)));
  assert.deepEqual(one.docs.map(d => d.id), ['z','old']);
  // 인덱스 선언 일치는 검사하지만 에뮬레이터로 원격 READY를 증명하지 않는다.
  const indexes = JSON.parse(readFileSync(new URL('../firestore.indexes.json', import.meta.url))).indexes;
  for (const field of ['searchChars','searchNgrams2']) {
    assert.ok(indexes.some(i => i.collectionGroup === 'Messages' && i.queryScope === 'COLLECTION' &&
      JSON.stringify(i.fields) === JSON.stringify([{fieldPath: field,arrayConfig:'CONTAINS'},{fieldPath:'seq',order:'DESCENDING'},{fieldPath:'__name__',order:'DESCENDING'}])));
  }
  await room.update({isClosed:true});
  await assertFails(page());
  await room.update({isClosed:false});
  await db.recursiveDelete(room.collection('Messages'));
});

test('일반 관리자 탈퇴 삭제가 검색 필드를 tombstone에서 제거한다', async () => {
  await db.collection('platformAdmins').doc(admin).set({isActive:true});
  const cases = [['own',author,author], ['admin',author,admin], ['account',deletedAuthor,null]];
  for (const [index, [id, sender, actor]] of cases.entries()) {
    const seq = index + 1;
    const ref = room.collection('Messages').doc(id);
    await ref.set(message(id, seq, '삭제 대상 ㅋㅋ', sender));
    if (actor) {
      await deleteChatMessageService(actor, now.getTime()/1000, {roomID, messageID:id, expectedSeq:seq,
        reasonCode:'chatMessageDeletion', reportTargetType:null, reportTargetID:null,
        clientRequestID:`a23e4567-e89b-42d3-a456-42661417400${index}`}, now, db);
    } else {
      await db.collection('users').doc(sender).set({accountStatus:'deletionPending', accountGenerationID:'search-generation'});
      await scrubMessagePage(sender, 'search-delete-request', 'search-generation', now);
    }
    const data = (await ref.get()).data();
    assert.equal(data.isDeleted, true, id);
    for (const field of ['searchNormalized','searchChars','searchNgrams2','searchIndexVersion']) assert.equal(field in data, false, `${id}:${field}`);
  }
  const remaining = await room.collection('Messages').where('searchNgrams2','array-contains','ㅋㅋ').get();
  assert.equal(remaining.empty, true);
});
