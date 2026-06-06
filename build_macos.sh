#!/bin/bash

# Exit on error
set -e

# Change directory to the script's directory (project root)
cd "$(dirname "$0")"

APP_NAME="Pod"
RELEASE_DIR="build/macos/Build/Products/Release"
APP_BUNDLE="${RELEASE_DIR}/${APP_NAME}.app"
DMG_OUTPUT="${RELEASE_DIR}/Pod.dmg"
STAGING_DIR="${RELEASE_DIR}/dmg_staging"
ENABLE_FINDER_DMG_LAYOUT="${ENABLE_FINDER_DMG_LAYOUT:-0}"

detect_sign_identity() {
  local identity
  for prefix in "Developer ID Application" "Apple Distribution" "Apple Development"; do
    identity=$(
      security find-identity -v -p codesigning 2>/dev/null \
        | awk -v prefix="${prefix}" -F '"' '$2 ~ "^" prefix { print $2; exit }'
    )
    if [ -n "${identity}" ]; then
      printf '%s' "${identity}"
      return 0
    fi
  done
  return 1
}

if [ -z "${SIGN_IDENTITY+x}" ]; then
  SIGN_IDENTITY="$(detect_sign_identity || true)"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

# macOS does not always have C.UTF-8; create-dmg invokes Perl/AppleScript tools
# that warn noisily when the inherited locale is unsupported.
if [ "${LC_ALL:-}" = "C.UTF-8" ] || [ "${LANG:-}" = "C.UTF-8" ]; then
  export LC_ALL="en_US.UTF-8"
  export LANG="en_US.UTF-8"
fi

cleanup() {
  rm -rf "${STAGING_DIR}"
  rm -f "${RELEASE_DIR}"/rw.*.Pod.dmg
}
trap cleanup EXIT

echo "========================================="
echo " 📦 Packaging Pod into DMG (macOS)       "
echo "========================================="

echo ""
echo "Step 1: Building Flutter macOS app in Release mode..."
BUILD_ARGS=(macos --release)
if flutter build macos -h 2>/dev/null | grep -q -- "--universal"; then
  BUILD_ARGS+=(--universal)
fi
flutter build "${BUILD_ARGS[@]}"

# Fallback check
if [ ! -d "${APP_BUNDLE}" ]; then
  if [ -d "${RELEASE_DIR}/pod.app" ]; then
    APP_NAME="pod"
    APP_BUNDLE="${RELEASE_DIR}/${APP_NAME}.app"
  else
    echo "❌ Error: Could not find build/.app bundle at ${RELEASE_DIR}."
    exit 1
  fi
fi

echo ""
echo "Step 2: Clearing quarantine/resource attributes before signing..."
xattr -cr "${APP_BUNDLE}" || true

echo ""
if [ "${SIGN_IDENTITY}" = "-" ]; then
  echo "Step 3: Ad-hoc code signing..."
  echo "⚠️  No valid Apple code signing identity was found. Set SIGN_IDENTITY explicitly or install a certificate with its private key."
  codesign --deep --force --sign - "${APP_BUNDLE}"
else
  echo "Step 3: Apple code signing with hardened runtime..."
  echo "✓ Signing identity: ${SIGN_IDENTITY}"
  codesign --deep --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"
fi
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
echo "✓ Code signing verified"

EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${APP_BUNDLE}/Contents/Info.plist")
EXECUTABLE_PATH="${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"
ARCHS=$(lipo -archs "${EXECUTABLE_PATH}" 2>/dev/null || true)
echo "✓ App executable architectures: ${ARCHS:-unknown}"
if [[ "${ARCHS}" != *"arm64"* ]]; then
  echo "⚠️  Warning: arm64 is missing. Apple Silicon Macs, including M4, may not open this build."
fi

echo ""
echo "Step 4: Preparing clean staging directory (app bundle only)..."
cleanup
mkdir -p "${STAGING_DIR}"
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"

echo ""
echo "Step 5: Removing old DMG (if exists)..."
rm -f "${DMG_OUTPUT}"

echo ""
echo "Step 6: Creating DMG with create-dmg..."

# Background image is 1440x900 pixels
# On Retina (2x): 1440px = 720 logical points → window-size 720x450 fills perfectly
# On non-Retina (1x): image larger than window, Finder clips to window → still fills
#
# Icon positions (in logical points):
#   Pod.app:      left-center  x=190, y=240
#   Applications: right-center x=530, y=240
CREATE_DMG_ARGS=(
  --volname "Pod"
  --window-pos 200 120
  --window-size 540 380
  --icon-size 110
  --text-size 14
  --icon "${APP_NAME}.app" 135 190
  --hide-extension "${APP_NAME}.app"
  --app-drop-link 405 190
  --hdiutil-quiet
)

if [ "${ENABLE_FINDER_DMG_LAYOUT}" != "1" ]; then
  CREATE_DMG_ARGS+=(--skip-jenkins)
fi

if ! create-dmg "${CREATE_DMG_ARGS[@]}" "${DMG_OUTPUT}" "${STAGING_DIR}/"; then
  echo "⚠️  create-dmg Finder layout failed; retrying without Finder AppleScript..."
  cleanup
  mkdir -p "${STAGING_DIR}"
  cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
  rm -f "${DMG_OUTPUT}"
  create-dmg \
    --volname "Pod" \
    --app-drop-link 405 190 \
    --hdiutil-quiet \
    --skip-jenkins \
    "${DMG_OUTPUT}" \
    "${STAGING_DIR}/"
fi

echo ""
echo "Step 7: Signing DMG..."
if [ "${SIGN_IDENTITY}" = "-" ]; then
  codesign --force --sign - "${DMG_OUTPUT}" || true
else
  codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG_OUTPUT}"
fi

echo ""
echo "Step 8: Cleaning up staging directory..."
cleanup

echo ""
echo "========================================="
echo " 🎉 DMG Created Successfully!"
echo " Path: ${DMG_OUTPUT}"
echo "========================================="
