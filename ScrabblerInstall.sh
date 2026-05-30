#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="Release"
DEVICE_ID=""
TEAM_ID="${SCRABBLER_DEVELOPMENT_TEAM:-}"
USE_CACHED_PROVISIONING=false
BUNDLE_ID="com.andromedon.scrabbler"
CONSOLE_DICTIONARY="Scrabbler.ConsoleApp/Data/dictionary-pl.txt"
IOS_DICTIONARY="Scrabbler.iOS/ScrabblerKit/Sources/ScrabblerKit/Resources/Data/dictionary-pl.txt"

usage() {
  cat <<'EOF'
Usage:
  ./ScrabblerInstall.sh [--debug|--release] [--device DEVICE_ID] [--team TEAM_ID] [--use-cached-provisioning]

Examples:
  ./ScrabblerInstall.sh
  ./ScrabblerInstall.sh --release --device 5B23B55F-73D0-5289-A601-BD2CF9A19377
  ./ScrabblerInstall.sh --debug --team ABCDE12345
  ./ScrabblerInstall.sh --use-cached-provisioning

If --device is omitted, the script uses the first connected iPhone from:
  xcrun devicectl list devices

If --team is omitted, the script uses SCRABBLER_DEVELOPMENT_TEAM when set.
Otherwise Xcode uses the DEVELOPMENT_TEAM configured in:
  Scrabbler.iOS/Scrabbler.xcodeproj

Default configuration: Release.
Default provisioning behavior: renew local provisioning profile before build.
EOF
}

renew_local_provisioning_profiles() {
  local bundle_id="$1"
  local profiles_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

  if [[ ! -d "$profiles_dir" ]]; then
    echo "Provisioning profile cache directory not found: $profiles_dir"
    return
  fi

  local removed=0
  while IFS= read -r -d '' profile; do
    if /usr/bin/grep -a -q "$bundle_id" "$profile"; then
      echo "Removing cached provisioning profile for ${bundle_id}: ${profile}"
      rm -f "$profile"
      removed=$((removed + 1))
    fi
  done < <(find "$profiles_dir" -maxdepth 1 -name '*.mobileprovision' -print0)

  if [[ "$removed" -eq 0 ]]; then
    echo "No cached provisioning profiles found for ${bundle_id}."
  fi
}

prepare_local_dictionary() {
  if [[ ! -f "$CONSOLE_DICTIONARY" ]]; then
    echo "Full dictionary not found at ${CONSOLE_DICTIONARY}; native app will use bundled sample dictionary."
    return
  fi

  if [[ ! -f "$IOS_DICTIONARY" || "$CONSOLE_DICTIONARY" -nt "$IOS_DICTIONARY" ]]; then
    echo "Copying full dictionary into native app resources..."
    cp "$CONSOLE_DICTIONARY" "$IOS_DICTIONARY"
  fi
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
    --use-cached-provisioning)
      USE_CACHED_PROVISIONING=true
      shift
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
BUILD_TIMESTAMP_UTC="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

if [[ "$USE_CACHED_PROVISIONING" != true ]]; then
  renew_local_provisioning_profiles "$BUNDLE_ID"
else
  echo "Using cached provisioning profile for ${BUNDLE_ID}."
fi

prepare_local_dictionary

BUILD_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=iOS"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -allowProvisioningUpdates
  -allowProvisioningDeviceRegistration
  CODE_SIGN_STYLE=Automatic
  SCRABBLER_BUILD_TIMESTAMP="$BUILD_TIMESTAMP_UTC"
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
