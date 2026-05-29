#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="Release"
DEVICE_ID=""
TEAM_ID=""

usage() {
  cat <<'EOF'
Usage:
  ./ScrabblerInstall.sh [--debug|--release] [--device DEVICE_ID] [--team TEAM_ID]

Examples:
  ./ScrabblerInstall.sh
  ./ScrabblerInstall.sh --release --device 5B23B55F-73D0-5289-A601-BD2CF9A19377
  ./ScrabblerInstall.sh --debug --team ABCDE12345

If --device is omitted, the script uses the first connected iPhone from:
  xcrun devicectl list devices

If --team is omitted, Xcode uses the DEVELOPMENT_TEAM configured in:
  Scrabbler.iOS/Scrabbler.xcodeproj

Default configuration: Release.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug|-d)
      CONFIGURATION="Debug"
      shift
      ;;
    --release|-r)
      CONFIGURATION="Release"
      shift
      ;;
    --device)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --device." >&2
        usage
        exit 2
      fi
      DEVICE_ID="$2"
      shift 2
      ;;
    --team)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --team." >&2
        usage
        exit 2
      fi
      TEAM_ID="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(xcrun devicectl list devices | awk '$4 == "connected" && $5 == "iPhone" { print $3; exit }')"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "No connected iPhone found. Pass --device DEVICE_ID explicitly." >&2
  exit 1
fi

PROJECT="Scrabbler.iOS/Scrabbler.xcodeproj"
SCHEME="Scrabbler"
DERIVED_DATA_PATH="$(pwd)/Scrabbler.iOS/build/DerivedData"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}-iphoneos/Scrabbler.app"

BUILD_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=iOS"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -allowProvisioningUpdates
  CODE_SIGN_STYLE=Automatic
  build
)

if [[ -n "$TEAM_ID" ]]; then
  BUILD_ARGS+=(DEVELOPMENT_TEAM="$TEAM_ID")
fi

echo "Building native Scrabbler (${CONFIGURATION}) for iPhone..."
xcodebuild "${BUILD_ARGS[@]}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded, but app bundle was not found at: $APP_PATH" >&2
  exit 1
fi

echo "Installing ${APP_PATH} on device ${DEVICE_ID}..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "Installed native Scrabbler ${CONFIGURATION} build on ${DEVICE_ID}."
