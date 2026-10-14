#!/bin/zsh
# Interim binary distribution while Developer ID enrollment is pending.
set -euo pipefail
cd "${0:A:h:h}"
export VERSION="${VERSION:-0.1.0}"
export BUILD_NUMBER="${BUILD_NUMBER:-1}"
export SIGNING_IDENTITY=- ALLOW_ADHOC_SIGNING=1 UNIVERSAL=1 DISTRIBUTION=0
./Scripts/build-app.sh
mkdir -p build/preview
ditto -c -k --keepParent build/SimpleShot.app build/preview/SimpleShot.zip
(cd build/preview && shasum -a 256 SimpleShot.zip > SHA256SUMS)
echo 'Unnotarized preview packaged in build/preview; macOS approval is required.'
