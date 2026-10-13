#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
app="$PWD/DerivedData/Build/Products/Release-iphoneos/EasyTrack.app"
output="$PWD/DerivedData/EasyTrack-unsigned.ipa"
if [ ! -d "$app" ]; then
  echo "Release app not found. Build Release for generic iOS first." >&2
  exit 1
fi
staging="$(mktemp -d /private/tmp/easytrack-ipa.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/Payload"
ditto --norsrc --noextattr "$app" "$staging/Payload/EasyTrack.app"
cd "$staging"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent Payload "$output"
echo "$output"
