# OutPick Entrypoints

## 목적

기능 수정이나 새 기능 추가 시 AI 에이전트가 어디부터 봐야 하는지 빠르게 확인하기 위한 문서다.

## 공통 진입점

- 앱 조립: `OutPick/App`
- 기능 코드: `OutPick/Features`
- 공통 인프라: `OutPick/Infra`
- Firebase Functions: `functions/src/index.ts`
- Firestore rules: `firestore.rules`
- Firestore indexes: `firestore.indexes.json`

## Lookbook

- CompositionRoot: `OutPick/Features/Lookbook/LookbookCompositionRoot.swift`
- Container: `OutPick/Features/Lookbook/LookbookContainer.swift`
- Coordinator: `OutPick/Features/Lookbook/Coordinators/LookbookCoordinator.swift`
- ViewModels: `OutPick/Features/Lookbook/ViewModels`
- Views: `OutPick/Features/Lookbook/Views`
- UseCases: `OutPick/Features/Lookbook/Domains/UseCases`
- Entities: `OutPick/Features/Lookbook/Domains/Entities`
- Repository protocols: `OutPick/Features/Lookbook/Repositories/Protocols`
- Repository implementations: `OutPick/Features/Lookbook/Repositories/Implementations`

## Chat

- CompositionRoot: `OutPick/Features/Chat/ChatCompositionRoot.swift`
- Container: `OutPick/Features/Chat/ChatContainer.swift`
- Coordinator: `OutPick/Features/Chat/ChatCoordinator.swift`
- ViewModels: `OutPick/Features/Chat/ViewModels`
- Controllers: `OutPick/Features/Chat/Controllers`
- UseCases: `OutPick/Features/Chat/Domain/UseCases`
- Repositories/Managers: `OutPick/Features/Chat/Repositories`, `OutPick/Features/Chat/Managers`

## Profile

- CompositionRoot: `OutPick/Features/Profile/ProfileCompositionRoot.swift`
- Detail CompositionRoot: `OutPick/Features/Profile/UserProfileDetailCompositionRoot.swift`
- Coordinator: `OutPick/Features/Profile/ProfileCoordinator.swift`
- Detail Coordinator: `OutPick/Features/Profile/UserProfileDetailCoordinator.swift`
- ViewModels: `OutPick/Features/Profile/ViewModels`
- Views: `OutPick/Features/Profile/Views`
- Repositories: `OutPick/Features/Profile/Repository`

## Login

- CompositionRoot: `OutPick/Features/Login/Presentation/LoginCompositionRoot.swift`
- ViewModel: `OutPick/Features/Login/Presentation/LoginViewModel.swift`
- ViewController: `OutPick/Features/Login/Presentation/LoginViewController.swift`
- Auth Repository: `OutPick/Features/Login/Repository/DefaultSocialAuthRepository.swift`
- Protocols: `OutPick/Features/Login/Protocols`

## 좋아요 탭 현재 작업

- 진행 문서: `docs/ai/tasks/liked-tab/`
- 현재 상태 포인터: `docs/ai/tasks/active.md`
- 확실하지 않음: 이 섹션은 현재 작업 이관 전 1차 진입점이다. `HANDOFF.md` 이관 후 갱신한다.
