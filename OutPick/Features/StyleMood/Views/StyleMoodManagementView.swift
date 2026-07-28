import SwiftUI

private struct StyleMoodEditorTarget: Identifiable {
    let id: String
    let mood: StyleMood?

    static func create() -> StyleMoodEditorTarget {
        StyleMoodEditorTarget(id: "create-\(UUID().uuidString)", mood: nil)
    }

    static func edit(_ mood: StyleMood) -> StyleMoodEditorTarget {
        StyleMoodEditorTarget(id: "edit-\(mood.id)", mood: mood)
    }
}

struct StyleMoodManagementView: View {
    @StateObject private var viewModel: StyleMoodManagementViewModel
    private let coordinator: LookbookCoordinator

    @State private var editorTarget: StyleMoodEditorTarget?

    init(
        viewModel: StyleMoodManagementViewModel,
        coordinator: LookbookCoordinator
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.coordinator = coordinator
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                searchField

                if viewModel.isLoading {
                    ProgressView()
                        .tint(OutPickTheme.SwiftUIColor.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ForEach(StyleMoodGroup.allCases.filter { $0 != .other }, id: \.self) { group in
                        let moods = viewModel.visibleMoods(in: group)
                        if moods.isEmpty == false {
                            moodGroup(group, moods: moods)
                        }
                    }

                    if viewModel.moods.isEmpty == false,
                       viewModel.searchText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                       ).isEmpty == false,
                       hasVisibleMoods == false {
                        Text("검색 결과가 없습니다")
                            .font(.footnote)
                            .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                }

                if let message = viewModel.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
        .lookbookNavigationBar(
            title: "스타일 키워드 관리",
            showsBackButton: true,
            onBack: { coordinator.pop() }
        )
        .safeAreaInset(edge: .bottom) {
            Button {
                editorTarget = .create()
            } label: {
                Label("새 스타일 키워드 추가", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(OutPickTheme.SwiftUIColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(20)
            .background(OutPickTheme.SwiftUIColor.backgroundBase)
        }
        .task {
            await viewModel.load()
        }
        .sheet(item: $editorTarget) { target in
            StyleMoodEditorView(
                existingMood: target.mood,
                isSaving: viewModel.isSaving,
                onCancel: { editorTarget = nil },
                onSave: { draft, status in
                    Task {
                        let saved = await viewModel.save(
                            existingMood: target.mood,
                            draft: draft,
                            status: status
                        )
                        if saved != nil {
                            editorTarget = nil
                        }
                    }
                }
            )
        }
    }

    private var hasVisibleMoods: Bool {
        StyleMoodGroup.allCases
            .filter { $0 != .other }
            .contains { viewModel.visibleMoods(in: $0).isEmpty == false }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.iconSecondary)

            TextField("이름 또는 별칭 검색", text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

            if viewModel.searchText.isEmpty == false {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.iconSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(OutPickTheme.SwiftUIColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func moodGroup(_ group: StyleMoodGroup, moods: [StyleMood]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.displayName)
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

            ForEach(moods) { mood in
                Button {
                    editorTarget = .edit(mood)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mood.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                            if mood.aliases.isEmpty == false {
                                Text(mood.aliases.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if mood.status == .inactive {
                            Text("비활성")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
                        }
                        Image(systemName: "chevron.right")
                            .foregroundStyle(OutPickTheme.SwiftUIColor.iconSecondary)
                    }
                    .padding(16)
                    .background(OutPickTheme.SwiftUIColor.surfaceBase)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
