#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
validator="$script_directory/validate-and-copy-firebase-config.sh"
fixture="$script_directory/fixtures/GoogleService-Info-Fixture.plist"
production_url="https://outpick-socket-2w7zhxurhq-du.a.run.app"
temporary_directory=$(mktemp -d)

cleanup() {
  rm -rf "$temporary_directory"
}
trap cleanup EXIT

run_validator() {
  OUTPICK_VALIDATE_ONLY=1 \
  OUTPICK_ENVIRONMENT="$1" \
  PRODUCT_BUNDLE_IDENTIFIER="$2" \
  OUTPICK_EXPECTED_FIREBASE_PROJECT_ID="$3" \
  OUTPICK_FIREBASE_PLIST_PATH="$4" \
  OUTPICK_SOCKET_URL="$5" \
  OUTPICK_PRODUCTION_SOCKET_URL="$production_url" \
  OUTPICK_GOOGLE_REVERSED_CLIENT_ID="$6" \
  OUTPICK_KAKAO_NATIVE_APP_KEY="$7" \
  OUTPICK_KAKAO_URL_SCHEME="$8" \
  "$validator"
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    echo "expected failure but succeeded: $*" >&2
    exit 1
  fi
}

development_plist="$temporary_directory/Development.plist"
production_plist="$temporary_directory/Production.plist"
cp "$fixture" "$development_plist"
cp "$fixture" "$production_plist"
/usr/libexec/PlistBuddy -c "Set :BUNDLE_ID GayoonKim.OutPick" "$production_plist"
/usr/libexec/PlistBuddy -c "Set :PROJECT_ID outpick-664ae" "$production_plist"
/usr/libexec/PlistBuddy -c "Set :CLIENT_ID production.apps.googleusercontent.com" "$production_plist"
/usr/libexec/PlistBuddy -c "Set :REVERSED_CLIENT_ID com.googleusercontent.apps.production" "$production_plist"

run_validator \
  development \
  GayoonKim.OutPick.dev \
  outpick-test \
  "$development_plist" \
  https://development-socket.example.com \
  com.googleusercontent.apps.development \
  development-kakao-key \
  kakaodevelopment-kakao-key

run_validator \
  production \
  GayoonKim.OutPick \
  outpick-664ae \
  "$production_plist" \
  "$production_url" \
  com.googleusercontent.apps.production \
  production-kakao-key \
  kakaoproduction-kakao-key

expect_failure run_validator \
  development \
  GayoonKim.OutPick.dev \
  outpick-test \
  "$temporary_directory/Missing.plist" \
  https://development-socket.example.com \
  com.googleusercontent.apps.development \
  development-kakao-key \
  kakaodevelopment-kakao-key

expect_failure run_validator \
  development \
  GayoonKim.OutPick \
  outpick-test \
  "$development_plist" \
  https://development-socket.example.com \
  com.googleusercontent.apps.development \
  development-kakao-key \
  kakaodevelopment-kakao-key

expect_failure run_validator \
  development \
  GayoonKim.OutPick.dev \
  outpick-664ae \
  "$development_plist" \
  https://development-socket.example.com \
  com.googleusercontent.apps.development \
  development-kakao-key \
  kakaodevelopment-kakao-key

expect_failure run_validator \
  development \
  GayoonKim.OutPick.dev \
  outpick-test \
  "$development_plist" \
  "$production_url" \
  com.googleusercontent.apps.development \
  development-kakao-key \
  kakaodevelopment-kakao-key

expect_failure run_validator \
  development \
  GayoonKim.OutPick.dev \
  outpick-test \
  "$development_plist" \
  https://development-socket.example.com \
  com.googleusercontent.apps.wrong \
  development-kakao-key \
  kakaodevelopment-kakao-key

expect_failure run_validator \
  development \
  GayoonKim.OutPick.dev \
  outpick-test \
  "$development_plist" \
  https://development-socket.example.com \
  com.googleusercontent.apps.development \
  development-kakao-key \
  kakaowrong-key

echo "Firebase environment validator tests passed."
