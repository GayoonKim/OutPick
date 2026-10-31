import assert from 'node:assert/strict';
import test from 'node:test';
import {readdir, readFile} from 'node:fs/promises';
import {resolve, relative} from 'node:path';
const root = resolve(import.meta.dirname, '../..');
async function swiftFiles(directory) {
  const rows = await readdir(directory, {withFileTypes: true});
  return (await Promise.all(rows.map(row => row.isDirectory() ? swiftFiles(resolve(directory, row.name)) : row.isFile() && row.name.endsWith('.swift') ? [resolve(directory, row.name)] : []))).flat();
}
const files = await swiftFiles(resolve(root, 'OutPick'));
const sources = await Promise.all(files.map(async path => ({path: relative(root, path), text: await readFile(path, 'utf8')})));
test('IAR-S01 공개 앱에 관리자 화면 세션 조립과 진입점이 없다', () => {
  for (const prefix of ['OutPick/Features/Lookbook/Views/Admin/', 'OutPick/Features/Lookbook/Views/CreateBrand/']) {
    assert.deepEqual(sources.filter(row => row.path.startsWith(prefix)).map(row => row.path), [], prefix);
  }
  for (const name of ['BrandAdminSessionStore', 'BrandAdminCapabilitiesCloudFunctionsClient', 'LookbookAdminHomeView', 'AdminBrandManagementView', 'AdminLookbookDeletionManagementView', 'AdminBrandRequestGroupsView', 'StyleMoodEditorView', 'SeasonMoodManagementView', 'StyleMoodManagementViewModel', 'StyleMoodMutationDraft', 'AdminBrandRequestGroup', 'pushAdminHome', 'pushAdminBrandManagement', 'pushAdminLookbookDeletionManagement']) {
    const remaining = sources.filter(row => new RegExp('\\b' + name + '\\b').test(row.text)).map(row => row.path);
    assert.deepEqual(remaining, [], name + ' 관리 전용 경로가 남아 있습니다.');
  }
});
test('IAR-S02 공개 앱이 기존 관리자 callable을 호출하지 않는다', () => {
  for (const name of ['getBrandAdminCapabilities', 'createBrand', 'updateBrand', 'addBrandManager', 'removeBrandManager', 'updateBrandLogoPaths', 'softDeleteSeason', 'batchSoftDeleteSeasons', 'restoreSeason', 'softDeletePost', 'batchSoftDeletePosts', 'restorePost', 'requestBrandDeletion', 'cancelBrandDeletion', 'listLookbookDeletionRequests', 'retryFailedLookbookDeletionPurge', 'createStyleMood', 'updateStyleMood', 'updateSeasonMoods', 'listBrandRequestGroups', 'updateBrandRequestGroupStage', 'resolveBrandRequestGroup', 'markBrandRequestGroupBrandCreated']) {
    const remaining = sources.filter(row => row.text.includes('"' + name + '"')).map(row => row.path);
    assert.deepEqual(remaining, [], name + ' 관리 호출이 남아 있습니다.');
  }
});
test('IAR-S03 공개 요청 내역 스타일 조회와 본인 댓글 흐름은 남는다', async () => {
  const request = await readFile(resolve(root, 'OutPick/Features/Lookbook/Repositories/Protocols/BrandRequestRepositoryProtocol.swift'), 'utf8');
  assert.match(request, /func submitBrandRequest\(/);
  assert.match(request, /func listMyBrandRequests\(/);
  const moods = await readFile(resolve(root, 'OutPick/Features/StyleMood/Repositories/FirestoreStyleMoodRepository.swift'), 'utf8');
  assert.match(moods, /whereField\("status", isEqualTo: "active"\)/);
  assert.doesNotMatch(moods, /fetchAllMoods/);
  assert.doesNotMatch(request, /func (listBrandRequestGroups|updateBrandRequestGroupStage|resolveBrandRequestGroup|markBrandRequestGroupBrandCreated)\(/);
  for (const path of ['OutPick/Features/Lookbook/ViewModels/PostCommentsViewModel.swift', 'OutPick/Features/Lookbook/ViewModels/PostCommentRepliesViewModel.swift']) {
    const text = await readFile(resolve(root, path), 'utf8');
    assert.match(text, /func canDelete\(/);
    assert.doesNotMatch(text, /isBrandWritable/);
    assert.match(text, /canReportOrBlock/);
  }
});
