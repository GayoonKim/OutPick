import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, readdirSync, existsSync} from 'node:fs';
import {join} from 'node:path';

const endpoints = [
  "requestSeasonImport",
  "requestSeasonAssetRetry",
  "requestSeasonCandidateImportJobs",
  "runLookbookExtractionDiagnostic",
  "getLatestLookbookExtractionDiagnostic",
  "getLookbookExtractionReview",
  "reviewLookbookExtraction",
  "retryLookbookExtractionAfterFix",
  "requestLookbookSeasonRepair",
  "previewLookbookSeasonRepair",
  "applyLookbookSeasonRepair",
  "discoverSeasonCandidates",
  "requestSeasonDiscovery",
  "cancelSeasonDiscovery",
  "retrySeasonDiscovery",
  "resolveSeasonDiscoveryCandidate",
  "retrySeasonDiscoveryAfterExtractionFix",
  "getSeasonImportBatch",
  "getSeasonImportFailures",
  "requestSeasonImportFailureRetry",
  "dismissSeasonImportFailure"
];
const retiredFiles = [
  "OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsSeasonImportRepository.swift",
  "OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsSeasonAssetRetryRepository.swift",
  "OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsSeasonImportJobRequestingRepository.swift",
  "OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsSeasonCandidateDiscoveryRepository.swift",
  "OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsLookbookExtractionReviewRepository.swift",
  "OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsLookbookSeasonRepairRepository.swift",
  "OutPick/Features/Lookbook/Repositories/Implementations/FirestoreSeasonCandidateRepository.swift",
  "OutPick/Features/Lookbook/Repositories/Implementations/FirestoreSeasonImportJobRepository.swift",
  "OutPick/Features/Lookbook/Repositories/Protocols/SeasonImportRequestingRepository.swift",
  "OutPick/Features/Lookbook/Repositories/Protocols/SeasonAssetRetryRequestingRepository.swift",
  "OutPick/Features/Lookbook/Repositories/Protocols/SeasonImportJobRequestingRepositoryProtocol.swift",
  "OutPick/Features/Lookbook/Repositories/Protocols/SeasonCandidateDiscoveryRepositoryProtocol.swift",
  "OutPick/Features/Lookbook/Repositories/Protocols/LookbookExtractionReviewRepositoryProtocol.swift",
  "OutPick/Features/Lookbook/Repositories/Protocols/LookbookSeasonRepairRepositoryProtocol.swift",
  "OutPick/Features/Lookbook/Repositories/Protocols/SeasonCandidateRepositoryProtocol.swift",
  "OutPick/Features/Lookbook/Repositories/Protocols/SeasonImportJobRepositoryProtocol.swift",
  "OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsMappers/SeasonImportCloudFunctionsMapper.swift",
  "OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsMappers/LookbookExtractionReviewCloudFunctionsMapper.swift",
  "OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsMappers/LookbookSeasonRepairCloudFunctionsMapper.swift",
  "OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsMappers/LookbookExtractionDiagnosticCloudFunctionsMapper.swift",
  "OutPick/Features/Lookbook/Domains/UseCases/StartSeasonImportExtractionUseCase.swift",
  "OutPick/Features/Lookbook/Domains/UseCases/ManageSeasonImportJobsUseCase.swift",
  "OutPick/Features/Lookbook/Domains/UseCases/ManageLookbookExtractionReviewUseCase.swift",
  "OutPick/Features/Lookbook/Domains/UseCases/ManageLookbookSeasonRepairUseCase.swift",
  "OutPick/Features/Lookbook/Domains/UseCases/LoadSelectableSeasonCandidatesUseCase.swift",
  "OutPick/Features/Lookbook/ViewModels/CreateSeasonFromURLViewModel.swift",
  "OutPick/Features/Lookbook/ViewModels/CreateBrandDiscoveryViewModel.swift",
  "OutPick/Features/Lookbook/ViewModels/SeasonImportManagementViewModel.swift",
  "OutPick/Features/Lookbook/ViewModels/SeasonDiscoveryReviewViewModel.swift",
  "OutPick/Features/Lookbook/ViewModels/LookbookExtractionReviewViewModel.swift",
  "OutPick/Features/Lookbook/ViewModels/LookbookSeasonRepairViewModel.swift",
  "OutPick/Features/Lookbook/Views/BrandDetail/SeasonImportManagementView.swift",
  "OutPick/Features/Lookbook/Views/BrandDetail/SeasonDiscoveryReviewView.swift",
  "OutPick/Features/Lookbook/Views/BrandDetail/LookbookExtractionReviewView.swift",
  "OutPick/Features/Lookbook/Views/BrandDetail/LookbookSeasonRepairView.swift",
  "OutPick/Features/Lookbook/Views/CreateBrand/season/CreateSeasonFromURLView.swift",
  "OutPick/Features/Lookbook/Views/CreateBrand/brand/CreateBrandDiscoveringView.swift",
  "OutPick/Features/Lookbook/Views/CreateBrand/brand/CreateBrandCandidateSelectionView.swift",
  "OutPick/Features/Lookbook/Views/CreateBrand/brand/SeasonCandidateCoverView.swift",
  "OutPick/Features/Lookbook/Domains/Entities/SeasonImportRequestReceipt.swift",
  "OutPick/Features/Lookbook/Domains/Entities/SeasonAssetRetryReceipt.swift",
  "OutPick/Features/Lookbook/Domains/Entities/SeasonImportBatchRequestResult.swift",
  "OutPick/Features/Lookbook/Domains/Entities/SeasonImportExtractionProgress.swift",
  "OutPick/Features/Lookbook/Domains/Entities/SeasonCandidateDiscoveryResult.swift",
  "OutPick/Features/Lookbook/Domains/Entities/SeasonImportJob.swift",
  "OutPick/Features/Lookbook/Domains/Entities/SeasonCandidate.swift",
  "OutPick/Features/Lookbook/Domains/Entities/LookbookExtractionDiagnostic.swift",
  "OutPick/Features/Lookbook/Domains/Entities/LookbookExtractionReview.swift",
  "OutPick/Features/Lookbook/Domains/Entities/LookbookSeasonRepair.swift",
  "OutPick/Features/Lookbook/Models/DTOs/SeasonImportJobDTO.swift",
  "OutPick/Features/Lookbook/Models/DTOs/SeasonCandidateDTO.swift",
  "OutPickTests/StartSeasonImportExtractionUseCaseTests.swift",
  "OutPickTests/SeasonDiscoveryManagementViewModelTests.swift",
  "OutPickTests/LookbookExtractionReviewViewModelTests.swift",
  "OutPickTests/LookbookSeasonRepairViewModelTests.swift",
  "OutPickTests/CloudFunctions/CloudFunctionsSeasonImportRepositoryTests.swift",
  "OutPickTests/SeasonImportJobRepairStateTests.swift"
];
const retiredTypes = new Set(["CloudFunctionsSeasonImportRepository","CloudFunctionsSeasonAssetRetryRepository","CloudFunctionsSeasonImportJobRequestingRepository","CloudFunctionsSeasonCandidateDiscoveryRepository","CloudFunctionsLookbookExtractionReviewRepository","CloudFunctionsLookbookSeasonRepairRepository","FirestoreSeasonCandidateRepository","FirestoreSeasonImportJobRepository","SeasonImportRequestingRepository","SeasonAssetRetryRequestingRepository","SeasonImportJobRequestingRepositoryProtocol","SeasonCandidateDiscoveryRepositoryProtocol","LookbookExtractionReviewRepositoryProtocol","LookbookSeasonRepairRepositoryProtocol","SeasonCandidateRepositoryProtocol","SeasonImportJobRepositoryProtocol","SeasonImportCloudFunctionsMapper","LookbookExtractionReviewCloudFunctionsMapper","LookbookSeasonRepairCloudFunctionsMapper","LookbookExtractionDiagnosticCloudFunctionsMapper","StartSeasonImportExtractionUseCase","ManageSeasonImportJobsUseCase","ManageLookbookExtractionReviewUseCase","ManageLookbookSeasonRepairUseCase","LoadSelectableSeasonCandidatesUseCase","CreateSeasonFromURLViewModel","CreateBrandDiscoveryViewModel","SeasonImportManagementViewModel","SeasonDiscoveryReviewViewModel","LookbookExtractionReviewViewModel","LookbookSeasonRepairViewModel","SeasonImportManagementView","SeasonDiscoveryReviewView","LookbookExtractionReviewView","LookbookSeasonRepairView","CreateSeasonFromURLView","CreateBrandDiscoveringView","CreateBrandCandidateSelectionView","SeasonCandidateCoverView","SeasonImportRequestReceipt","SeasonAssetRetryReceipt","SeasonImportBatchRequestResult","SeasonImportExtractionProgress","SeasonCandidateDiscoveryResult","SeasonImportJob","SeasonCandidate","LookbookExtractionDiagnostic","LookbookExtractionReview","LookbookSeasonRepair","SeasonImportJobDTO","SeasonCandidateDTO","StartSeasonImportExtractionUseCaseTests","SeasonDiscoveryManagementViewModelTests","LookbookExtractionReviewViewModelTests","LookbookSeasonRepairViewModelTests","CloudFunctionsSeasonImportRepositoryTests","SeasonImportJobRepairStateTests"]);
const read = path => readFileSync(path, 'utf8');
function swiftFiles(root) {
  return readdirSync(root, {withFileTypes: true}).flatMap(entry =>
    entry.isDirectory() ? swiftFiles(join(root, entry.name)) :
      entry.name.endsWith('.swift') ? [join(root, entry.name)] : []);
}
const app = swiftFiles('OutPick').map(path => ({path, text: read(path)}));

