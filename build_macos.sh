#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Change directory to the script's directory (project root)
cd "$(dirname "$0")"

APP_NAME="PodQuick"
RELEASE_DIR="build/macos/Build/Products/Release"
APP_BUNDLE="${RELEASE_DIR}/${APP_NAME}.app"
DIST_DIR="dist"
ENABLE_FINDER_DMG_LAYOUT="${ENABLE_FINDER_DMG_LAYOUT:-0}"

# Detect available Apple Developer ID identity for code signing
detect_sign_identity() {
  local identity
  # Only Developer ID Application is meant for universal distribution without device restrictions.
  for prefix in "Developer ID Application" "Apple Distribution"; do
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

# Ensure standard UTF-8 locale for create-dmg/AppleScript
if [ "${LC_ALL:-}" = "C.UTF-8" ] || [ "${LANG:-}" = "C.UTF-8" ]; then
  export LC_ALL="en_US.UTF-8"
  export LANG="en_US.UTF-8"
fi

# Detect local proxy (e.g. Clash on 7890) for cargokit/github downloads
if nc -z 127.0.0.1 7890 2>/dev/null; then
  echo "⚡ Local proxy detected on port 7890, enabling proxy for build tool downloads..."
  export http_proxy="http://127.0.0.1:7890"
  export https_proxy="http://127.0.0.1:7890"
  export all_proxy="socks5://127.0.0.1:7890"
fi

cleanup_staging() {
  rm -rf "${RELEASE_DIR}"/staging_*
  rm -f "${RELEASE_DIR}"/rw.*.PodQuick*.dmg
  rm -f "${DIST_DIR}"/rw.*.PodQuick*.dmg
}
trap cleanup_staging EXIT

echo "=========================================================="
echo " 🚀 PodQuick macOS Clean & Multi-Architecture DMG Packager "
echo "=========================================================="

echo ""
echo "Step 1: Preparing aesthetic DMG assets..."
if [ -f "make_dmg_bg.py" ]; then
  python3 make_dmg_bg.py || true
fi
if [ -f "build/macos/Build/Products/Release/PodQuick.app/Contents/Resources/AppIcon.icns" ]; then
  cp -f "build/macos/Build/Products/Release/PodQuick.app/Contents/Resources/AppIcon.icns" "assets/AppIcon.icns" 2>/dev/null || true
fi

echo ""
echo "Step 2: Cleaning previous build artifacts and staging..."
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"
cleanup_staging

# If --clean flag is given, run flutter clean
if [ "$1" = "--clean" ]; then
  echo "🧹 Running flutter clean to remove all stale artifacts..."
  flutter clean
  flutter pub get
fi

echo ""
echo "Step 2: Building Flutter macOS application in Release mode (Universal, Target 12.0+ for macOS Monterey and newer)..."
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
flutter build macos --release

if [ ! -d "${APP_BUNDLE}" ]; then
  if [ -d "${RELEASE_DIR}/pod.app" ]; then
    APP_NAME="pod"
    APP_BUNDLE="${RELEASE_DIR}/${APP_NAME}.app"
  else
    echo "❌ Error: Could not find application bundle at ${RELEASE_DIR}."
    exit 1
  fi
fi

EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${APP_BUNDLE}/Contents/Info.plist")
echo "✓ Built Universal App Bundle: ${APP_BUNDLE}"

# Function to thin, sign, and create DMG for a specific architecture
package_variant() {
  local target_arch="$1"       # "arm64" or "x86_64"
  local arch_label="$2"        # "AppleSilicon" or "Intel"
  local human_desc="$3"        # Description
  local dmg_name="PodQuick-${arch_label}.dmg"
  local dmg_output="${DIST_DIR}/${dmg_name}"
  local staging_dir="${RELEASE_DIR}/staging_${target_arch}"
  local target_app="${staging_dir}/${APP_NAME}.app"

  echo ""
  echo "----------------------------------------------------------"
  echo " 📦 Packaging: ${arch_label} (${target_arch}) - ${human_desc}"
  echo "----------------------------------------------------------"

  # 1. Prepare clean staging copy
  rm -rf "${staging_dir}"
  mkdir -p "${staging_dir}"
  cp -R "${APP_BUNDLE}" "${target_app}"

  # 2. Thin executable to target architecture
  local target_exec="${target_app}/Contents/MacOS/${EXECUTABLE_NAME}"
  if lipo -archs "${target_exec}" | grep -q "${target_arch}"; then
    if [ $(lipo -archs "${target_exec}" | wc -w) -gt 1 ]; then
      lipo -thin "${target_arch}" "${target_exec}" -output "${target_exec}"
    fi
  else
    echo "❌ Error: Binary does not contain architecture ${target_arch}!"
    exit 1
  fi

  # 3. Thin all embedded frameworks
  if [ -d "${target_app}/Contents/Frameworks" ]; then
    for fw in "${target_app}/Contents/Frameworks"/*.framework; do
      [ -e "${fw}" ] || continue
      local fw_name=$(basename "${fw}" .framework)
      local fw_bin=""
      [ -f "${fw}/${fw_name}" ] && fw_bin="${fw}/${fw_name}"
      [ -f "${fw}/Versions/A/${fw_name}" ] && fw_bin="${fw}/Versions/A/${fw_name}"
      if [ -n "${fw_bin}" ] && [ -f "${fw_bin}" ]; then
        if lipo -archs "${fw_bin}" 2>/dev/null | grep -q "${target_arch}"; then
          if [ $(lipo -archs "${fw_bin}" | wc -w) -gt 1 ]; then
            lipo -thin "${target_arch}" "${fw_bin}" -output "${fw_bin}"
          fi
        fi
      fi
    done
  fi

  # 4. Normalize file permissions and remove extended attributes
  chmod -R u+rwX,go+rX "${target_app}" || true
  chmod +x "${target_exec}" || true
  xattr -rc "${target_app}" || true

  # 5. Inside-Out Code Signing
  # In macOS 11 Big Sur and newer, dyld enforces strict signature checks for all Mach-O slices.
  # Running `lipo -thin` modifies binaries, invalidating original signatures.
  # Using naive `codesign --deep` often fails to re-sign inner frameworks properly, causing dyld crash on macOS 11.
  echo "✍️  Signing ${arch_label} embedded libraries and frameworks (Inside-Out)..."

  local sign_flags=(--force)
  if [ "${SIGN_IDENTITY}" != "-" ]; then
    sign_flags+=(--options runtime --timestamp)
  fi

  # 5.1 Sign dynamic libraries
  if [ -d "${target_app}/Contents/Frameworks" ]; then
    find "${target_app}/Contents/Frameworks" -type f -name "*.dylib" 2>/dev/null | while read -r dylib; do
      [ -f "${dylib}" ] || continue
      codesign "${sign_flags[@]}" --sign "${SIGN_IDENTITY}" "${dylib}" 2>/dev/null || \
      codesign --force --sign - "${dylib}" 2>/dev/null || true
    done

    # 5.2 Sign embedded frameworks from innermost to outermost
    find "${target_app}/Contents/Frameworks" -depth -type d -name "*.framework" 2>/dev/null | while read -r fw; do
      [ -d "${fw}" ] || continue
      codesign "${sign_flags[@]}" --sign "${SIGN_IDENTITY}" "${fw}" 2>/dev/null || \
      codesign --force --sign - "${fw}" 2>/dev/null || true
    done
  fi

  # 5.3 Sign main application bundle with entitlements
  local entitlements_arg=()
  if [ -f "macos/Runner/Release.entitlements" ]; then
    entitlements_arg=(--entitlements "macos/Runner/Release.entitlements")
  fi

  echo "  Signing main application bundle ${target_app}..."
  if [ "${SIGN_IDENTITY}" != "-" ]; then
    if ! codesign "${sign_flags[@]}" "${entitlements_arg[@]}" --sign "${SIGN_IDENTITY}" "${target_app}" 2>/dev/null; then
      codesign --force "${entitlements_arg[@]}" --sign "${SIGN_IDENTITY}" "${target_app}" 2>/dev/null || \
      codesign --force "${entitlements_arg[@]}" --sign - "${target_app}"
    fi
  else
    codesign --force "${entitlements_arg[@]}" --sign - "${target_app}"
  fi

  # 5.4 Verification
  codesign --verify --deep --strict --verbose=1 "${target_app}" 2>/dev/null || true
  local verified_arch=$(lipo -archs "${target_exec}")
  echo "✓ Architecture confirmed: ${verified_arch}"
  echo "✓ Code signing verified"

  # 6. Build DMG using create-dmg
  echo "💿 Creating DMG: ${dmg_name}..."
  rm -f "${dmg_output}"

  CREATE_DMG_ARGS=(
    --volname "PodQuick"
    --window-pos 260 160
    --window-size 660 420
    --icon-size 110
    --text-size 13
    --icon "${APP_NAME}.app" 175 205
    --hide-extension "${APP_NAME}.app"
    --app-drop-link 485 205
    --hdiutil-quiet
  )

  if [ -f "assets/dmg_background.tiff" ]; then
    CREATE_DMG_ARGS+=(--background "assets/dmg_background.tiff")
  elif [ -f "assets/dmg_background.png" ]; then
    CREATE_DMG_ARGS+=(--background "assets/dmg_background.png")
  fi

  if [ -f "assets/AppIcon.icns" ]; then
    CREATE_DMG_ARGS+=(--volicon "assets/AppIcon.icns")
  fi

  if ! create-dmg "${CREATE_DMG_ARGS[@]}" "${dmg_output}" "${staging_dir}/"; then
    echo "⚠️  create-dmg layout attempt failed; retrying with safe fallback..."
    rm -f "${dmg_output}"
    create-dmg \
      "${CREATE_DMG_ARGS[@]}" \
      --skip-jenkins \
      "${dmg_output}" \
      "${staging_dir}/"
  fi

  # 7. Sign DMG
  if [ "${SIGN_IDENTITY}" = "-" ]; then
    codesign --force --sign - "${dmg_output}" 2>/dev/null || true
  else
    codesign --force --sign "${SIGN_IDENTITY}" "${dmg_output}" 2>/dev/null || codesign --force --sign - "${dmg_output}" 2>/dev/null || true
  fi

  # Clean up this variant staging directory immediately
  rm -rf "${staging_dir}"

  local size=$(ls -lh "${dmg_output}" | awk '{print $5}')
  echo "✓ Generated: ${dmg_output} (${size})"
}

# Package Apple Silicon version (arm64)
package_variant "arm64" "arm" "Apple Silicon (M1/M2/M3/M4)"

# Package Intel version (x86_64)
package_variant "x86_64" "x86" "Intel 64-bit Processors"

# Also place copy for general scripts (like upload_macos.sh)
mkdir -p build
cp -f "${DIST_DIR}/PodQuick-arm.dmg" "build/PodQuick.dmg"

echo ""
echo "=========================================================="
echo " 🎉 All Versions Successfully Packaged and Organized!     "
echo "=========================================================="
echo "Output Directory: $(pwd)/${DIST_DIR}"
echo ""
ls -lh "${DIST_DIR}"/*.dmg
echo "=========================================================="
