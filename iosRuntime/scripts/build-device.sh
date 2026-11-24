#!/bin/bash
# Build RuntimeApp.app for a real iPhone (see build-app.sh for options).
#
# Signing uses the Apple Development identity in the keychain and the
# provisioning profile Xcode created for this bundle id. Install with:
#   xcrun devicectl device install app --device <UDID> build/device/RuntimeApp.app
exec env TARGET=device "$(cd "$(dirname "$0")" && pwd)/build-app.sh" "$@"
