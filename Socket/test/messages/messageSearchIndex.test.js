import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {buildSearchIndexedFields, normalizeSearchText, searchQueryToken} from '../../src/messages/messageSearchIndex.js';
import {caseFolding, removedDiacritics} from '../../src/messages/messageSearchUnicodeData.js';

const root = new URL('../../../contracts/chat-search/', import.meta.url);
const read = name => readFileSync(new URL(name, root), 'utf8');
const fixture = JSON.parse(read('normalization-v2.json'));
const decode = hex => String.fromCodePoint(...hex.trim().split(/\s+/).map(s => parseInt(s, 16)));

test('공통 v2 fixture의 정규화와 token이 일치한다', () => {
  assert.equal(fixture.version, 2);
  assert.equal(fixture.fixtures.length, 25);
  for (const row of fixture.fixtures) {
    assert.deepEqual(buildSearchIndexedFields(row.raw), {
      searchNormalized: row.normalized, searchChars: row.searchChars,
      searchNgrams2: row.searchNgrams2, searchIndexVersion: 2
    }, row.id);
    assert.deepEqual(searchQueryToken(row.raw), row.queryToken, row.id);
    assert.equal(normalizeSearchText(row.normalized), row.normalized, row.id);
  }
  assert.throws(() => normalizeSearchText('\ud800'), TypeError);
  assert.throws(() => normalizeSearchText('\udc00'), TypeError);
  assert.throws(() => normalizeSearchText(123), TypeError);
  const spaces = [9,10,11,12,13,32,133,160,5760,8192,8193,8194,8195,8196,8197,8198,8199,8200,8201,8202,8232,8233,8239,8287,12288];
  for (const cp of spaces) assert.equal(normalizeSearchText(`A${String.fromCodePoint(cp)}B`), 'a b');
  assert.equal(normalizeSearchText('A\ufeffB'), 'a\ufeffb');
});

test('고정 Unicode 매핑과 정규화 corpus를 통과한다', () => {
  const manifest = JSON.parse(read('unicode/manifest.json'));
  assert.equal(manifest.unicodeVersion, '15.1.0');
  for (const [name, hash] of Object.entries(manifest.files)) {
    assert.equal(createHash('sha256').update(read(`unicode/${name}`)).digest('hex'), hash, name);
  }
  execFileSync(process.execPath, [new URL('generate-unicode.mjs', root).pathname, '--check']);
  let foldingCount = 0;
  for (const line of read('unicode/CaseFolding.txt').split('\n')) {
    const [hex, status, mapped] = line.split('#')[0].split(';').map(s => s.trim());
    if (!['C', 'F'].includes(status)) continue;
    foldingCount++;
    assert.equal(caseFolding.get(parseInt(hex, 16)), decode(mapped), hex);
    assert.equal(normalizeSearchText(decode(hex)), normalizeSearchText(decode(mapped)), hex);
  }
  assert.equal(foldingCount, 1530);
  assert.equal(caseFolding.size, 1530);
  const marks = new Set(read('unicode/UnicodeData.txt').split('\n').filter(line => ['Mn','Me'].includes(line.split(';')[2])).map(line => parseInt(line.split(';')[0], 16)));
  const expectedRemoved = new Set();
  for (const line of read('unicode/PropList.txt').split('\n')) {
    const [range, property] = line.split('#')[0].split(';').map(s => s.trim());
    if (property !== 'Diacritic') continue;
    const [lo, hi = lo] = range.split('..').map(s => parseInt(s, 16));
    for (let cp = lo; cp <= hi; cp++) if (marks.has(cp)) expectedRemoved.add(cp);
  }
  assert.equal(expectedRemoved.size, 707);
  assert.deepEqual(removedDiacritics, expectedRemoved);
  let corpusCount = 0;
  for (const line of read('unicode/NormalizationTest.txt').split('\n')) {
    if (!/^[0-9A-F]/.test(line)) continue;
    corpusCount++;
    const c = line.split(';').slice(0, 5).map(decode);
    for (const s of c.slice(0, 3)) {
      assert.equal(s.normalize('NFC'), c[1], line);
      assert.equal(s.normalize('NFD'), c[2], line);
      assert.equal(normalizeSearchText(s), normalizeSearchText(c[0]), line);
      assert.equal(normalizeSearchText(normalizeSearchText(s)), normalizeSearchText(s), line);
    }
    for (const s of c.slice(3)) {
      assert.equal(s.normalize('NFC'), c[3], line);
      assert.equal(s.normalize('NFD'), c[4], line);
    }
  }
  assert.ok(corpusCount > 19000, corpusCount);
  // 별도 프로세스의 언어 환경에서도 같은 고정 fixture를 검사한다.
  for (const locale of ['ko_KR.UTF-8', 'en_US.UTF-8', 'tr_TR.UTF-8']) {
    execFileSync(process.execPath, ['--input-type=module', '-e', `
      import assert from 'node:assert/strict';
      import {normalizeSearchText} from ${JSON.stringify(new URL('../../src/messages/messageSearchIndex.js', import.meta.url).href)};
      assert.equal(normalizeSearchText('Iİı CAFÉ Σς Straße'), 'iiı cafe σσ strasse');
    `], {env: {...process.env, LANG: locale, LC_ALL: locale}});
  }
});
