# Main Tab Shell Standardization QA Checklist

## 빌드/정적 검증

- [x] `git diff --check`
- [x] `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`
- [x] `rg "CustomTabBarViewController|CustomTabBarView"`로 앱 실행 경로 잔여 사용처 확인

## 기본 탭 QA

- [x] 로그인 후 메인 탭에 진입한다.
- [x] 오픈채팅 탭으로 전환된다.
- [x] 참여 채팅방 탭으로 전환된다.
- [x] 룩북 탭으로 전환된다.
- [x] 좋아요 탭으로 전환된다.
- [x] 내 정보 탭으로 전환된다.
- [x] 이미 선택된 탭을 다시 눌러도 scroll-to-top, refresh, pop 같은 동작이 발생하지 않는다.
- [x] 탭 바 높이와 터치 영역이 기존 60pt 성격을 유지한다.

## Chat QA

- [x] 오픈채팅 root에서는 탭 바가 보인다.
- [x] 참여 채팅방 root에서는 탭 바가 보인다.
- [x] Chat 검색 화면으로 push되면 탭 바가 숨겨진다.
- [x] Chat 검색 화면 back/cancel은 pop 경로를 탄다.
- [x] Chat 방 생성 화면으로 push되면 탭 바가 숨겨진다.
- [x] Chat 방 생성 화면 back/cancel은 pop 경로를 탄다.
- [x] Chat 방 본문으로 push되면 탭 바가 숨겨진다.
- [x] Chat 방 본문 커스텀 back 버튼은 pop 경로를 탄다.
- [x] Chat 방 본문 edge swipe pop이 동작한다.
- [x] Chat 방 본문 edge swipe 취소 시 화면과 탭 바 상태가 깨지지 않는다.
- [x] Chat 방 본문에서 root로 돌아오면 탭 바가 늦게 올라오지 않고 자연스럽게 복구된다.

## Lookbook/Liked QA

- [x] Lookbook root에서는 탭 바가 보인다.
- [x] Liked root에서는 탭 바가 보인다.
- [x] Lookbook 브랜드 상세로 push되면 탭 바가 숨겨진다.
- [x] Lookbook 시즌 상세로 push되면 탭 바가 숨겨진다.
- [x] Lookbook 포스트 상세로 push되면 탭 바가 숨겨진다.
- [x] Liked에서 브랜드/시즌/포스트 상세로 push되면 탭 바가 숨겨진다.
- [x] 상세 커스텀 back 버튼은 pop 경로를 탄다.
- [x] 상세 edge swipe pop이 동작한다.
- [x] 상세 edge swipe 취소 시 화면과 탭 바 상태가 깨지지 않는다.
- [x] root로 돌아오면 탭 바가 늦게 올라오지 않고 자연스럽게 복구된다.

## Cross-feature Routing QA

- [x] 룩북 공유 완료 후 채팅방 이동이 Joined Rooms 탭 navigation stack에서 동작한다.
- [x] 채팅방 공유 카드 탭 시 Lookbook 탭 navigation stack에 상세가 push된다.
- [x] route 전환 전 표시 중인 sheet/modal dismiss 정책이 유지된다.

## 남은 위험

- 기존 custom tab bar와 시스템 tab bar의 터치/선택 feedback 차이는 후속 UI 조정 후보다.
