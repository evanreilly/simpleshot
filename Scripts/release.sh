#!/bin/zsh
# Build, notarize, and package locally. Does not publish or alter your installed app.
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "${ROOT_DIR}"
: "${VERSION:?Set VERSION to a release version such as 0.1.0}"
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application certificate}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool Keychain profile}"
if [[ ! "${VERSION}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo 'VERSION must have the form 1.2.3.' >&2
    exit 1
fi
if [[ "${SIGNING_IDENTITY}" != 'Developer ID Application: '* ]]; then
    echo 'Public releases require a Developer ID Application certificate.' >&2
    exit 1
fi
export BUILD_NUMBER="${BUILD_NUMBER:-1}"
swift test
UNIVERSAL=1 DISTRIBUTION=1 CONFIGURATION=release ./Scripts/build-app.sh
APP="${ROOT_DIR}/build/SimpleShot.app"
DIST="${ROOT_DIR}/build/release-${VERSION}"
mkdir -p "${DIST}"
STAGING="$(mktemp -d "${ROOT_DIR}/build/dmg.XXXXXX")"
trap 'rm -rf "${STAGING}"' EXIT

# Notarize and staple the app before embedding it in the disk image.
ditto -c -k --keepParent "${APP}" "${STAGING}/SimpleShot.zip"
xcrun notarytool submit "${STAGING}/SimpleShot.zip" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"
codesign --verify --deep --strict "${APP}"
spctl --assess --type execute --verbose=2 "${APP}"
rm "${STAGING}/SimpleShot.zip"
ditto "${APP}" "${STAGING}/SimpleShot.app"
ln -s /Applications "${STAGING}/Applications"
DMG="${DIST}/SimpleShot.dmg"
hdiutil create -volname SimpleShot -srcfolder "${STAGING}" -format UDZO -ov "${DMG}"
codesign --sign "${SIGNING_IDENTITY}" --timestamp "${DMG}"
xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}"
(cd "${DIST}" && shasum -a 256 SimpleShot.dmg > SHA256SUMS)
SHA256="$(shasum -a 256 "${DMG}" | awk '{print $1}')"
cat > "${DIST}/simpleshot.rb" <<EOF
cask "simpleshot" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/evanreilly/simpleshot/releases/download/v#{version}/SimpleShot.dmg"
  name "SimpleShot"
  desc "Menu-bar screenshot capture and annotation"
  homepage "https://github.com/evanreilly/simpleshot"

  depends_on macos: ">= :sonoma"
  app "SimpleShot.app"
end
EOF
echo "Ready for review: ${DIST}"
echo "Upload SimpleShot.dmg and SHA256SUMS to release v${VERSION}."
