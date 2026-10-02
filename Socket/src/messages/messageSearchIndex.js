import {caseFolding, removedDiacritics} from './messageSearchUnicodeData.js';

export const searchIndexVersion = 2;
const whitespace = new Set([9, 10, 11, 12, 13, 32, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288]);

export function normalizeSearchText(rawText) {
  if (rawText == null) return '';
  if (typeof rawText !== 'string') throw new TypeError('검색 본문은 문자열이어야 합니다.');
  for (const scalar of rawText) {
    const value = scalar.codePointAt(0);
    if (value >= 0xD800 && value <= 0xDFFF) throw new TypeError('유효하지 않은 Unicode 본문입니다.');
  }
  const folded = [...rawText.normalize('NFD')].map(c => caseFolding.get(c.codePointAt(0)) ?? c).join('');
  const composed = [...folded.normalize('NFD')].filter(c => !removedDiacritics.has(c.codePointAt(0))).join('').normalize('NFC');
  let result = '';
  let pendingSpace = false;
  for (const scalar of composed) {
    if (whitespace.has(scalar.codePointAt(0))) {
      pendingSpace = result.length > 0;
    } else {
      if (pendingSpace) result += ' ';
      result += scalar;
      pendingSpace = false;
    }
  }
  return result;
}

export function buildSearchIndexedFields(rawText) {
  const searchNormalized = normalizeSearchText(rawText);
  const scalars = [...searchNormalized];
  return {
    searchNormalized,
    searchChars: [...new Set(scalars.filter(c => c !== ' '))],
    searchNgrams2: [...new Set(scalars.slice(1).map((c, i) => scalars[i] + c))],
    searchIndexVersion
  };
}

export function searchQueryToken(keyword) {
  const scalars = [...normalizeSearchText(keyword)];
  if (!scalars.length) return null;
  return scalars.length === 1
    ? {field: 'searchChars', token: scalars[0]}
    : {field: 'searchNgrams2', token: scalars[0] + scalars[1]};
}

// 저장 경계에서는 외부 검색 필드를 버리고 서버가 확정한 본문만 사용한다.
export function withMessageSearchProjection(message) {
  const clean = {...message};
  for (const key of ['searchNormalized', 'searchChars', 'searchNgrams2', 'searchIndexVersion']) delete clean[key];
  const type = String(clean.messageType ?? '').toLowerCase();
  if (!['text', 'image', 'video'].includes(type) || clean.isDeleted || clean.serverGenerated || typeof clean.msg !== 'string') return clean;
  const fields = buildSearchIndexedFields(clean.msg);
  return fields.searchNormalized ? {...clean, ...fields} : clean;
}
