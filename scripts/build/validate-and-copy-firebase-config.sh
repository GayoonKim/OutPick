#!/bin/sh

set -eu

fail() {
  echo "error: [OutPick Environment] $1" >&2
  exit 1
}

require_value() {
  variable_name="$1"
  eval "variable_value=\${$variable_name:-}"
  [ -n "$variable_value" ] || fail "$variable_name 값이 비어 있습니다."
}

require_value OUTPICK_ENVIRONMENT
require_value PRODUCT_BUNDLE_IDENTIFIER
require_value OUTPICK_EXPECTED_FIREBASE_PROJECT_ID
require_value OUTPICK_FIREBASE_PLIST_PATH
require_value OUTPICK_SOCKET_URL
require_value OUTPICK_GOOGLE_REVERSED_CLIENT_ID
require_value OUTPICK_KAKAO_NATIVE_APP_KEY
require_value OUTPICK_KAKAO_URL_SCHEME

[ -f "$OUTPICK_FIREBASE_PLIST_PATH" ] || fail "Firebase plist를 찾을 수 없습니다: $OUTPICK_FIREBASE_PLIST_PATH"

plist_bundle_id=$(/usr/libexec/PlistBuddy -c "Print :BUNDLE_ID" "$OUTPICK_FIREBASE_PLIST_PATH" 2>/dev/null) || \
  fail "Firebase plist에 BUNDLE_ID가 없습니다."
plist_project_id=$(/usr/libexec/PlistBuddy -c "Print :PROJECT_ID" "$OUTPICK_FIREBASE_PLIST_PATH" 2>/dev/null) || \
  fail "Firebase plist에 PROJECT_ID가 없습니다."
plist_client_id=$(/usr/libexec/PlistBuddy -c "Print :CLIENT_ID" "$OUTPICK_FIREBASE_PLIST_PATH" 2>/dev/null) || \
  fail "Firebase plist에 Google CLIENT_ID가 없습니다."
plist_reversed_client_id=$(/usr/libexec/PlistBuddy -c "Print :REVERSED_CLIENT_ID" "$OUTPICK_FIREBASE_PLIST_PATH" 2>/dev/null) || \
  fail "Firebase plist에 REVERSED_CLIENT_ID가 없습니다."

[ "$plist_bundle_id" = "$PRODUCT_BUNDLE_IDENTIFIER" ] || \
  fail "Bundle ID 불일치: build=$PRODUCT_BUNDLE_IDENTIFIER, plist=$plist_bundle_id"
[ "$plist_project_id" = "$OUTPICK_EXPECTED_FIREBASE_PROJECT_ID" ] || \
  fail "Firebase project 불일치: expected=$OUTPICK_EXPECTED_FIREBASE_PROJECT_ID, plist=$plist_project_id"
[ -n "$plist_client_id" ] || fail "Firebase Google CLIENT_ID가 비어 있습니다."
[ "$plist_reversed_client_id" = "$OUTPICK_GOOGLE_REVERSED_CLIENT_ID" ] || \
  fail "Google callback scheme 불일치: build=$OUTPICK_GOOGLE_REVERSED_CLIENT_ID, plist=$plist_reversed_client_id"

case "$OUTPICK_ENVIRONMENT" in
  development)
    expected_kakao_native_app_key="f5f18b00bc7b163aa5be39fef99e646d"
    expected_socket_url="https://outpick-socket-development-xyenspjiwa-du.a.run.app"
    [ "$PRODUCT_BUNDLE_IDENTIFIER" = "GayoonKim.OutPick.dev" ] || \
      fail "Development Bundle ID는 GayoonKim.OutPick.dev여야 합니다."
    [ "$OUTPICK_EXPECTED_FIREBASE_PROJECT_ID" = "outpick-test" ] || \
      fail "Development Firebase project는 outpick-test여야 합니다."
    [ "$OUTPICK_SOCKET_URL" = "$expected_socket_url" ] || \
      fail "Development Socket URL이 canonical URL과 다릅니다."
    ;;
  production)
    expected_kakao_native_app_key="a2b20f7bedfb9582147f572ef004d0f0"
    expected_socket_url="https://outpick-socket-2w7zhxurhq-du.a.run.app"
    [ "$PRODUCT_BUNDLE_IDENTIFIER" = "GayoonKim.OutPick" ] || \
      fail "Production Bundle ID는 GayoonKim.OutPick이어야 합니다."
    [ "$OUTPICK_EXPECTED_FIREBASE_PROJECT_ID" = "outpick-664ae" ] || \
      fail "Production Firebase project는 outpick-664ae여야 합니다."
    [ "$OUTPICK_SOCKET_URL" = "$expected_socket_url" ] || \
      fail "Production Socket URL이 canonical 운영 URL과 다릅니다."
    ;;
  *)
    fail "지원하지 않는 OUTPICK_ENVIRONMENT입니다: $OUTPICK_ENVIRONMENT"
    ;;
esac

[ "$OUTPICK_KAKAO_NATIVE_APP_KEY" = "$expected_kakao_native_app_key" ] || \
  fail "Kakao Native App Key가 실행 환경과 일치하지 않습니다."
[ "$OUTPICK_KAKAO_URL_SCHEME" = "kakao$expected_kakao_native_app_key" ] || \
  fail "Kakao callback scheme이 실행 환경의 Native App Key와 일치하지 않습니다."

if [ "${OUTPICK_VALIDATE_ONLY:-0}" = "1" ]; then
  exit 0
fi

require_value TARGET_BUILD_DIR
require_value UNLOCALIZED_RESOURCES_FOLDER_PATH

destination_directory="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
destination_path="$destination_directory/GoogleService-Info.plist"

mkdir -p "$destination_directory"
cp "$OUTPICK_FIREBASE_PLIST_PATH" "$destination_path"

echo "[OutPick Environment] $OUTPICK_ENVIRONMENT Firebase config 검증·복사 완료"
