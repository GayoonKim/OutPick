//
//  CreateBrandView.swift
//  OutPick
//
//  Created by 김가윤 on 12/20/25.
//

import SwiftUI
import UIKit
import PhotosUI

struct CreateBrandView: View {

    @StateObject private var viewModel: CreateBrandViewModel
    @State private var isImagePickerPresented: Bool = false
    @State private var heroProgress: CGFloat = 0
    @State private var revealedFormItemCount: Int = 0
    @State private var isGuideVisible: Bool = false
    @State private var didStartEntranceAnimation: Bool = false
    @State private var entranceTask: Task<Void, Never>?
    let onCompleted: (CreateBrandViewModel.CreatedBrand) -> Void

    /// RepositoryProvider 기반으로만 의존성을 주입합니다.
    /// - Note: 화면/상위 조립 계층(AppContainer 등)에서 provider를 내려주는 구조를 유지합니다.
    init(
        provider: LookbookRepositoryProvider = .shared,
        onCompleted: @escaping (CreateBrandViewModel.CreatedBrand) -> Void = { _ in }
    ) {
        _viewModel = StateObject(
            wrappedValue: CreateBrandViewModel(
                brandStore: provider.brandStore,
                storageService: provider.storageService,
                thumbnailer: provider.thumbnailer
            )
        )
        self.onCompleted = onCompleted
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    introSection(containerHeight: proxy.size.height, containerWidth: proxy.size.width)
                    formSection
                    guideSection
                }
                .frame(minHeight: proxy.size.height, alignment: .top)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.97, blue: 0.94),
                        Color.white
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
        }
        .sheet(isPresented: $isImagePickerPresented) {
            BrandLogoPicker { picked in
                viewModel.setPickedLogo(
                    thumbImage: picked.thumbImage,
                    thumbData: picked.thumbData,
                    detailData: picked.detailData
                )
            } onFailed: { error in
                viewModel.message = "로고 이미지 처리 실패: \(error.localizedDescription)"
            }
        }
        .onAppear {
            startEntranceAnimationIfNeeded()
        }
        .onDisappear {
            entranceTask?.cancel()
        }
    }
}

private extension CreateBrandView {
    var totalAnimatedFormItemCount: Int { 5 }

