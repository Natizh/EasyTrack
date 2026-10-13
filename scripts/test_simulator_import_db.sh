#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
  echo "Usage: test_simulator_import_db.sh /path/to/simulator/EasyTrack.sqlite" >&2
  exit 1
fi
database_path="$1"
cd "$(dirname "$0")/.."
mkdir -p .cache/modulecache DerivedData/SimulatorSmoke
CLANG_MODULE_CACHE_PATH="$PWD/.cache/modulecache" SWIFT_MODULECACHE_PATH="$PWD/.cache/modulecache" \
  xcrun swiftc -module-cache-path "$PWD/.cache/modulecache" \
  EasyTrack/Shared/Models.swift EasyTrack/Import/SeedMapper.swift \
  EasyTrack/Persistence/SQLiteDatabase.swift Tests/SimulatorImportSmoke/main.swift \
  -lsqlite3 -o DerivedData/SimulatorSmoke/simulator-import-smoke
DerivedData/SimulatorSmoke/simulator-import-smoke "$database_path"
