#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="Release"
DEVICE_ID=""
TEAM_ID="${SCRABBLER_DEVELOPMENT_TEAM:-}"
USE_CACHED_PROVISIONING=false
BUNDLE_ID="com.andromedon.scrabblernet"

usage() {
  cat <<'EOF'
Usage:
  ./ScrabblerNetInstall.sh [--debug|--release] [--device DEVICE_ID] [--team TEAM_ID] [--use-cached-provisioning]

Examples:
  ./ScrabblerNetInstall.sh
  ./ScrabblerNetInstall.sh --release --device 5B23B55F-73D0-5289-A601-BD2CF9A19377
  ./ScrabblerNetInstall.sh --debug --team ABCDE12345
  ./ScrabblerNetInstall.sh --use-cached-provisioning

If --device is omitted, the script uses the first connected iPhone from:
  xcrun devicectl list devices

If --team is omitted, the script uses SCRABBLER_DEVELOPMENT_TEAM when set.
Otherwise .NET iOS uses the signing defaults available from Xcode/keychain.

Default configuration: Release.
Default provisioning behavior: renew local provisioning profile with xcodebuild before .NET build.
EOF
}

detect_team_id_from_profiles() {
  local profiles_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

  if [[ ! -d "$profiles_dir" ]]; then
    return
  fi

  while IFS= read -r -d '' profile; do
    if /usr/bin/grep -a -q "com.andromedon.scrabbler" "$profile"; then
      /usr/bin/grep -a -A2 "<key>TeamIdentifier</key>" "$profile" |
        /usr/bin/grep -a "<string>" |
        head -n 1 |
        sed -E 's/.*<string>([^<]+)<\/string>.*/\1/'
      return
    fi
  done < <(find "$profiles_dir" -maxdepth 1 -name '*.mobileprovision' -print0)
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

refresh_provisioning_profile_with_xcodebuild() {
  local bundle_id="$1"
  local configuration="$2"
  local team_id="$3"
  local derived_data_path

  derived_data_path="${TMPDIR:-/tmp}/scrabblernet-provisioning-warmup-derived-data"

  local warmup_args=(
    -project "Scrabbler.iOS/Scrabbler.xcodeproj"
    -scheme "Scrabbler"
    -configuration "$configuration"
    -destination "generic/platform=iOS"
    -derivedDataPath "$derived_data_path"
    -allowProvisioningUpdates
    -allowProvisioningDeviceRegistration
    PRODUCT_BUNDLE_IDENTIFIER="$bundle_id"
    CODE_SIGN_STYLE=Automatic
    build
  )

  if [[ -n "$team_id" ]]; then
    warmup_args+=(DEVELOPMENT_TEAM="$team_id")
  fi

  echo "Refreshing provisioning profile for ${bundle_id} with xcodebuild..."
  xcodebuild "${warmup_args[@]}" >/tmp/scrabblernet-provisioning-warmup.log || {
    echo "Could not refresh provisioning profile with xcodebuild." >&2
    echo "xcodebuild log: /tmp/scrabblernet-provisioning-warmup.log" >&2
    echo "Try opening Scrabbler.iOS/Scrabbler.xcodeproj once, selecting your Team, or rerun with --team TEAM_ID." >&2
    return 1
  }
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

if [[ -z "$TEAM_ID" ]]; then
  TEAM_ID="$(detect_team_id_from_profiles || true)"
fi

PROJECT="Scrabbler.Maui/Scrabbler.Maui.csproj"
FRAMEWORK="net10.0-ios"
RUNTIME="ios-arm64"
APP_PATH="Scrabbler.Maui/bin/${CONFIGURATION}/${FRAMEWORK}/${RUNTIME}/Scrabbler.Maui.app"

if [[ "$USE_CACHED_PROVISIONING" != true ]]; then
  renew_local_provisioning_profiles "$BUNDLE_ID"
  refresh_provisioning_profile_with_xcodebuild "$BUNDLE_ID" "$CONFIGURATION" "$TEAM_ID"
else
  echo "Using cached provisioning profile for ${BUNDLE_ID}."
fi

BUILD_ARGS=(
  "$PROJECT"
  -f "$FRAMEWORK"
  -p:RuntimeIdentifier="$RUNTIME"
  "-p:CodesignKey=Apple Development"
)

if [[ "$CONFIGURATION" == "Release" ]]; then
  BUILD_ARGS=(-c Release "${BUILD_ARGS[@]}")
fi

if [[ -n "$TEAM_ID" ]]; then
  BUILD_ARGS+=(-p:CodesignTeamId="$TEAM_ID")
fi

echo "Building Scrabbler NET (${CONFIGURATION}) for ${RUNTIME}..."
dotnet build "${BUILD_ARGS[@]}"

echo "Installing ${APP_PATH} on device ${DEVICE_ID}..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "Installed Scrabbler NET ${CONFIGURATION} build on ${DEVICE_ID}."
