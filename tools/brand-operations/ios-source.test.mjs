import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = (path) => readFileSync(path, 'utf8');
const base = 'OutPick/Features/Lookbook/';

test('B5-S04 브랜드 공유의 저장 스냅샷을 보존하며 화면과 프리패치에서 이미지를 제외한다', () => {
  const chat = 'OutPick/Features/Chat/';
  assert.match(source(chat + 'Domain/Models/LookbookSharedContent.swift'), /contentType == \.brand \? nil : thumbnailPathSnapshot/);
  assert.doesNotMatch(source(chat + 'Controllers/ChatViewController+MediaViewport.swift'), /thumbnailPathSnapshot/);
  assert.doesNotMatch(source(chat + 'Views/LookbookShareMessageContentView.swift'), /content\.thumbnailPathSnapshot/);
  assert.match(source(chat + 'Views/Cell/ChatMessageCell.swift'), /representedLookbookSharedContent\?\.displayThumbnailPath/);
  assert.match(source(base + 'Domains/UseCases/MakeLookbookSharedContentUseCase.swift').split('private func makeBrandContent')[1].split('private func makeSeasonContent')[0], /thumbnailPathSnapshot: nil/);
});

test('B5-S01 세 브랜드 목록의 SDK 쿼리에 명시 public 조건을 유지한다', () => {
  const repository = source(base + 'Repositories/Implementations/FirestoreBrandRepository.swift');
  for (const name of ['fetchBrands', 'fetchFeaturedBrands', 'fetchInterestedStyleBrands']) {
    const body = repository.split(`func ${name}(`)[1].split('\n    private func')[0].split('\n    func ')[0];
    assert.match(body, /whereField\("publicationStatus", isEqualTo: "public"\)/);
  }
  assert.match(repository.split('func fetchBrand(')[1].split('func fetchBrands(')[0], /guard brand\.isVisibleToUsers/);
});

test('B5-S02 브랜드 카드와 상세의 로고 요청은0이며 시즌 이미지 경로를 보존한다', () => {
  for (const path of ['Views/LookbookHome/BrandRowView.swift', 'Views/LookbookHome/InterestedStyleBrandCardView.swift',
    'Views/Liked/LikedBrandCardView.swift', 'Views/BrandDetail/BrandDetailHeaderView.swift']) {
    assert.doesNotMatch(source(base + path), /loadImage\(|LookbookAssetImageView\(|\.task\(|logoLoadKey|imageHeight|collageHeight/);
  }
  assert.doesNotMatch(source(base + 'ViewModels/LookbookHomeViewModel.swift'), /\.prefetch\(|\.prefetchAssets\(|\.loadImage\(/);
  assert.match(source(base + 'Views/BrandDetail/SeasonCoverThumbView.swift'), /LookbookAssetImageView\(/);
  assert.match(source(base + 'Views/Liked/LikedPostCardView.swift'), /LookbookAssetImageView\(/);
  assert.match(source(base + 'Services/ImageLoading/BrandImageCache.swift'), /loadImage\(/);
});

test('B5-S03 공개 검색20과 조건별 요청 진입을 연결한다', () => {
  const home = source(base + 'ViewModels/LookbookHomeViewModel.swift');
  assert.match(home, /searchLimit: Int = 20/);
  assert.match(home, /searchPhase == \.results \|\| searchPhase == \.empty/);
  const view = source(base + 'Views/LookbookHome/LookbookHomeView.swift');
  assert.match(view.split('case .results:')[1].split('case .empty:')[0], /brandRequestButton/);
  assert.match(view.split('case .empty:')[1].split('case .failed')[0], /requestBrand\(using: coordinator\)/);
});
