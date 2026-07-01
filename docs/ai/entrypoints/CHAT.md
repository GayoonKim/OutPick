# Chat Entrypoints

## 목적

Chat 기능 수정 시 관련 화면, ViewModel, UseCase, Repository, 검색 인덱스 진입점을 빠르게 찾기 위한 문서다.

## 방 목록 검색

- 화면: `OutPick/Features/Chat/Controllers/RoomSearchViewController.swift`
- ViewModel: `OutPick/Features/Chat/ViewModels/RoomSearchViewModel.swift`
- UseCase: `OutPick/Features/Chat/Domain/UseCases/RoomSearchUseCase.swift`
- Repository protocol: `OutPick/DB/Firebase/DatabaseManager/Protocols/FirebaseChatRoomRepositoryProtocol.swift`
- Repository implementation: `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseChatRoomRepository.swift`
- 검색 인덱스 모델: `OutPick/Features/Chat/Domain/Models/ChatRoomSearchIndex.swift`
- Room 저장 인덱스 반영: `OutPick/Features/Chat/Domain/Models/ChatRoom.swift`
- Firestore indexes: `firestore.indexes.json`

방 목록 검색은 방 이름과 방 설명에서 자동 생성한 검색 token을 기준으로 동작한다. 입력과 상태 흐름은 `RoomSearchViewModel`의 Combine state publisher가 소유하고, 방 선택 같은 단발 라우팅 이벤트는 `RoomSearchViewController`의 클로저를 유지한다.
