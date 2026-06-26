# ADR-006: Firebase/Firestore 운영 변경은 명시 승인과 검증 절차를 우선한다


상태: accepted

결정:

- Firebase Functions, Firestore rules, Firestore indexes 변경은 관련 workflow를 확인한다.
- Functions 변경 시 기본 배포 대상은 `firebase deploy --only functions --project outpick-664ae`다.
- Firestore rules 변경 시 기본 배포 대상은 `firebase deploy --only firestore:rules --project outpick-664ae`다.
- Firestore indexes 변경 시 기본 배포 대상은 `firebase deploy --only firestore:indexes --project outpick-664ae`다.
- 운영 함수 삭제, 데이터 삭제, 마이그레이션, 보안 규칙 완화처럼 되돌리기 어려운 작업은 사용자 명시 승인 없이 진행하지 않는다.

이유:

- Firebase/Firestore 변경은 운영 데이터, 보안, 배포 상태에 직접 영향을 줄 수 있다.
- 특히 원격에만 남아 있는 Function 삭제는 실제 운영 영향이 불명확할 수 있어 자동으로 진행하면 위험하다.

트레이드오프:

- 배포와 삭제 작업에서 추가 확인 단계가 필요하다.
- 대신 운영 장애나 데이터 손상 가능성을 줄인다.

재검토 조건:

- 배포 자동화가 안정화되고 staging/production 분리가 명확해지면 승인 기준과 자동화 범위를 다시 정의한다.

