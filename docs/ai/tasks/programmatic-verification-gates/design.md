# 프로그램적 검증 — 간소화 설계

2026-10-01 최신 사용자 결정: 사용자가 GPT-6.1 Sol High ↔ GPT-6.1 Sol Light를 직접 바꾸고, 공통 AGENTS.md와 실제 프로그램적 게이트를 사용한다. 기존 역할은 유지한다.

기준 문서는 [간소화 운영 기준](../../architecture/PROGRAMMATIC_VERIFICATION.md)이다. 이전 자동 전달·권한 분리 인프라·범용 제품화 설계와 미실행 Go 테스트 초안은 삭제한다.

- 사용자+GPT-6.1 Sol High: 요구사항·계획·테스트·합격 기준 검토.
- GPT-6.1 Sol Light: 승인된 구현·게이트 실행·원본 결과 보고.
- 프로그램: 필수 검사 실행과 누락·실패·통과 판정.
- GPT-6.1 Sol High: 결과 분석과 수정 방향 검토.
- 모델 변경: 사용자가 직접 수행.

필수 검사·합격 기준·누락 방지는 유지한다. Node.js 공용 원본을 `tools/verification-gate/`에서 버전 관리하고 공용 위치에 설치한다. OutPick별 설정은 `verification/`에서 관리한다.

다음 작업: [계획](plan.md). 현재 수행 상태: [진행](progress.md).
