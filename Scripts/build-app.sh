#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${ROOT_DIR}/build"
APP_DIR="${OUTPUT_DIR}/SimpleShot.app"
BUILD_SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [[ -z "${BUILD_SIGNING_IDENTITY}" && -f "${ROOT_DIR}/.signing-identity" ]]; then
    IFS= read -r BUILD_SIGNING_IDENTITY < "${ROOT_DIR}/.signing-identity"
fi

if [[ -z "${BUILD_SIGNING_IDENTITY}" || "${BUILD_SIGNING_IDENTITY}" == "-" ]]; then
    if [[ "${ALLOW_ADHOC_SIGNING:-0}" != "1" ]]; then
        echo "A persistent code-signing identity is required for SimpleShot updates." >&2
        echo "In Xcode Settings > Accounts > Manage Certificates, create an Apple Development certificate." >&2
        echo "Then run: SIGNING_IDENTITY='Apple Development: …' Scripts/build-app.sh" >&2
        echo "For disposable builds only, opt in with ALLOW_ADHOC_SIGNING=1 (Screen Recording approval may be lost)." >&2
        exit 1
    fi
    BUILD_SIGNING_IDENTITY="-"
fi

cd "${ROOT_DIR}"
BUILD_ARGS=(-c "${CONFIGURATION}")
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/SimpleShot" "${APP_DIR}/Contents/MacOS/SimpleShot"
cp "${ROOT_DIR}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"

if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_DIR}/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP_DIR}/Contents/Info.plist"
fi
SIGN_ARGS=(--force --sign "${BUILD_SIGNING_IDENTITY}")
if [[ "${DISTRIBUTION:-0}" == "1" ]]; then
    SIGN_ARGS+=(--options runtime --timestamp --entitlements "${ROOT_DIR}/Resources/Distribution.entitlements")
fi
codesign "${SIGN_ARGS[@]}" "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"
echo "Built ${APP_DIR}"
