import SwiftUI

struct StyleMoodEditorView: View {
    let existingMood: StyleMood?
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: (StyleMoodMutationDraft, StyleMoodStatus) -> Void

    @State private var displayName: String
    @State private var displayGroup: StyleMoodGroup
    @State private var aliasesText: String
    @State private var isFeaturedInOnboarding: Bool
    @State private var status: StyleMoodStatus

    init(
        existingMood: StyleMood?,
        isSaving: Bool,
        onCancel: @escaping () -> Void,
        onSave: @escaping (StyleMoodMutationDraft, StyleMoodStatus) -> Void
    ) {
        self.existingMood = existingMood
        self.isSaving = isSaving
        self.onCancel = onCancel
        self.onSave = onSave
        _displayName = State(initialValue: existingMood?.displayName ?? "")
        _displayGroup = State(initialValue: existingMood?.displayGroup ?? .essential)
        _aliasesText = State(initialValue: existingMood?.aliases.joined(separator: ", ") ?? "")
        _isFeaturedInOnboarding = State(
            initialValue: existingMood?.isFeaturedInOnboarding ?? false
        )
        _status = State(initialValue: existingMood?.status ?? .active)
    }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    editorialHeader
                    keywordFields
                    groupSelection
                    settingCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 32)
            }
            .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
            .outpickDismissKeyboardOnTap()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: onCancel)
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveButton
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(OutPickTheme.SwiftUIColor.backgroundBase)
            }
        }
        .navigationViewStyle(.stack)
    }

    private var editorialHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("STYLE KEYWORD")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(OutPickTheme.SwiftUIColor.accent)

            Text(existingMood == nil ? "새 스타일 키워드" : "스타일 키워드 편집")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

            Text("검색과 스타일 연결에 사용할 이름과 분류를 정리합니다")
                .font(.subheadline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
    }

    private var keywordFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("KEYWORD")

            VStack(spacing: 0) {
                editorialTextField(
                    title: "이름",
                    placeholder: "예: 다크 아카데미아",
                    text: $displayName
                )

                Divider()
                    .overlay(OutPickTheme.SwiftUIColor.borderSubtle)
                    .padding(.leading, 16)

                editorialTextField(
                    title: "별칭",
                    placeholder: "쉼표로 구분해 입력",
                    text: $aliasesText
                )
            }
            .background(OutPickTheme.SwiftUIColor.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
            )
        }
    }

    private var groupSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("GROUP")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(
                        StyleMoodGroup.allCases.filter { $0 != .other },
                        id: \.self
                    ) { group in
                        Button {
                            displayGroup = group
                        } label: {
                            Text(group.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    displayGroup == group
                                    ? OutPickTheme.SwiftUIColor.backgroundBase
                                    : OutPickTheme.SwiftUIColor.textPrimary
                                )
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(
                                    displayGroup == group
                                    ? OutPickTheme.SwiftUIColor.accent
                                    : OutPickTheme.SwiftUIColor.surfaceBase
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            displayGroup == group
                                            ? OutPickTheme.SwiftUIColor.accent
                                            : OutPickTheme.SwiftUIColor.borderSubtle,
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var settingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("VISIBILITY")

            VStack(spacing: 0) {
                editorialToggle(
                    title: "온보딩 추천",
                    subtitle: "새 사용자의 관심 스타일 선택에 노출합니다",
                    isOn: $isFeaturedInOnboarding
                )

                if existingMood != nil {
                    Divider()
                        .overlay(OutPickTheme.SwiftUIColor.borderSubtle)
                        .padding(.leading, 16)

                    editorialToggle(
                        title: "활성 상태",
                        subtitle: "검색과 새로운 스타일 연결에 사용할 수 있습니다",
                        isOn: Binding(
                            get: { status == .active },
                            set: { status = $0 ? .active : .inactive }
                        )
                    )
                }
            }
            .background(OutPickTheme.SwiftUIColor.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
            )
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            ZStack {
                Text(existingMood == nil ? "스타일 키워드 등록" : "변경사항 저장")
                    .opacity(isSaving ? 0 : 1)

                if isSaving {
                    ProgressView()
                        .tint(OutPickTheme.SwiftUIColor.accent)
                }
            }
            .font(.headline)
            .foregroundStyle(
                canSave
                ? OutPickTheme.SwiftUIColor.backgroundBase
                : OutPickTheme.SwiftUIColor.textDisabled
            )
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                canSave
                ? OutPickTheme.SwiftUIColor.accent
                : OutPickTheme.SwiftUIColor.surfaceElevated
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(canSave == false)
    }

    private var canSave: Bool {
        isSaving == false &&
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(OutPickTheme.SwiftUIColor.textTertiary)
    }

    private func editorialTextField(
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)

            TextField(placeholder, text: text)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(16)
    }

    private func editorialToggle(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }
        }
        .tint(OutPickTheme.SwiftUIColor.accent)
        .padding(16)
    }

    private func save() {
        onSave(
            StyleMoodMutationDraft(
                moodID: nil,
                displayName: displayName,
                displayGroup: displayGroup,
                aliases: aliasesText.split(separator: ",").map(String.init),
                sortOrder: existingMood?.sortOrder,
                isFeaturedInOnboarding: isFeaturedInOnboarding
            ),
            status
        )
    }
}
