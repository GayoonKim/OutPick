# iOS 프로그램적 검증

Node 24, Xcode, iPhone 17 Pro iOS 26.2 Simulator와 로컬 Development Firebase plist가 필요하다.

```sh
node tools/verification-gate/gate.mjs --project . --config verification/ios-migration-all.json
node tools/verification-gate/gate.mjs --project . --config verification/repository-integrity.json
node tools/verification-gate/gate.mjs --project . --config verification/secrets.json
```

ios-migration-all은 기존 앱 설정 24개 check의 shell/xcode selector·필수 ID 합집합이다. ios-migration-map으로 대응을 확인한다. 결과는 output/verification/{실행 ID}/summary.json과 원본 로그에 저장된다. 필수 누락/skip/0건/실패/환경 미준비를 통과로 처리하지 않는다.

민감정보 검사는 고정 Gitleaks release를 .local/tools/gitleaks에 준비하고 tools/security/gitleaks-lock.json의 checksum과 대조한다. .local/security-policy.json에는 version=1, forbiddenValues, 명시 reviewedBinaryPrefixes를 구성한다. 실제 금지 값은 로그나 커밋에 포함하지 않는다. candidate/index/전송 commit 범위를 각각 검사하며 새 iOS 이관 history 범위는 기존 기준 commit 이후다. 과거 전체 공개 이력은 이번 검사 대상이 아니다.

계약/공용 도구 변경은 manifest의 source와 파일 해시를 리뷰하고 갱신한다. 사본 파일만 바꾸면 integrity gate가 실패한다. 실제 Chrome/Safari·Google/Kakao 로그인은 수동 QA이며 자동 테스트로 대체하지 않는다.
