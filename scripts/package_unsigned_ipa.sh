#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
project_root="$PWD"
derived="${EASYTRACK_DERIVED_DATA:-$PWD/DerivedData}"
case "$derived" in /*) ;; *) derived="$PWD/$derived" ;; esac
app="$derived/Build/Products/Release-iphoneos/EasyTrack.app"
output="${EASYTRACK_IPA_OUTPUT:-$derived/EasyTrack-unsigned.ipa}"
case "$output" in /*) ;; *) output="$PWD/$output" ;; esac
if [ ! -d "$app" ]; then
  echo "Release app not found. Build Release for generic iOS first." >&2
  exit 1
fi
if [ -e "$output" ]; then
  echo "IPA already exists; choose a new EASYTRACK_IPA_OUTPUT path to preserve it." >&2
  exit 1
fi
python3 scripts/validate_unsigned_ipa.py "$app"
staging="$(mktemp -d /private/tmp/easytrack-ipa.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/Payload"
ditto --norsrc --noextattr "$app" "$staging/Payload/EasyTrack.app"
cd "$staging"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent Payload "$output"
python3 "$project_root/scripts/validate_unsigned_ipa.py" "$output"
echo "$output"
