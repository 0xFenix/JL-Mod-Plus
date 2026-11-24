#!/bin/bash
# Build RuntimeApp.app for the iOS simulator (see build-app.sh for options).
exec env TARGET=sim "$(cd "$(dirname "$0")" && pwd)/build-app.sh" "$@"
