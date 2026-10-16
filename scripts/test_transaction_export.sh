#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
fixture_dir="$PWD/DerivedData/TransactionExportFixtures"
mkdir -p "$fixture_dir" "$PWD/.build/clang-cache"
EASYTRACK_EXPORT_ARTIFACT_DIR="$fixture_dir" \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
SWIFTPM_CACHE_PATH="$PWD/.build/swiftpm-cache" \
  swift test --disable-sandbox --scratch-path "$PWD/.build" --filter TransactionExportTests
if [ -d "$PWD/DerivedData/python-test-tools" ]; then
  PYTHONPATH="$PWD/DerivedData/python-test-tools${PYTHONPATH:+:$PYTHONPATH}" \
    python3 scripts/validate_transaction_export.py "$fixture_dir"
else
  python3 scripts/validate_transaction_export.py "$fixture_dir"
fi
