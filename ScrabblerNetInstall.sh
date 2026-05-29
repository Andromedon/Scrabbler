#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="Release"
DEVICE_ID=""

usage() {
  cat <<'EOF'
Usage:
  ./ScrabblerNetInstall.sh [--debug|--release] [--device DEVICE_ID]

Examples:
  ./ScrabblerNetInstall.sh
  ./ScrabblerNetInstall.sh --release --device 5B23B55F-73D0-5289-A601-BD2CF9A19377
  ./ScrabblerNetInstall.sh --debug

If --device is omitted, the script uses the first connected iPhone from:
  xcrun devicectl list devices

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

PROJECT="Scrabbler.Maui/Scrabbler.Maui.csproj"
FRAMEWORK="net10.0-ios"
RUNTIME="ios-arm64"
APP_PATH="Scrabbler.Maui/bin/${CONFIGURATION}/${FRAMEWORK}/${RUNTIME}/Scrabbler.Maui.app"

echo "Building Scrabbler NET (${CONFIGURATION}) for ${RUNTIME}..."
if [[ "$CONFIGURATION" == "Release" ]]; then
  dotnet build "$PROJECT" -c Release -f "$FRAMEWORK" -p:RuntimeIdentifier="$RUNTIME"
else
  dotnet build "$PROJECT" -f "$FRAMEWORK" -p:RuntimeIdentifier="$RUNTIME"
fi

echo "Installing ${APP_PATH} on device ${DEVICE_ID}..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "Installed Scrabbler NET ${CONFIGURATION} build on ${DEVICE_ID}."