test('L178-S01 종료21개 호출이 공개 앱의 모든 Swift 소스에서 제거된다', () => {
  assert.equal(endpoints.length, 21);
  for (const {path, text} of app) {
    for (const endpoint of endpoints) assert.ok(!text.includes(endpoint), path + ': ' + endpoint);
  }
});

test('L178-S02 전용 UI DI와 원명령 복원 경로가 남지 않는다', () => {
  for (const path of retiredFiles) assert.equal(existsSync(path), false, path);
  for (const {path, text} of app) {
    for (const name of retiredTypes) assert.ok(!text.includes(name), path + ': ' + name);
  }
  const base = 'OutPick/Features/Lookbook/';
  assert.doesNotMatch(read(base + 'Views/Admin/AdminBrandManagementView.swift'), /importSeasons|seasonAddition|importManagement/);
  const flow = read(base + 'Views/CreateBrand/brand/CreateBrandFlowView.swift');
  assert.doesNotMatch(flow, /discovering|candidateSelection|discoveryViewModel/);
  assert.match(flow, /CreateBrandCompletedView\(/);
  assert.match(flow, /onFinished\(latestCreatedBrand\?\.id\)/);
});

test('L178-S03 공개 소비자와 목록 밖 관리자 및 공유 큐 저장을 유지한다', () => {
  const text = app.map(item => item.text).join('\n');
  for (const endpoint of ['submitBrandRequest', 'listMyBrandRequests', 'searchBrands',
    'getBrandAdminCapabilities', 'addBrandManager', 'removeBrandManager', 'updateSeasonMoods',
    'createBrand', 'updateBrand', 'softDeleteSeason', 'restoreSeason']) {
    assert.ok(text.includes('"' + endpoint + '"'), endpoint);
  }
  const provider = read('OutPick/Features/Lookbook/Repositories/LookbookRepositoryProvider.swift');
  for (const property of ['seasonRepository', 'brandImageCache', 'seasonMoodAdminRepository',
    'lookbookDeletionRepository', 'importRequestStore']) assert.ok(provider.includes(property), property);
  assert.match(read('OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsBrandStore.swift'),
    /LookbookImportQueueRequestCoordinator/);
  assert.ok(existsSync('OutPick/Features/Lookbook/Domains/Entities/LookbookImportRequest.swift'));
});

test('L178-S04 기존 큐와 마이그레이션 게이트에 종료된 selector가 남지 않는다', () => {
  const active = [];
  for (const path of ['verification/lookbook-queue-ios.json', 'verification/ios-migration-all.json']) {
    const config = JSON.parse(read(path));
    for (const check of config.checks) active.push(...check.args, ...(check.requiredTests ?? []));
  }
  const map = JSON.parse(read('verification/ios-migration-map.json'));
  active.push(...map.selectors, ...map.requiredTests, ...map.mappings.flatMap(row => row.requiredTests));
  for (const value of active) {
    for (const name of retiredTypes) assert.ok(!value.includes(name), value);
  }
});
