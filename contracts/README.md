# OutPick Versioned Contracts

## 목적

앱·Functions·Socket·Worker·Rules가 함께 소비하는 exact enum, 상태 전이, identity와 API 계약의 진입점이다. 문서의 제품 결정과 실제 구현 사이에서 이름·상태·오류가 달라지지 않게 versioned JSON을 기준으로 사용한다.

## 계약 목록

| 계약 | 파일 | 소비자 | 관련 결정 |
| --- | --- | --- | --- |
| Chat UGC safety/moderation v1 | `chat-moderation-v1.json` | iOS, Functions, Socket, Firestore/Storage Rules, 관리자 웹 | ADR-024, `docs/ai/tasks/chat-ugc-safety-room-moderation/` |
| Lookbook extraction issue v1 | `lookbook-extraction-issue-v1.json` | Functions, Lookbook import worker, 운영 CLI | `docs/ai/tasks/lookbook-extraction-issue-operations/` |

## 변경 원칙

- 호환되는 필드·enum 추가도 계약 fixture와 각 소비자 테스트를 함께 갱신한다.
- 기존 의미를 바꾸거나 enum을 제거하면 schemaVersion을 올리고 migration·rollback을 먼저 기록한다.
- raw secret, provider token, email, 운영 credential과 실제 사용자 데이터는 계약 파일에 넣지 않는다.
- JSON parse와 소비자별 contract test가 통과하기 전에는 배포하지 않는다.
