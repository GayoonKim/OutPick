import SwiftUI

struct SeasonMoodManagementView: View {
    let season: Season
    let moods: [StyleMood]
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: (Set<String>) -> Void

    @State private var selectedMoodIDs: Set<String>

    init(
        season: Season,
        moods: [StyleMood],
        isSaving: Bool,
        onCancel: @escaping () -> Void,
        onSave: @escaping (Set<String>) -> Void
    ) {
        self.season = season
        self.moods = moods
        self.isSaving = isSaving
        self.onCancel = onCancel
        self.onSave = onSave
        _selectedMoodIDs = State(initialValue: Set(season.moodIDs))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SEASON EDIT")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(OutPickTheme.SwiftUIColor.accent)

                        Text(season.displayTitle)
                            .font(.system(size: 30, weight: .bold, design: .serif))
                            .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                        Text("이 시즌을 설명하는 스타일 키워드를 최대 5개 선택합니다")
                            .font(.subheadline)
                            .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    }

                    StyleMoodSelectionSection(
                        moods: moods,
                        selectedMoodIDs: $selectedMoodIDs,
                        title: "시즌 스타일",
                        requiresSearchToBrowse: true
                    )
                }
                .padding(20)
            }
            .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(selectedMoodIDs)
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(OutPickTheme.SwiftUIColor.accent)
                        } else {
                            Text("저장")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
