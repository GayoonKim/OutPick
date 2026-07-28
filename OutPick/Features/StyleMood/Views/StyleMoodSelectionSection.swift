import SwiftUI

struct StyleMoodSelectionSection: View {
    let moods: [StyleMood]
    @Binding var selectedMoodIDs: Set<String>
    var title: String = "브랜드 스타일"
    var maximumSelectionCount: Int = 5
    var showsAddButton: Bool = false
    var requiresSearchToBrowse: Bool = false
    var onAddMood: (() -> Void)?

    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("STYLE INDEX")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.accent)

                    Text(title)
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                }

                Spacer()

                Text("\(selectedMoodIDs.count)/\(maximumSelectionCount)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(
                        selectedMoodIDs.count == maximumSelectionCount
                        ? OutPickTheme.SwiftUIColor.accent
                        : OutPickTheme.SwiftUIColor.textSecondary
                    )
            }

            if requiresSearchToBrowse {
                searchField
                selectedMoodChips

                if hasSearchQuery {
                    if matchingMoods.isEmpty {
                        emptySearchCard
                    } else if unselectedMatchingMoods.isEmpty == false {
                        moodList(unselectedMatchingMoods)
                    }
                }
            } else {
                moodList(selectableMoods)

                if showsAddButton {
                    addMoodButton
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.iconSecondary)

            TextField("스타일 키워드 검색", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

            if searchText.isEmpty == false {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.iconSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("스타일 키워드 검색어 지우기")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var selectedMoodChips: some View {
        if selectedMoods.isEmpty == false {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedMoods) { mood in
                        Button {
                            selectedMoodIDs.remove(mood.id)
                        } label: {
                            HStack(spacing: 6) {
                                Text(mood.displayName)
                                    .lineLimit(1)
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(OutPickTheme.SwiftUIColor.accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(mood.displayName) 선택 해제")
                    }
                }
            }
        }
    }

    private func moodList(_ displayedMoods: [StyleMood]) -> some View {
        VStack(spacing: 0) {
            ForEach(displayedMoods) { mood in
                Button {
                    toggle(mood)
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mood.displayName)
                                .font(.system(size: 16, weight: .semibold, design: .serif))
                                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                            if mood.aliases.isEmpty == false {
                                Text(mood.aliases.prefix(3).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Image(
                            systemName: selectedMoodIDs.contains(mood.id)
                            ? "checkmark.circle.fill"
                            : "plus.circle"
                        )
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            selectedMoodIDs.contains(mood.id)
                            ? OutPickTheme.SwiftUIColor.accent
                            : OutPickTheme.SwiftUIColor.iconSecondary
                        )
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 58)
                    .contentShape(Rectangle())
                    .opacity(
                        selectedMoodIDs.count >= maximumSelectionCount &&
                        selectedMoodIDs.contains(mood.id) == false
                        ? 0.45
                        : 1
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    selectedMoodIDs.count >= maximumSelectionCount &&
                    selectedMoodIDs.contains(mood.id) == false
                )

                if mood.id != displayedMoods.last?.id {
                    Divider()
                        .overlay(OutPickTheme.SwiftUIColor.borderSubtle)
                        .padding(.leading, 16)
                }
            }
        }
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
        )
    }

    private var emptySearchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("일치하는 스타일 키워드가 없습니다")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                Text("다른 이름이나 별칭으로 검색해 보세요")
                    .font(.caption)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }

            if shouldShowAddButton {
                Divider()
                    .overlay(OutPickTheme.SwiftUIColor.borderSubtle)
                addMoodButton
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
        )
    }

    private var addMoodButton: some View {
        Button {
            onAddMood?()
        } label: {
            HStack {
                Label("새 스타일 키워드 추가", systemImage: "plus")
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
            }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
        }
        .buttonStyle(.plain)
        .disabled(selectedMoodIDs.count >= maximumSelectionCount)
        .opacity(selectedMoodIDs.count >= maximumSelectionCount ? 0.45 : 1)
    }

    private var selectableMoods: [StyleMood] {
        moods.filter {
            $0.status == .active || selectedMoodIDs.contains($0.id)
        }
    }

    private var selectedMoods: [StyleMood] {
        moods.filter { selectedMoodIDs.contains($0.id) }
    }

    private var matchingMoods: [StyleMood] {
        StyleMoodPickerPolicy.searchResults(in: moods, query: searchText)
    }

    private var unselectedMatchingMoods: [StyleMood] {
        matchingMoods.filter { selectedMoodIDs.contains($0.id) == false }
    }

    private var hasSearchQuery: Bool {
        StyleMoodPickerPolicy.normalizedQuery(searchText).isEmpty == false
    }

    private var shouldShowAddButton: Bool {
        showsAddButton &&
        StyleMoodPickerPolicy.shouldShowCreateAction(
            query: searchText,
            matchingMoods: matchingMoods,
            selectedCount: selectedMoodIDs.count,
            maximumSelectionCount: maximumSelectionCount
        )
    }

    private func toggle(_ mood: StyleMood) {
        if selectedMoodIDs.contains(mood.id) {
            selectedMoodIDs.remove(mood.id)
        } else if mood.status == .active,
                  selectedMoodIDs.count < maximumSelectionCount {
            selectedMoodIDs.insert(mood.id)
        }
    }
}
