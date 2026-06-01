# OutPick Data Schema

## 목적

OutPick의 주요 데이터 모델, Firestore 문서 구조, 로컬 저장 구조를 AI 에이전트가 확인하기 위한 문서다.

## 작성 원칙

- 데이터 모델은 기능 요구사항과 완료 기준에서 출발한다.
- Firebase, Firestore, Cloud Functions, 로컬 저장소 접근은 View에서 직접 하지 않는다.
- Repository와 UseCase 경계를 통해 데이터 접근 책임을 분리한다.
- 확정되지 않은 컬렉션, 필드, 인덱스는 확실하지 않음으로 표시한다.

## 현재 상태

- 확실하지 않음: 전체 데이터 스키마는 아직 완성 정리되지 않았다.
- 현재 코드 기준 룩북 영역에는 Brand, Season, Post, Comment, user state 계열 모델이 존재한다.
- Firestore rules와 indexes는 루트의 `firestore.rules`, `firestore.indexes.json`을 기준으로 확인한다.