    func introSection(containerHeight: CGFloat, containerWidth: CGFloat) -> some View {
        let contentWidth = max(containerWidth - 40, 0)
        let introWidth = min(contentWidth, 360)
        let centeredLeadingOffset = max((contentWidth - introWidth) / 2, 0)
        let initialTopPadding = max(containerHeight * 0.38, 24)
        let finalTopPadding: CGFloat = 8

        return VStack(alignment: .leading, spacing: 12) {
            Text("브랜드 등록을 시작합니다")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("브랜드 기본 정보와 URL을 먼저 저장하고, 다음 단계에서 시즌 후보를 탐색할 준비를 합니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: introWidth, alignment: .leading)
        .padding(.top, initialTopPadding - (initialTopPadding - finalTopPadding) * heroProgress)
        .offset(
            x: centeredLeadingOffset * (1 - heroProgress),
            y: (1 - heroProgress) * 18
        )
        .opacity(Double(heroProgress))
        .mask(alignment: .leading) {
            Rectangle()
                .scaleEffect(x: max(heroProgress, 0.001), y: 1, anchor: .leading)
        }
    }

    var formSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            animatedFormItem(index: 0) {
                formField(title: "브랜드명") {
                    TextField("예: LOEWE", text: $viewModel.brandName)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                }
            }

            animatedFormItem(index: 1) {
                formField(title: "브랜드 URL") {
                    TextField("https://www.example.com", text: $viewModel.websiteURLText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
            }

            animatedFormItem(index: 2) {
                formField(title: "로고") {
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            isImagePickerPresented = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "photo.on.rectangle.angled")
                                Text(viewModel.selectedLogoImage == nil ? "로고 이미지 선택" : "로고 이미지 다시 선택")
                                Spacer()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(Color(red: 0.95, green: 0.92, blue: 0.86))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        if let selectedLogoImage = viewModel.selectedLogoImage {
                            Image(uiImage: selectedLogoImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                            Button {
                                viewModel.clearPickedLogo()
                            } label: {
                                Text("로고 이미지 제거")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.black)
                            }
                        } else {
                            Text("선택된 로고 이미지가 없습니다.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            animatedFormItem(index: 3) {
                Toggle(isOn: $viewModel.isFeatured) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("피처드")
                            .font(.subheadline.weight(.semibold))
                        Text("홈에서 더 우선적으로 보여줄 브랜드로 표시합니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.black)
            }

            if let message = viewModel.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            animatedFormItem(index: 4) {
                Button {
                    Task {
                        if let createdBrand = await viewModel.saveBrand() {
                            onCompleted(createdBrand)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Spacer()
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("브랜드 생성")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 16)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(
                    viewModel.isSaving ||
                    viewModel.brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .opacity(
                    viewModel.isSaving ||
                    viewModel.brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? 0.55 : 1
                )
            }
        }
        .padding(20)
        .background(.white.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 18, x: 0, y: 10)
        .opacity(revealedFormItemCount > 0 ? 1 : 0)
        .offset(y: revealedFormItemCount > 0 ? 0 : 18)
    }

    var guideSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("안내")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("브랜드 내부 ID는 자동 생성되며, 동일한 브랜드명은 중복 등록할 수 없습니다. 브랜드 URL은 이후 시즌 후보 자동 탐지의 기준값으로 사용됩니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .opacity(isGuideVisible ? 1 : 0)
        .offset(x: isGuideVisible ? 0 : -20)
    }

    func formField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color(red: 0.98, green: 0.98, blue: 0.97))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    func animatedFormItem<Content: View>(
        index: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isVisible = revealedFormItemCount > index

        return content()
            .opacity(isVisible ? 1 : 0)
            .offset(x: isVisible ? 0 : -24)
    }

    func startEntranceAnimationIfNeeded() {
        guard !didStartEntranceAnimation else { return }
        didStartEntranceAnimation = true

        entranceTask = Task {
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.9)) {
                    heroProgress = 1
                }
            }

            try? await Task.sleep(nanoseconds: 320_000_000)

            for index in 0..<totalAnimatedFormItemCount {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.45)) {
                        revealedFormItemCount = index + 1
                    }
                }

                try? await Task.sleep(nanoseconds: 90_000_000)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.4)) {
                    isGuideVisible = true
                }
            }
        }
    }
}

// MARK: - iOS 15 호환 이미지 피커 (PHPickerViewController)

private struct BrandLogoPickResult {
    let thumbImage: UIImage
    let thumbData: Data
    let detailData: Data
}

private struct BrandLogoPicker: UIViewControllerRepresentable {

    let onPicked: (BrandLogoPickResult) -> Void
    let onFailed: (Error) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onFailed: onFailed)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {

        let onPicked: (BrandLogoPickResult) -> Void
        let onFailed: (Error) -> Void

        init(
            onPicked: @escaping (BrandLogoPickResult) -> Void,
            onFailed: @escaping (Error) -> Void
        ) {
            self.onPicked = onPicked
            self.onFailed = onFailed
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let first = results.first else { return }

            Task {
                do {
                    let pair = try await DefaultMediaProcessingService.shared.makePair(from: first, index: 0)
                    defer { try? FileManager.default.removeItem(at: pair.originalFileURL) }

                    guard let thumbImage = UIImage(data: pair.thumbData) else {
                        throw NSError(
                            domain: "BrandLogoPicker",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "썸네일 이미지 생성에 실패했습니다."]
                        )
                    }
                    let detailPolicy = ThumbnailPolicies.brandLogoDetail
                    guard
                        let detailData = DefaultMediaProcessingService.makeThumbnailData(
                            from: pair.originalFileURL,
                            maxPixel: detailPolicy.maxPixelSize,
                            quality: detailPolicy.quality
                        )
                    else {
                        throw NSError(
                            domain: "BrandLogoPicker",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "확대용 이미지 생성에 실패했습니다."]
                        )
                    }

                    await MainActor.run {
                        onPicked(
                            BrandLogoPickResult(
                                thumbImage: thumbImage,
                                thumbData: pair.thumbData,
                                detailData: detailData
                            )
                        )
                    }
                } catch {
                    await MainActor.run {
                        onFailed(error)
                    }
                }
            }
        }
    }
}

#Preview {
    CreateBrandView()
}
