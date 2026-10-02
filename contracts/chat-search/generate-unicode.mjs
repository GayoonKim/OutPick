import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';

const root = new URL('../../', import.meta.url);
const source = new URL('unicode/', import.meta.url);
const names = ['CaseFolding.txt', 'PropList.txt', 'UnicodeData.txt', 'NormalizationTest.txt', 'ReadMe.txt', 'LICENSE.txt'];
const texts = Object.fromEntries(await Promise.all(names.map(async name => [name, await readFile(new URL(name, source), 'utf8')])));
const folds = new Map();
for (const line of texts['CaseFolding.txt'].split('\n')) {
  const [code, status, value] = line.split('#')[0].split(';').map(s => s.trim());
  if (status === 'C' || status === 'F') folds.set(parseInt(code, 16), value.split(' ').map(s => parseInt(s, 16)));
}
const marks = new Set();
for (const line of texts['UnicodeData.txt'].split('\n')) {
  const [code, , category] = line.split(';');
  if (category === 'Mn' || category === 'Me') marks.add(parseInt(code, 16));
}
const removed = [];
for (const line of texts['PropList.txt'].split('\n')) {
  const [range, property] = line.split('#')[0].split(';').map(s => s.trim());
  if (property !== 'Diacritic') continue;
  const [first, last = first] = range.split('..').map(s => parseInt(s, 16));
  for (let code = first; code <= last; code++) if (marks.has(code)) removed.push(code);
}
const entries = [...folds].sort((a, b) => a[0] - b[0]);
removed.sort((a, b) => a - b);
const header = '// generate-unicode.mjs로 생성. 직접 수정하지 않는다. Unicode 15.1.0.\n/*\n' + texts['LICENSE.txt'] + '*/\n';
const js = header + `export const caseFolding = new Map(${JSON.stringify(entries.map(([k, v]) => [k, String.fromCodePoint(...v)]))});\nexport const removedDiacritics = new Set(${JSON.stringify(removed)});\n`;
const swift = header + 'enum ChatSearchUnicodeData {\n    static let caseFolding: [UInt32: String] = [\n' +
  entries.map(([k, v]) => `        ${k}: "${v.map(c => `\\u{${c.toString(16)}}`).join('')}",`).join('\n') +
  '\n    ]\n    static let removedDiacritics: Set<UInt32> = [\n' +
  Array.from({length: Math.ceil(removed.length / 16)}, (_, i) => '        ' + removed.slice(i * 16, i * 16 + 16).join(', ') + ',').join('\n') + '\n    ]\n}\n';
const manifest = JSON.stringify({unicodeVersion: '15.1.0', sourceURL: 'https://www.unicode.org/Public/zipped/15.1.0/UCD.zip', licenseURL: 'https://www.unicode.org/license.txt', caseFoldingCount: entries.length, removedDiacriticCount: removed.length, files: Object.fromEntries(names.map(name => [name, createHash('sha256').update(texts[name]).digest('hex')]))}, null, 2) + '\n';
const outputs = [
  ['Socket/src/messages/messageSearchUnicodeData.js', js],
  ['OutPick/Features/Chat/Domain/Models/ChatSearchUnicodeData.swift', swift],
  ['contracts/chat-search/unicode/manifest.json', manifest],
  ['OutPick/Resources/ChatSearchUnicode-LICENSE.txt', texts['LICENSE.txt']]
];
for (const [path, content] of outputs) {
  const url = new URL(path, root);
  if (process.argv.includes('--check')) {
    if (await readFile(url, 'utf8') !== content) throw new Error(`생성 자료 불일치: ${path}`);
  } else {
    await mkdir(new URL('.', url), {recursive: true});
    await writeFile(url, content);
  }
}
console.log(`Unicode 15.1: folding ${entries.length}, diacritics ${removed.length}, ${process.argv.includes('--check') ? '일치 확인' : '생성 완료'} (${fileURLToPath(source)})`);
